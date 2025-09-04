class MigrationStatus < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }
  scope :default, -> { find_by(default: true) }

  before_save :ensure_single_default, if: :default?

  has_many :isilon_folders

  def to_s
    name
  end

  private

  def ensure_single_default
    MigrationStatus.where.not(id: id).update_all(default: false)
  end
end
