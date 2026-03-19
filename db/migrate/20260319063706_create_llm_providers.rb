class CreateLlmProviders < ActiveRecord::Migration[7.2]
  def change
    create_table :llm_providers, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :api_endpoint, null: false
      t.string :api_key
      t.jsonb :models, default: {}
      t.string :role, null: false, default: "main"
      t.integer :priority, default: 0
      t.boolean :enabled, default: true
      t.timestamps
    end

    add_index :llm_providers, [:family_id, :role]
    add_index :llm_providers, [:family_id, :enabled]
  end
end
