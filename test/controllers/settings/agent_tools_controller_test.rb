require "test_helper"

class Settings::AgentToolsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "index renders tool list" do
    get settings_agent_tools_path
    assert_response :ok
  end

  test "update creates or updates tool config" do
    patch settings_agent_tool_path("get_accounts"), params: {
      agent_tool_config: { enabled: false, permission_level: "confirm" }
    }
    assert_redirected_to settings_agent_tools_path

    config = families(:dylan_family).agent_tool_configs.find_by(tool_name: "get_accounts")
    assert_not config.enabled?
    assert_equal "confirm", config.permission_level
  end
end
