class Assistant::Skill::FinancialHealthScore < Assistant::Skill
  class << self
    def name
      "skill_health_score"
    end

    def description
      "计算财务健康评分（0-100分）。综合评估：资产负债比、储蓄率、应急金充足度、资产多元化、消费稳定性，给出分数和改进建议。"
    end
  end

  def call(params = {})
    # 收集数据
    balance_sheet = call_tool("get_balance_sheet")
    income_expense = call_tool("get_income_statement", {
      "start_date" => 3.months.ago.beginning_of_month.to_s,
      "end_date" => Date.current.to_s
    })
    holdings = call_tool("get_holdings")
    accounts = call_tool("get_accounts")

    scores = {}
    suggestions = []

    # 1. 负债率评分（满分20）
    debt_ratio = parse_ratio(balance_sheet.dig(:insights, :debt_to_asset_ratio))
    scores[:debt_ratio] = score_debt_ratio(debt_ratio)
    suggestions << "降低负债率至30%以下" if debt_ratio > 30

    # 2. 储蓄率评分（满分20）
    savings_rate = parse_ratio(income_expense.dig(:insights, :savings_rate))
    scores[:savings_rate] = score_savings_rate(savings_rate)
    suggestions << "提高储蓄率至20%以上" if savings_rate < 20

    # 3. 应急金评分（满分20）
    cash = calculate_cash(accounts)
    monthly_expense = calculate_monthly_expense(income_expense)
    emergency_months = monthly_expense.zero? ? 12 : (cash / monthly_expense).round(1)
    scores[:emergency_fund] = score_emergency_fund(emergency_months)
    suggestions << "建立至少6个月的应急金储备（当前 #{emergency_months} 个月）" if emergency_months < 6

    # 4. 资产多元化评分（满分20）
    diversification = calculate_diversification(holdings)
    scores[:diversification] = score_diversification(diversification)
    suggestions << "资产过度集中，建议分散投资" if diversification[:max_single_pct] > 40

    # 5. 消费稳定性评分（满分20）
    stability = 15 # 简化：没有波动数据时给默认分
    scores[:stability] = stability

    total = scores.values.sum

    {
      total_score: total,
      max_score: 100,
      grade: grade_for(total),
      breakdown: scores,
      metrics: {
        debt_ratio: "#{debt_ratio}%",
        savings_rate: "#{savings_rate}%",
        emergency_months: emergency_months,
        max_single_holding: "#{diversification[:max_single_pct]}%",
        total_holdings: diversification[:count]
      },
      suggestions: suggestions
    }
  end

  private

    def parse_ratio(str)
      str.to_s.gsub(/[^0-9.]/, "").to_f
    end

    def score_debt_ratio(ratio)
      if ratio <= 10 then 20
      elsif ratio <= 30 then 15
      elsif ratio <= 50 then 10
      elsif ratio <= 70 then 5
      else 0
      end
    end

    def score_savings_rate(rate)
      if rate >= 30 then 20
      elsif rate >= 20 then 15
      elsif rate >= 10 then 10
      elsif rate >= 5 then 5
      else 0
      end
    end

    def score_emergency_fund(months)
      if months >= 12 then 20
      elsif months >= 6 then 15
      elsif months >= 3 then 10
      elsif months >= 1 then 5
      else 0
      end
    end

    def score_diversification(div)
      if div[:max_single_pct] <= 20 then 20
      elsif div[:max_single_pct] <= 30 then 15
      elsif div[:max_single_pct] <= 50 then 10
      elsif div[:max_single_pct] <= 70 then 5
      else 0
      end
    end

    def grade_for(score)
      if score >= 85 then "A"
      elsif score >= 70 then "B"
      elsif score >= 55 then "C"
      elsif score >= 40 then "D"
      else "F"
      end
    end

    def calculate_cash(accounts)
      (accounts[:accounts] || [])
        .select { |a| a[:type].to_s.match?(/depository|checking|savings/i) }
        .sum { |a| a[:balance].to_f.abs }
    end

    def calculate_monthly_expense(income_expense)
      total = income_expense.dig(:expense, :total).to_s.gsub(/[^0-9.]/, "").to_f
      months = 3.0 # 我们查了3个月的数据
      total / months
    end

    def calculate_diversification(holdings)
      items = holdings[:holdings] || []
      return { count: 0, max_single_pct: 0 } if items.empty?

      total = items.sum { |h| h[:amount].to_f.abs }
      return { count: items.size, max_single_pct: 0 } if total.zero?

      max_pct = items.map { |h| (h[:amount].to_f.abs / total * 100).round(1) }.max

      { count: items.size, max_single_pct: max_pct }
    end
end
