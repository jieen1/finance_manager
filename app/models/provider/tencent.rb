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
        req.params["fundFlag"] = 0
        req.params["app"] = "official_website"
        req.params["query"] = symbol
      end
      
      data = JSON.parse(response.body)
      stocks = data.dig("stock") || []
      
      # 根据country_code和exchange_operating_mic过滤结果
      filtered_stocks = stocks.select do |stock|
        stock_exchange = extract_exchange_code(stock["code"])
        stock_country = extract_country_code(stock["code"])
        
        exchange_match = exchange_operating_mic.nil? || stock_exchange == exchange_operating_mic
        country_match = country_code.nil? || stock_country == country_code
        
        exchange_match && country_match
      end
      
      result = filtered_stocks.map do |stock|
        security = Security.new(
          symbol: normalize_symbol(stock["code"]),
          name: stock["name"],
          logo_url: nil, # 腾讯接口不提供logo
          exchange_operating_mic: extract_exchange_code(stock["code"]),
          country_code: extract_country_code(stock["code"])
        )
        security
      end
      
      result
    end
  end
  
  def fetch_security_info(symbol:, exchange_operating_mic:)
    with_provider_response do
      # 先获取实时行情数据来获取基本信息
      realtime_data = fetch_realtime_data(symbol, exchange_operating_mic)
      
      result = SecurityInfo.new(
        symbol: symbol,
        name: realtime_data[:name],
        links: {},
        logo_url: nil,
        description: nil,
        kind: "stock",
        exchange_operating_mic: exchange_operating_mic
      )
      
      result
    end
  end
  
  def fetch_security_price(symbol:, exchange_operating_mic:, date:)
    with_provider_response do
      Rails.logger.info("[TencentProvider] 获取证券价格: symbol=#{symbol}, exchange_operating_mic=#{exchange_operating_mic}, date=#{date}")
      
      # 对于历史价格，尝试获取历史数据
      if date < Date.current
        Rails.logger.info("[TencentProvider] 获取历史价格数据")
        historical_data = fetch_security_prices(symbol: symbol, exchange_operating_mic: exchange_operating_mic, start_date: date, end_date: date)
        Rails.logger.info("[TencentProvider] 历史数据数量: #{historical_data.length}")
        raise ProviderError, "No prices found for security #{symbol} on date #{date}" if historical_data.empty?
        return historical_data.first
      end
      
      # 对于当前日期，获取实时数据
      realtime_data = fetch_realtime_data(symbol, exchange_operating_mic)
      
      current_price = realtime_data[:current_price]
      if current_price.nil? || current_price <= 0
        Rails.logger.warn("[TencentProvider] 无效的价格数据: #{current_price}")
        raise ProviderError, "Invalid price data for security #{symbol}: #{current_price}"
      end
      
      result = Price.new(
        symbol: symbol,
        date: date,
        price: current_price,
        currency: get_currency_for_exchange(exchange_operating_mic),
        exchange_operating_mic: exchange_operating_mic
      )
      
      Rails.logger.info("[TencentProvider] 返回Price: #{result.inspect}")
      result
    end
  end
  
  def fetch_security_prices(symbol:, exchange_operating_mic:, start_date:, end_date:)
    with_provider_response do
      Rails.logger.info("[TencentProvider] 获取证券价格范围: symbol=#{symbol}, exchange_operating_mic=#{exchange_operating_mic}, start_date=#{start_date}, end_date=#{end_date}")
      
      tencent_symbol = convert_to_tencent_symbol(symbol, exchange_operating_mic)
      Rails.logger.info("[TencentProvider] 转换后的腾讯代码: #{tencent_symbol}")
      
      prices = []
      
      # 按年份分批获取历史数据
      start_year = start_date.year
      end_year = end_date.year
      
      (start_year..end_year).each do |year|
        year_prices = fetch_year_prices(tencent_symbol, year)
        prices.concat(year_prices)
      end
      
      # 过滤日期范围
      filtered_prices = prices.select do |price|
        price.date >= start_date && price.date <= end_date
      end
      
      filtered_prices
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
    # 处理688110.SH格式
    if code.include?('.')
      symbol_part, exchange_part = code.split('.')
      case exchange_part.upcase
      when "SH"
        "XSHG" # 上海证券交易所
      when "SZ"
        "XSHE" # 深圳证券交易所
      when "HK"
        "XHKG" # 香港交易所
      else
        nil
      end
    else
      # 处理腾讯格式
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
  end
  
  def extract_country_code(code)
    # 处理688110.SH格式
    if code.include?('.')
      symbol_part, exchange_part = code.split('.')
      case exchange_part.upcase
      when "SH", "SZ"
        "CN"
      when "HK"
        "HK"
      else
        nil
      end
    else
      # 处理腾讯格式
      case code
      when /^(sh|sz)/
        "CN"
      when /^hk/
        "HK"
      else
        nil
      end
    end
  end
  
  def convert_to_tencent_symbol(symbol, exchange_operating_mic)
    # 处理688110.SH这种格式
    if symbol.include?('.')
      symbol_part, exchange_part = symbol.split('.')
      case exchange_part.upcase
      when "SH"
        "sh#{symbol_part}"
      when "SZ"
        "sz#{symbol_part}"
      when "HK"
        "hk#{symbol_part}"
      else
        symbol
      end
    else
      # 使用exchange_operating_mic参数
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
    url = "http://qt.gtimg.cn/q=#{tencent_symbol}"
    response = client.get(url)
    # 解析腾讯返回的数据格式
    # v_sz000858="51~五 粮 液~000858~27.78~0.18~0.65~417909~116339~~1054.52";
    match = response.body.match(/v_#{tencent_symbol}="([^"]+)"/)
    
    if match.nil?
      Rails.logger.warn("[TencentProvider] 未找到匹配的实时数据: #{tencent_symbol}")
      return {}
    end
    
    fields = match[1].split('~')
    result = {
      name: fields[1],
      current_price: fields[3].to_f > 0 ? fields[3].to_f : nil,
      change: fields[4].to_f,
      change_percent: fields[5].to_f,
      volume: fields[6].to_i,
      turnover: fields[7].to_f,
      market_cap: fields[9].to_f
    }
    
    result
  end
  
  # 获取指定年份的历史价格数据
  def fetch_year_prices(tencent_symbol, year)
    url = "http://web.ifzq.gtimg.cn/appstock/app/kline/kline"
    params = {
      "_var" => "kline_day#{year}",
      "param" => "#{tencent_symbol},day,#{year}-01-01,#{year + 1}-12-31,640",
      "r" => rand.to_s
    }
    
    response = client.get(url, params)
    
    # 解析历史数据
    match = response.body.match(/\{.*\}/)
    if match.nil?
      Rails.logger.warn("[TencentProvider] 未找到JSON数据: #{tencent_symbol}")
      return []
    end
    
    data = JSON.parse(match[0])
    stock_data = data.dig("data", tencent_symbol, "day") || []
    
    result = stock_data.map do |day_data|
      price_value = day_data[2].to_f
      if price_value <= 0
        Rails.logger.warn("[TencentProvider] 跳过无效历史价格: #{price_value}")
        next
      end
      
      price = Price.new(
        symbol: tencent_symbol.gsub(/^(sh|sz|hk)/, ''),
        date: Date.parse(day_data[0]),
        price: price_value, # 收盘价
        currency: get_currency_for_symbol(tencent_symbol),
        exchange_operating_mic: get_exchange_for_symbol(tencent_symbol)
      )
      price
    end.compact
    
    result
  rescue => error
    Rails.logger.error("[TencentProvider] 获取#{year}年数据失败: #{tencent_symbol} - #{error.message}")
    Rails.logger.error("[TencentProvider] 错误堆栈: #{error.backtrace.first(5).join('\n')}")
    []
  end
end
