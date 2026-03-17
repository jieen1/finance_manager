class Account::MarketDataImporter
  attr_reader :account

  def initialize(account)
    @account = account
  end

  def import_all
    import_exchange_rates
    import_security_prices
  end

  def import_exchange_rates
    return unless needs_exchange_rates?
    return unless ExchangeRate.provider

    pair_dates = {}

    # 1. ENTRY-BASED PAIRS – currencies that differ from the account currency
    account.entries
           .where.not(currency: account.currency)
           .group(:currency)
           .minimum(:date)
           .each do |source_currency, date|
      key = [ source_currency, account.currency ]
      pair_dates[key] = [ pair_dates[key], date ].compact.min
    end

    # 2. ACCOUNT-BASED PAIR – convert the account currency to the family currency (if different)
    if foreign_account?
      key = [ account.currency, account.family.currency ]
      pair_dates[key] = [ pair_dates[key], account.start_date ].compact.min
    end

    pair_dates.each do |(source, target), start_date|
      ExchangeRate.import_provider_rates(
        from: source,
        to: target,
        start_date: start_date,
        end_date: Date.current
      )
    end
  end

  def import_security_prices
    return unless Security.provider

    # Load all unique securities in one query (includes avoids N+1 on security association)
    account_securities = account.trades.includes(:security).map(&:security).uniq

    return if account_securities.empty?

    # Batch load earliest trade date per security in ONE query instead of one per security
    first_dates_by_security = account.trades.with_entry
                                            .joins(:entry)
                                            .where(entries: { account_id: account.id })
                                            .group("trades.security_id")
                                            .minimum("entries.date")

    account_securities.each do |security|
      security.import_provider_prices(
        start_date: first_dates_by_security[security.id],
        end_date: Date.current
      )

      security.import_provider_details
    end
  end

    def needs_exchange_rates?
      has_multi_currency_entries? || foreign_account?
    end

    def has_multi_currency_entries?
      account.entries.where.not(currency: account.currency).exists?
    end

    def foreign_account?
      account.currency != account.family.currency
    end
end
