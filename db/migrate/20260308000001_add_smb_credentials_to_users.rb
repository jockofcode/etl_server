class AddSmbCredentialsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :smb_username, :string
    add_column :users, :smb_password_ciphertext, :text
  end
end
