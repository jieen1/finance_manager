# This job runs during market hours to fetch real-time market data
# for A-shares and H-shares only
class RealtimeMarketDataJob < ApplicationJob
  queue_as :scheduled

  def perform
    return if Rails.env.development?
    
    # Only run during A-share and H-share market hours
    unless market_open?
      Rails.logger.debug("[RealtimeMarketDataJob] Market is closed, skipping update")
      return
    end
    
    Rails.logger.info("[RealtimeMarketDataJob] Starting real-time market data update")
    
    # Get securities with active holdings (last 3 days to cover settlement lag)
    held_security_ids = Holding.where(date: 3.days.ago..).distinct.pluck(:security_id)
    securities = Security.online.where(id: held_security_ids, country_code: [ "CN", "HK" ])
    
    if securities.empty?
      Rails.logger.info("[RealtimeMarketDataJob] No A-share or H-share securities found")
      return
    end
    
    Rails.logger.info("[RealtimeMarketDataJob] Updating #{securities.count} securities")

    # Batch update current day prices
    updated_security_ids = update_securities_batch(securities)

    # Trigger today-only sync for all accounts holding the updated securities
    trigger_today_sync(updated_security_ids) if updated_security_ids.any?

    Rails.logger.info("[RealtimeMarketDataJob] Completed real-time market data update")
  end

  private

  def market_open?
    now = Time.current.in_time_zone('Asia/Shanghai')
    
    # Check if it's a weekday (Monday = 1, Friday = 5)
    return false unless (1..5).include?(now.wday)
    
    # A-share market hours: 9:30-11:30, 13:00-15:00 (Beijing time)
    # H-share market hours: 9:30-12:00, 13:00-16:00 (Hong Kong time, same as Beijing time)
    morning_start = now.beginning_of_day + 9.hours + 30.minutes
    morning_end = now.beginning_of_day + 11.hours + 30.minutes
    afternoon_start = now.beginning_of_day + 13.hours
    afternoon_end = now.beginning_of_day + 16.hours  # H股4点收盘
    
    (now >= morning_start && now <= morning_end) || 
    (now >= afternoon_start && now <= afternoon_end)
  end

  # Returns the list of security IDs whose prices were successfully updated
  def update_securities_batch(securities)
    return [] unless Security.provider.present?

    securities_array = securities.to_a
    updated_security_ids = []

    provider = Security.provider
    Rails.logger.info("[RealtimeMarketDataJob] Provider class: #{provider.class.name}")
    Rails.logger.info("[RealtimeMarketDataJob] respond_to? fetch_batch_realtime_data: #{provider.respond_to?(:fetch_batch_realtime_data)}")

    if provider.respond_to?(:fetch_batch_realtime_data)
      Rails.logger.info("[RealtimeMarketDataJob] Using batch real-time data fetching for #{securities_array.count} securities")
      batch_results = provider.fetch_batch_realtime_data(securities_array)
      Rails.logger.info("[RealtimeMarketDataJob] Batch results: #{batch_results.keys.count} securities updated")

      securities_array.each do |security|
        tencent_symbol = Security.provider.send(:convert_to_tencent_symbol, security.ticker, security.exchange_operating_mic)
        realtime_data = batch_results[tencent_symbol]

        if realtime_data.present? && realtime_data[:current_price].present?
          update_security_price_from_realtime(security, realtime_data)
          updated_security_ids << security.id
        else
          Rails.logger.warn("[RealtimeMarketDataJob] No real-time data for #{security.ticker}")
        end
      rescue => e
        Rails.logger.error("[RealtimeMarketDataJob] Failed to update #{security.ticker}: #{e.message}")
        Sentry.capture_exception(e) do |scope|
          scope.set_tags(security_id: security.id, security_ticker: security.ticker)
        end
      end
    else
      Rails.logger.warn("[RealtimeMarketDataJob] Batch method not available, falling back to individual updates")
      securities_array.each do |security|
        update_security_price(security)
        updated_security_ids << security.id
      rescue => e
        Rails.logger.error("[RealtimeMarketDataJob] Failed to update #{security.ticker}: #{e.message}")
        Sentry.capture_exception(e) do |scope|
          scope.set_tags(security_id: security.id, security_ticker: security.ticker)
        end
      end
    end

    updated_security_ids
  end

  # Trigger a today-only windowed sync for all accounts holding the updated securities.
  # Uses window_start_date: Date.current so only today's holdings and balance are recalculated.
  def trigger_today_sync(updated_security_ids)
    account_ids = Holding
      .where(date: 3.days.ago.., security_id: updated_security_ids)
      .distinct
      .pluck(:account_id)

    Rails.logger.info("[RealtimeMarketDataJob] Triggering today-only sync for #{account_ids.size} accounts")

    Account.where(id: account_ids).each do |account|
      account.sync_later(window_start_date: Date.current, window_end_date: Date.current)
    rescue => e
      Rails.logger.error("[RealtimeMarketDataJob] Failed to trigger sync for account #{account.id}: #{e.message}")
    end
  end

  def update_security_price_from_realtime(security, realtime_data)
    # Upsert the price data using real-time data - always update the price
    price_record = Security::Price.find_or_initialize_by(
      security_id: security.id,
      date: Date.current
    )
    old_price = price_record.price
    price_record.price = realtime_data[:current_price]
    price_record.currency = get_currency_for_exchange(security.exchange_operating_mic)
    price_record.save!
    
    Rails.logger.info("[RealtimeMarketDataJob] Batch updated #{security.ticker}: #{old_price} -> #{realtime_data[:current_price]}")
  end

  def update_security_price(security)
    return unless Security.provider.present?
    
    # Fetch current day price
    response = Security.provider.fetch_security_price(
      symbol: security.ticker,
      exchange_operating_mic: security.exchange_operating_mic,
      date: Date.current
    )
    
    return unless response.success?
    
    price_data = response.data
    
    # Upsert the price data - always update the price
    price_record = Security::Price.find_or_initialize_by(
      security_id: security.id,
      date: price_data.date
    )
    old_price = price_record.price
    price_record.price = price_data.price
    price_record.currency = price_data.currency
    price_record.save!
    
    Rails.logger.info("[RealtimeMarketDataJob] Updated #{security.ticker}: #{old_price} -> #{price_data.price}")
  rescue => e
    Rails.logger.error("[RealtimeMarketDataJob] Error updating #{security.ticker}: #{e.message}")
    raise e
  end

  def get_currency_for_exchange(exchange_operating_mic)
    case exchange_operating_mic
    when "XSHG", "XSHE"
      "CNY"
    when "XHKG"
      "HKD"
    else
      "CNY"
    end
  end
end
