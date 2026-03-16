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

      ths_session.record_sync!
      results
    rescue ThsClient::AuthError => e
      ths_session.mark_expired!(e.message)
      raise
    end

    private

    def sync_trades(client, fund_key:)
      page = 1
      loop do
        data = client.money_history(fund_key: fund_key, page: page, count: 50)
        records = data.dig("ex_data", "list") || []
        break if records.empty?

        records.each { |record| store_and_import(record) }

        break if records.size < 50
        page += 1
        break if page > 100
      end
    rescue ThsClient::ApiError => e
      results[:errors] << "money_history page=#{page}: #{e.message}"
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

      # Already imported - check if fee needs update
      if ext_record.persisted? && ext_record.status == "imported"
        maybe_update_fee(ext_record, record)
        return
      end

      ext_record.assign_attributes(
        family: family,
        record_type: rec_type,
        raw_data: record,
        status: "pending"
      )
      ext_record.save!

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

    # When fee was 0 (same-day trade before settlement), update with real fee next day
    def maybe_update_fee(ext_record, record)
      if ThsSync::TradeMapper.fee_changed?(ext_record.entry, record)
        entry = ext_record.entry
        trade = entry.entryable
        new_fee = record["fee_total"].to_f

        trade.update!(fee: new_fee)
        # Recalculate entry amount with new fee
        signed_qty = trade.qty
        fee_impact = signed_qty.positive? ? new_fee : -new_fee
        new_amount = (signed_qty * trade.price) + fee_impact
        entry.update!(amount: new_amount)

        # Update raw_data with latest values
        ext_record.update!(raw_data: record)

        entry.account.sync_later
        results[:updated] += 1
      else
        results[:skipped] += 1
      end
    rescue => e
      results[:errors] << "fee_update #{ext_record.external_id}: #{e.message}"
      results[:skipped] += 1
    end

    def find_investment_account
      @investment_account ||= family.accounts
        .where(accountable_type: "Investment")
        .where(status: "active")
        .first
    end
  end
end
