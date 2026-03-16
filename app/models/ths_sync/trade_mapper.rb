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

    OP_TO_TYPE = {
      "1" => "buy",
      "2" => "sell",
      "5" => "buy",
      "35" => "sell"
    }.freeze

    def self.external_id(record)
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
      case record["op"].to_s
      when "6" then "dividend"
      when "1", "2", "5", "35" then "trade"
      else "unknown"
      end
    end

    def self.to_trade_params(record, account_id:)
      op = record["op"].to_s
      trade_type = OP_TO_TYPE[op]
      return nil unless trade_type

      market = record["market"].to_s
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
  end
end
