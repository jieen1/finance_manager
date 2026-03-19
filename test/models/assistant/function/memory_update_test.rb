require "test_helper"

class Assistant::Function::MemoryUpdateTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @function = Assistant::Function::MemoryUpdate.new(@user)
    @family = families(:dylan_family)
  end

  test "creates new core memory" do
    assert_difference "AgentMemory.count", 1 do
      result = @function.call("key" => "investment_style", "value" => "偏好指数基金")
      assert result[:success]
      assert_equal "investment_style", result[:key]
    end

    memory = @family.agent_memories.core.find_by(key: "investment_style")
    assert_equal "偏好指数基金", memory.value
  end

  test "updates existing core memory" do
    assert_no_difference "AgentMemory.count" do
      result = @function.call("key" => "risk_profile", "value" => "激进型投资者")
      assert result[:success]
    end

    memory = @family.agent_memories.core.find_by(key: "risk_profile")
    assert_equal "激进型投资者", memory.value
  end
end
