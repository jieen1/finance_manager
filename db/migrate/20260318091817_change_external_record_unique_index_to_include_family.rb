class ChangeExternalRecordUniqueIndexToIncludeFamily < ActiveRecord::Migration[7.2]
  def change
    remove_index :external_records, [:source, :external_id]
    add_index :external_records, [:source, :external_id, :family_id], unique: true
  end
end
