class Trade < ApplicationRecord
  include Entryable, Monetizable

  monetize :price, :fee

  belongs_to :security

  validates :qty, presence: true
  validates :price, :currency, presence: true
  validates :fee, numericality: { greater_than_or_equal_to: 0 }

  # Set default fee value
  after_initialize :set_default_fee, if: :new_record?

  class << self
    def build_name(type, qty, ticker)
      prefix = type == "buy" ? I18n.t("trades.buy") : I18n.t("trades.sell")
      I18n.t(
        "trades.trade_name",
        prefix: prefix,
        qty: qty.to_d.abs,
        ticker: ticker
      )
    end
  end

  def unrealized_gain_loss
    return nil if qty.negative?
    current_price = security.current_price
    return nil if current_price.nil?

    current_value = current_price * qty.abs
    # Include fee in cost basis calculation
    cost_basis = (price_money * qty.abs) + fee_money

    Trend.new(
      current: current_value, 
      previous: cost_basis,
      color_preference: account.family.users.first&.trend_color_preference
    )
  end

  private

  def set_default_fee
    self.fee ||= 0
  end
end
