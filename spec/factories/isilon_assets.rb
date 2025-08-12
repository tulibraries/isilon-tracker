# frozen_string_literal: true

FactoryBot.define do
  factory :isilon_asset do
    association :parent_folder, factory: :isilon_folder

    isilon_name { "asset.txt" }
    isilon_path { File.join(parent_folder.full_path, isilon_name) }
  end
end
