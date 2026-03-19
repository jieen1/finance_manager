require "test_helper"

class UserSubscriptionTest < ActiveSupport::TestCase
  setup do
    @subscription = user_subscriptions(:netflix)
    @family = families(:dylan_family)
    @account = accounts(:depository)
  end

  test "valid subscription" do
    assert @subscription.valid?
  end

  test "requires name" do
    @subscription.name = nil
    assert_not @subscription.valid?
  end

  test "requires positive amount" do
    @subscription.amount = 0
    assert_not @subscription.valid?

    @subscription.amount = -5
    assert_not @subscription.valid?
  end

  test "requires valid billing_cycle" do
    @subscription.billing_cycle = "invalid"
    assert_not @subscription.valid?
  end

  test "billing_day must be between 1 and 28" do
    @subscription.billing_day = 0
    assert_not @subscription.valid?

    @subscription.billing_day = 29
    assert_not @subscription.valid?

    @subscription.billing_day = 15
    assert @subscription.valid?
  end

  test "active scope returns only active subscriptions" do
    active = @family.user_subscriptions.active
    assert active.all?(&:active?)
    assert_not active.any?(&:paused?)
  end

  test "paused scope returns only paused subscriptions" do
    paused = @family.user_subscriptions.paused
    assert paused.all?(&:paused?)
  end

  test "due_on returns active subscriptions due on or before date" do
    due = UserSubscription.due_on(Date.new(2026, 3, 15))
    assert_includes due, user_subscriptions(:netflix)
    assert_not_includes due, user_subscriptions(:spotify)
    assert_not_includes due, user_subscriptions(:paused_sub)
  end

  test "billing_cycle_label returns Chinese label" do
    assert_equal "每月", @subscription.billing_cycle_label

    @subscription.billing_cycle = "yearly"
    assert_equal "每年", @subscription.billing_cycle_label

    @subscription.billing_cycle = "weekly"
    assert_equal "每周", @subscription.billing_cycle_label

    @subscription.billing_cycle = "quarterly"
    assert_equal "每季度", @subscription.billing_cycle_label
  end

  test "charge creates an entry and transaction" do
    assert_difference [ "Entry.count", "Transaction.count" ], 1 do
      entry = @subscription.charge!
      assert_equal @subscription.name, entry.name
      assert_equal @subscription.amount, entry.amount
      assert_equal @subscription.currency, entry.currency
      assert_equal @account, entry.account
      assert entry.entryable.is_a?(Transaction)
      assert_equal @subscription.category, entry.entryable.category
    end
  end

  test "charge advances next_billing_date for monthly" do
    @subscription.update!(next_billing_date: Date.new(2026, 3, 15), billing_cycle: "monthly", billing_day: 15)
    @subscription.charge!
    assert_equal Date.new(2026, 4, 15), @subscription.next_billing_date
  end

  test "charge advances next_billing_date for weekly" do
    @subscription.update!(next_billing_date: Date.new(2026, 3, 15), billing_cycle: "weekly", billing_day: 15)
    @subscription.charge!
    assert_equal Date.new(2026, 3, 22), @subscription.next_billing_date
  end

  test "charge advances next_billing_date for quarterly" do
    @subscription.update!(next_billing_date: Date.new(2026, 1, 15), billing_cycle: "quarterly", billing_day: 15)
    @subscription.charge!
    assert_equal Date.new(2026, 4, 15), @subscription.next_billing_date
  end

  test "charge advances next_billing_date for yearly" do
    @subscription.update!(next_billing_date: Date.new(2026, 3, 15), billing_cycle: "yearly", billing_day: 15)
    @subscription.charge!
    assert_equal Date.new(2027, 3, 15), @subscription.next_billing_date
  end

  test "advance handles month-end billing day" do
    @subscription.update!(next_billing_date: Date.new(2026, 1, 28), billing_cycle: "monthly", billing_day: 28)
    @subscription.charge!
    assert_equal Date.new(2026, 2, 28), @subscription.next_billing_date
  end

  test "yearly_cost calculation" do
    @subscription.billing_cycle = "monthly"
    @subscription.amount = 10
    assert_equal 120, @subscription.yearly_cost

    @subscription.billing_cycle = "yearly"
    assert_equal 10, @subscription.yearly_cost

    @subscription.billing_cycle = "weekly"
    assert_equal 520, @subscription.yearly_cost

    @subscription.billing_cycle = "quarterly"
    assert_equal 40, @subscription.yearly_cost
  end

  test "monthly_cost calculation" do
    @subscription.billing_cycle = "monthly"
    @subscription.amount = 12
    assert_equal 12, @subscription.monthly_cost

    @subscription.billing_cycle = "yearly"
    assert_equal 1, @subscription.monthly_cost

    @subscription.billing_cycle = "quarterly"
    assert_equal 4, @subscription.monthly_cost
  end

  test "belongs to family" do
    assert_equal @family, @subscription.family
  end

  test "belongs to account" do
    assert_equal @account, @subscription.account
  end

  test "family has_many user_subscriptions" do
    assert_includes @family.user_subscriptions, @subscription
  end
end
