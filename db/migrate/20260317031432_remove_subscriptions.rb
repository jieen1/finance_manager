class RemoveSubscriptions < ActiveRecord::Migration[7.2]
  def up
    drop_table :subscriptions, if_exists: true
    remove_column :families, :stripe_customer_id, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
