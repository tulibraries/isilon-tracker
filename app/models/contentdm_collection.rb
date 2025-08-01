class ContentdmCollection < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }

  def to_s
    name
  end
end
