class CreateAgentToolConfigs < ActiveRecord::Migration[7.2]
  def change
    create_table :agent_tool_configs, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :tool_name, null: false
      t.boolean :enabled, default: true
      t.string :permission_level, null: false, default: "auto"
      t.string :tier, null: false, default: "core"
      t.jsonb :config, default: {}
      t.timestamps
    end

    add_index :agent_tool_configs, [:family_id, :tool_name], unique: true
  end
end
