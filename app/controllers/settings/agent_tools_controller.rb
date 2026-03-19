class Settings::AgentToolsController < ApplicationController
  def index
    @breadcrumbs = [ [ "首页", root_path ], [ "工具管理", nil ] ]
    @tool_registry = Assistant::ToolRegistry.new(Current.family)
    @tools = @tool_registry.tool_info
    render layout: "settings"
  end

  def update
    config = Current.family.agent_tool_configs.find_or_initialize_by(tool_name: params[:id])
    config.update!(tool_config_params)

    respond_to do |format|
      format.html { redirect_to settings_agent_tools_path, notice: "工具设置已更新" }
      format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, settings_agent_tools_path) }
    end
  end

  private

    def tool_config_params
      params.require(:agent_tool_config).permit(:enabled, :permission_level, :tier)
    end
end
