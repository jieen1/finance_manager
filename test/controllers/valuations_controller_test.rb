require "test_helper"

class ValuationsControllerTest < ActionDispatch::IntegrationTest
  include EntryableResourceInterfaceTest

  setup do
    sign_in @user = users(:family_admin)
    @entry = entries(:valuation)
  end

  test "investment account cannot create reconciliation valuation" do
    account = accounts(:investment)

    assert_no_difference [ "Entry.count", "Valuation.count" ] do
      post valuations_url, params: {
        entry: {
          amount: account.balance + 100,
          date: Date.current.to_s,
          account_id: account.id
        }
      }
    end

    assert_redirected_to account_url(account)
  end

  test "updates entry with basic attributes" do
    assert_no_difference [ "Entry.count", "Valuation.count" ] do
      patch valuation_url(@entry), params: {
        entry: {
          amount: 22000,
          date: Date.current,
          notes: "Test notes"
        }
      }
    end

    assert_enqueued_with job: SyncJob

    assert_redirected_to account_url(@entry.account)

    @entry.reload
    assert_equal 22000, @entry.amount
    assert_equal "Test notes", @entry.notes
  end
end
