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
      trigger_account_sync
      ths_session.record_sync!
      results
    rescue ThsClient::AuthError => e
      ths_session.mark_expired!(e.message)
      raise
    end

    private

    # v2 API: date range + pagination via max_page, returns sub-order fills with unique vid
    # Incremental: last 3 days. First-time: full history from account start.
    def sync_trades(client, fund_key:)
      start_date = incremental_start_date
      end_date = Date.current
      all_records = []
      page = 1

      loop do
        data = client.money_history_v2(
          fund_key: fund_key,
          start_date: start_date,
          end_date: end_date,
          page: page,
          count: 50
        )
        records = data.dig("ex_data", "list") || []
        break if records.empty?

        all_records.concat(records)

        max_page = data.dig("ex_data", "max_page") || 1
        break if page >= max_page
        page += 1
        break if page > 200
      end

      # 按日期正序处理（op=18 去重需要最早的排在前面）
      all_records.sort_by! { |r| [r["entry_date"].to_s, r["entry_time"].to_s] }

      # Pre-compute lot prices from buy records for reverse repo interest calculation
      @repo_lot_prices = {}
      all_records.select { |r| r["op"].to_s == "5" && ThsSync::TradeMapper.reverse_repo?(r) }.each do |r|
        qty = r["entry_count"].to_f.abs
        money = r["entry_money"].to_f
        @repo_lot_prices[r["code"].to_s.strip] = (money / qty).round(2) if qty > 0
      end

      all_records.each { |record| store_and_import(record) }

      # Remove records that no longer exist in the API (e.g. 分笔 replaced by 汇总 after settlement)
      purge_stale_records(all_records, start_date, end_date)
    rescue ThsClient::ApiError => e
      results[:errors] << "money_history_v2: #{e.message}"
    end

    # Delete ExternalRecords (and their entries) whose vid no longer appears in the API response
    # for the synced date range. This handles分笔→汇总 replacement after settlement.
    def purge_stale_records(api_records, query_start_date, query_end_date)
      api_vids = api_records.map { |r| r["vid"].to_s.strip }.to_set

      # Find DB records in the queried date range that are no longer in the API
      stale = ExternalRecord.where(source: "ths", family: family)
        .where("record_type IN ('trade', 'cash_flow')")
        .where("raw_data->>'entry_date' >= ? AND raw_data->>'entry_date' <= ?",
               query_start_date.to_s, query_end_date.to_s)
        .reject { |r| api_vids.include?(r.external_id) }

      stale.each do |r|
        entry = r.entry
        r.update_columns(entry_id: nil)
        r.destroy!
        entry&.destroy!

        # Also remove associated interest entry if this was a repo sell
        if r.raw_data["op"].to_s == "35"
          interest_ext = ExternalRecord.find_by(source: "ths", external_id: "#{r.external_id}_interest")
          if interest_ext
            interest_entry = interest_ext.entry
            interest_ext.update_columns(entry_id: nil)
            interest_ext.destroy!
            interest_entry&.destroy!
          end
        end
      end

      Rails.logger.info("[ThsSync] Purged #{stale.size} stale records") if stale.any?
    end

    # Incremental: last 3 days. First-time: from earliest possible date.
    def incremental_start_date
      has_history = ExternalRecord.where(source: "ths", family: family).imported.exists?
      has_history ? Date.current - 3 : Date.new(2020, 1, 1)
    end

    # For trigger_account_sync: determine whether to do windowed or full sync
    def incremental_cutoff_date
      has_history = ExternalRecord.where(source: "ths", family: family).imported.exists?
      return nil unless has_history
      (Date.current - 3).to_s
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
      elsif rec_type == "cash_flow"
        import_cash_flow(ext_record, record)
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
        # Use THS entry_money (actual broker settlement) instead of qty×price for accuracy.
        # entry_money excludes fee; fee is always in CNY.
        # Skip for reverse repo sells (op=35) — they use qty×lot_price with separate interest entry.
        money = record["entry_money"].to_f
        fee_amt = record["fee_total"].to_f
        is_sell = %w[2 35].include?(record["op"].to_s)
        if money > 0 && record["op"].to_s != "35"
          signed_money = is_sell ? -(money - fee_amt) : (money + fee_amt)
          entry.update_columns(amount: signed_money, currency: "CNY")
        end

        ext_record.mark_imported!(entry)
        results[:created] += 1

        # Reverse repo maturity: create an interest income entry for the profit
        interest = ThsSync::TradeMapper.reverse_repo_interest(record, buy_lot_prices: @repo_lot_prices || {})
        if interest
          create_repo_interest_income(account, record, interest)
        end
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

        money = record["entry_money"].to_f
        is_sell = %w[2 35].include?(record["op"].to_s)
        if money > 0 && record["op"].to_s != "35"
          new_amount = is_sell ? -(money - new_fee) : (money + new_fee)
        else
          new_amount = is_sell ? -(signed_qty.abs * new_price) + new_fee : (signed_qty.abs * new_price) + new_fee
        end

        trade.update!(qty: signed_qty, price: new_price, fee: new_fee)
        entry.update!(amount: new_amount, currency: "CNY")
        ext_record.update!(raw_data: record)

        results[:updated] += 1
      else
        results[:skipped] += 1
      end
    rescue => e
      results[:errors] << "update #{ext_record.external_id}: #{e.message}"
      results[:skipped] += 1
    end

    # Import dividend (op=6) and tax (op=95) as Transaction entries.
    # op=6 派息: cash inflow (negative amount)
    # op=95 缴税: cash outflow (positive amount)
    def import_cash_flow(ext_record, record)
      account = find_investment_account
      unless account
        ext_record.mark_error!("No investment account found")
        return
      end

      op = record["op"].to_s
      money = record["entry_money"].to_f
      code = record["code"].to_s.strip
      date = record["entry_date"]

      if op == "6"
        name = "派息 #{code}"
        amount = -money  # inflow
      elsif op == "95"
        name = "缴税 #{code}"
        amount = money   # outflow
      else
        ext_record.mark_skipped!("unknown cash_flow op=#{op}")
        return
      end

      entry = account.entries.create!(
        name: name,
        date: date,
        amount: amount,
        currency: "CNY",
        excluded: true,
        entryable: Transaction.new
      )

      ext_record.mark_imported!(entry)
      results[:created] += 1
    rescue => e
      ext_record.mark_error!(e.message) if ext_record.persisted?
      results[:errors] << "cash_flow #{code}: #{e.message}"
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

    # Create an interest income entry for reverse repo maturity profit.
    # Uses vid + "_interest" as external_id to avoid duplicate creation on re-sync.
    def create_repo_interest_income(account, record, interest)
      vid = record["vid"].to_s.strip
      ext_id = "#{vid}_interest"

      # Already created?
      return if ExternalRecord.exists?(source: "ths", external_id: ext_id)

      code = record["code"].to_s.strip
      rate = record["entry_price"].to_f
      date = record["entry_date"]

      entry = account.entries.create!(
        name: "逆回购利息 #{code} (利率#{rate}%)",
        date: date,
        amount: -interest,
        excluded: true,
        currency: "CNY",
        entryable: Transaction.new
      )

      ExternalRecord.create!(
        source: "ths",
        external_id: ext_id,
        family: family,
        record_type: "interest",
        raw_data: record,
        status: "imported",
        entry: entry
      )

      results[:created] += 1
    rescue => e
      results[:errors] << "repo_interest #{code}: #{e.message}"
    end

    # Trigger a single sync after all trades have been imported.
    # First-time full import: full sync (no window). Incremental: windowed from cutoff date.
    def trigger_account_sync
      return unless (account = find_investment_account)

      cutoff = incremental_cutoff_date
      if cutoff
        account.sync_later(window_start_date: Date.parse(cutoff), window_end_date: Date.current)
      else
        account.sync_later
      end
    end

    def find_investment_account
      @investment_account ||= family.accounts
        .where(accountable_type: "Investment")
        .where(status: "active")
        .first
    end
  end
end
