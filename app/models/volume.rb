class Volume < ApplicationRecord
  has_many :isilon_folders
  has_many :top_level_folders, -> { where(parent_folder_id: nil) }, class_name: "IsilonFolder"
  has_many :isilon_assets, through: :isilon_folders
end
