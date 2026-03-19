class Assistant::Function::GetBudgets < Assistant::Function
  class << self
    def name
      "get_budgets"
    end

    def description
      "查询用户当前预算及执行情况。返回各分类预算金额和实际支出，用于分析是否超支。"
    end
  end

  def call(params = {})
    month = params["month"] || Date.current.strftime("%Y-%m")
    date = Date.parse("#{month}-01")
    budget = family.budgets.find_by(start_date: date.beginning_of_month)

    return { message: "#{month} 暂无预算设置" } unless budget

    {
      month: month,
      budget_categories: budget.budget_categories.includes(:category).map { |bc|
        {
          category: bc.category&.name || "未分类",
          budgeted: bc.budgeted_spending.to_f,
          actual: bc.spending.to_f,
          remaining: (bc.budgeted_spending - bc.spending).to_f,
          over_budget: bc.spending > bc.budgeted_spending
        }
      }
    }
  end
end
