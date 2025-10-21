require "administrate/field/base"

class ChartkickField < Administrate::Field::Base
  def chart_method
    options.fetch(:chart_method, :column_chart)
  end

  def chart_options
    options.fetch(:chart_options, {})
  end

  def chart_data
    data || {}
  end

  def blank_slate_text
    options.fetch(:blank_slate_text, "No data available")
  end
end
