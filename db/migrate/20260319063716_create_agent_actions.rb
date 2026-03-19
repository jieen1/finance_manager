class CreateAgentActions < ActiveRecord::Migration[7.2]
  def change
    create_table :agent_actions, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :chat, type: :uuid, foreign_key: true
      t.references :message, type: :uuid, foreign_key: true
      t.string :tool_name, null: false
      t.jsonb :params, default: {}
      t.jsonb :result, default: {}
      t.string :status, null: false, default: "pending"
      t.string :permission_level, null: false, default: "auto"
      t.string :source, null: false, default: "chat"
      t.text :error_message
      t.datetime :executed_at
      t.timestamps
    end

    add_index :agent_actions, [:family_id, :created_at]
    add_index :agent_actions, :status
  end
end
