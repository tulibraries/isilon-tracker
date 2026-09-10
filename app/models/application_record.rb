# frozen_string_literal: true

class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  devise :omniauthable, omniauth_providers: [ :google_oauth2 ]
end
