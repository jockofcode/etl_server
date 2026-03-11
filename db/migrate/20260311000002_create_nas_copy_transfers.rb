class CreateNasCopyTransfers < ActiveRecord::Migration[8.0]
  def change
    create_table :nas_copy_transfers do |t|
      t.integer :user_id, null: false
      t.string  :local_path, null: false
      t.string  :nas_path, null: false
      t.string  :nas_filename
      t.string  :status, null: false, default: "queued" # queued | done | failed
      t.text    :error
      t.timestamps
    end
    add_index :nas_copy_transfers, [ :user_id, :created_at ]
  end
end
