class ThsSession < ApplicationRecord
  belongs_to :family
  belongs_to :account, optional: true

  scope :active, -> { where(status: "active") }

  validates :userid, presence: true
  validates :cookies, presence: true

  def expired?
    status == "expired" || (expires_at.present? && expires_at < Time.current)
  end

  def mark_expired!(error_msg = nil)
    update!(status: "expired", last_error: error_msg)
  end

  def mark_active!
    update!(status: "active", last_error: nil)
  end

  def record_sync!
    update!(last_synced_at: Time.current)
  end
end
