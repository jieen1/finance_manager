module Monetizable
  extend ActiveSupport::Concern

  class_methods do
    def monetize(*fields)
      fields.each do |field|
        define_method("#{field}_money") do |**args|
          value = self.send(field, **args)
          currency_field = "#{field}_currency"
          
          # If field has corresponding currency field, use it; otherwise use default currency
          currency = if respond_to?(currency_field) && send(currency_field).present?
                      send(currency_field)
                    else
                      monetizable_currency
                    end

          return nil if value.nil? || currency.nil?

          Money.new(value, currency)
        end
      end
    end
  end

  private
    def monetizable_currency
      currency
    end
end
