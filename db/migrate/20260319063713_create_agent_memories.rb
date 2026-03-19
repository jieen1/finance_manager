class CreateAgentMemories < ActiveRecord::Migration[7.2]
  def change
    create_table :agent_memories, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :memory_type, null: false
      t.string :key
      t.text :value, null: false
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :agent_memories, [:family_id, :memory_type]
    add_index :agent_memories, [:family_id, :memory_type, :key], unique: true,
              name: "index_agent_memories_unique_core_key",
              where: "memory_type = 'core'"
  end
end
