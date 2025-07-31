# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Seed the migration status table.
migration_statuses = [
  { name: "Needs review", default: true },
  { name: "OK to migrate" },
  { name: "Don’t migrate" },
  { name: "Migrated" },
  { name: "Migration in progress" },
  { name: "Needs further investigation" },
  { name: "Save elsewhere" }
]

migration_statuses.each do |status_attrs|
  MigrationStatus.find_or_create_by!(name: status_attrs[:name]) do |status|
    status.default = status_attrs[:default] || false
    status.active = true
  end
end
