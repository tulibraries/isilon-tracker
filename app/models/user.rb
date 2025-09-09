class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :timeoutable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  enum :status, { inactive: "inactive", active: "active" }, suffix: true

  before_validation :assign_names_from_name_field

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
    name.presence || email.split("@").first.titleize
  end

  protected

  def assign_names_from_name_field
    return if name.blank?
    parts = name.split(" ", 2)
    self.first_name ||= parts.first
    self.last_name  ||= parts.second if parts.size > 1
  end
end
