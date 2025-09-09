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
    
    # Get all online A-share and H-share securities
    securities = Security.online.where(country_code: ['CN', 'HK'])
    
    if securities.empty?
      Rails.logger.info("[RealtimeMarketDataJob] No A-share or H-share securities found")
      return
    end
    
    Rails.logger.info("[RealtimeMarketDataJob] Updating #{securities.count} securities")
    
    # Batch update current day prices
    update_securities_batch(securities)
    
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

  def update_securities_batch(securities)
    return unless Security.provider.present?
    
    # Convert securities to array for batch processing
    securities_array = securities.to_a
    
    # Use batch real-time data fetching
    provider = Security.provider
    Rails.logger.info("[RealtimeMarketDataJob] Provider class: #{provider.class.name}")
    Rails.logger.info("[RealtimeMarketDataJob] Provider methods: #{provider.methods.grep(/batch/)}")
    Rails.logger.info("[RealtimeMarketDataJob] respond_to? fetch_batch_realtime_data: #{provider.respond_to?(:fetch_batch_realtime_data)}")
    
    if provider.respond_to?(:fetch_batch_realtime_data)
      Rails.logger.info("[RealtimeMarketDataJob] Using batch real-time data fetching for #{securities_array.count} securities")
      batch_results = provider.fetch_batch_realtime_data(securities_array)
      Rails.logger.info("[RealtimeMarketDataJob] Batch results: #{batch_results.keys.count} securities updated")
      
      # Process batch results
      securities_array.each do |security|
        tencent_symbol = Security.provider.send(:convert_to_tencent_symbol, security.ticker, security.exchange_operating_mic)
        realtime_data = batch_results[tencent_symbol]
        
        if realtime_data.present? && realtime_data[:current_price].present?
          update_security_price_from_realtime(security, realtime_data)
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
      # Fallback to individual updates if batch method not available
      Rails.logger.warn("[RealtimeMarketDataJob] Batch method not available, falling back to individual updates")
      securities_array.each do |security|
        update_security_price(security)
      rescue => e
        Rails.logger.error("[RealtimeMarketDataJob] Failed to update #{security.ticker}: #{e.message}")
        Sentry.capture_exception(e) do |scope|
          scope.set_tags(security_id: security.id, security_ticker: security.ticker)
        end
      end
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
