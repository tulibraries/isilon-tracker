class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :timeoutable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  has_many :assigned_assets, class_name: "IsilonAsset", foreign_key: "assigned_to_id"
  enum :status, { inactive: "inactive", active: "active" }, suffix: true
  before_validation :assign_names_from_name_field
  before_validation :ensure_random_password, if: :new_record?

  validates :status, inclusion: { in: statuses.keys }

  def self.from_omniauth(access_token)
    data = access_token.info
    user = User.where(email: data["email"]).first_or_initialize

    user.name ||= data["name"]
    user.password ||= Devise.friendly_token[0, 20]

    user.save! if user.changed?
    user
  end

  def title
    if name.present?
      name
    elsif first_name.present? || last_name.present?
      [ first_name, last_name ].compact.join(" ")
    else
      email.split("@").first.titleize
    end
  end

  protected

  def assign_names_from_name_field
    return if name.blank?
    parts = name.split(" ", 2)
    self.first_name ||= parts.first
    self.last_name  ||= parts.second if parts.size > 1
  end

  private

  def ensure_random_password
    return if password.present?
    # friendly_token is secure and URL-safe; 20 chars >= Devise default min length (6)
    token = Devise.friendly_token[0, 20] # 20 chars by default
    self.password = token
    self.password_confirmation = token
  end
end
