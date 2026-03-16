class ThsClient
  BASE_URL = "https://tzzb.10jqka.com.cn/caishen_httpserver/tzzb"

  # Headers copied exactly from browser request sample to avoid detection
  BROWSER_HEADERS = {
    "accept" => "application/json, text/plain, */*",
    "accept-language" => "zh-CN,zh;q=0.9",
    "content-type" => "application/x-www-form-urlencoded",
    "sec-ch-ua" => '"Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"',
    "sec-ch-ua-mobile" => "?0",
    "sec-ch-ua-platform" => '"Windows"',
    "sec-fetch-dest" => "empty",
    "sec-fetch-mode" => "cors",
    "sec-fetch-site" => "same-origin",
    "Referer" => "https://tzzb.10jqka.com.cn/pc/index.html"
  }.freeze

  attr_reader :ths_session

  def initialize(ths_session)
    @ths_session = ths_session
  end

  def account_list
    post("/caishen_fund/pc/account/v1/account_list")
  end

  def money_history(fund_key:, page: 1, count: 50)
    post("/caishen_fund/pc/account/v1/get_money_history", {
      "fund_key" => fund_key.to_s,
      "sort_type" => "entry_date",
      "sort_order" => "1",
      "page" => page.to_s,
      "count" => count.to_s
    })
  end

  def stock_position(fund_key:)
    post("/caishen_fund/pc/asset/v1/stock_position", {
      "fund_key" => fund_key.to_s
    })
  end

  # Get HKD→CNY exchange rate
  def hk_rate
    post("/caishen_fund/stock_common/v1/hk_rate")
  end

  def alive?
    result = account_list
    result && result["error_code"] == "0"
  rescue
    false
  end

  private

  def post(path, extra_params = {})
    url = URI("#{BASE_URL}#{path}")
    userid = ths_session.userid

    params = {
      "terminal" => "1",
      "version" => "0.0.0",
      "userid" => userid,
      "user_id" => userid
    }.merge(extra_params)

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = Net::HTTP::Post.new(url.path)
    BROWSER_HEADERS.each { |k, v| request[k] = v }
    request["Cookie"] = ths_session.cookies
    request.body = URI.encode_www_form(params)

    response = http.request(request)

    unless response.body.start_with?("{")
      raise AuthError, "Non-JSON response (likely auth failed): #{response.body[0..100]}"
    end

    data = JSON.parse(response.body)

    if data["error_code"] != "0"
      raise ApiError, "THS error_code=#{data["error_code"]}: #{data["error_msg"]}"
    end

    data
  rescue JSON::ParserError => e
    raise ParseError, "Invalid JSON from THS: #{e.message}"
  end

  class AuthError < StandardError; end
  class ApiError < StandardError; end
  class ParseError < StandardError; end
end
