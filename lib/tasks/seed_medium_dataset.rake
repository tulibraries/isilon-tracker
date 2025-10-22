namespace :db do
  desc "Seed database with medium dataset for testing (faster)"
  task seed_medium_dataset: :environment do
    puts "🚀 Starting medium dataset seed..."

    # Configuration - smaller numbers for testing
    num_volumes = 1
    folders_per_volume = 1_000     # 1K folders
    assets_per_folder = 5          # Average 5 assets per folder
    max_folder_depth = 5           # Maximum nesting depth

    total_folders = num_volumes * folders_per_volume
    total_assets = total_folders * assets_per_folder

    puts "Planning to create:"
    puts "  📁 #{total_folders.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} folders"
    puts "  📄 #{total_assets.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} assets"
    puts ""

    # Ensure we have required reference data
    ensure_reference_data

    # Get reference data
    migration_statuses = MigrationStatus.all
    users = User.all
    aspace_collections = AspaceCollection.all
    contentdm_collections = ContentdmCollection.all

    puts "Reference data counts:"
    puts "  👥 #{users.count} users"
    puts "  📋 #{migration_statuses.count} migration statuses"
    puts "  🏛️ #{aspace_collections.count} aspace collections"
    puts "  💿 #{contentdm_collections.count} contentdm collections"
    puts ""

    # Create volume
    volume = Volume.find_or_create_by!(name: "Medium Test Volume")
    puts "📦 Created volume: #{volume.name}"

    # Create folder structure
    puts "\n🏗️ Building folder structure..."
    reset_folder_counters

    # Create root folders (depth 0)
    root_folder_count = (folders_per_volume * 0.1).to_i # 10% at root level

    puts "  Creating #{root_folder_count} root folders..."
    root_folders = create_folders_simple(volume, nil, root_folder_count, 0, "Root")

    # Create nested folders
    remaining_folders = folders_per_volume - root_folder_count
    all_folders = root_folders.dup
    current_depth = 1

    while remaining_folders > 0 && current_depth < max_folder_depth
      folders_at_depth = [ remaining_folders / 3, 200 ].min
      puts "  Creating #{folders_at_depth} folders at depth #{current_depth}..."

      parent_folders = all_folders.select { |f| f[:depth] == current_depth - 1 }
      break if parent_folders.empty?

      new_folders = []
      folders_at_depth.times do |i|
        parent = parent_folders.sample
        folder = create_folders_simple(volume, parent[:folder], 1, current_depth, "L#{current_depth}").first
        new_folders << folder
      end

      all_folders.concat(new_folders)
      remaining_folders -= folders_at_depth
      current_depth += 1
    end

    puts "  ✅ Created #{volume.isilon_folders.count} folders"

    # Create assets
    puts "  🎨 Creating assets..."
    create_assets_simple(volume, assets_per_folder, migration_statuses, users, aspace_collections, contentdm_collections)
    puts "  ✅ Created #{IsilonAsset.where(parent_folder_id: volume.isilon_folders.ids).count} assets"

    # Final statistics
    puts "\n📊 Final Statistics:"
    puts "  📁 Folders: #{volume.isilon_folders.count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "  📄 Assets: #{IsilonAsset.where(parent_folder_id: volume.isilon_folders.ids).count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts ""
    puts "🎉 Medium dataset seeding complete!"
    puts "💡 Test performance at: http://localhost:3000/volumes/#{volume.id}"
  end

  private

  def ensure_reference_data
    # Ensure we have users
    if User.count < 10
      puts "Creating test users..."
      10.times do |i|
        User.find_or_create_by!(email: "testuser#{i + 1}@temple.edu") do |user|
          user.first_name = "Test"
          user.last_name = "User#{i + 1}"
          user.status = :active
        end
      end
    end

    # Ensure migration statuses exist
    if MigrationStatus.count == 0
      puts "Creating migration statuses..."
      [ "Needs review", "OK to migrate", "Don't migrate", "Migrated" ].each_with_index do |name, i|
        MigrationStatus.find_or_create_by!(name: name) do |status|
          status.default = i == 0
          status.active = true
        end
      end
    end

    # Create some collections if they don't exist
    if AspaceCollection.count < 5
      puts "Creating test aspace collections..."
      5.times do |i|
        AspaceCollection.find_or_create_by!(name: "Test ASpace Collection #{i + 1}") do |collection|
          collection.active = true
        end
      end
    end

    if ContentdmCollection.count < 5
      puts "Creating test contentdm collections..."
      5.times do |i|
        ContentdmCollection.find_or_create_by!(name: "Test ContentDM Collection #{i + 1}") do |collection|
          collection.active = true
        end
      end
    end
  end

  def create_folders_simple(volume, parent_folder, count, depth, prefix)
    folders = []
    counter = folder_counter_for(volume.id, parent_folder&.id)

    count.times do
      index = counter.increment
      folder_name = "#{prefix}_#{depth}_#{index}"
      full_path = parent_folder ? "#{parent_folder.full_path}/#{folder_name}" : "/#{folder_name}"

      folder = IsilonFolder.create!(
        volume: volume,
        parent_folder: parent_folder,
        full_path: full_path
      )

      folders << { folder: folder, depth: depth }
    end

    folders
  end

  def reset_folder_counters
    @folder_counters = {}
  end

  def folder_counter_for(volume_id, parent_folder_id)
    @folder_counters ||= {}
    key = [ volume_id, parent_folder_id || :root ]
    @folder_counters[key] ||= Counter.new
  end

  class Counter
    def initialize
      @value = 0
    end

    def increment
      @value += 1
    end
  end

  def create_assets_simple(volume, assets_per_folder, migration_statuses, users, aspace_collections, contentdm_collections)
    extensions = %w[.jpg .png .tiff .pdf .doc .docx .mp4 .mov .wav .mp3]

    volume.isilon_folders.find_each do |folder|
      num_assets = rand(1..assets_per_folder)

      num_assets.times do |i|
        extension = extensions.sample
        filename = "asset_#{folder.id}_#{i + 1}#{extension}"

        IsilonAsset.create!(
          parent_folder: folder,
          isilon_name: filename,
          isilon_path: "#{folder.full_path}/#{filename}",
          file_size: rand(1024..10_485_760).to_s, # 1KB to 10MB stored as string
          file_type: extension.delete_prefix("."),
          migration_status: migration_statuses.sample,
          assigned_to: [ nil, nil, users.sample ].sample, # 66% unassigned
          aspace_collection: rand(10) < 2 ? aspace_collections.sample : nil,
          contentdm_collection: rand(10) < 3 ? contentdm_collections.sample : nil
        )
      end
    end
  end
end
