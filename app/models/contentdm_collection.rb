class ContentdmCollection < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  scope :active, -> { where(active: true) }
  has_many :isilon_assets, dependent: :restrict_with_error

  def to_s
    name
  end
end
