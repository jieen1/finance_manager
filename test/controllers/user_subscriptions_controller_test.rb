require "test_helper"

class UserSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @subscription = user_subscriptions(:netflix)
  end

  test "index" do
    get user_subscriptions_path
    assert_response :ok
  end

  test "new" do
    get new_user_subscription_path
    assert_response :ok
  end

  test "create with valid params" do
    assert_difference "UserSubscription.count", 1 do
      post user_subscriptions_path, params: {
        user_subscription: {
          name: "New Service",
          amount: 19.99,
          currency: "USD",
          billing_cycle: "monthly",
          billing_day: 10,
          next_billing_date: "2026-04-10",
          account_id: accounts(:depository).id,
          color: "#e99537"
        }
      }
    end

    assert_redirected_to user_subscriptions_path
  end

  test "create with invalid params" do
    assert_no_difference "UserSubscription.count" do
      post user_subscriptions_path, params: {
        user_subscription: {
          name: "",
          amount: 0,
          billing_cycle: "monthly",
          billing_day: 10,
          next_billing_date: "2026-04-10",
          account_id: accounts(:depository).id
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "edit" do
    get edit_user_subscription_path(@subscription)
    assert_response :ok
  end

  test "update" do
    patch user_subscription_path(@subscription), params: {
      user_subscription: { name: "Netflix Premium" }
    }
    assert_redirected_to user_subscriptions_path
    assert_equal "Netflix Premium", @subscription.reload.name
  end

  test "destroy" do
    assert_difference "UserSubscription.count", -1 do
      delete user_subscription_path(@subscription)
    end
    assert_redirected_to user_subscriptions_path
  end

  test "toggle_status pauses active subscription" do
    assert @subscription.active?
    post toggle_status_user_subscription_path(@subscription)
    assert_redirected_to user_subscriptions_path
    assert @subscription.reload.paused?
  end

  test "toggle_status resumes paused subscription" do
    paused = user_subscriptions(:paused_sub)
    assert paused.paused?
    post toggle_status_user_subscription_path(paused)
    assert_redirected_to user_subscriptions_path
    assert paused.reload.active?
  end
end
