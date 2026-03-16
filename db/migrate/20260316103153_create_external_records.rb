class CreateExternalRecords < ActiveRecord::Migration[7.2]
  def change
    create_table :external_records, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true
      t.string :source, null: false
      t.string :external_id, null: false
      t.string :record_type, null: false
      t.jsonb :raw_data, null: false, default: {}
      t.string :status, default: "pending"
      t.string :error_message
      t.references :entry, type: :uuid, foreign_key: true
      t.timestamps
    end

    add_index :external_records, [:source, :external_id], unique: true
    add_index :external_records, [:family_id, :source, :status]
    add_index :external_records, :status
  end
end
