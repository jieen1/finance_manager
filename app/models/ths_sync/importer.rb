module ThsSync
  class Importer
    attr_reader :ths_session, :family, :results

    def initialize(ths_session)
      @ths_session = ths_session
      @family = ths_session.family
      @results = { created: 0, updated: 0, skipped: 0, errors: [] }
    end

    def sync!
      client = ThsClient.new(ths_session)

      begin
        account_data = client.account_list
        ths_accounts = account_data.dig("ex_data", "list") || []
      rescue ThsClient::ApiError
        ths_accounts = []
      end

      if ths_accounts.any?
        ths_accounts.each do |ths_account|
          fund_key = ths_account["fund_key"] || ths_account["manual_id"]
          sync_trades(client, fund_key: fund_key) if fund_key.present?
          sync_positions(client, fund_key: fund_key) if fund_key.present?
        end
      else
        sync_trades(client, fund_key: "84360053")
        sync_positions(client, fund_key: "84360053")
      end

      sync_hk_rate(client)
      ths_session.record_sync!
      results
    rescue ThsClient::AuthError => e
      ths_session.mark_expired!(e.message)
      raise
    end

    private

    # 增量同步：只拉最近3天的数据（覆盖前一天用于更新结算后的手续费）
    # 首次全量同步：如果没有任何已导入记录，拉取全部历史
    def sync_trades(client, fund_key:)
      cutoff_date = incremental_cutoff_date
      all_records = []
      page = 1

      loop do
        data = client.money_history(fund_key: fund_key, page: page, count: 50)
        records = data.dig("ex_data", "list") || []
        break if records.empty?

        # 增量模式：数据按日期倒序返回，遇到早于截止日期的就停止
        if cutoff_date
          recent = records.select { |r| r["entry_date"].to_s >= cutoff_date }
          all_records.concat(recent)
          break if recent.size < records.size # 已经到达截止日期
        else
          all_records.concat(records)
        end

        break if records.size < 50
        page += 1
        break if page > 200
      end

      # 按日期正序处理（op=18 去重需要最早的排在前面）
      all_records.sort_by! { |r| [r["entry_date"].to_s, r["entry_time"].to_s] }
      all_records.each { |record| store_and_import(record) }
    rescue ThsClient::ApiError => e
      results[:errors] << "money_history: #{e.message}"
    end

    # 有历史数据时只拉最近3天，否则全量
    def incremental_cutoff_date
      has_history = ExternalRecord.where(source: "ths", family: family).imported.exists?
      return nil unless has_history # 首次全量

      (Date.current - 3).to_s # 最近3天（今天+昨天+前天，覆盖结算延迟）
    end

    def sync_positions(client, fund_key:)
      data = client.stock_position(fund_key: fund_key)
      positions = data.dig("ex_data", "position") || []

      positions.each do |pos|
        ExternalRecord.find_or_create_by(
          source: "ths_position",
          external_id: "pos_#{Date.current}_#{pos["code"]}"
        ) do |r|
          r.family = family
          r.record_type = "position"
          r.raw_data = pos
          r.status = "imported"
        end
      end
    rescue ThsClient::ApiError => e
      results[:errors] << "stock_position: #{e.message}"
    end

    def store_and_import(record)
      ext_id = ThsSync::TradeMapper.external_id(record)
      rec_type = ThsSync::TradeMapper.record_type(record)

      ext_record = ExternalRecord.find_or_initialize_by(
        source: "ths",
        external_id: ext_id
      )

      # Already imported - check if fee needs update or data changed
      if ext_record.persisted? && ext_record.status == "imported"
        maybe_update_trade(ext_record, record)
        return
      end

      ext_record.assign_attributes(
        family: family,
        record_type: rec_type,
        raw_data: record,
        status: "pending"
      )
      ext_record.save!

      # op=18(转入/中签): 同一code只导入第一条，后续的是账户间转移
      if record["op"].to_s == "18"
        @imported_op18_codes ||= Set.new
        if @imported_op18_codes.include?(record["code"])
          ext_record.mark_skipped!("duplicate op=18 for #{record["code"]}")
          return
        end
        @imported_op18_codes.add(record["code"])
      end

      if rec_type == "trade"
        import_trade(ext_record, record)
      else
        ext_record.mark_skipped!("type=#{rec_type}")
      end
    rescue => e
      results[:errors] << "#{ext_id}: #{e.message}"
    end

    def import_trade(ext_record, record)
      account = find_investment_account
      unless account
        ext_record.mark_error!("No investment account found")
        return
      end

      params = ThsSync::TradeMapper.to_trade_params(record, account_id: account.id)
      unless params
        ext_record.mark_skipped!("unmappable")
        return
      end

      form_params = params.except(:account_id)
      form = Trade::CreateForm.new(**form_params.merge(account: account))
      entry = form.create

      if entry.persisted?
        ext_record.mark_imported!(entry)
        results[:created] += 1
      else
        msg = entry.errors.full_messages.join(", ")
        ext_record.mark_error!(msg)
        results[:errors] << "#{ext_record.external_id}: #{msg}"
      end
    end

    # Update existing trade if data changed (fee update after settlement, or qty correction)
    def maybe_update_trade(ext_record, record)
      entry = ext_record.entry
      return (results[:skipped] += 1) unless entry

      trade = entry.entryable
      new_fee = record["fee_total"].to_f
      new_qty = record["entry_count"].to_f.abs
      new_price = record["entry_price"].to_f

      old_fee = trade.fee.to_f
      old_qty = trade.qty.abs.to_f
      old_price = trade.price.to_f

      fee_changed = new_fee > 0 && (new_fee - old_fee).abs > 0.001
      qty_changed = (new_qty - old_qty).abs > 0.001
      price_changed = (new_price - old_price).abs > 0.001

      if fee_changed || qty_changed || price_changed
        signed_qty = trade.qty.positive? ? new_qty : -new_qty
        fee_impact = signed_qty.positive? ? new_fee : -new_fee
        new_amount = (signed_qty * new_price) + fee_impact

        trade.update!(qty: signed_qty, price: new_price, fee: new_fee)
        entry.update!(amount: new_amount)
        ext_record.update!(raw_data: record)

        entry.account.sync_later
        results[:updated] += 1
      else
        results[:skipped] += 1
      end
    rescue => e
      results[:errors] << "update #{ext_record.external_id}: #{e.message}"
      results[:skipped] += 1
    end

    # Sync HKD→CNY rate from THS to keep consistent with THS calculations
    def sync_hk_rate(client)
      data = client.hk_rate
      ex = data["ex_data"]
      return unless ex

      rate = ex["rate"].to_f
      date_str = ex["date"].to_s
      return if rate.zero? || date_str.blank?

      date = Date.parse("#{date_str[0..3]}-#{date_str[4..5]}-#{date_str[6..7]}")

      ExchangeRate.find_or_initialize_by(
        from_currency: "HKD",
        to_currency: "CNY",
        date: date
      ).update!(rate: rate)

      # Also store previous day rate if available
      if ex["before_rate"].present? && ex["before_date"].present?
        before_rate = ex["before_rate"].to_f
        bd = ex["before_date"].to_s
        before_date = Date.parse("#{bd[0..3]}-#{bd[4..5]}-#{bd[6..7]}")
        ExchangeRate.find_or_initialize_by(
          from_currency: "HKD",
          to_currency: "CNY",
          date: before_date
        ).update!(rate: before_rate)
      end
    rescue => e
      Rails.logger.warn("[ThsSync] hk_rate sync failed: #{e.message}")
    end

    def find_investment_account
      @investment_account ||= family.accounts
        .where(accountable_type: "Investment")
        .where(status: "active")
        .first
    end
  end
end
