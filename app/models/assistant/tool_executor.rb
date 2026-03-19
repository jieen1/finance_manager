class Assistant::ToolExecutor
  RATE_LIMIT_WINDOW = 1.minute
  RATE_LIMIT_MAX = 20
  AMOUNT_THRESHOLD = 50_000

  def initialize(user, tool_registry:)
    @user = user
    @family = user.family
    @tool_registry = tool_registry
  end

  def execute(function_request, source: "chat", chat: nil, message: nil)
    tool_name = function_request.function_name
    params = parse_params(function_request.function_args)
    permission = @tool_registry.permission_level(tool_name)

    # Safety guards
    guard_result = run_guards(tool_name, params, permission)
    if guard_result[:blocked]
      action = log_action(tool_name, params, permission, source, chat, message, status: "failed", error: guard_result[:message])
      return { error: guard_result[:message], action_id: action.id }
    end

    case permission
    when "auto"
      execute_and_log(tool_name, params, permission, source, chat, message)
    when "confirm", "approve"
      action = log_action(tool_name, params, permission, source, chat, message, status: "pending")
      { pending: true, action_id: action.id, permission_level: permission,
        message: "此操作需要您的#{permission == 'confirm' ? '确认' : '审批'}" }
    end
  end

  def execute_function(tool_name, params)
    tool_class = @tool_registry.find_tool_class(tool_name)
    raise "Unknown tool: #{tool_name}" unless tool_class

    tool = tool_class.new(@user)
    tool.call(params.is_a?(String) ? JSON.parse(params) : params)
  end

  private

    def execute_and_log(tool_name, params, permission, source, chat, message)
      result = execute_function(tool_name, params)
      log_action(tool_name, params, permission, source, chat, message, status: "executed", result: result)
      result
    rescue => e
      log_action(tool_name, params, permission, source, chat, message, status: "failed", error: e.message)
      { error: e.message }
    end

    def log_action(tool_name, params, permission, source, chat, message, status:, result: nil, error: nil)
      AgentAction.create!(
        family: @family,
        chat: chat,
        message: message,
        tool_name: tool_name,
        params: params,
        result: result || {},
        status: status,
        permission_level: permission,
        source: source,
        error_message: error,
        executed_at: status == "executed" ? Time.current : nil
      )
    end

    def run_guards(tool_name, params, permission)
      # Rate limiting
      recent_count = @family.agent_actions
        .where(tool_name: tool_name)
        .where("created_at > ?", RATE_LIMIT_WINDOW.ago)
        .count

      if recent_count >= RATE_LIMIT_MAX
        return { blocked: true, message: "操作频率过高，请稍后再试（#{tool_name} 最近1分钟已调用#{recent_count}次）" }
      end

      # Amount threshold for auto-execute write operations
      if permission == "auto" && params["amount"].present?
        amount = params["amount"].to_f.abs
        if amount > AMOUNT_THRESHOLD
          return { blocked: true, message: "金额较大（#{amount}），自动执行已阻止，请手动确认" }
        end
      end

      { blocked: false }
    end

    def parse_params(args)
      case args
      when String
        JSON.parse(args)
      when Hash
        args
      else
        {}
      end
    rescue JSON::ParserError
      {}
    end
end
