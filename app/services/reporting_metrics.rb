module ReportingMetrics
  module_function

  def volume_progress_leaderboard
    totals = volume_asset_counts
    migrated = volume_asset_counts(status: "Migrated")

    ensure_volume_keys!(totals)
    ensure_volume_keys!(migrated)

    totals.each_with_object({}) do |((id, name), total), hash|
      label = name || "Volume ##{id}"
      migrated_count = migrated[[id, name]] || 0
      percentage = total.positive? ? ((migrated_count.to_f / total) * 100).round(2) : 0
      hash[label] = percentage
    end
  end

  def asset_backlog_by_volume
    totals = volume_asset_counts
    migrated = volume_asset_counts(status: "Migrated")

    ensure_volume_keys!(totals)
    ensure_volume_keys!(migrated)

    totals.each_with_object({}) do |((id, name), total), hash|
      backlog = total - (migrated[[id, name]] || 0)
      label = name || "Volume ##{id}"
      hash[label] = backlog
    end
  end

  def user_workload_across_volumes
    IsilonAsset.joins(:assigned_to)
               .group("users.name")
               .order(Arel.sql("COUNT(*) DESC"))
               .count
               .transform_keys { |name| name || "Unnamed User" }
  end

  def assignment_aging_by_user
    scope = IsilonAsset.includes(:assigned_to, :migration_status)
                       .where.not(assigned_to: nil)
                       .where.not(migration_statuses: { name: "Migrated" })

    grouped = scope.group_by do |asset|
      asset.assigned_to&.name.presence || "Unnamed User"
    end

    grouped.each_with_object({}) do |(name, assets), hash|
      average_days = assets.sum { |asset| age_in_days(asset) } / assets.size
      hash[name] = average_days.round(1)
    end
  end

  def top_file_types_migrated(limit: 10)
    IsilonAsset.joins(:migration_status)
               .where(migration_statuses: { name: "Migrated" })
               .where.not(file_type: [ nil, "" ])
               .group("LOWER(isilon_assets.file_type)")
               .order(Arel.sql("COUNT(*) DESC"))
               .limit(limit)
               .count
  end

  def duplicate_and_raw_content
    duplicates = IsilonAsset.where.not(duplicate_of_id: nil).count
    raw_matches = IsilonAsset.where("LOWER(isilon_path) LIKE ?", "%/raw/%").count

    {
      "Duplicate" => duplicates,
      "Raw" => raw_matches
    }
  end

  def volume_asset_counts(status: nil)
    scope = IsilonAsset.joins(parent_folder: :volume)
    scope = scope.joins(:migration_status) if status
    scope = scope.where(migration_statuses: { name: status }) if status

    scope.group("volumes.id", "volumes.name").count
  end
  private_class_method :volume_asset_counts

  def ensure_volume_keys!(hash)
    Volume.find_each do |volume|
      key = [ volume.id, volume.name ]
      hash[key] ||= 0
    end
  end
  private_class_method :ensure_volume_keys!

  def age_in_days(asset)
    reference_time = asset.updated_at || asset.created_at || Time.current
    ((Time.current - reference_time) / 1.day).to_f
  end
  private_class_method :age_in_days
end
