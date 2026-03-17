require "test_helper"

class ThsSync::ImporterTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @family = families(:dylan_family)
    @account = accounts(:investment)
    @ths_session = ThsSession.create!(
      family: @family,
      userid: "test_user",
      cookies: '{"cookie": "test"}',
      status: "active"
    )
  end

  def stub_client(client)
    client.stubs(:account_list).returns({ "ex_data" => { "list" => [] } })
    client.stubs(:money_history_v2).returns({ "ex_data" => { "list" => [], "max_page" => 1 } })
    client.stubs(:stock_position).returns({ "ex_data" => { "position" => [] } })
    client.stubs(:hk_rate).returns({})
  end

  # -----------------------------------------------------------------------
  # Core invariant: entire batch triggers exactly ONE account sync
  # -----------------------------------------------------------------------
  test "triggers exactly one account sync regardless of trade count" do
    client = stub
    stub_client(client)
    ThsClient.stubs(:new).returns(client)

    ExternalRecord.where(source: "ths", family: @family).delete_all

    @account.expects(:sync_later).once

    ThsSync::Importer.any_instance.stubs(:sync_trades)
    ThsSync::Importer.any_instance.stubs(:sync_positions)
    ThsSync::Importer.any_instance.stubs(:find_investment_account).returns(@account)

    importer = ThsSync::Importer.new(@ths_session)
    importer.sync!
  end

  test "incremental sync triggers windowed sync from cutoff date" do
    ExternalRecord.create!(
      source: "ths",
      family: @family,
      external_id: "existing_#{SecureRandom.hex(4)}",
      record_type: "trade",
      raw_data: {},
      status: "imported"
    )

    client = stub
    stub_client(client)
    ThsClient.stubs(:new).returns(client)

    expected_cutoff = Date.current - 3

    @account.expects(:sync_later).with(
      window_start_date: expected_cutoff,
      window_end_date: Date.current
    ).once

    ThsSync::Importer.any_instance.stubs(:find_investment_account).returns(@account)

    importer = ThsSync::Importer.new(@ths_session)
    importer.sync!
  end

  test "first-time full sync triggers full sync (no window)" do
    ExternalRecord.where(source: "ths", family: @family).delete_all

    client = stub
    stub_client(client)
    ThsClient.stubs(:new).returns(client)

    @account.expects(:sync_later).once  # no window args = full sync

    ThsSync::Importer.any_instance.stubs(:find_investment_account).returns(@account)

    importer = ThsSync::Importer.new(@ths_session)
    importer.sync!
  end
end
