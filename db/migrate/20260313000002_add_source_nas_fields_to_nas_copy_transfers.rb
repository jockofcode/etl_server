class AddSourceNasFieldsToNasCopyTransfers < ActiveRecord::Migration[8.0]
  def change
    add_reference :nas_copy_transfers, :source_nas_account,
                  foreign_key: { to_table: :nas_accounts }
    add_column :nas_copy_transfers, :source_nas_path, :string
  end
end
