class IsilonFolder < ApplicationRecord
  belongs_to :volume
  belongs_to :parent_folder, class_name: "IsilonFolder", foreign_key: "parent_folder_id", optional: true
  has_many :child_folders, class_name: "IsilonFolder", foreign_key: "parent_folder_id"
  has_many :isilon_assets, foreign_key: "parent_folder_id"

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
