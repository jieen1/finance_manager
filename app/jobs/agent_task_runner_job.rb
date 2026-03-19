# 任务调度器：定期检查所有到期任务并执行。
# 这是任务中心的核心 Job，由 sidekiq-cron 每分钟触发一次。
class AgentTaskRunnerJob < ApplicationJob
  queue_as :low_priority

  def perform
    AgentTask.due_now.find_each do |task|
      user = task.family.users.first
      next unless user

      result = task.execute!(user)

      # 记录到操作日志
      AgentAction.create!(
        family: task.family,
        tool_name: task.action_type,
        params: task.action_params || {},
        result: result || {},
        status: result ? "executed" : "failed",
        permission_level: "auto",
        source: "scheduler",
        error_message: task.last_error,
        executed_at: Time.current
      )

      Rails.logger.info "[AgentTaskRunner] Executed: #{task.name} (#{task.action_type})"
    rescue => e
      Rails.logger.error "[AgentTaskRunner] Failed task #{task.id}: #{e.message}"
    end
  end
end
