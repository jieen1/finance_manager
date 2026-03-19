require "test_helper"

class AgentActionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @pending_action = agent_actions(:pending_action)
  end

  test "index shows actions" do
    get agent_actions_path
    assert_response :ok
  end

  test "reject action" do
    patch agent_action_path(@pending_action, decision: "reject")
    assert_redirected_to agent_actions_path(tab: "all")
    assert_equal "rejected", @pending_action.reload.status
  end
end
