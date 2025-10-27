module Admin
  class ReportsController < Admin::ApplicationController
    def show
      @volume_progress = ReportingMetrics.volume_progress_leaderboard
      @asset_backlog = ReportingMetrics.asset_backlog_by_volume
      @user_workload = ReportingMetrics.user_workload_across_volumes
      @assignment_aging = ReportingMetrics.assignment_aging_by_user
      @top_file_types = ReportingMetrics.top_file_types_migrated
      @duplicate_or_raw = ReportingMetrics.duplicate_and_raw_content
    end
  end
end
