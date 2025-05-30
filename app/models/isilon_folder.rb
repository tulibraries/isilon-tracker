class IsilonFolder < ApplicationRecord
  belongs_to :parent_folder, class_name: "IsilonFolder", optional: true
  has_many :child_folders, class_name: "IsilonFolder", foreign_key: "parent_folder_id"
  belongs_to :volume
  has_many :isilon_assets
end
