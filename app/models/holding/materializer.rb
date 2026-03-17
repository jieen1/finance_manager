# "Materializes" holdings (similar to a DB materialized view, but done at the app level)
# into a series of records we can easily query and join with other data.
class Holding::Materializer
  def initialize(account, strategy:, window_start_date: nil)
    @account = account
    @strategy = strategy
    @window_start_date = window_start_date
  end

  def materialize_holdings
    calculate_holdings

    Rails.logger.info("Persisting #{@holdings.size} holdings")
    persist_holdings

    # Skip purge for windowed recalculation — we only computed a subset of dates
    if strategy == :forward && !@window_start_date
      purge_stale_holdings
    end

    @holdings
  end

  private
    attr_reader :account, :strategy

    def calculate_holdings
      @holdings = calculator.calculate
    end

    def persist_holdings
      current_time = Time.now

      rows = @holdings.map { |h| h.attributes
             .slice("date", "currency", "qty", "price", "amount", "security_id")
             .merge("account_id" => account.id, "updated_at" => current_time) }

      # Batch upsert to avoid holding DB locks for too long on large datasets.
      # Each batch commits independently, giving web queries a chance to run between batches.
      rows.each_slice(2000) do |batch|
        account.holdings.upsert_all(batch, unique_by: %i[account_id security_id date currency])
      end
    end

    def purge_stale_holdings
      portfolio_security_ids = account.trades.pluck(:security_id).uniq

      # If there are no securities in the portfolio, delete all holdings
      if portfolio_security_ids.empty?
        Rails.logger.info("Clearing all holdings (no securities)")
        account.holdings.delete_all
      else
        deleted_count = account.holdings.delete_by("date < ? OR security_id NOT IN (?)", account.start_date, portfolio_security_ids)
        Rails.logger.info("Purged #{deleted_count} stale holdings") if deleted_count > 0
      end
    end

    def calculator
      if strategy == :reverse
        portfolio_snapshot = Holding::PortfolioSnapshot.new(account)
        Holding::ReverseCalculator.new(account, portfolio_snapshot: portfolio_snapshot)
      else
        Holding::ForwardCalculator.new(account, window_start_date: @window_start_date)
      end
    end
end
