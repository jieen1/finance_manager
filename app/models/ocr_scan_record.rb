# 记录每张截图的 OCR 处理状态，通过 file_hash 防止重复处理。
class OcrScanRecord < ApplicationRecord
  belongs_to :family
  belongs_to :entry, optional: true

  STATUSES = %w[pending processing success failed skipped].freeze

  validates :file_name, :file_path, :file_hash, :status, presence: true
  validates :file_hash, uniqueness: { scope: :family_id }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
  scope :success, -> { where(status: "success") }
  scope :failed, -> { where(status: "failed") }
  scope :skipped, -> { where(status: "skipped") }
  scope :pending, -> { where(status: "pending") }

  def success?
    status == "success"
  end

  def failed?
    status == "failed"
  end

  def amount
    ocr_result&.dig("amount")
  end

  def merchant
    ocr_result&.dig("merchant")
  end

  def category_name
    ocr_result&.dig("category")
  end

  def recognized_date
    ocr_result&.dig("date")
  end
end
