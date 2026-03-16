class CreateThsSessions < ActiveRecord::Migration[7.2]
  def change
    create_table :ths_sessions, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true
      t.string :userid, null: false
      t.text :cookies, null: false
      t.string :status, default: "active"
      t.datetime :expires_at
      t.datetime :last_synced_at
      t.string :last_error
      t.timestamps
    end

    add_index :ths_sessions, [:family_id, :status]
  end
end
