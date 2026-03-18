class AddAccountIdToThsSessions < ActiveRecord::Migration[7.2]
  def change
    add_reference :ths_sessions, :account, null: true, foreign_key: true, type: :uuid
  end
end
