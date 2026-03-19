class Assistant::Function::GetHoldings < Assistant::Function
  class << self
    def name
      "get_holdings"
    end

    def description
      "查询用户当前持仓明细，包括证券名称、持有数量、当前价格、市值和盈亏。用于分析投资组合。"
    end
  end

  def call(params = {})
    latest_date = family.holdings.maximum(:date) || Date.current
    holdings = family.holdings.includes(:security, :account)
      .where(date: latest_date)
      .where("qty > 0")

    {
      as_of_date: latest_date,
      total_count: holdings.size,
      holdings: holdings.map { |h|
        {
          security: h.security&.name || h.security&.ticker || "未知",
          ticker: h.security&.ticker,
          account: h.account.name,
          qty: h.qty.to_f,
          price: h.price.to_f,
          amount: h.amount.to_f,
          currency: h.currency
        }
      }
    }
  end
end
