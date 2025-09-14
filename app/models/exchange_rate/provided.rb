module ExchangeRate::Provided
  extend ActiveSupport::Concern

  class_methods do
    def provider
      registry = Provider::Registry.for_concept(:exchange_rates)
      provider_name = Setting.securities_provider.to_sym
      registry.get_provider(provider_name)
    rescue => e
      Rails.logger.error("[ExchangeRate::Provided] Provider error: #{e.message}")
      nil
    end

    def find_or_fetch_rate(from:, to:, date: Date.current, cache: true)
      rate = find_by(from_currency: from, to_currency: to, date: date)
      return rate if rate&.present?
      
      provider_instance = provider
      return nil unless provider_instance.present? # No provider configured (some self-hosted apps)

      response = provider_instance.fetch_exchange_rate(from: from, to: to, date: date)

      return nil unless response&.success? # Provider error

      rate = response.data
      ExchangeRate.find_or_create_by!(
        from_currency: rate.from,
        to_currency: rate.to,
        date: rate.date,
        rate: rate.rate
      ) if cache
      rate
    end

    # @return [Integer] The number of exchange rates synced
    def import_provider_rates(from:, to:, start_date:, end_date:, clear_cache: false)
      unless provider.present?
        Rails.logger.warn("No provider configured for ExchangeRate.import_provider_rates")
        return 0
      end

      ExchangeRate::Importer.new(
        exchange_rate_provider: provider,
        from: from,
        to: to,
        start_date: start_date,
        end_date: end_date,
        clear_cache: clear_cache
      ).import_provider_rates
    end
  end
end
