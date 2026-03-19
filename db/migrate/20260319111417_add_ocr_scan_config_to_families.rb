class AddOcrScanConfigToFamilies < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :ocr_scan_enabled, :boolean, default: false
    add_column :families, :ocr_scan_folder, :string
    add_column :families, :ocr_scan_account_id, :uuid
    add_column :families, :ocr_scan_interval, :integer, default: 15
    add_column :families, :ocr_scan_last_at, :datetime
  end
end
