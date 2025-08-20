class IsilonFolder < ApplicationRecord
  belongs_to :volume
  belongs_to :parent_folder, class_name: "IsilonFolder", foreign_key: "parent_folder_id", optional: true
  has_many :child_folders, class_name: "IsilonFolder", foreign_key: "parent_folder_id"
  has_many :isilon_assets, foreign_key: "parent_folder_id"
  belongs_to :migration_status, optional: true

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
end
