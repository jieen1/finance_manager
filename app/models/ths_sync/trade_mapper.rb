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
    # op=18: 转入(新股中签配售) → 作为买入
    OP_TO_TYPE = {
      "1" => "buy",
      "2" => "sell",
      "18" => "buy"  # 中签/转入
    }.freeze

    # Operations to completely ignore (not store as trade)
    # op=5: 逆回购买入
    # op=35: 逆回购到期卖出
    # op=6: 派息/分红
    # op=95: 缴税
    # op=234: 组合费用(code=00000)
    # op=19: 转出(弃购退款)
    SKIP_OPS = %w[5 35 6 95 234 19].freeze

    def self.external_id(record)
      # 唯一键不含fee（因为当日fee=0，次日结算后才有值，但是同一笔交易）
      parts = [
        record["account_id"] || record["fund_key"] || "default",
        record["entry_date"],
        record["entry_time"],
        record["code"],
        record["op"]
      ].map { |v| v.to_s.strip }
      parts.join("_")
    end

    def self.record_type(record)
      op = record["op"].to_s
      return "skip" if SKIP_OPS.include?(op)
      return "trade" if OP_TO_TYPE.key?(op)
      "unknown"
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

      {
        account_id: account_id,
        date: record["entry_date"],
        type: trade_type,
        ticker: "#{code}|#{exchange}",
        qty: qty,
        price: record["entry_price"].to_f,
        fee: record["fee_total"].to_f,
        currency: currency,
        fee_currency: "CNY"
      }
    end

    # Check if a trade needs fee update (fee was 0 on creation day, now has real value)
    def self.fee_changed?(existing_entry, record)
      return false unless existing_entry
      new_fee = record["fee_total"].to_f
      old_fee = existing_entry.entryable&.fee.to_f
      # Only update if new fee is non-zero and different from stored fee
      new_fee > 0 && (new_fee - old_fee).abs > 0.001
    end
  end
end
