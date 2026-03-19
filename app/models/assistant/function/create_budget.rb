class Assistant::Function::CreateBudget < Assistant::Function
  class << self
    def name
      "create_budget"
    end

    def description
      "为指定分类创建或更新月度预算。可以设定每月在某个分类上的预算上限。"
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: %w[category_name amount],
      properties: {
        category_name: {
          type: "string",
          description: "分类名称"
        },
        amount: {
          type: "number",
          description: "预算金额（正数）"
        },
        month: {
          type: "string",
          description: "月份 YYYY-MM（默认当月）"
        }
      }
    )
  end

  def call(params = {})
    month = params["month"] || Date.current.strftime("%Y-%m")
    date = Date.parse("#{month}-01")

    category = family.categories.find_by(name: params["category_name"])
    return { error: "分类 '#{params['category_name']}' 不存在" } unless category

    budget = family.budgets.find_or_create_by!(start_date: date.beginning_of_month) do |b|
      b.end_date = date.end_of_month
    end

    bc = budget.budget_categories.find_or_initialize_by(category: category)
    bc.budgeted_spending = params["amount"].to_d
    bc.save!

    {
      success: true,
      category: category.name,
      budgeted: bc.budgeted_spending.to_f,
      month: month
    }
  end
end
