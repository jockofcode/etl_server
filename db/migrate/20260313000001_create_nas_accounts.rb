class CreateNasAccounts < ActiveRecord::Migration[8.0]
  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  class MigrationNasAccount < ApplicationRecord
    self.table_name = "nas_accounts"
  end

  class MigrationNasCopyTransfer < ApplicationRecord
    self.table_name = "nas_copy_transfers"
  end

  def up
    create_table :nas_accounts do |t|
      t.integer :user_id, null: false
      t.string :username, null: false
      t.text :password_ciphertext, null: false
      t.timestamps
    end

    add_index :nas_accounts, [:user_id, :username], unique: true
    add_foreign_key :nas_accounts, :users

    add_reference :nas_copy_transfers, :nas_account, foreign_key: true

    MigrationUser.reset_column_information
    MigrationNasAccount.reset_column_information
    MigrationNasCopyTransfer.reset_column_information

    MigrationUser.where.not(smb_username: [nil, ""]).find_each do |user|
      next if user.smb_password_ciphertext.blank?

      account = MigrationNasAccount.find_or_create_by!(user_id: user.id, username: user.smb_username.to_s.strip.downcase) do |nas_account|
        nas_account.password_ciphertext = user.smb_password_ciphertext
      end

      MigrationNasCopyTransfer.where(user_id: user.id, nas_account_id: nil).update_all(nas_account_id: account.id)
    end
  end

  def down
    remove_reference :nas_copy_transfers, :nas_account, foreign_key: true
    remove_foreign_key :nas_accounts, :users
    drop_table :nas_accounts
  end
end