module ReportingMetrics
  module_function

  CACHE_TTL = 15.minutes

  def volume_progress_over_time
    Rails.cache.fetch("reporting/volume_progress_over_time", expires_in: CACHE_TTL) do
      totals = assets_relation
        .group("volumes.id", volume_label_expression)
        .pluck("volumes.id", volume_label_expression, "COUNT(isilon_assets.id)")
        .each_with_object({}) do |(id, label, total), memo|
          memo[id] = { label: label, total: total.to_i }
        end

      return {} if totals.empty?

      daily_rows = assets_relation
        .group(
          Arel.sql("volumes.id"),
          Arel.sql(volume_label_expression),
          Arel.sql("DATE(COALESCE(isilon_assets.updated_at, isilon_assets.created_at))")
        )
        .pluck(
          Arel.sql("volumes.id"),
          Arel.sql(volume_label_expression),
          Arel.sql("DATE(COALESCE(isilon_assets.updated_at, isilon_assets.created_at))"),
          Arel.sql("SUM(CASE WHEN migration_statuses.name = 'Migrated' THEN 1 ELSE 0 END)")
        )

      daily_rows.group_by { |volume_id, *_| volume_id }.each_with_object({}) do |(volume_id, rows), hash|
        meta = totals[volume_id]
        next unless meta && meta[:total].positive?

        cumulative = 0
        data_points = rows.sort_by { |row| row[2] }.map do |_vid, _label, day, migrated|
          cumulative += migrated.to_i
          percentage = ((cumulative.to_f / meta[:total]) * 100).round(2)
          [day, percentage]
        end

        hash[meta[:label]] = data_points
      end
    end
  end

  def volume_progress_leaderboard
    Rails.cache.fetch("reporting/volume_progress_leaderboard", expires_in: CACHE_TTL) do
      assets_relation
        .group(Arel.sql(volume_label_expression))
        .pluck(
          Arel.sql(volume_label_expression),
          Arel.sql("COUNT(isilon_assets.id)"),
          Arel.sql("SUM(CASE WHEN migration_statuses.name = 'Migrated' THEN 1 ELSE 0 END)")
        )
        .each_with_object({}) do |(label, total, migrated), hash|
          percentage = total.to_i.positive? ? ((migrated.to_f / total) * 100).round(2) : 0
          hash[label] = percentage
        end
    end
  end

  def asset_backlog_by_volume
    Rails.cache.fetch("reporting/asset_backlog_by_volume", expires_in: CACHE_TTL) do
      assets_relation
        .group(Arel.sql(volume_label_expression))
        .pluck(
          Arel.sql(volume_label_expression),
          Arel.sql("COUNT(isilon_assets.id)"),
          Arel.sql("SUM(CASE WHEN migration_statuses.name = 'Migrated' THEN 1 ELSE 0 END)")
        )
        .each_with_object({}) do |(label, total, migrated), hash|
          hash[label] = total.to_i - migrated.to_i
        end
    end
  end

  def user_workload_across_volumes
    Rails.cache.fetch("reporting/user_workload", expires_in: CACHE_TTL) do
      IsilonAsset
        .left_outer_joins(:assigned_to)
        .group("COALESCE(users.name, users.email, 'Unassigned')")
        .order(Arel.sql("COUNT(*) DESC"))
        .count
    end
  end

  def assignment_aging_by_user
    Rails.cache.fetch("reporting/assignment_aging", expires_in: CACHE_TTL) do
      age_expression = case ActiveRecord::Base.connection.adapter_name.downcase
                       when "postgresql"
                         "EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - COALESCE(isilon_assets.updated_at, isilon_assets.created_at))) / 86400.0"
                       when "sqlite"
                         "(julianday('now') - julianday(COALESCE(isilon_assets.updated_at, isilon_assets.created_at)))"
                       else
                         "EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - COALESCE(isilon_assets.updated_at, isilon_assets.created_at))) / 86400.0"
                       end

      IsilonAsset
        .left_outer_joins(:assigned_to, :migration_status)
        .where.not(migration_statuses: { name: "Migrated" })
        .group("COALESCE(users.name, users.email, 'Unassigned')")
        .pluck(
          Arel.sql("COALESCE(users.name, users.email, 'Unassigned')"),
          Arel.sql("AVG(#{age_expression})")
        )
        .each_with_object({}) do |(name, avg_days), hash|
          hash[name] = avg_days.to_f.round(1)
        end
    end
  end

  def top_file_types_migrated(limit: 10)
    Rails.cache.fetch(["reporting/top_file_types", limit], expires_in: CACHE_TTL) do
      IsilonAsset
        .joins(:migration_status)
        .where(migration_statuses: { name: "Migrated" })
        .where.not(file_type: [nil, ""])
        .group("LOWER(isilon_assets.file_type)")
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(limit)
        .count
    end
  end

  def duplicate_and_raw_content
    Rails.cache.fetch("reporting/duplicate_vs_raw", expires_in: CACHE_TTL) do
      duplicates = IsilonAsset.where.not(duplicate_of_id: nil).count
      raw_matches = IsilonAsset.where("LOWER(isilon_path) LIKE ?", "%/raw/%").count

      {
        "Duplicate" => duplicates,
        "Raw" => raw_matches
      }
    end
  end

  def assets_relation
    IsilonAsset.joins(parent_folder: :volume).left_outer_joins(:migration_status)
  end
  private_class_method :assets_relation

  def volume_label_expression
    adapter = ActiveRecord::Base.connection.adapter_name.downcase
    if adapter == "postgresql"
      "COALESCE(volumes.name, 'Volume ' || volumes.id::text)"
    else
      "COALESCE(volumes.name, 'Volume ' || volumes.id)"
    end
  end
  private_class_method :volume_label_expression
end
