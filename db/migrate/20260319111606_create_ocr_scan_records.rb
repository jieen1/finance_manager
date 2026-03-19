class CreateOcrScanRecords < ActiveRecord::Migration[7.2]
  def change
    create_table :ocr_scan_records, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :entry, foreign_key: true, type: :uuid

      t.string :file_name, null: false
      t.string :file_path, null: false
      t.string :file_hash, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :ocr_result, default: {}
      t.text :error_message
      t.datetime :processed_at

      t.timestamps
    end

    add_index :ocr_scan_records, [:family_id, :file_hash], unique: true
    add_index :ocr_scan_records, [:family_id, :status]
  end
end
