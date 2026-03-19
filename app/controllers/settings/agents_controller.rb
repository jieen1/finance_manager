class Settings::AgentsController < ApplicationController
  def show
    @breadcrumbs = [ [ "首页", root_path ], [ "Agent设置", nil ] ]
    @core_memories = Current.family.agent_memories.core.order(:key)
    @archival_memories = Current.family.agent_memories.archival.recent.limit(20)
    render layout: "settings"
  end

  def update
    family_attrs = agent_params.to_h

    # Parse heartbeat checklist from textarea (one item per line)
    if params.dig(:family, :agent_heartbeat_checklist_text).present?
      family_attrs[:agent_heartbeat_checklist] = params[:family][:agent_heartbeat_checklist_text]
        .split("\n").map(&:strip).reject(&:blank?)
    elsif params.dig(:family, :agent_heartbeat_checklist_text) == ""
      family_attrs[:agent_heartbeat_checklist] = []
    end

    Current.family.update!(family_attrs)

    # Handle core memory updates
    if params[:memories].present?
      params[:memories].each do |_idx, mem|
        next if mem[:key].blank?
        memory = Current.family.agent_memories.find_or_initialize_by(memory_type: "core", key: mem[:key])
        if mem[:value].blank?
          memory.destroy if memory.persisted?
        else
          memory.update!(value: mem[:value])
        end
      end
    end

    redirect_to settings_agent_path, notice: "Agent设置已更新"
  end

  private

    def agent_params
      params.require(:family).permit(
        :agent_persona, :agent_heartbeat_enabled,
        :agent_heartbeat_interval, :agent_heartbeat_active_start, :agent_heartbeat_active_end,
        :ocr_scan_enabled, :ocr_scan_folder, :ocr_scan_account_id, :ocr_scan_interval
      )
    end
end
