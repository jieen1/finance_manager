class SetFeeCurrencyForExistingTrades < ActiveRecord::Migration[7.0]
  def up
    # Set fee_currency to currency for existing trades where fee_currency is nil
    Trade.where(fee_currency: nil).update_all("fee_currency = currency")
  end

  def down
    # No need to rollback as fee_currency can be null
  end
end
