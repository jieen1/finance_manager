require "test_helper"

class Provider::TencentTest < ActiveSupport::TestCase
  setup do
    @provider = Provider::Tencent.new
  end

  # 模拟 Faraday 客户端，返回腾讯格式的历史K线响应
  def stub_kline_response(tencent_symbol, year, day_data)
    json_data = { "code" => 0, "msg" => "", "data" => { tencent_symbol => { "day" => day_data } } }.to_json
    body = "kline_day#{year}=#{json_data}"

    mock_response = mock("faraday_response")
    mock_response.stubs(:body).returns(body)
    mock_response
  end

  test "fetch_year_prices uses HTTPS endpoint" do
    mock_response = stub_kline_response("sz000001", 2024, [
      [ "2024-01-02", "9.390", "9.210", "9.420", "9.210", "1158366.000" ]
    ])

    # 验证请求的 URL 以 https:// 开头
    mock_client = mock("faraday_client")
    mock_client.expects(:get).with do |url, _params|
      url.start_with?("https://")
    end.returns(mock_response)

    @provider.stubs(:client).returns(mock_client)

    prices = @provider.send(:fetch_year_prices, "sz000001", 2024)

    assert_equal 1, prices.length
    assert_equal Date.parse("2024-01-02"), prices.first.date
    assert_equal 9.21, prices.first.price
    assert_equal "CNY", prices.first.currency
    assert_equal "XSHE", prices.first.exchange_operating_mic
  end

  test "fetch_year_prices parses multiple records correctly" do
    mock_response = stub_kline_response("sh600150", 2024, [
      [ "2024-03-01", "10.50", "10.80", "10.90", "10.40", "500000.000" ],
      [ "2024-03-04", "10.80", "10.70", "11.00", "10.60", "600000.000" ],
      [ "2024-03-05", "10.70", "10.90", "11.10", "10.65", "700000.000" ]
    ])

    mock_client = mock("faraday_client")
    mock_client.expects(:get).returns(mock_response)
    @provider.stubs(:client).returns(mock_client)

    prices = @provider.send(:fetch_year_prices, "sh600150", 2024)

    assert_equal 3, prices.length
    assert prices.all? { |p| p.currency == "CNY" }
    assert prices.all? { |p| p.exchange_operating_mic == "XSHG" }
    # 收盘价是 fields[2]（第3列）
    assert_equal 10.80, prices[0].price
    assert_equal 10.70, prices[1].price
    assert_equal 10.90, prices[2].price
  end

  test "fetch_year_prices returns empty array when JSON not found" do
    mock_response = mock("faraday_response")
    mock_response.stubs(:body).returns("<html>404 Not Found</html>")

    mock_client = mock("faraday_client")
    mock_client.expects(:get).returns(mock_response)
    @provider.stubs(:client).returns(mock_client)

    prices = @provider.send(:fetch_year_prices, "sz000001", 2024)

    assert_equal [], prices
  end

  test "fetch_year_prices returns empty array on network error" do
    mock_client = mock("faraday_client")
    mock_client.expects(:get).raises(Faraday::ConnectionFailed.new("getaddrinfo failed"))
    @provider.stubs(:client).returns(mock_client)

    prices = @provider.send(:fetch_year_prices, "sz000001", 2024)

    assert_equal [], prices
  end

  test "fetch_year_prices skips records with zero price" do
    mock_response = stub_kline_response("sz000001", 2024, [
      [ "2024-01-02", "0.00", "0.00", "0.00", "0.00", "0.000" ],
      [ "2024-01-03", "9.50", "9.60", "9.70", "9.40", "500000.000" ]
    ])

    mock_client = mock("faraday_client")
    mock_client.expects(:get).returns(mock_response)
    @provider.stubs(:client).returns(mock_client)

    prices = @provider.send(:fetch_year_prices, "sz000001", 2024)

    assert_equal 1, prices.length
    assert_equal Date.parse("2024-01-03"), prices.first.date
  end

  test "fetch_year_prices handles HK stocks with HKD currency" do
    mock_response = stub_kline_response("hk00700", 2024, [
      [ "2024-01-02", "300.00", "305.00", "310.00", "298.00", "10000.000" ]
    ])

    mock_client = mock("faraday_client")
    mock_client.expects(:get).returns(mock_response)
    @provider.stubs(:client).returns(mock_client)

    prices = @provider.send(:fetch_year_prices, "hk00700", 2024)

    assert_equal 1, prices.length
    assert_equal "HKD", prices.first.currency
    assert_equal "XHKG", prices.first.exchange_operating_mic
  end
end
