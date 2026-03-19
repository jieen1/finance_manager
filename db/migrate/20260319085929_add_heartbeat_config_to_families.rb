class AddHeartbeatConfigToFamilies < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :agent_heartbeat_interval, :integer, default: 30
    add_column :families, :agent_heartbeat_active_start, :string, default: "08:00"
    add_column :families, :agent_heartbeat_active_end, :string, default: "22:00"
  end
end
