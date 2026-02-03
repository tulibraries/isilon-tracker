# frozen_string_literal: true

require "administrate/field/base"

class HasDuplicatesField < Administrate::Field::Base
  def to_s
    data ? "Yes" : ""
  end
end
