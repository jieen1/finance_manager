module ThsSync
  class TradeMapper
    MARKET_TO_EXCHANGE = {
      "1" => "XSHE",   # Shenzhen
      "2" => "XSHG",   # Shanghai
      "15" => "XHKG",  # Hong Kong
      "3" => "XNAS",   # NASDAQ
      "4" => "XNYS"    # NYSE
    }.freeze

    MARKET_TO_CURRENCY = {
      "1" => "CNY",
      "2" => "CNY",
      "15" => "HKD",
      "3" => "USD",
      "4" => "USD"
    }.freeze

    # Only real stock buy/sell operations
    # op=1: 普通买入
    # op=2: 普通卖出
    # op=5: 逆回购买入 → buy
    # op=18: 转入(新股中签配售) → buy
    # op=35: 逆回购到期 → sell
    OP_TO_TYPE = {
      "1" => "buy",
      "2" => "sell",
      "5" => "buy",     # 逆回购买入
      "18" => "buy",    # 中签/转入
      "35" => "sell"    # 逆回购到期
    }.freeze

    # op=6: 派息/分红 → cash income
    # op=95: 缴税 → cash expense
    CASH_FLOW_OPS = %w[6 95].freeze

    SKIP_OPS = %w[234 19].freeze

    # Reverse repo codes: 204001(GC001), 204002(GC002), 204003(GC003), 204007(GC007),
    # 131810(R-001), 131811(R-002), etc.
    REVERSE_REPO_CODES = /\A(204\d{3}|131\d{3})\z/.freeze

    def self.external_id(record)
      record["vid"].to_s.strip
    end

    def self.record_type(record)
      op = record["op"].to_s
      return "skip" if SKIP_OPS.include?(op)
      return "cash_flow" if CASH_FLOW_OPS.include?(op)
      return "trade" if OP_TO_TYPE.key?(op)
      "unknown"
    end

    def self.reverse_repo?(record)
      record["code"].to_s.strip.match?(REVERSE_REPO_CODES)
    end

    def self.to_trade_params(record, account_id:)
      op = record["op"].to_s
      trade_type = OP_TO_TYPE[op]
      return nil unless trade_type

      market = (record["market_code"].presence || record["market"].presence).to_s
      exchange = MARKET_TO_EXCHANGE[market] || "XSHG"
      currency = MARKET_TO_CURRENCY[market] || "CNY"
      code = record["code"].to_s.strip

      return nil if code.blank? || code == "00000"

      qty = record["entry_count"].to_f.abs
      return nil if qty.zero?

      price = record["entry_price"].to_f

      # op=18 (中签/转入): price from API is always 0, look up the actual IPO price
      if op == "18" && price.zero?
        security = Security::Resolver.new(code, exchange_operating_mic: exchange).resolve
        db_price = security&.prices&.find_by(date: record["entry_date"])&.price
        return nil unless db_price&.positive? # skip if no price available at all
        price = db_price.to_f
      end

      # Reverse repo: lot price varies (1000 for 204xxx, 100 for 131xxx).
      # For sells (op=35), entry_money includes interest so we can't derive lot_price from it.
      if reverse_repo?(record)
        lot_price = if op == "5" && record["entry_money"].to_f > 0
          (record["entry_money"].to_f / qty).round(2)
        else
          code.start_with?("131") ? 100.0 : 1000.0
        end
        {
          account_id: account_id,
          date: record["entry_date"],
          type: trade_type,
          ticker: "#{code}|#{exchange}",
          qty: qty,
          price: lot_price,
          fee: record["fee_total"].to_f,
          currency: currency,
          fee_currency: "CNY"
        }
      else
        {
          account_id: account_id,
          date: record["entry_date"],
          type: trade_type,
          ticker: "#{code}|#{exchange}",
          qty: qty,
          price: price,
          fee: record["fee_total"].to_f,
          currency: currency,
          fee_currency: "CNY"
        }
      end
    end

    # For reverse repo maturity (op=35), calculate the interest income.
    # The corresponding buy (op=5) has entry_money = qty × lot_price (principal).
    # The sell (op=35) has entry_money = principal + interest.
    # We need to find the matching buy's lot_price to compute interest.
    def self.reverse_repo_interest(record, buy_lot_prices: {})
      return nil unless record["op"].to_s == "35" && reverse_repo?(record)

      qty = record["entry_count"].to_f.abs
      money = record["entry_money"].to_f
      code = record["code"].to_s.strip

      # Use the buy lot_price for this code, or infer from known conventions
      lot_price = buy_lot_prices[code] || (code.start_with?("131") ? 100.0 : 1000.0)
      principal = qty * lot_price
      interest = money - principal
      return nil if interest <= 0.001

      interest
    end
  end
end
