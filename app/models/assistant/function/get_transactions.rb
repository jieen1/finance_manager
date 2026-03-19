class Assistant::Function::GetTransactions < Assistant::Function
  include Pagy::Backend

  class << self
    def default_page_size
      50
    end

    def name
      "get_transactions"
    end

    def description
      <<~INSTRUCTIONS
        搜索用户交易记录，支持多种过滤条件。

        适用场景：查找特定交易、统计小范围交易数据。
        不适用：大时间范围分析（请用 get_income_statement）。

        支持分页，每页 #{default_page_size} 条。响应包含 total_pages、page、total_results、total_income、total_expenses。

        示例（最近30天）：
        ```
        get_transactions({ page: 1, start_date: "#{30.days.ago.to_date}", end_date: "#{Date.current}" })
        ```

        复杂示例：
        ```
        get_transactions({ page: 1, search: "海底捞", accounts: ["现金"], categories: ["餐饮"], amount: "100", amount_operator: "greater" })
        ```
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [ "order", "page", "page_size" ],
      properties: {
        page: {
          type: "integer",
          description: "Page number"
        },
        order: {
          enum: [ "asc", "desc" ],
          description: "Order of the transactions by date"
        },
        search: {
          type: "string",
          description: "Search for transactions by name"
        },
        amount: {
          type: "string",
          description: "Amount for transactions (must be used with amount_operator)"
        },
        amount_operator: {
          type: "string",
          description: "Operator for amount (must be used with amount)",
          enum: [ "equal", "less", "greater" ]
        },
        start_date: {
          type: "string",
          description: "Start date for transactions in YYYY-MM-DD format"
        },
        end_date: {
          type: "string",
          description: "End date for transactions in YYYY-MM-DD format"
        },
        accounts: {
          type: "array",
          description: "Filter transactions by account name",
          items: { enum: family_account_names },
          minItems: 1,
          uniqueItems: true
        },
        categories: {
          type: "array",
          description: "Filter transactions by category name",
          items: { enum: family_category_names },
          minItems: 1,
          uniqueItems: true
        },
        merchants: {
          type: "array",
          description: "Filter transactions by merchant name",
          items: { enum: family_merchant_names },
          minItems: 1,
          uniqueItems: true
        },
        tags: {
          type: "array",
          description: "Filter transactions by tag name",
          items: { enum: family_tag_names },
          minItems: 1,
          uniqueItems: true
        }
      }
    )
  end

  def call(params = {})
    search_params = params.except("order", "page")

    search = Transaction::Search.new(family, filters: search_params)
    transactions_query = search.transactions_scope
    pagy_query = params["order"] == "asc" ? transactions_query.chronological : transactions_query.reverse_chronological

    # By default, we give a small page size to force the AI to use filters effectively and save on tokens
    pagy, paginated_transactions = pagy(
      pagy_query.includes(
        { entry: :account },
        :category, :merchant, :tags,
        transfer_as_outflow: { inflow_transaction: { entry: :account } },
        transfer_as_inflow: { outflow_transaction: { entry: :account } }
      ),
      page: params["page"] || 1,
      limit: default_page_size
    )

    totals = search.totals

    normalized_transactions = paginated_transactions.map do |txn|
      entry = txn.entry
      {
        date: entry.date,
        amount: entry.amount.abs,
        currency: entry.currency,
        formatted_amount: entry.amount_money.abs.format,
        classification: entry.amount < 0 ? "income" : "expense",
        account: entry.account.name,
        category: txn.category&.name,
        merchant: txn.merchant&.name,
        tags: txn.tags.map(&:name),
        is_transfer: txn.transfer?
      }
    end

    {
      transactions: normalized_transactions,
      total_results: pagy.count,
      page: pagy.page,
      page_size: default_page_size,
      total_pages: pagy.pages,
      total_income: totals.income_money.format,
      total_expenses: totals.expense_money.format
    }
  end

  private
    def default_page_size
      self.class.default_page_size
    end
end
