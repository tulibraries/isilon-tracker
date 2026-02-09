# frozen_string_literal: true

require "administrate/field/base"

class FileSizeField < Administrate::Field::Base
  include ActionView::Helpers::NumberHelper

  def to_s
    return "" if data.blank?

    number_to_human_size(data.to_i)
  end
end
