class LlmProvider < ApplicationRecord
  belongs_to :family

  encrypts :api_key

  ROLES = %w[main fast vision].freeze

  validates :name, :api_endpoint, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :name, uniqueness: { scope: :family_id }

  scope :enabled, -> { where(enabled: true) }
  scope :by_role, ->(role) { where(role: role).order(:priority) }
  scope :alphabetically, -> { order(:name) }

  def resolved_models
    (models || {}).values.compact.reject(&:blank?)
  end

  def supports_model?(model_name)
    resolved_models.include?(model_name)
  end

  def primary_model
    resolved_models.first
  end

  def to_provider
    Provider::GenericOpenai.new(api_key, api_endpoint: api_endpoint, models: resolved_models)
  end
end
