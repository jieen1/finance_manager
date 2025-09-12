class AddMerchantColLabelToImports < ActiveRecord::Migration[7.2]
  def change
    add_column :imports, :merchant_col_label, :string
  end
end
