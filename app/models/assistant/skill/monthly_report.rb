class Assistant::Skill::MonthlyReport < Assistant::Skill
  class << self
    def name
      "skill_monthly_report"
    end

    def description
      "生成月度财务报告。自动汇总收支、资产变化、持仓表现、预算执行、异常消费等，一次调用获取完整分析。"
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [],
      properties: {
        month: {
          type: "string",
          description: "月份 YYYY-MM（默认上月）"
        }
      }
    )
  end

  def call(params = {})
    month = params["month"] || 1.month.ago.strftime("%Y-%m")
    start_date = Date.parse("#{month}-01")
    end_date = start_date.end_of_month

    # 1. 收支分析
    income_expense = call_tool("get_income_statement", {
      "start_date" => start_date.to_s,
      "end_date" => end_date.to_s
    })

    # 2. 资产负债表
    balance_sheet = call_tool("get_balance_sheet")

    # 3. 持仓明细
    holdings = call_tool("get_holdings")

    # 4. 预算执行
    budgets = call_tool("get_budgets", { "month" => month })

    # 5. 订阅汇总
    subscriptions = call_tool("get_subscriptions")

    # 6. 异常检测：找出同比上月增长超50%的分类
    prev_month = (start_date - 1.month).strftime("%Y-%m")
    prev_start = Date.parse("#{prev_month}-01")
    prev_end = prev_start.end_of_month
    prev_income_expense = call_tool("get_income_statement", {
      "start_date" => prev_start.to_s,
      "end_date" => prev_end.to_s
    })

    anomalies = detect_anomalies(income_expense, prev_income_expense)

    {
      report_month: month,
      income_expense: {
        income: income_expense[:income],
        expense: income_expense[:expense],
        savings_rate: income_expense.dig(:insights, :savings_rate)
      },
      net_worth: balance_sheet[:net_worth],
      holdings_summary: {
        total_count: holdings[:total_count],
        top_holdings: holdings[:holdings]&.first(5)
      },
      budget_execution: budgets,
      subscriptions: {
        active_count: subscriptions[:active_count],
        monthly_total: subscriptions[:monthly_total]
      },
      anomalies: anomalies
    }
  end

  private

    def detect_anomalies(current, previous)
      return [] unless current.dig(:expense, :by_category) && previous.dig(:expense, :by_category)

      current_cats = parse_categories(current[:expense][:by_category])
      prev_cats = parse_categories(previous[:expense][:by_category])

      anomalies = []
      current_cats.each do |name, amount|
        prev_amount = prev_cats[name] || 0
        next if prev_amount.zero? || amount.zero?

        change_pct = ((amount - prev_amount) / prev_amount.to_f * 100).round(1)
        if change_pct > 50
          anomalies << { category: name, current: amount, previous: prev_amount, change_percent: change_pct }
        end
      end
      anomalies
    end

    def parse_categories(by_category)
      return {} unless by_category.is_a?(Array)
      by_category.each_with_object({}) do |cat, hash|
        name = cat[:name] || cat["name"]
        total = cat[:total] || cat["total"]
        hash[name] = total.to_f if name && total
      end
    end
end
