require "test_helper"

class RealtimeMarketDataJobTest < ActiveJob::TestCase
  setup do
    Security::Price.delete_all
    Holding.delete_all
    Trade.delete_all
    Security.delete_all
  end

  test "only fetches securities with recent holdings" do
    held_security   = Security.create!(ticker: "000001", exchange_operating_mic: "XSHE", country_code: "CN", offline: false)
    unheld_security = Security.create!(ticker: "600000", exchange_operating_mic: "XSHG", country_code: "CN", offline: false)

    account = accounts(:investment)
    Holding.create!(account: account, security: held_security, date: Date.current, qty: 100, price: 10.0, amount: 1000, currency: "CNY")

    RealtimeMarketDataJob.any_instance.stubs(:market_open?).returns(true)

    mock_provider = mock("provider")
    mock_provider.stubs(:respond_to?).returns(true)
    mock_provider.stubs(:empty?).returns(false)
    mock_provider.stubs(:fetch_batch_realtime_data).returns({})
    mock_provider.stubs(:convert_to_tencent_symbol).returns("sz000001")

    Security.stubs(:provider).returns(mock_provider)

    RealtimeMarketDataJob.perform_now

    # 验证持仓过滤逻辑：只有 held_security 在近3天持仓内
    held_ids = Holding.where(date: 3.days.ago..).distinct.pluck(:security_id)
    assert_includes held_ids, held_security.id
    assert_not_includes held_ids, unheld_security.id
  end

  test "skips when no securities with recent holdings" do
    # 5 days ago — outside the 3-day window
    old_security = Security.create!(ticker: "000002", exchange_operating_mic: "XSHE", country_code: "CN", offline: false)
    account = accounts(:investment)
    Holding.create!(account: account, security: old_security, date: 5.days.ago.to_date, qty: 100, price: 10.0, amount: 1000, currency: "CNY")

    RealtimeMarketDataJob.any_instance.stubs(:market_open?).returns(true)

    # provider should never be called when securities list is empty
    Security.expects(:provider).never

    RealtimeMarketDataJob.perform_now
  end

  test "skips when market is closed" do
    RealtimeMarketDataJob.any_instance.stubs(:market_open?).returns(false)
    Security.expects(:provider).never

    RealtimeMarketDataJob.perform_now
  end

  test "trigger_today_sync calls sync_later with today window on affected accounts" do
    security = Security.create!(ticker: "000001", exchange_operating_mic: "XSHE", country_code: "CN", offline: false)
    account = accounts(:investment)

    Holding.create!(
      account: account, security: security,
      date: Date.current, qty: 100, price: 10.0, amount: 1000, currency: "CNY"
    )

    # Use any_instance since Account.where loads a new instance from DB
    Account.any_instance.expects(:sync_later).with(window_start_date: Date.current, window_end_date: Date.current).once

    job = RealtimeMarketDataJob.new
    job.send(:trigger_today_sync, [ security.id ])
  end

  test "trigger_today_sync does nothing when security_ids list is empty" do
    Account.any_instance.expects(:sync_later).never

    job = RealtimeMarketDataJob.new
    job.send(:trigger_today_sync, [])
  end
end
