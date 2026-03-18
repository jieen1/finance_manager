class ReplaceThsSessionAccountIdWithMappings < ActiveRecord::Migration[7.2]
  def change
    add_column :ths_sessions, :fund_account_mappings, :jsonb, default: {}
    remove_reference :ths_sessions, :account, foreign_key: true, type: :uuid
  end
end
