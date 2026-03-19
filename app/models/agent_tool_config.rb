class AgentToolConfig < ApplicationRecord
  belongs_to :family

  PERMISSION_LEVELS = %w[auto confirm approve].freeze
  TIERS = %w[core extended deferred].freeze

  validates :tool_name, presence: true, uniqueness: { scope: :family_id }
  validates :permission_level, presence: true, inclusion: { in: PERMISSION_LEVELS }
  validates :tier, presence: true, inclusion: { in: TIERS }

  scope :enabled, -> { where(enabled: true) }
  scope :by_tier, ->(tier) { where(tier: tier) }
end
