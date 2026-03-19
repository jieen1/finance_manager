require "test_helper"

class Assistant::ToolExecutorTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = families(:dylan_family)
    @registry = Assistant::ToolRegistry.new(@family)
    @executor = Assistant::ToolExecutor.new(@user, tool_registry: @registry)
  end

  test "auto permission executes immediately and logs" do
    request = mock_function_request("get_balance_sheet", "{}")

    assert_difference "AgentAction.count", 1 do
      result = @executor.execute(request)
      assert_not result[:error]
    end

    action = AgentAction.last
    assert_equal "executed", action.status
    assert_equal "auto", action.permission_level
    assert action.executed_at.present?
  end

  test "confirm permission creates pending action" do
    # Ensure create_transaction is set to confirm
    @family.agent_tool_configs.find_by(tool_name: "create_transaction")&.update!(permission_level: "confirm")
    @family.reload
    registry = Assistant::ToolRegistry.new(@family)
    executor = Assistant::ToolExecutor.new(@user, tool_registry: registry)

    request = mock_function_request("create_transaction", '{"account_name":"Checking Account","date":"2026-03-19","amount":35,"description":"test"}')

    result = nil
    assert_difference "AgentAction.count", 1 do
      result = executor.execute(request)
    end

    assert result[:pending]
    assert_equal "confirm", result[:permission_level]

    action = AgentAction.find(result[:action_id])
    assert_equal "pending", action.status
  end

  test "rate limiting blocks excessive calls" do
    request = mock_function_request("get_balance_sheet", "{}")

    # Create many recent actions to trigger rate limit
    21.times do
      AgentAction.create!(
        family: @family,
        tool_name: "get_balance_sheet",
        status: "executed",
        permission_level: "auto",
        source: "chat"
      )
    end

    result = @executor.execute(request)
    assert result[:error]
    assert_match(/频率/, result[:error])
  end

  test "amount threshold blocks large auto transactions" do
    # Set create_transaction to auto for this test
    @family.agent_tool_configs.find_by(tool_name: "create_transaction")&.update!(permission_level: "auto")
    @family.reload

    # Reinitialize with fresh registry
    registry = Assistant::ToolRegistry.new(@family)
    executor = Assistant::ToolExecutor.new(@user, tool_registry: registry)

    # Verify the permission is auto
    assert_equal "auto", registry.permission_level("create_transaction")

    request = mock_function_request("create_transaction", '{"account_name":"Checking Account","date":"2026-03-19","amount":60000,"description":"big purchase"}')

    result = executor.execute(request)
    assert result[:error], "Expected error for large amount but got: #{result.inspect}"
    assert_match(/金额/, result[:error])
  end

  test "execute_function runs the tool" do
    result = @executor.execute_function("get_balance_sheet", {})
    assert result.is_a?(Hash)
    assert result[:net_worth].present?
  end

  private

  def mock_function_request(name, args)
    Provider::LlmConcept::ChatFunctionRequest.new(
      id: "test-#{SecureRandom.hex(4)}",
      call_id: "call-#{SecureRandom.hex(4)}",
      function_name: name,
      function_args: args
    )
  end
end
