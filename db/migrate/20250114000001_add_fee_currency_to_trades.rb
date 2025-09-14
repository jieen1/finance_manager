class AddFeeCurrencyToTrades < ActiveRecord::Migration[7.0]
  def change
    add_column :trades, :fee_currency, :string
    add_index :trades, :fee_currency
  end
end
