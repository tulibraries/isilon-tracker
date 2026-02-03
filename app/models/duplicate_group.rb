# frozen_string_literal: true

class DuplicateGroup < ApplicationRecord
  has_many :duplicate_group_memberships, dependent: :delete_all
  has_many :isilon_assets, through: :duplicate_group_memberships
end
