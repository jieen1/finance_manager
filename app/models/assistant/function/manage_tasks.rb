# Agent 工具：管理任务中心的任务（创建/列表/暂停/恢复/删除）。
class Assistant::Function::ManageTasks < Assistant::Function
  class << self
    def name
      "manage_tasks"
    end

    def description
      "管理定时任务。支持：创建新任务、查看任务列表、暂停/恢复/删除任务、手动执行任务。"
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: %w[action],
      properties: {
        action: {
          type: "string",
          enum: %w[list create pause resume delete run],
          description: "操作类型"
        },
        task_id: {
          type: "string",
          description: "任务ID（pause/resume/delete/run 时需要）"
        },
        name: {
          type: "string",
          description: "任务名称（create 时需要）"
        },
        description: {
          type: "string",
          description: "任务描述"
        },
        action_type: {
          type: "string",
          description: "执行的操作类型（skill_monthly_report/skill_health_score/skill_detect_anomalies/auto_categorize/ocr_scan/custom等）"
        },
        schedule_type: {
          type: "string",
          enum: %w[every once cron],
          description: "调度类型：every=间隔执行, once=一次性, cron=Cron表达式"
        },
        interval_minutes: {
          type: "integer",
          description: "间隔分钟数（schedule_type=every 时）"
        },
        cron_expression: {
          type: "string",
          description: "Cron表达式（schedule_type=cron 时）"
        },
        run_at: {
          type: "string",
          description: "执行时间 ISO 8601（schedule_type=once 时）"
        }
      }
    )
  end

  def call(params = {})
    case params["action"]
    when "list"
      list_tasks
    when "create"
      create_task(params)
    when "pause"
      toggle_task(params["task_id"], :pause!)
    when "resume"
      toggle_task(params["task_id"], :resume!)
    when "delete"
      delete_task(params["task_id"])
    when "run"
      run_task(params["task_id"])
    else
      { error: "未知操作: #{params['action']}" }
    end
  end

  private

    def list_tasks
      tasks = family.agent_tasks.recent

      {
        total: tasks.size,
        active: tasks.count(&:active?),
        tasks: tasks.map { |t|
          {
            id: t.id,
            name: t.name,
            type: t.type_label,
            manageable: t.agent_manageable?,
            action: t.action_label,
            schedule: t.schedule_label,
            status: t.status,
            last_run: t.last_run_at&.strftime("%Y-%m-%d %H:%M"),
            next_run: t.next_run_at&.strftime("%Y-%m-%d %H:%M"),
            run_count: t.run_count
          }
        }
      }
    end

    def create_task(params)
      task = family.agent_tasks.create!(
        name: params["name"] || "Agent创建的任务",
        description: params["description"],
        task_type: "agent",
        action_type: params["action_type"] || "custom",
        schedule_type: params["schedule_type"] || "every",
        interval_minutes: params["interval_minutes"],
        cron_expression: params["cron_expression"],
        run_at: params["run_at"].present? ? Time.parse(params["run_at"]) : nil,
        action_params: params.slice("extra_params").presence || {}
      )

      { success: true, task_id: task.id, name: task.name, next_run: task.next_run_at&.strftime("%Y-%m-%d %H:%M") }
    end

    def toggle_task(task_id, method)
      task = family.agent_tasks.find(task_id)
      return { error: "无权操作：#{task.type_label}类型的任务不允许AI修改" } unless task.agent_manageable?
      task.send(method)
      { success: true, task_id: task.id, status: task.status }
    end

    def delete_task(task_id)
      task = family.agent_tasks.find(task_id)
      return { error: "无权操作：#{task.type_label}类型的任务不允许AI删除" } unless task.agent_manageable?
      task.destroy!
      { success: true, deleted: task.name }
    end

    def run_task(task_id)
      task = family.agent_tasks.find(task_id)
      result = task.execute!(user)
      { success: true, task_id: task.id, result: result }
    end
end
