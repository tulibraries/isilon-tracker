# frozen_string_literal: true

require "administrate/field/base"

class LastUpdatedByField < Administrate::Field::Base
  def to_s
    value = data.to_s.strip
    return "" if value.blank?

    user = find_user(value)
    user ? user.title : value
  end

  private

  def find_user(value)
    return if value.blank?

    if value.match?(/\A\d+\z/)
      user = User.find_by(id: value.to_i)
      return user if user
    end

    User.find_by(email: value) || User.find_by(name: value)
  end
end
