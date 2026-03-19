class AgentMemory < ApplicationRecord
  belongs_to :family

  MEMORY_TYPES = %w[core archival].freeze

  validates :memory_type, presence: true, inclusion: { in: MEMORY_TYPES }
  validates :value, presence: true
  validates :key, presence: true, uniqueness: { scope: [ :family_id, :memory_type ] }, if: :core?

  scope :core, -> { where(memory_type: "core") }
  scope :archival, -> { where(memory_type: "archival") }
  scope :recent, -> { order(updated_at: :desc) }
  scope :search, ->(query) { where("value ILIKE ?", "%#{sanitize_sql_like(query)}%") }

  def core?
    memory_type == "core"
  end

  def archival?
    memory_type == "archival"
  end
end
