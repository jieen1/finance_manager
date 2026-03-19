class Assistant::Function::GetSubscriptions < Assistant::Function
  class << self
    def name
      "get_subscriptions"
    end

    def description
      "查询用户订阅列表，包括订阅名称、金额、扣费周期、下次扣费日期和状态。"
    end
  end

  def call(params = {})
    subs = family.user_subscriptions.alphabetically

    {
      total_count: subs.size,
      active_count: subs.active.size,
      monthly_total: subs.active.sum(&:monthly_cost).to_f,
      yearly_total: subs.active.sum(&:yearly_cost).to_f,
      subscriptions: subs.map { |s|
        {
          name: s.name,
          amount: s.amount.to_f,
          currency: s.currency,
          cycle: s.billing_cycle_label,
          next_billing: s.next_billing_date.to_s,
          status: s.status,
          account: s.account.name,
          category: s.category&.name
        }
      }
    }
  end
end
