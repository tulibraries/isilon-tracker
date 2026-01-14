module Admin
  class ReportsController < Admin::ApplicationController
    def show
      @decision_progress = ReportingMetrics.decision_progress_at_a_glance
      @migration_status_overview = ReportingMetrics.migration_status_overview
    end
  end
end
