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
  #          Exchange Rates
  # ================================

  def fetch_exchange_rate(from:, to:, date:)
    with_provider_response do
      Rails.logger.info("[TencentProvider] 获取汇率: from=#{from}, to=#{to}, date=#{date}")
      
      # 构建腾讯汇率代码
      tencent_code = build_tencent_fx_code(from, to)
      return nil unless tencent_code
      
      # 获取实时汇率数据
      response = client.get("https://qt.gtimg.cn/?q=#{tencent_code}")
      
      # 解析汇率数据
      rate_data = parse_exchange_rate_response(response.body, tencent_code)
      return nil unless rate_data
      
      # 返回标准格式的汇率数据
      Rate.new(
        date: date.to_date,
        from: from,
        to: to,
        rate: rate_data[:rate]
      )
    end
  end

  def fetch_exchange_rates(from:, to:, start_date:, end_date:)
    with_provider_response do
      Rails.logger.info("[TencentProvider] 获取汇率范围: from=#{from}, to=#{to}, start_date=#{start_date}, end_date=#{end_date}")
      
      # 腾讯接口只提供实时汇率，历史数据需要其他方式获取
      # 这里我们返回当前汇率，历史数据可以通过其他提供者补充
      current_rate = fetch_exchange_rate(from: from, to: to, date: Date.current)
      
      if current_rate
        # 为整个日期范围填充当前汇率（实际应用中可能需要更复杂的历史数据获取）
        rates = []
        start_date.upto(end_date) do |date|
          rates << Rate.new(
            date: date,
            from: from,
            to: to,
            rate: current_rate.rate
          )
        end
        rates
      else
        []
      end
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
        exchange_code = extract_exchange_code(stock["code"])
        logo_url = ::Security::LogoGenerator.generate_logo_url(
          name: stock["name"],
          symbol: normalize_symbol(stock["code"]),
          exchange_operating_mic: exchange_code
        )
        
        Rails.logger.info("[TencentProvider] 生成Security: name=#{stock["name"]}, logo_url=#{logo_url}")
        
        security = Security.new(
          symbol: normalize_symbol(stock["code"]),
          name: stock["name"],
          logo_url: logo_url,
          exchange_operating_mic: exchange_code,
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
        logo_url: ::Security::LogoGenerator.generate_logo_url(
          name: realtime_data[:name],
          symbol: symbol,
          exchange_operating_mic: exchange_operating_mic
        ),
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
  
  # 批量获取实时行情数据
  def fetch_batch_realtime_data(securities)
    return {} if securities.empty?
    
    # 构建批量查询URL，最多支持100个股票
    tencent_symbols = securities.map { |s| convert_to_tencent_symbol(s.ticker, s.exchange_operating_mic) }
    batch_size = 100
    results = {}
    
    tencent_symbols.each_slice(batch_size) do |batch|
      symbols_param = batch.join(',')
      url = "http://qt.gtimg.cn/q=#{symbols_param}"
      
      begin
        response = client.get(url)
        batch_results = parse_batch_realtime_response(response.body, batch)
        results.merge!(batch_results)
      rescue => e
        Rails.logger.error("[TencentProvider] 批量查询失败: #{e.message}")
        # 如果批量查询失败，回退到单个查询
        batch.each do |tencent_symbol|
          begin
            single_result = fetch_single_realtime_data(tencent_symbol)
            results[tencent_symbol] = single_result if single_result.present?
          rescue => single_error
            Rails.logger.error("[TencentProvider] 单个查询也失败 #{tencent_symbol}: #{single_error.message}")
          end
        end
      end
    end
    
    results
  end

  def parse_batch_realtime_response(response_body, tencent_symbols)
    results = {}
    
    tencent_symbols.each do |tencent_symbol|
      # 解析每个股票的数据
      # v_sz000858="51~五 粮 液~000858~27.78~0.18~0.65~417909~116339~~1054.52";
      match = response_body.match(/v_#{tencent_symbol}="([^"]+)"/)
      
      if match
        fields = match[1].split('~')
        results[tencent_symbol] = {
          name: fields[1],
          current_price: fields[3].to_f > 0 ? fields[3].to_f : nil,
          change: fields[4].to_f,
          change_percent: fields[5].to_f,
          volume: fields[6].to_i,
          turnover: fields[7].to_f,
          market_cap: fields[9].to_f
        }
      else
        Rails.logger.warn("[TencentProvider] 批量查询中未找到数据: #{tencent_symbol}")
      end
    end
    
    results
  end
  
  private
  
  # 构建腾讯汇率代码
  def build_tencent_fx_code(from, to)
    # 腾讯汇率代码格式：wh + 货币对代码
    # 例如：whHKDCNY, whUSDCNY
    case "#{from}#{to}".upcase
    when "HKDCNY"
      "whHKDCNY"
    when "USDCNY"
      "whUSDCNY"
    when "EURCNY"
      "whEURCNY"
    when "GBPCNY"
      "whGBPCNY"
    when "JPYCNY"
      "whJPYCNY"
    when "AUDCNY"
      "whAUDCNY"
    when "CADCNY"
      "whCADCNY"
    when "CHFCNY"
      "whCHFCNY"
    when "SGDCNY"
      "whSGDCNY"
    when "NZDCNY"
      "whNZDCNY"
    when "CNYHKD"
      "whCNYHKD"
    when "CNYUSD"
      "whCNYUSD"
    when "CNYEUR"
      "whCNYEUR"
    when "CNYGBP"
      "whCNYGBP"
    when "CNYJPY"
      "whCNYJPY"
    when "CNYAUD"
      "whCNYAUD"
    when "CNYCAD"
      "whCNYCAD"
    when "CNYCHF"
      "whCNYCHF"
    when "CNYSGD"
      "whCNYSGD"
    when "CNYNZD"
      "whCNYNZD"
    else
      Rails.logger.warn("[TencentProvider] 不支持的货币对: #{from}#{to}")
      nil
    end
  end
  
  # 解析腾讯汇率响应数据
  def parse_exchange_rate_response(response_body, tencent_code)
    # 解析格式：v_whHKDCNY="310~港元人民币~HKDCNY~0.9154~0~20250913045451~0.9136~0.9136~0.9159~0.9136~0.9154~0.9160~0.0018~0.20~0.11~0.13~-0.24~0.10~-2.53~0.9475~0.9005";
    match = response_body.match(/v_#{tencent_code}="([^"]+)"/)
    
    if match.nil?
      Rails.logger.warn("[TencentProvider] 未找到汇率数据: #{tencent_code}")
      return nil
    end
    
    fields = match[1].split('~')
    
    # 字段解析：
    # 0: 状态码 (310表示成功)
    # 1: 货币对名称
    # 2: 货币对代码
    # 3: 当前汇率
    # 5: 时间戳
    # 6: 昨收价
    # 7: 今开价
    # 8: 最高价
    # 9: 最低价
    # 10: 买一价
    # 11: 卖一价
    # 12: 涨跌额
    # 13: 涨跌幅%
    
    if fields.length < 11
      Rails.logger.warn("[TencentProvider] 汇率数据字段不完整: #{fields.length}")
      return nil
    end
    
    status_code = fields[0]
    if status_code != "310"
      Rails.logger.warn("[TencentProvider] 汇率接口返回错误状态: #{status_code}")
      return nil
    end
    
    current_rate = fields[3].to_f
    if current_rate <= 0
      Rails.logger.warn("[TencentProvider] 无效的汇率值: #{current_rate}")
      return nil
    end
    
    {
      rate: current_rate,
      change: fields[12].to_f,
      change_percent: fields[13].to_f,
      open: fields[7].to_f,
      previous_close: fields[6].to_f,
      high: fields[8].to_f,
      low: fields[9].to_f,
      timestamp: fields[5]
    }
  end
  
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


  def fetch_single_realtime_data(tencent_symbol)
    url = "http://qt.gtimg.cn/q=#{tencent_symbol}"
    response = client.get(url)
    match = response.body.match(/v_#{tencent_symbol}="([^"]+)"/)
    
    return {} if match.nil?
    
    fields = match[1].split('~')
    {
      name: fields[1],
      current_price: fields[3].to_f > 0 ? fields[3].to_f : nil,
      change: fields[4].to_f,
      change_percent: fields[5].to_f,
      volume: fields[6].to_i,
      turnover: fields[7].to_f,
      market_cap: fields[9].to_f
    }
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
