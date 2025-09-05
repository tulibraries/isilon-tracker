FactoryBot.define do
  factory :aspace_collection do
    sequence(:name) { |n| "Aspace Collection #{n}" }
    active { true }
  end
end
