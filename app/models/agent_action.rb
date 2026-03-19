class AgentAction < ApplicationRecord
  belongs_to :family
  belongs_to :chat, optional: true
  belongs_to :message, optional: true

  STATUSES = %w[pending approved executed rejected failed].freeze
  PERMISSION_LEVELS = %w[auto confirm approve].freeze
  SOURCES = %w[chat heartbeat scheduler ocr webhook].freeze

  validates :tool_name, :status, :permission_level, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :permission_level, inclusion: { in: PERMISSION_LEVELS }
  validates :source, inclusion: { in: SOURCES }

  scope :recent, -> { order(created_at: :desc) }
  scope :pending_approval, -> { where(status: "pending") }
  scope :executed, -> { where(status: "executed") }
  scope :failed, -> { where(status: "failed") }

  def pending?
    status == "pending"
  end

  def executed?
    status == "executed"
  end

  def approve_and_execute!(executor)
    result = executor.execute_function(tool_name, params)
    update!(status: "executed", result: result, executed_at: Time.current)
    result
  rescue => e
    update!(status: "failed", error_message: e.message)
    raise
  end

  def reject!
    update!(status: "rejected")
  end
end
