require "test_helper"

class Assistant::ToolRegistryTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @registry = Assistant::ToolRegistry.new(@family)
  end

  test "all tools are accessible" do
    assert Assistant::ToolRegistry::ALL_TOOLS.any?
    assert_includes Assistant::ToolRegistry::CORE_TOOLS, Assistant::Function::GetTransactions
    assert_includes Assistant::ToolRegistry::EXTENDED_TOOLS, Assistant::Function::CreateTransaction
  end

  test "enabled_tools respects config" do
    # categorize_transactions is disabled in fixtures
    tools = @registry.enabled_tools
    tool_names = tools.map(&:tool_name)
    assert_not_includes tool_names, "categorize_transactions"
  end

  test "enabled_tools includes tools without config" do
    tools = @registry.enabled_tools
    tool_names = tools.map(&:tool_name)
    assert_includes tool_names, "get_accounts"
  end

  test "permission_level returns config value" do
    assert_equal "confirm", @registry.permission_level("create_transaction")
  end

  test "permission_level defaults for unconfigured tools" do
    assert_equal "auto", @registry.permission_level("get_accounts")
  end

  test "permission_level defaults to confirm for write tools" do
    # create_transaction is a write tool with no explicit config override here
    # (fixture sets it to confirm, so this tests the fixture path)
    assert_equal "confirm", @registry.permission_level("create_transaction")
  end

  test "memory tools default to auto" do
    assert_equal "auto", @registry.permission_level("memory_update")
  end

  test "tool_info returns info for all tools" do
    info = @registry.tool_info
    assert info.any?
    info.each do |tool|
      assert tool[:name].present?
      assert_includes [true, false], tool[:enabled]
      assert_includes AgentToolConfig::PERMISSION_LEVELS, tool[:permission_level]
    end
  end

  test "find_tool_class finds by name" do
    klass = @registry.find_tool_class("get_transactions")
    assert_equal Assistant::Function::GetTransactions, klass
  end

  test "find_tool_class returns nil for unknown" do
    assert_nil @registry.find_tool_class("nonexistent")
  end
end
