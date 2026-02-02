# frozen_string_literal: true

FactoryBot.define do
  factory :isilon_asset do
    association :parent_folder, factory: :isilon_folder

    sequence(:isilon_name) { |n| "asset_#{n}.txt" }
    isilon_path { File.join(parent_folder.full_path, isilon_name) }
    full_isilon_path do
      volume_name = parent_folder.volume.name
      normalized_path = isilon_path.to_s.sub(%r{\A/+}, "")
      "/#{volume_name}/#{normalized_path}"
    end
  end
end
