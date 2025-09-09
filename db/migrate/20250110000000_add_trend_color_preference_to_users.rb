class AddTrendColorPreferenceToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :trend_color_preference, :string, default: "traditional", null: false
    add_index :users, :trend_color_preference
  end
end