class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :timeoutable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  enum active: {
    inactive: 'inactive',
    active: 'active'
  }, _suffix: true


  validates :active, inclusion: { in: actives.keys }
  validates :name, presence: true

  def title
    email
  end

  def self.from_omniauth(access_token)
    data = access_token.info
    User.where(email: data["email"]).first
  end
end
