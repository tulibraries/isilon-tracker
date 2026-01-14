module Admin
  class ReportsController < Admin::ApplicationController
    def show
      @decision_progress = ReportingMetrics.decision_progress_at_a_glance
    end
  end
end
