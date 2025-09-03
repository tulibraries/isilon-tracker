# frozen_string_literal: true

FactoryBot.define do
  factory :migration_status do
    sequence(:name) { |n| "Migration Status #{n}" }
    active { true }
    default { false }

    trait :default do
      name { "Needs review" }
      default { true }
    end

    trait :migrated do
      name { "Migrated" }
      default { false }
    end

    trait :dont_migrate do
      name { "Don't migrate" }
      default { false }
    end

    trait :inactive do
      active { false }
    end
  end
end
