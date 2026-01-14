module Admin
  class ReportsController < Admin::ApplicationController
    def show
      @decision_progress = ReportingMetrics.decision_progress_at_a_glance
      @migration_status_overview = ReportingMetrics.migration_status_overview
      @decision_progress_by_volume = ReportingMetrics.decision_progress_by_volume
      @decision_progress_by_assigned_user = ReportingMetrics.decision_progress_by_assigned_user
    end
  end
end
