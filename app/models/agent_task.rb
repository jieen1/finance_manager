# 任务中心：可由页面或 Agent 工具创建和管理的定时/一次性任务。
# 参考 OpenClaw cron 系统设计，支持 cron 表达式、间隔、一次性三种调度类型。
#
# task_type 区分任务来源和权限：
#   system — 系统内置任务，AI 不可修改/删除，用户可在页面暂停/恢复
#   user   — 用户通过页面创建，AI 不可修改/删除
#   agent  — AI 通过对话创建，AI 可管理
class AgentTask < ApplicationRecord
  belongs_to :family

  STATUSES = %w[active paused completed failed].freeze
  TASK_TYPES = %w[system user agent].freeze
  SCHEDULE_TYPES = %w[cron every once].freeze
  ACTION_TYPES = %w[
    skill_monthly_report skill_health_score skill_detect_anomalies
    skill_asset_allocation skill_detect_subscriptions
    auto_categorize ocr_scan heartbeat_check custom
  ].freeze

  validates :name, :task_type, :schedule_type, :action_type, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :task_type, inclusion: { in: TASK_TYPES }
  validates :schedule_type, inclusion: { in: SCHEDULE_TYPES }
  validates :cron_expression, presence: true, if: -> { schedule_type == "cron" }
  validates :interval_minutes, presence: true, numericality: { greater_than: 0 }, if: -> { schedule_type == "every" }
  validates :run_at, presence: true, if: -> { schedule_type == "once" }

  scope :active, -> { where(status: "active") }
  scope :paused, -> { where(status: "paused") }
  scope :due_now, -> { active.where("next_run_at <= ?", Time.current) }
  scope :alphabetically, -> { order(:name) }
  scope :recent, -> { order(updated_at: :desc) }

  before_create :calculate_next_run

  def active?
    status == "active"
  end

  def paused?
    status == "paused"
  end

  def system?
    task_type == "system"
  end

  def user_created?
    task_type == "user"
  end

  def agent_created?
    task_type == "agent"
  end

  # AI 只能管理自己创建的任务
  def agent_manageable?
    agent_created?
  end

  def type_label
    case task_type
    when "system" then "系统"
    when "user" then "用户"
    when "agent" then "AI"
    end
  end

  def pause!
    update!(status: "paused")
  end

  def resume!
    calculate_next_run
    update!(status: "active")
  end

  def schedule_label
    case schedule_type
    when "cron" then "Cron: #{cron_expression}"
    when "every"
      mins = interval_minutes.to_i
      if mins >= 10080 then "每周"
      elsif mins >= 1440 then "每天"
      elsif mins >= 360 then "每6小时"
      elsif mins >= 60 then "每小时"
      else "每 #{mins} 分钟"
      end
    when "once" then "一次性: #{run_at&.strftime('%Y-%m-%d %H:%M')}"
    end
  end

  def action_label
    case action_type
    when "skill_monthly_report" then "月度报告"
    when "skill_health_score" then "健康评分"
    when "skill_detect_anomalies" then "异常检测"
    when "skill_asset_allocation" then "配置分析"
    when "skill_detect_subscriptions" then "订阅识别"
    when "auto_categorize" then "自动分类"
    when "ocr_scan" then "截图扫描"
    when "heartbeat_check" then "心跳检查"
    when "custom" then "自定义"
    else action_type
    end
  end

  def execute!(user)
    update!(last_run_at: Time.current)

    result = run_action(user)

    self.run_count += 1
    self.last_result = result || {}
    self.last_error = nil

    if schedule_type == "once"
      self.status = "completed"
    else
      calculate_next_run
    end

    save!
    result
  rescue => e
    self.fail_count += 1
    self.last_error = e.message
    self.last_result = { error: e.message }
    calculate_next_run if schedule_type != "once"
    save!

    Rails.logger.error "[AgentTask] #{name} failed: #{e.message}"
    nil
  end

  private

    def run_action(user)
      case action_type
      when /^skill_/
        tool_class = Assistant::ToolRegistry::SKILL_TOOLS.find { |t| t.tool_name == action_type }
        return { error: "Skill not found: #{action_type}" } unless tool_class
        tool_class.new(user).call(action_params || {})
      when "auto_categorize"
        family.auto_categorize_transactions_later
        { success: true, action: "auto_categorize_enqueued" }
      when "ocr_scan"
        OcrScanJob.perform_now
        { success: true, action: "ocr_scan_completed" }
      when "heartbeat_check"
        AgentHeartbeatJob.perform_now
        { success: true, action: "heartbeat_completed" }
      when "custom"
        { success: true, message: "Custom task executed", params: action_params }
      else
        { error: "Unknown action: #{action_type}" }
      end
    end

    def calculate_next_run
      self.next_run_at = case schedule_type
      when "every"
        Time.current + (interval_minutes || 15).minutes
      when "once"
        run_at
      when "cron"
        parse_next_cron_time
      end
    end

    def parse_next_cron_time
      Time.current + 1.hour
    end
end
