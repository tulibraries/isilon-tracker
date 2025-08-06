class RemovePasswordFromUsers < ActiveRecord::Migration[7.2]
  def change
    remove_column :users, :password, :string
    remove_column :users, :encrypted_password, :string
    remove_column :users, :reset_password_token
    remove_column :users, :reset_password_sent_at
  end
end
