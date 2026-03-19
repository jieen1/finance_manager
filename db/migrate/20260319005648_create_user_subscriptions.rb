class CreateUserSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :user_subscriptions, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :category, foreign_key: true, type: :uuid

      t.string :name, null: false
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.string :currency, null: false
      t.string :billing_cycle, null: false, default: "monthly"
      t.integer :billing_day, null: false
      t.date :next_billing_date, null: false
      t.string :status, null: false, default: "active"
      t.text :notes
      t.string :color

      t.timestamps
    end

    add_index :user_subscriptions, [:family_id, :status]
    add_index :user_subscriptions, [:next_billing_date, :status]
  end
end
