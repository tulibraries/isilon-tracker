# frozen_string_literal: true

FactoryBot.define do
  factory :isilon_folder do
    volume
    parent_folder { nil }
    full_path { "Folder Name" }
  end
end
