# frozen_string_literal: true

class DuplicateGroupMembership < ApplicationRecord
  belongs_to :duplicate_group
  belongs_to :isilon_asset
end
