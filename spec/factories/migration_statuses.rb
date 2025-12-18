# frozen_string_literal: true

FactoryBot.define do
  factory :migration_status do
    sequence(:name) { |n| "Migration Status #{n}" }
    active { true }
    default { false }

    initialize_with do
      MigrationStatus.find_or_initialize_by(name: name).tap do |status|
        status.active = active
        status.default = default
        status.save!
      end
    end

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
