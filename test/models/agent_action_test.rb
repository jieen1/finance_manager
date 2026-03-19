require "test_helper"

class AgentActionTest < ActiveSupport::TestCase
  setup do
    @action = agent_actions(:executed_action)
    @pending = agent_actions(:pending_action)
    @family = families(:dylan_family)
  end

  test "valid action" do
    assert @action.valid?
  end

  test "requires tool_name" do
    @action.tool_name = nil
    assert_not @action.valid?
  end

  test "requires valid status" do
    @action.status = "invalid"
    assert_not @action.valid?
  end

  test "requires valid permission_level" do
    @action.permission_level = "invalid"
    assert_not @action.valid?
  end

  test "requires valid source" do
    @action.source = "invalid"
    assert_not @action.valid?
  end

  test "pending? check" do
    assert @pending.pending?
    assert_not @action.pending?
  end

  test "executed? check" do
    assert @action.executed?
    assert_not @pending.executed?
  end

  test "recent scope orders by created_at desc" do
    recent = @family.agent_actions.recent
    dates = recent.map(&:created_at)
    assert_equal dates, dates.sort.reverse
  end

  test "pending_approval scope" do
    pending = @family.agent_actions.pending_approval
    assert pending.all?(&:pending?)
  end

  test "reject! updates status" do
    @pending.reject!
    assert_equal "rejected", @pending.reload.status
  end
end
