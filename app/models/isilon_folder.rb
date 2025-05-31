class IsilonFolder < ApplicationRecord
  belongs_to :volume
  belongs_to :parent_folder, class_name: "IsilonFolder", foreign_key: "parent_folder_id", optional: true
  has_many :child_folders, class_name: "IsilonFolder", foreign_key: "parent_folder_id"
  has_many :isilon_assets, foreign_key: "parent_folder_id"
end
