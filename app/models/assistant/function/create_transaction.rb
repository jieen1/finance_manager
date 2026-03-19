class Assistant::Function::CreateTransaction < Assistant::Function
  class << self
    def name
      "create_transaction"
    end

    def description
      "创建一条新的交易记录。用于手动记账、OCR识别后记账等场景。正数为支出，负数为收入。"
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: %w[date amount description],
      properties: {
        account_name: {
          type: "string",
          description: "账户名称（可选，不指定时自动使用默认现金账户）"
        },
        date: {
          type: "string",
          description: "日期 YYYY-MM-DD"
        },
        amount: {
          type: "number",
          description: "金额。正数=支出，负数=收入"
        },
        description: {
          type: "string",
          description: "交易描述/备注"
        },
        category_name: {
          type: "string",
          description: "分类名称（可选）"
        },
        merchant_name: {
          type: "string",
          description: "商家名称（可选）"
        }
      }
    )
  end

  def call(params = {})
    account = resolve_account(params["account_name"])

    category = nil
    if params["category_name"].present?
      category = family.categories.find_or_create_by!(name: params["category_name"]) do |c|
        c.color = Category::COLORS.sample
        c.lucide_icon = "circle-dashed"
      end
    end

    entry = account.entries.create!(
      date: Date.parse(params["date"]),
      name: params["description"],
      amount: params["amount"].to_d,
      currency: account.currency,
      entryable: Transaction.new(category: category)
    )

    {
      success: true,
      entry_id: entry.id,
      amount: entry.amount_money.format,
      account: account.name,
      category: category&.name,
      date: entry.date.to_s
    }
  end

  private

    def resolve_account(account_name)
      if account_name.present?
        family.accounts.visible.find_by!(name: account_name)
      else
        # Auto-select: prefer Depository (cash/checking), then CreditCard, then any non-investment asset
        family.accounts.visible.find_by(accountable_type: "Depository") ||
          family.accounts.visible.find_by(accountable_type: "CreditCard") ||
          family.accounts.visible.assets.where.not(accountable_type: "Investment").first ||
          family.accounts.visible.assets.first ||
          raise(ActiveRecord::RecordNotFound, "没有找到可用的记账账户")
      end
    end
end
