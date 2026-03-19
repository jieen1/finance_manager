class AddAgentFieldsToFamilies < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :agent_persona, :text
    add_column :families, :agent_heartbeat_enabled, :boolean, default: false
    add_column :families, :agent_heartbeat_checklist, :jsonb, default: []
  end
end
