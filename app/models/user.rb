class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :timeoutable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  has_many :assigned_assets, class_name: "IsilonAsset", foreign_key: "assigned_to"

  enum :status, {
    inactive: "inactive",
    active: "active"
  }, suffix: true


  validates :status, inclusion: { in: statuses.keys }

  def title
    email
  end

  def display_name
    name.present? ? name : email
  end

  def password_required?
    false
  end

  def self.from_omniauth(access_token)
    data = access_token.info
    User.where(email: data["email"]).first
  end
end
