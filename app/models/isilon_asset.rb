class IsilonAsset < ApplicationRecord
  belongs_to :parent_folder, class_name: "IsilonFolder", foreign_key: "parent_folder_id", optional: true
  belongs_to :migration_status, optional: true  # optional: true if some records are still NULL
end
