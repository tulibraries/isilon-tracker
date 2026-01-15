class IsilonFolder < ApplicationRecord
  belongs_to :volume
  belongs_to :parent_folder, class_name: "IsilonFolder", foreign_key: "parent_folder_id", optional: true
  has_many :child_folders, class_name: "IsilonFolder", foreign_key: "parent_folder_id"
  has_many :isilon_assets, foreign_key: "parent_folder_id"
  belongs_to :assigned_to, class_name: "User", foreign_key: "assigned_to", optional: true

  def ancestors
    current = self
    [].tap do |list|
      while current.parent_folder
        current = current.parent_folder
        list.unshift(current)
      end
    end
  end

  def breadcrumb_trail
    crumbs = []
    current = self
    while current
      crumbs.unshift(current)
      current = current.parent_folder
    end
    crumbs
  end

  # Get all descendant folders (children, grandchildren, etc.)
  def descendant_folders
    descendants = []
    child_folders.each do |child|
      descendants << child
      descendants.concat(child.descendant_folders)
    end
    descendants
  end

  # Get all assets within this folder and all descendant folders
  def all_descendant_assets
    asset_ids = []

    asset_ids.concat(isilon_assets.pluck(:id))

    descendant_folders.each do |folder|
      asset_ids.concat(folder.isilon_assets.pluck(:id))
    end

    IsilonAsset.where(id: asset_ids)
  end
end
