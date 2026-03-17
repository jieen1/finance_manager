require "test_helper"

class Account::ChartableTest < ActiveSupport::TestCase
  test "generates balance series and caches result" do
    account = accounts(:depository)

    # First call should hit the builder
    series1 = account.balance_series
    assert_not_nil series1

    # Second call with same params should return cached result (no new builder created)
    series2 = account.balance_series
    assert_equal series1.values.size, series2.values.size

    # Different period should create a new series
    series3 = account.balance_series(period: Period.last_90_days)
    assert_not_nil series3

    # Different view should also work
    series4 = account.balance_series(period: Period.last_90_days, view: :cash_balance)
    assert_not_nil series4
  end
end
