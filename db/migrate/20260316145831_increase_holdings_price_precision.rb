class IncreaseHoldingsPricePrecision < ActiveRecord::Migration[7.2]
  def change
    # holdings.price stores currency-converted unit price (e.g. HKD 116.6 × 0.8822 = 102.86452)
    # 4 decimals truncates to 102.8645, causing rounding errors on large positions
    change_column :holdings, :price, :decimal, precision: 19, scale: 8
  end
end
