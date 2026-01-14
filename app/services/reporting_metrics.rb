module ReportingMetrics
  module_function

  CACHE_TTL = 15.minutes
  DECISION_MADE_STATUSES = [
    "ok to migrate",
    "don't migrate",
    "save elsewhere",
    "migrated",
    "migration in progress"
  ].freeze

  def decision_progress_at_a_glance
    Rails.cache.fetch("reporting/decision_progress", expires_in: CACHE_TTL) do
      counts_by_status = IsilonAsset
        .left_outer_joins(:migration_status)
        .group("LOWER(migration_statuses.name)")
        .count

      total_assets = counts_by_status.values.sum
      decision_made = counts_by_status.sum do |status_name, count|
        decision_made_status?(status_name) ? count.to_i : 0
      end
      decision_pending = total_assets - decision_made

      {
        decision_made: decision_segment_payload("Decision Made", decision_made, total_assets),
        decision_pending: decision_segment_payload("Decision Pending", decision_pending, total_assets),
        total: total_assets
      }
    end
  end

  def decision_segment_payload(label, count, total)
    {
      label: label,
      count: count,
      percentage: percentage(count, total)
    }
  end
  private_class_method :decision_segment_payload

  def decision_made_status?(status_name)
    DECISION_MADE_STATUSES.include?(normalize_status_name(status_name))
  end
  private_class_method :decision_made_status?

  def normalize_status_name(status_name)
    status_name.to_s.downcase.gsub(/\u2019/, "'")
  end
  private_class_method :normalize_status_name

  def percentage(part, total)
    return 0 if total.to_i.zero?

    ((part.to_f / total.to_f) * 100).round(1)
  end
  private_class_method :percentage
end
