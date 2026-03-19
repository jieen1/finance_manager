require "test_helper"

class Settings::AgentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "show renders agent settings page" do
    get settings_agent_path
    assert_response :ok
  end

  test "update saves persona" do
    patch settings_agent_path, params: {
      family: { agent_persona: "你是一个务实的财务管家" }
    }
    assert_redirected_to settings_agent_path
    assert_equal "你是一个务实的财务管家", families(:dylan_family).reload.agent_persona
  end

  test "update saves heartbeat setting" do
    patch settings_agent_path, params: {
      family: { agent_heartbeat_enabled: true }
    }
    assert_redirected_to settings_agent_path
    assert families(:dylan_family).reload.agent_heartbeat_enabled
  end

  test "update creates core memory" do
    assert_difference "AgentMemory.count", 1 do
      patch settings_agent_path, params: {
        family: { agent_persona: "" },
        memories: { "0" => { key: "new_key", value: "new_value" } }
      }
    end
  end
end
