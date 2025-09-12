class ChangeAssignedToToUserReference < ActiveRecord::Migration[7.2]
  def up
    # Add new assigned_to_id column as foreign key
    add_reference :isilon_assets, :assigned_to, null: true, foreign_key: { to_table: :users }

    # Migrate data: find users by email and set the foreign key
    IsilonAsset.reset_column_information
    IsilonAsset.find_each do |asset|
      if asset.read_attribute_before_type_cast('assigned_to').present? && asset.read_attribute_before_type_cast('assigned_to') != 'unassigned'
        user = User.find_by(email: asset.read_attribute_before_type_cast('assigned_to'))
        if user
          asset.update_column(:assigned_to_id, user.id)
        end
      end
    end

    # Remove old assigned_to string column
    remove_column :isilon_assets, :assigned_to

    # Rename assigned_to_id to assigned_to
    rename_column :isilon_assets, :assigned_to_id, :assigned_to
  end

  def down
    # Rename back to assigned_to_id
    rename_column :isilon_assets, :assigned_to, :assigned_to_id

    # Add back the string column
    add_column :isilon_assets, :assigned_to, :string, default: "unassigned"

    # Migrate data back: set email strings from user records
    IsilonAsset.reset_column_information
    IsilonAsset.find_each do |asset|
      if asset.assigned_to_id.present?
        user = User.find_by(id: asset.assigned_to_id)
        if user
          asset.update_column(:assigned_to, user.email)
        end
      end
    end

    # Remove the foreign key column
    remove_reference :isilon_assets, :assigned_to, foreign_key: { to_table: :users }
  end
end
