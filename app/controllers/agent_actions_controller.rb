class AgentActionsController < ApplicationController
  def index
    @breadcrumbs = [ [ "首页", root_path ], [ "操作日志", nil ] ]
    @all_actions = Current.family.agent_actions.recent.limit(100)
    @pending_actions = Current.family.agent_actions.pending_approval.recent
    @executed_actions = Current.family.agent_actions.executed.recent.limit(50)
    @failed_actions = Current.family.agent_actions.failed.recent.limit(50)
    @tab = params[:tab] || (@pending_actions.any? ? "pending" : "all")
    render layout: "settings"
  end

  def update
    @action = Current.family.agent_actions.find(params[:id])

    case params[:decision]
    when "approve"
      tool_registry = Assistant::ToolRegistry.new(Current.family)
      executor = Assistant::ToolExecutor.new(Current.user, tool_registry: tool_registry)
      begin
        @action.approve_and_execute!(executor)
        redirect_to agent_actions_path(tab: "executed"), notice: "操作已批准并执行"
      rescue => e
        redirect_to agent_actions_path(tab: "pending"), alert: "执行失败：#{e.message}"
      end
    when "reject"
      @action.reject!
      redirect_to agent_actions_path(tab: "all"), notice: "操作已拒绝"
    else
      redirect_to agent_actions_path, alert: "无效操作"
    end
  end
end
