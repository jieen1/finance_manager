class Assistant::Skill::QuickEntry < Assistant::Skill
  class << self
    def name
      "skill_quick_entry"
    end

    def description
      "快速批量记账。接收多条消费记录（每行一条），自动解析金额、分类、日期，批量创建交易。适用于一次性补录多笔消费。"
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: %w[entries account_name],
      properties: {
        entries: {
          type: "array",
          items: {
            type: "object",
            properties: {
              description: { type: "string", description: "消费描述" },
              amount: { type: "number", description: "金额（正数=支出）" },
              category: { type: "string", description: "分类名" },
              date: { type: "string", description: "日期 YYYY-MM-DD（默认今天）" }
            },
            required: %w[description amount]
          },
          description: "交易记录数组"
        },
        account_name: {
          type: "string",
          description: "统一使用的账户名"
        }
      }
    )
  end

  def call(params = {})
    account_name = params["account_name"]
    entries = params["entries"] || []

    results = []
    entries.each do |entry|
      result = call_tool("create_transaction", {
        "account_name" => account_name,
        "date" => entry["date"] || Date.current.to_s,
        "amount" => entry["amount"],
        "description" => entry["description"],
        "category_name" => entry["category"]
      })
      results << result
    end

    success_count = results.count { |r| r[:success] }
    total_amount = entries.sum { |e| e["amount"].to_f }

    {
      success: true,
      total_entries: entries.size,
      success_count: success_count,
      failed_count: entries.size - success_count,
      total_amount: format_amount(total_amount),
      details: results
    }
  end
end
