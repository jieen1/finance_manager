class UserSubscription < ApplicationRecord
  include Monetizable

  monetize :amount

  BILLING_CYCLES = {
    "weekly" => "每周",
    "monthly" => "每月",
    "quarterly" => "每季度",
    "yearly" => "每年"
  }.freeze

  COLORS = %w[#e99537 #4da568 #6471eb #db5a54 #df4e92 #c44fe9 #eb5429 #61c9ea #805dee #6ad28a].freeze

  belongs_to :family
  belongs_to :account
  belongs_to :category, optional: true

  validates :name, :amount, :currency, :billing_cycle, :billing_day, :next_billing_date, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :billing_cycle, inclusion: { in: BILLING_CYCLES.keys }
  validates :billing_day, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 28 }

  scope :active, -> { where(status: "active") }
  scope :paused, -> { where(status: "paused") }
  scope :due_on, ->(date) { active.where("next_billing_date <= ?", date) }
  scope :alphabetically, -> { order(:name) }

  def active?
    status == "active"
  end

  def paused?
    status == "paused"
  end

  def billing_cycle_label
    BILLING_CYCLES[billing_cycle] || billing_cycle
  end

  # Create a transaction entry for this subscription charge
  def charge!(date: nil)
    charge_date = date || next_billing_date

    entry = account.entries.create!(
      date: charge_date,
      name: name,
      amount: amount, # positive = outflow/expense
      currency: currency,
      entryable: Transaction.new(category: category)
    )

    advance_billing_date!

    entry
  end

  # Advance next_billing_date to the next cycle
  def advance_billing_date!
    new_date = case billing_cycle
    when "weekly"
      next_billing_date + 1.week
    when "monthly"
      next_month_billing_date
    when "quarterly"
      advance_months(3)
    when "yearly"
      advance_months(12)
    end

    update!(next_billing_date: new_date)
  end

  # Calculate yearly cost for display
  def yearly_cost
    case billing_cycle
    when "weekly" then amount * 52
    when "monthly" then amount * 12
    when "quarterly" then amount * 4
    when "yearly" then amount
    else amount
    end
  end

  # Calculate monthly cost for display
  def monthly_cost
    case billing_cycle
    when "weekly" then (amount * 52.0 / 12).round(2)
    when "monthly" then amount
    when "quarterly" then (amount / 3.0).round(2)
    when "yearly" then (amount / 12.0).round(2)
    else amount
    end
  end

  private

    def monetizable_currency
      currency || account&.currency || family&.currency
    end

    def next_month_billing_date
      advance_months(1)
    end

    def advance_months(months)
      target = next_billing_date >> months
      # Clamp day to billing_day, handling months with fewer days
      day = [ billing_day, Time.days_in_month(target.month, target.year) ].min
      Date.new(target.year, target.month, day)
    end
end
