# frozen_string_literal: true

FactoryBot.define do
  factory :isilon_folder do
    volume
    parent_folder { nil }
    full_path { "/volume/#{volume.id}/folder" }

    trait :root do
      parent_folder { nil }
    end

    trait :child_of do
      transient do
        parent { nil }
        name   { "folder-#{SecureRandom.hex(3)}" }
      end

      parent_folder { parent }
      full_path     { parent ? File.join(parent.full_path, name) : "/#{name}" }
    end

    trait :with_full_path do
      transient { path { nil } }
      full_path { path || full_path }
    end
  end
end
