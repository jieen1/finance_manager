class ThsSession < ApplicationRecord
  belongs_to :family

  scope :active, -> { where(status: "active") }

  # fund_account_mappings: { "fund_key" => "account_uuid", ... }
  # Maps THS fund accounts to system Investment accounts

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

  def account_for_fund(fund_key)
    account_id = fund_account_mappings[fund_key.to_s]
    return nil unless account_id.present?
    family.accounts.find_by(id: account_id)
  end
end
