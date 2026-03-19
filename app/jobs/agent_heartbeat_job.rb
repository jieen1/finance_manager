class AgentHeartbeatJob < ApplicationJob
  queue_as :low_priority

  def perform
    Family.where(agent_heartbeat_enabled: true).find_each do |family|
      process_family_heartbeat(family)
    rescue => e
      Rails.logger.error "[AgentHeartbeatJob] Failed for family #{family.id}: #{e.message}"
    end
  end

  private

    def process_family_heartbeat(family)
      checklist = family.agent_heartbeat_checklist
      return if checklist.blank?

      checklist.each do |item|
        AgentAction.create!(
          family: family,
          tool_name: "heartbeat_check",
          params: { checklist_item: item },
          status: "executed",
          permission_level: "auto",
          source: "heartbeat",
          executed_at: Time.current
        )
      end

      Rails.logger.info "[AgentHeartbeatJob] Processed #{checklist.size} items for family #{family.id}"
    end
end
