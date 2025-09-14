require "test_helper"

class Api::V1::TradesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @api_key = @user.api_keys.create!(
      name: "Test API Key",
      scopes: ["read_write"],
      source: "web"
    )
    @account = @user.family.accounts.investments.first
    @security = securities(:aapl)
    @trade = trades(:aapl_buy)
  end

  # Index tests
  test "should get index with valid API key" do
    get api_v1_trades_url, headers: { "X-Api-Key" => @api_key.plain_key }
    assert_response :success
    
    response_data = JSON.parse(response.body)
    assert response_data["trades"].is_a?(Array)
    assert response_data["pagination"].present?
  end

  test "should filter trades by account_id" do
    get api_v1_trades_url, 
        params: { account_id: @account.id },
        headers: { "X-Api-Key" => @api_key.plain_key }
    assert_response :success
    
    response_data = JSON.parse(response.body)
    response_data["trades"].each do |trade|
      assert_equal @account.id.to_s, trade["account"]["id"]
    end
  end

  test "should filter trades by type" do
    get api_v1_trades_url,
        params: { type: "buy" },
        headers: { "X-Api-Key" => @api_key.plain_key }
    assert_response :success
    
    response_data = JSON.parse(response.body)
    response_data["trades"].each do |trade|
      assert_equal "buy", trade["type"]
    end
  end

  test "should not get index without read scope" do
    @api_key.update!(scopes: ["write"])
    
    get api_v1_trades_url, headers: { "X-Api-Key" => @api_key.plain_key }
    assert_response :forbidden
  end

  # Show tests
  test "should show trade with valid API key" do
    get api_v1_trade_url(@trade), headers: { "X-Api-Key" => @api_key.plain_key }
    assert_response :success
    
    response_data = JSON.parse(response.body)
    assert_equal @trade.id.to_s, response_data["id"]
    assert response_data["security"].present?
    assert response_data["account"].present?
  end

  test "should not show trade from different family" do
    other_trade = trades(:other_family_trade)
    
    get api_v1_trade_url(other_trade), headers: { "X-Api-Key" => @api_key.plain_key }
    assert_response :not_found
  end

  # Create tests
  test "should create trade with valid data" do
    assert_difference("Trade.count") do
      post api_v1_trades_url, 
           params: {
             trade: {
               account_id: @account.id,
               date: Date.current,
               type: "buy",
               ticker: "AAPL|XNAS",
               qty: 10,
               price: 150.00,
               fee: 9.99
             }
           },
           headers: { "X-Api-Key" => @api_key.plain_key }
    end
    assert_response :created
    
    response_data = JSON.parse(response.body)
    assert response_data["id"].present?
    assert_equal "buy", response_data["type"]
    assert_equal 10, response_data["quantity"]
  end

  test "should create trade with manual ticker" do
    assert_difference("Trade.count") do
      post api_v1_trades_url,
           params: {
             trade: {
               account_id: @account.id,
               date: Date.current,
               type: "sell",
               manual_ticker: "CUSTOM",
               qty: 5,
               price: 100.00
             }
           },
           headers: { "X-Api-Key" => @api_key.plain_key }
    end
    assert_response :created
    
    response_data = JSON.parse(response.body)
    assert_equal "sell", response_data["type"]
    assert_equal "CUSTOM", response_data["security"]["ticker"]
    assert response_data["security"]["offline"]
  end

  test "should not create trade without required fields" do
    assert_no_difference("Trade.count") do
      post api_v1_trades_url,
           params: {
             trade: {
               account_id: @account.id,
               type: "buy"
               # Missing date, qty, price, ticker
             }
           },
           headers: { "X-Api-Key" => @api_key.plain_key }
    end
    assert_response :unprocessable_entity
    
    response_data = JSON.parse(response.body)
    assert_equal "validation_failed", response_data["error"]
    assert response_data["errors"].any?
  end

  test "should not create trade without ticker information" do
    assert_no_difference("Trade.count") do
      post api_v1_trades_url,
           params: {
             trade: {
               account_id: @account.id,
               date: Date.current,
               type: "buy",
               qty: 10,
               price: 150.00
               # Missing ticker and manual_ticker
             }
           },
           headers: { "X-Api-Key" => @api_key.plain_key }
    end
    assert_response :unprocessable_entity
    
    response_data = JSON.parse(response.body)
    assert_equal "validation_failed", response_data["error"]
    assert_includes response_data["errors"], "Ticker symbol is required"
  end

  test "should not create trade without write scope" do
    @api_key.update!(scopes: ["read"])
    
    assert_no_difference("Trade.count") do
      post api_v1_trades_url,
           params: {
             trade: {
               account_id: @account.id,
               date: Date.current,
               type: "buy",
               ticker: "AAPL|XNAS",
               qty: 10,
               price: 150.00
             }
           },
           headers: { "X-Api-Key" => @api_key.plain_key }
    end
    assert_response :forbidden
  end

  test "should not create trade with invalid account" do
    assert_no_difference("Trade.count") do
      post api_v1_trades_url,
           params: {
             trade: {
               account_id: "invalid-uuid",
               date: Date.current,
               type: "buy",
               ticker: "AAPL|XNAS",
               qty: 10,
               price: 150.00
             }
           },
           headers: { "X-Api-Key" => @api_key.plain_key }
    end
    assert_response :not_found
  end

  # Update tests
  test "should update trade with valid data" do
    patch api_v1_trade_url(@trade),
          params: {
            trade: {
              qty: 15,
              price: 155.00,
              fee: 12.99
            }
          },
          headers: { "X-Api-Key" => @api_key.plain_key }
    assert_response :success
    
    response_data = JSON.parse(response.body)
    assert_equal 15, response_data["quantity"]
  end

  test "should not update trade without write scope" do
    @api_key.update!(scopes: ["read"])
    
    patch api_v1_trade_url(@trade),
          params: {
            trade: {
              qty: 15
            }
          },
          headers: { "X-Api-Key" => @api_key.plain_key }
    assert_response :forbidden
  end

  # Delete tests
  test "should delete trade" do
    assert_difference("Trade.count", -1) do
      delete api_v1_trade_url(@trade), headers: { "X-Api-Key" => @api_key.plain_key }
    end
    assert_response :success
    
    response_data = JSON.parse(response.body)
    assert_equal "Trade deleted successfully", response_data["message"]
  end

  test "should not delete trade without write scope" do
    @api_key.update!(scopes: ["read"])
    
    assert_no_difference("Trade.count") do
      delete api_v1_trade_url(@trade), headers: { "X-Api-Key" => @api_key.plain_key }
    end
    assert_response :forbidden
  end

  # Authentication tests
  test "should not access without authentication" do
    get api_v1_trades_url
    assert_response :unauthorized
  end

  test "should not access with invalid API key" do
    get api_v1_trades_url, headers: { "X-Api-Key" => "invalid-key" }
    assert_response :unauthorized
  end

  test "should not access with revoked API key" do
    @api_key.revoke!
    
    get api_v1_trades_url, headers: { "X-Api-Key" => @api_key.plain_key }
    assert_response :unauthorized
  end

  # OAuth tests
  test "should work with OAuth token" do
    oauth_app = Doorkeeper::Application.create!(
      name: "Test App",
      redirect_uri: "urn:ietf:wg:oauth:2.0:oob"
    )
    
    access_token = Doorkeeper::AccessToken.create!(
      application: oauth_app,
      resource_owner_id: @user.id,
      scopes: "read_write"
    )
    
    get api_v1_trades_url, headers: { "Authorization" => "Bearer #{access_token.plaintext_token}" }
    assert_response :success
  end
end
