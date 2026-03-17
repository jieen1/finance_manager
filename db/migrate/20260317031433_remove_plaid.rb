class RemovePlaid < ActiveRecord::Migration[7.2]
  def up
    remove_column :accounts, :plaid_account_id, if_exists: true
    drop_table :plaid_accounts, if_exists: true
    drop_table :plaid_items, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
