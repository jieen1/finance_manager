class Assistant::Function::CategorizeTransactions < Assistant::Function
  class << self
    def name
      "categorize_transactions"
    end

    def description
      "批量分类未分类的交易记录。将指定的交易设置为指定的分类。"
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: %w[category_name],
      properties: {
        category_name: {
          type: "string",
          description: "目标分类名称"
        },
        start_date: {
          type: "string",
          description: "开始日期 YYYY-MM-DD（可选，默认最近30天）"
        },
        end_date: {
          type: "string",
          description: "结束日期 YYYY-MM-DD（可选）"
        },
        match_name: {
          type: "string",
          description: "按交易名称模糊匹配（可选）"
        }
      }
    )
  end

  def call(params = {})
    category = family.categories.find_or_create_by!(name: params["category_name"]) do |c|
      c.color = Category::COLORS.sample
      c.lucide_icon = "circle-dashed"
    end

    scope = family.transactions.joins(:entry)
      .where(category_id: nil)

    if params["start_date"].present?
      scope = scope.where("entries.date >= ?", Date.parse(params["start_date"]))
    end

    if params["end_date"].present?
      scope = scope.where("entries.date <= ?", Date.parse(params["end_date"]))
    end

    if params["match_name"].present?
      scope = scope.where("entries.name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params["match_name"])}%")
    end

    count = scope.update_all(category_id: category.id)

    {
      success: true,
      categorized_count: count,
      category: category.name
    }
  end
end
