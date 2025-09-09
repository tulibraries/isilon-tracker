FactoryBot.define do
  factory :contentdm_collection do
    sequence(:name) { |n| "ContentDM Collection #{n}" }
    active { true }
  end
end
