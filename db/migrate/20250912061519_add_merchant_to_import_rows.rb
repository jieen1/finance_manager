class AddMerchantToImportRows < ActiveRecord::Migration[7.2]
  def change
    add_column :import_rows, :merchant, :string
    add_index :import_rows, :merchant
  end
end
