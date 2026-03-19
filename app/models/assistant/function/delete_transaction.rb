class Assistant::Function::DeleteTransaction < Assistant::Function
  class << self
    def name
      "delete_transaction"
    end

    def description
      "删除指定的交易记录。需要提供交易的日期和描述来定位。此为高风险操作，默认需要审批。"
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: %w[date description],
      properties: {
        date: {
          type: "string",
          description: "交易日期 YYYY-MM-DD"
        },
        description: {
          type: "string",
          description: "交易描述/名称（模糊匹配）"
        },
        account_name: {
          type: "string",
          description: "账户名称（可选，用于精确匹配）"
        }
      }
    )
  end

  def call(params = {})
    scope = family.entries.where(date: Date.parse(params["date"]))
      .where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params["description"])}%")

    if params["account_name"].present?
      account = family.accounts.find_by(name: params["account_name"])
      scope = scope.where(account: account) if account
    end

    entries = scope.limit(5)

    if entries.empty?
      return { error: "未找到匹配的交易记录" }
    end

    if entries.size > 1
      return {
        error: "找到多条匹配记录，请提供更精确的信息",
        matches: entries.map { |e| { date: e.date.to_s, name: e.name, amount: e.amount.to_f, account: e.account.name } }
      }
    end

    entry = entries.first
    entry.destroy!

    { success: true, deleted: { date: entry.date.to_s, name: entry.name, amount: entry.amount.to_f } }
  end
end
