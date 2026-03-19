require "test_helper"

class AgentToolConfigTest < ActiveSupport::TestCase
  setup do
    @config = agent_tool_configs(:get_transactions_config)
  end

  test "valid config" do
    assert @config.valid?
  end

  test "requires tool_name" do
    @config.tool_name = nil
    assert_not @config.valid?
  end

  test "tool_name unique per family" do
    duplicate = @config.dup
    assert_not duplicate.valid?
  end

  test "requires valid permission_level" do
    @config.permission_level = "invalid"
    assert_not @config.valid?

    AgentToolConfig::PERMISSION_LEVELS.each do |level|
      @config.permission_level = level
      assert @config.valid?, "Should accept permission_level: #{level}"
    end
  end

  test "requires valid tier" do
    @config.tier = "invalid"
    assert_not @config.valid?
  end

  test "enabled scope" do
    family = families(:dylan_family)
    enabled = family.agent_tool_configs.enabled
    assert enabled.none? { |c| !c.enabled? }
  end
end
