# frozen_string_literal: true

FactoryBot.define do
  factory :isilon_asset do
    isilon_name { "asset.txt" }
    isilon_path { "/test/path/asset.txt" }
    parent_folder factory: :isilon_folder
  end
end
