class Provider::Tencent < Provider
  include ExchangeRateConcept, SecurityConcept
  
  Error = Class.new(Provider::Error)
  InvalidStockDataError = Class.new(Error)
  
  def initialize
    # 腾讯财经接口无需API密钥
  end
  
  def healthy?
    with_provider_response do
      # 测试接口可用性
      response = client.get("http://qt.gtimg.cn/q=sz000001")
      response.body.present?
    end
  end
  
  # ================================
  #           Securities
  # ================================
  
  def search_securities(symbol, country_code: nil, exchange_operating_mic: nil)
    with_provider_response do
      response = client.get("https://proxy.finance.qq.com/cgi/cgi-bin/smartbox/search") do |req|
        req.params["stockFlag"] = 1
        req.params["fundFlag"] = 1
        req.params["app"] = "official_website"
        req.params["query"] = symbol
      end
      
      data = JSON.parse(response.body)
      stocks = data.dig("stock") || []
      
      stocks.map do |stock|
        Provider::SecurityConcept::Security.new(
          symbol: normalize_symbol(stock["code"]),
          name: stock["name"],
          logo_url: nil, # 腾讯接口不提供logo
          exchange_operating_mic: extract_exchange_code(stock["code"]),
          country_code: extract_country_code(stock["code"])
        )
      end
    end
  end
  
  def fetch_security_info(symbol:, exchange_operating_mic:)
    with_provider_response do
      # 先获取实时行情数据来获取基本信息
      realtime_data = fetch_realtime_data(symbol, exchange_operating_mic)
      
      Provider::SecurityConcept::SecurityInfo.new(
        symbol: symbol,
        name: realtime_data[:name],
        links: {},
        logo_url: nil,
        description: nil,
        kind: "stock",
        exchange_operating_mic: exchange_operating_mic
      )
    end
  end
  
  def fetch_security_price(symbol:, exchange_operating_mic: nil, date:)
    with_provider_response do
      realtime_data = fetch_realtime_data(symbol, exchange_operating_mic)
      
      Provider::SecurityConcept::Price.new(
        symbol: symbol,
        date: date,
        price: realtime_data[:current_price],
        currency: get_currency_for_exchange(exchange_operating_mic),
        exchange_operating_mic: exchange_operating_mic
      )
    end
  end
  
  def fetch_security_prices(symbol:, exchange_operating_mic: nil, start_date:, end_date:)
    with_provider_response do
      tencent_symbol = convert_to_tencent_symbol(symbol, exchange_operating_mic)
      prices = []
      
      # 按年份分批获取历史数据
      start_year = start_date.year
      end_year = end_date.year
      
      (start_year..end_year).each do |year|
        year_prices = fetch_year_prices(tencent_symbol, year)
        prices.concat(year_prices)
      end
      
      # 过滤日期范围
      prices.select do |price|
        price.date >= start_date && price.date <= end_date
      end
    end
  end
  
  private
  
  def client
    @client ||= Faraday.new do |faraday|
      faraday.request(:retry, {
        max: 2,
        interval: 0.05,
        interval_randomness: 0.5,
        backoff_factor: 2
      })
      faraday.response :raise_error
      faraday.headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    end
  end
  
  # 数据转换和工具方法
  def normalize_symbol(code)
    # 将腾讯格式的代码转换为标准格式
    # sh688110 -> 688110
    # sz000001 -> 000001
    # hk00700 -> 00700
    code.gsub(/^(sh|sz|hk)/, '')
  end
  
  def extract_exchange_code(code)
    case code
    when /^sh/
      "XSHG" # 上海证券交易所
    when /^sz/
      "XSHE" # 深圳证券交易所
    when /^hk/
      "XHKG" # 香港交易所
    else
      nil
    end
  end
  
  def extract_country_code(code)
    case code
    when /^(sh|sz)/
      "CN"
    when /^hk/
      "HK"
    else
      nil
    end
  end
  
  def convert_to_tencent_symbol(symbol, exchange_operating_mic)
    case exchange_operating_mic
    when "XSHG"
      "sh#{symbol}"
    when "XSHE"
      "sz#{symbol}"
    when "XHKG"
      "hk#{symbol}"
    else
      symbol
    end
  end
  
  def get_currency_for_exchange(exchange_operating_mic)
    case exchange_operating_mic
    when "XSHG", "XSHE"
      "CNY"
    when "XHKG"
      "HKD"
    else
      "CNY"
    end
  end
  
  def get_currency_for_symbol(symbol)
    case symbol
    when /^hk/
      "HKD"
    else
      "CNY"
    end
  end
  
  def get_exchange_for_symbol(symbol)
    case symbol
    when /^sh/
      "XSHG"
    when /^sz/
      "XSHE"
    when /^hk/
      "XHKG"
    else
      nil
    end
  end
  
  # 获取实时行情数据
  def fetch_realtime_data(symbol, exchange_operating_mic)
    tencent_symbol = convert_to_tencent_symbol(symbol, exchange_operating_mic)
    response = client.get("http://qt.gtimg.cn/q=#{tencent_symbol}")
    
    # 解析腾讯返回的数据格式
    # v_sz000858="51~五 粮 液~000858~27.78~0.18~0.65~417909~116339~~1054.52";
    match = response.body.match(/v_#{tencent_symbol}="([^"]+)"/)
    return {} unless match
    
    fields = match[1].split('~')
    {
      name: fields[1],
      current_price: fields[3].to_f,
      change: fields[4].to_f,
      change_percent: fields[5].to_f,
      volume: fields[6].to_i,
      turnover: fields[7].to_f,
      market_cap: fields[9].to_f
    }
  end
  
  # 获取指定年份的历史价格数据
  def fetch_year_prices(tencent_symbol, year)
    response = client.get("http://web.ifzq.gtimg.cn/appstock/app/kline/kline") do |req|
      req.params["_var"] = "kline_day#{year}"
      req.params["param"] = "#{tencent_symbol},day,#{year}-01-01,#{year + 1}-12-31,640"
      req.params["r"] = rand.to_s
    end
    
    # 解析历史数据
    match = response.body.match(/\{.*\}/)
    return [] unless match
    
    data = JSON.parse(match[0])
    stock_data = data.dig("data", tencent_symbol, "day") || []
    
    stock_data.map do |day_data|
      Provider::SecurityConcept::Price.new(
        symbol: tencent_symbol.gsub(/^(sh|sz|hk)/, ''),
        date: Date.parse(day_data[0]),
        price: day_data[2].to_f, # 收盘价
        currency: get_currency_for_symbol(tencent_symbol),
        exchange_operating_mic: get_exchange_for_symbol(tencent_symbol)
      )
    end
  rescue => error
    Rails.logger.warn("Failed to fetch year #{year} prices for #{tencent_symbol}: #{error.message}")
    []
  end
end
