class ExternalRecord < ApplicationRecord
  belongs_to :family
  belongs_to :entry, optional: true

  scope :pending, -> { where(status: "pending") }
  scope :imported, -> { where(status: "imported") }
  scope :errored, -> { where(status: "error") }
  scope :from_ths, -> { where(source: "ths") }

  validates :source, presence: true
  validates :external_id, presence: true, uniqueness: { scope: :source }
  validates :record_type, presence: true

  def mark_imported!(entry)
    update!(status: "imported", entry: entry, error_message: nil)
  end

  def mark_error!(message)
    update!(status: "error", error_message: message)
  end

  def mark_skipped!(reason = nil)
    update!(status: "skipped", error_message: reason)
  end
end
