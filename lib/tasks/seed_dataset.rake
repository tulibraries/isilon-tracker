namespace :db do
  desc "Seed a dataset for reporting demos"
  task seed_dataset: :environment do
    puts "🚀 Seeding medium dataset..."

    ActiveRecord::Base.transaction do
      reference = ensure_reference_data

      volume = Volume.find_or_create_by!(name: "Demo Migration Volume")
      puts "📦 Using volume: #{volume.name}"

      folders_created = 0
      assets_created  = 0

      root_count = 3
      child_count = 4
      grandchild_count = 5
      assets_per_folder = 25

      puts "🏗️ Building folder structure..."
      root_count.times do |root_index|
        root = create_folder!(volume, nil, "Root-#{root_index + 1}")
        folders_created += 1

        child_count.times do |child_index|
          child = create_folder!(volume, root, "Project-#{child_index + 1}")
          folders_created += 1

          grandchild_count.times do |grandchild_index|
            grandchild = create_folder!(volume, child, "Batch-#{grandchild_index + 1}")
            folders_created += 1

            assets_created += create_assets!(grandchild, assets_per_folder, reference)
          end
        end
      end

      puts "✅ Created #{folders_created} folders"
      puts "🎨 Created #{assets_created} assets"
    end

    puts "🎉 Done!"
  end
end

def ensure_reference_data
  statuses = MigrationStatus.all
  if statuses.empty?
    puts "  Creating migration statuses..."
    names = [
      "Needs review",
      "OK to migrate",
      "Migrated",
      "Don't migrate"
    ]

    names.each_with_index do |name, index|
      MigrationStatus.create!(
        name: name,
        active: true,
        default: index.zero?
      )
    end
  end

  users = User.limit(3)
  if users.count < 3
    puts "  Creating sample users..."
    needed = 3 - users.count
    needed.times do |i|
      User.create!(
        email: "demo_user#{i + 1}@example.com",
        password: SecureRandom.alphanumeric(16),
        status: :active,
        first_name: "Demo",
        last_name: "User#{i + 1}"
      )
    end
  end

  aspace = AspaceCollection.first || AspaceCollection.create!(name: "Demo ASpace Collection", active: true)
  contentdm = ContentdmCollection.first || ContentdmCollection.create!(name: "Demo ContentDM Collection", active: true)

  {
    statuses: MigrationStatus.all.to_a,
    users: User.where(status: "active").to_a,
    aspace_collection: aspace,
    contentdm_collection: contentdm
  }
end

def create_folder!(volume, parent_folder, name)
  full_path = parent_folder ? "#{parent_folder.full_path}/#{name}" : "/#{name}"

  IsilonFolder.find_or_create_by!(volume: volume, full_path: full_path) do |folder|
    folder.parent_folder = parent_folder
  end
end

def create_assets!(folder, amount, reference)
  statuses = reference[:statuses]
  users    = reference[:users]
  aspace   = reference[:aspace_collection]
  contentdm = reference[:contentdm_collection]

  extensions = %w[jpg png tiff pdf doc mp4 mov wav mp3]

  amount.times do |index|
    extension = extensions.sample
    filename = "#{folder.id}-asset-#{index + 1}.#{extension}"

    IsilonAsset.create!(
      parent_folder: folder,
      isilon_name: filename,
      isilon_path: "#{folder.full_path}/#{filename}",
      file_size: rand(5_000..75_000_000).to_s,
      file_type: extension,
      migration_status: statuses.sample,
      assigned_to: users.sample,
      aspace_collection: aspace,
      contentdm_collection: contentdm,
      created_at: rand(120).days.ago,
      updated_at: rand(60).days.ago
    )
  rescue ActiveRecord::RecordInvalid => e
    puts "    ⚠️ Skipped asset due to validation error: #{e.record.errors.full_messages.join(", ")}"
  end

  amount
end
