namespace :db do
  desc "Seed database with large dataset for performance testing"
  task seed_large_dataset: :environment do
    puts "🚀 Starting large dataset seed..."

    # Configuration
    num_volumes = 2
    folders_per_volume = 50_000    # 50K folders per volume
    assets_per_folder = 1000      # Average 1000 assets per folder
    max_folder_depth = 8          # Maximum nesting depth

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

    # Create volumes
    volumes = []
    num_volumes.times do |i|
      volume = Volume.find_or_create_by!(name: "Performance Test Volume #{i + 1}")
      volumes << volume
      puts "📦 Created volume: #{volume.name}"
    end

    # Create folder structure for each volume
    volumes.each_with_index do |volume, vol_index|
      puts "\n🏗️ Building folder structure for #{volume.name}..."
      reset_folder_counters

      # Track folders for efficient parent assignment
      folders_by_depth = Array.new(max_folder_depth) { [] }

      # Create root folders (depth 0)
      root_folder_count = (folders_per_volume * 0.1).to_i # 10% at root level

      puts "  Creating #{root_folder_count} root folders..."
      root_folders = create_folders_batch(
        volume: volume,
        parent_folder: nil,
        count: root_folder_count,
        depth: 0,
        prefix: "Root"
      )
      folders_by_depth[0] = root_folders

      # Create nested folder structure
      remaining_folders = folders_per_volume - root_folder_count
      current_depth = 1

      while remaining_folders > 0 && current_depth < max_folder_depth
        # Distribute remaining folders across depths (more at shallow depths)
        folders_at_this_depth = [ remaining_folders / (max_folder_depth - current_depth),
                                folders_per_volume / (max_folder_depth + 1) ].min

        puts "  Creating #{folders_at_this_depth} folders at depth #{current_depth}..."

        # Select random parents from previous depth
        potential_parents = folders_by_depth[current_depth - 1]
        break if potential_parents.empty?

        new_folders = []
        folders_at_this_depth.times do |i|
          parent = potential_parents.sample
          batch_size = [ 10, folders_at_this_depth - i ].min

          batch_folders = create_folders_batch(
            volume: volume,
            parent_folder: parent,
            count: batch_size,
            depth: current_depth,
            prefix: "L#{current_depth}"
          )
          new_folders.concat(batch_folders)
          i += batch_size - 1
        end

        folders_by_depth[current_depth] = new_folders
        remaining_folders -= folders_at_this_depth
        current_depth += 1
      end

      puts "  ✅ Created #{volume.isilon_folders.count} folders for #{volume.name}"

      # Create assets for this volume's folders
      puts "  🎨 Creating assets..."
      create_assets_for_volume(volume, assets_per_folder, migration_statuses, users, aspace_collections, contentdm_collections)
      puts "  ✅ Created #{volume.isilon_folders.joins(:isilon_assets).count} assets for #{volume.name}"
    end

    # Final statistics
    puts "\n📊 Final Statistics:"
    puts "  📦 Volumes: #{Volume.count}"
    puts "  📁 Folders: #{IsilonFolder.count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts "  📄 Assets: #{IsilonAsset.count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
    puts ""
    puts "🎉 Large dataset seeding complete!"
    puts "💡 Test performance at: http://localhost:3000/volumes/#{volumes.first.id}"
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

  def create_folders_batch(volume:, parent_folder:, count:, depth:, prefix:)
    folders = []
    counter = folder_counter_for(volume.id, parent_folder&.id)

    # Use efficient batch insert
    folder_attrs = count.times.map do
      index = counter.increment
      folder_name = "#{prefix}_#{depth}_#{index}"
      full_path = build_folder_path(parent_folder, folder_name)

      {
        volume_id: volume.id,
        parent_folder_id: parent_folder&.id,
        full_path: full_path,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    # Insert in batches of 1000 for efficiency
    folder_attrs.each_slice(1000) do |batch|
      result = IsilonFolder.insert_all(batch, returning: [ :id, :full_path ])
      batch_folders = result.rows.map do |row|
        folder = IsilonFolder.new
        folder.id = row[0]
        folder.full_path = row[1]
        folder
      end
      folders.concat(batch_folders)
    end

    folders
  end

  def build_folder_path(parent, name)
    if parent
      "#{parent.full_path}/#{name}"
    else
      "/#{name}"
    end
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

  def create_assets_for_volume(volume, assets_per_folder, migration_statuses, users, aspace_collections, contentdm_collections)
    folders = volume.isilon_folders.to_a

    puts "    Creating assets for #{folders.count} folders..."

    # File extensions for realistic data
    extensions = %w[.jpg .png .tiff .pdf .doc .docx .mp4 .mov .wav .mp3 .xml .txt]

    folders.each_slice(100) do |folder_batch|
      folder_batch.each do |folder|
        # Randomize number of assets per folder (0 to 2x average)
        num_assets = rand(0..[ assets_per_folder * 2, 5000 ].min)

        asset_attrs = []

        num_assets.times do |i|
          extension = extensions.sample
          filename = "asset_#{folder.id}_#{i + 1}#{extension}"

          asset_attrs << {
            parent_folder_id: folder.id,
            isilon_name: filename,
            isilon_path: "#{folder.full_path}/#{filename}",
            file_size: rand(1024..1_073_741_824).to_s, # 1KB to 1GB, stored as string
            file_type: extension.delete_prefix("."),
            migration_status_id: migration_statuses.sample.id,
            assigned_to: [ nil, nil, nil, users.sample.id ].sample, # 75% unassigned
            aspace_collection_id: rand(10) < 2 ? aspace_collections.sample.id : nil, # 20% have aspace
            contentdm_collection_id: rand(10) < 3 ? contentdm_collections.sample.id : nil, # 30% have contentdm
            created_at: Time.current,
            updated_at: Time.current
          }
        end

        IsilonAsset.insert_all(asset_attrs) if asset_attrs.any?
      end
    end
  end
end
