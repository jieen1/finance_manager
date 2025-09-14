require "test_helper"

class TradeTest < ActiveSupport::TestCase
  test "build_name generates buy trade name" do
    name = Trade.build_name("buy", 10, "AAPL")
    assert_equal "Buy 10.0 shares of AAPL", name
  end

  test "build_name generates sell trade name" do
    name = Trade.build_name("sell", 5, "MSFT")
    assert_equal "Sell 5.0 shares of MSFT", name
  end

  test "build_name handles absolute value for negative quantities" do
    name = Trade.build_name("sell", -5, "GOOGL")
    assert_equal "Sell 5.0 shares of GOOGL", name
  end

  test "build_name handles decimal quantities" do
    name = Trade.build_name("buy", 0.25, "BTC")
    assert_equal "Buy 0.25 shares of BTC", name
  end

  test "validates fee is non-negative" do
    trade = Trade.new(qty: 10, price: 100, currency: "USD", fee: -5)
    assert_not trade.valid?
    assert_includes trade.errors[:fee], "must be greater than or equal to 0"
  end

  test "allows zero fee" do
    trade = Trade.new(qty: 10, price: 100, currency: "USD", fee: 0)
    assert trade.valid?
  end

  test "allows positive fee" do
    trade = Trade.new(qty: 10, price: 100, currency: "USD", fee: 5.99)
    assert trade.valid?
  end

  test "allows different currencies for price and fee" do
    trade = Trade.new(
      qty: 10, 
      price: 100, 
      currency: "USD", 
      fee: 5.99, 
      fee_currency: "EUR"
    )
    assert trade.valid?
  end

  test "defaults fee_currency to currency when not specified" do
    trade = Trade.new(qty: 10, price: 100, currency: "USD", fee: 5.99)
    trade.valid?
    assert_equal "USD", trade.fee_currency
  end

  test "fee_money uses fee_currency when available" do
    trade = Trade.new(qty: 10, price: 100, currency: "USD", fee: 5.99, fee_currency: "EUR")
    fee_money = trade.fee_money
    assert_equal "EUR", fee_money.currency.iso_code
    assert_equal 5.99, fee_money.amount
  end

  test "unrealized_gain_loss includes fee in cost basis" do
    security = securities(:aapl)
    trade = Trade.new(
      qty: 10,
      price: 100,
      fee: 9.99,
      currency: "USD",
      security: security
    )
    
    # Mock current price
    security.stubs(:current_price).returns(Money.new(11000, "USD"))
    
    gain_loss = trade.unrealized_gain_loss
    assert_not_nil gain_loss
    
    # Cost basis should include fee: (10 * 100) + 9.99 = 1009.99
    expected_cost_basis = Money.new(100999, "USD")
    assert_equal expected_cost_basis, gain_loss.previous
  end
end
