class Volume < ApplicationRecord
  has_many :isilon_folders
  has_many :isilon_assets, through: :isilon_folders
end
