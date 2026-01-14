require "csv"

module Admin
  class ReportsController < Admin::ApplicationController
    def show
      @decision_progress = ReportingMetrics.decision_progress_at_a_glance
      @migration_status_overview = ReportingMetrics.migration_status_overview
      @decision_progress_by_volume = ReportingMetrics.decision_progress_by_volume
      @decision_progress_by_assigned_user = ReportingMetrics.decision_progress_by_assigned_user
    end

    def volume_migration_status_csv
      csv_data = CSV.generate(headers: true) do |csv|
        csv << ["Volume", "Migration Status", "Asset Count"]
        ReportingMetrics.asset_counts_by_volume_and_migration_status.each do |row|
          csv << [row[:volume], row[:migration_status], row[:count]]
        end
      end

      send_data csv_data, filename: "asset_counts_by_volume_and_migration_status-#{Time.current.to_date}.csv"
    end

    def assigned_user_migration_status_csv
      csv_data = CSV.generate(headers: true) do |csv|
        csv << ["Assigned User", "Migration Status", "Asset Count"]
        ReportingMetrics.asset_counts_by_assigned_user_and_migration_status.each do |row|
          csv << [row[:assigned_user], row[:migration_status], row[:count]]
        end
      end

      send_data csv_data, filename: "asset_counts_by_assigned_user_and_migration_status-#{Time.current.to_date}.csv"
    end
  end
end
