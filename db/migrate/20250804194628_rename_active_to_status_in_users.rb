class RenameActiveToStatusInUsers < ActiveRecord::Migration[7.2]
  def change
    rename_column :users, :active, :status
  end
end
