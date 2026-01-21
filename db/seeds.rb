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
  { name: "Don't migrate" },
  { name: "Migrated" },
  { name: "Migration in progress" },
  { name: "Needs further investigation" },
  { name: "Save elsewhere" }
]

puts "Seeding MigrationStatuses..."

migration_statuses.each do |status_attrs|
  MigrationStatus.find_or_create_by!(name: status_attrs[:name]) do |status|
    status.default = status_attrs[:default] || false
    status.active = true
  end
end
puts "Seeded #{MigrationStatus.count} MigrationStatuses."

require 'csv'
require 'rake'

puts "Seeding AspaceCollections..."
file_path = Rails.root.join("db", "data", "aspace-collection.csv")

CSV.foreach(file_path) do |row|
  name = row[0].strip
  next if name.blank?

  AspaceCollection.find_or_create_by!(name: name) do |collection|
    collection.active = true
  end
end
puts "Seeded #{AspaceCollection.count} AspaceCollections."
puts


puts "Seeding ContentdmCollections..."
csv_path = Rails.root.join("db", "data", "contentdm_collection.csv")

CSV.foreach(csv_path, headers: true, col_sep: "\t") do |row|
  name = row["Collection"].to_s.strip
  next if name.blank?

  ContentdmCollection.find_or_create_by!(name: name) do |collection|
    collection.active = true
  end
end

puts "Seeded #{ContentdmCollection.count} ContentdmCollections."

# Initial root user

root_email = "templelibraries@gmail.com"
User.create!([

      { email: root_email, remember_created_at: nil, provider: nil, uid: nil, name: "Temple University Libraries", status: "active" }
]) unless User.exists?(email: root_email)

puts "Running user setup tasks..."

Rails.application.load_tasks unless Rake::Task.task_defined?("users:sync_initial")

%w[users:sync_initial users:generate_passwords].each do |task_name|
  task = Rake::Task[task_name]
  task.reenable
  task.invoke
end
