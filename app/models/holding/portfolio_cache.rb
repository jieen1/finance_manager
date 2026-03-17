class Holding::PortfolioCache
  attr_reader :account, :use_holdings

  class SecurityNotFound < StandardError
    def initialize(security_id, account_id)
      super("Security id=#{security_id} not found in portfolio cache for account #{account_id}.  This should not happen unless securities were preloaded incorrectly.")
    end
  end

  def initialize(account, use_holdings: false)
    @account = account
    @use_holdings = use_holdings
    load_prices
  end

  def get_trades(date: nil)
    if date.blank?
      trades
    else
      trades_by_date[date] || []
    end
  end

  # O(1) hash lookup — no DB queries, no linear scan.
  # Returns a Security::Price with amount already converted to account currency.
  def get_price(security_id, date, source: nil)
    security = @security_cache[security_id]
    raise SecurityNotFound.new(security_id, account.id) unless security

    if source.present?
      security[:prices_by_date_source][[date, source]]
    else
      security[:prices_by_date][date]
    end
  end

  def get_securities
    @security_cache.map { |_, v| v[:security] }
  end

  private
    PriceWithPriority = Data.define(:price, :priority, :source)

    def trades
      @trades ||= account.entries.includes(entryable: :security).trades.chronological.to_a
    end

    def trades_by_date
      @trades_by_date ||= trades.group_by(&:date)
    end

    def holdings
      @holdings ||= account.holdings.chronological.to_a
    end

    def collect_unique_securities
      unique_securities_from_trades = trades.map(&:entryable).map(&:security).uniq

      return unique_securities_from_trades unless use_holdings

      unique_securities_from_holdings = holdings.map(&:security).uniq

      (unique_securities_from_trades + unique_securities_from_holdings).uniq
    end

    # Loads all known prices for all securities, pre-converts currencies, and builds
    # date-indexed hashes so get_price is a pure O(1) hash lookup with zero DB hits.
    #
    # Price priority (lower = higher priority):
    #   1 – DB / provider prices
    #   2 – Trade prices
    #   3 – Holding prices
    def load_prices
      @security_cache = {}
      securities = collect_unique_securities
      return if securities.empty?

      Rails.logger.info "Preloading #{securities.size} securities for account #{account.id}"

      security_ids = securities.map(&:id)

      # 1. Batch load ALL DB prices for all securities in ONE query
      raw_db_prices = Security::Price
        .where(security_id: security_ids, date: account.start_date..Date.current)
        .to_a

      # 2. Batch load exchange rates for price→account currency conversion in ONE query
      price_currencies = raw_db_prices.map(&:currency).uniq.reject { |c| c == account.currency }
      price_dates      = raw_db_prices.map(&:date).uniq

      exchange_rate_map = if price_currencies.any? && price_dates.any?
        ExchangeRate
          .where(from_currency: price_currencies, to_currency: account.currency, date: price_dates)
          .each_with_object({}) { |r, h| h[[r.from_currency, r.date]] = r.rate }
      else
        {}
      end

      # 3. Group data by security_id for O(1) lookup
      db_prices_by_security  = raw_db_prices.group_by(&:security_id)
      trades_by_security     = trades.group_by { |t| t.entryable.security_id }
      holdings_by_security   = use_holdings ? holdings.group_by(&:security_id) : {}

      securities.each do |security|
        all_candidates = []

        (db_prices_by_security[security.id] || []).each do |price|
          all_candidates << PriceWithPriority.new(price: price, priority: 1, source: "db")
        end

        (trades_by_security[security.id] || []).each do |trade|
          all_candidates << PriceWithPriority.new(
            price: Security::Price.new(
              security: security,
              price: trade.entryable.price,
              currency: trade.entryable.currency,
              date: trade.date
            ),
            priority: 2,
            source: "trade"
          )
        end

        (holdings_by_security[security.id] || []).each do |holding|
          all_candidates << PriceWithPriority.new(
            price: Security::Price.new(
              security: security,
              price: holding.price,
              currency: holding.currency,
              date: holding.date
            ),
            priority: 3,
            source: "holding"
          )
        end

        # 4. Build date-indexed hash: pre-select best priority and pre-convert currency
        prices_by_date        = {}
        prices_by_date_source = {}

        all_candidates.group_by { |c| c.price.date }.each do |date, candidates|
          best = candidates.min_by(&:priority)
          converted = convert_to_account_currency(best.price, date, exchange_rate_map)
          prices_by_date[date] = converted if converted

          # Also index by source for source-filtered lookups
          candidates.group_by(&:source).each do |src, src_candidates|
            best_src   = src_candidates.min_by(&:priority)
            converted_src = convert_to_account_currency(best_src.price, date, exchange_rate_map)
            prices_by_date_source[[date, src]] = converted_src if converted_src
          end
        end

        @security_cache[security.id] = {
          security:              security,
          prices_by_date:        prices_by_date,
          prices_by_date_source: prices_by_date_source
        }
      end
    end

    # Convert a raw price to account currency using the pre-loaded rate map (no DB hit).
    def convert_to_account_currency(raw_price, date, exchange_rate_map)
      converted_amount = if raw_price.currency == account.currency
        raw_price.price
      else
        rate = exchange_rate_map[[raw_price.currency, date]] || 1
        raw_price.price * rate
      end

      Security::Price.new(
        security_id: raw_price.security_id,
        date: date,
        price: converted_amount,
        currency: account.currency
      )
    end
end
