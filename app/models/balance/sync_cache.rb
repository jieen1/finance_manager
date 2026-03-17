class Balance::SyncCache
  def initialize(account)
    @account = account
  end

  def get_valuation(date)
    converted_entries.find { |e| e.date == date && e.valuation? }
  end

  def get_holdings(date)
    converted_holdings.select { |h| h.date == date }
  end

  def get_entries(date)
    converted_entries.select { |e| e.date == date && (e.transaction? || e.trade?) }
  end

  private
    attr_reader :account

    def converted_entries
      @converted_entries ||= begin
        entries = account.entries.order(:date).to_a
        rate_map = prefetch_exchange_rates(entries)
        entries.map { |e| apply_conversion(e, rate_map) }
      end
    end

    def converted_holdings
      @converted_holdings ||= begin
        holdings = account.holdings.to_a
        rate_map = prefetch_exchange_rates(holdings)
        holdings.map { |h| apply_conversion(h, rate_map) }
      end
    end

    # Load all exchange rates needed for a set of records in ONE query.
    # Returns a hash keyed by [from_currency, date] → rate (BigDecimal).
    def prefetch_exchange_rates(records)
      foreign = records.reject { |r| r.currency == account.currency }
      return {} if foreign.empty?

      currencies = foreign.map(&:currency).uniq
      dates = foreign.map(&:date).uniq

      ExchangeRate
        .where(from_currency: currencies, to_currency: account.currency, date: dates)
        .each_with_object({}) { |r, h| h[[r.from_currency, r.date]] = r.rate }
    end

    # Convert a record's amount to account currency using the pre-loaded rate map.
    # Falls back to rate=1 (same-currency pass-through) when no rate is found.
    def apply_conversion(record, rate_map)
      return record if record.currency == account.currency

      converted = record.dup
      rate = rate_map[[record.currency, record.date]] || 1
      converted.amount = record.amount * rate
      converted.currency = account.currency
      converted
    end
end
