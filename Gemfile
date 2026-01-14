source "https://rubygems.org"

gem "active_model_serializers"
gem "administrate"
gem "bootsnap", require: false
gem "bootstrap"
gem "cssbundling-rails"
gem "csv"
gem "devise", "~> 4.9"
gem "dotenv-rails"
gem "jbuilder"
gem "jsbundling-rails"
gem "okcomputer", "~> 1.19"
gem "omniauth"
gem "omniauth-google-oauth2"
gem "omniauth-rails_csrf_protection"
gem "pg", "~> 1.6"
gem "puma", ">= 5.0"
gem "rails", "~> 7.2.2"
gem "sprockets-rails"
gem "sqlite3", ">= 2.1"
gem "stimulus-rails"
gem "turbo-rails"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "chartkick", "~> 5.0"
gem "uri", ">= 1.0.4"

group :development, :test do
  gem "brakeman", require: false
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "pry"
  gem "pry-byebug"
  gem "pry-rails"
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails"
end

group :development do
  gem "better_errors"
  gem "spring"
  gem "spring-watcher-listen"
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "cuprite"
  gem "factory_bot_rails"
  gem "launchy"
  gem "orderly"
  gem "rails-controller-testing"
  gem "rspec-activemodel-mocks"
  gem "selenium-webdriver"
  gem "shoulda-matchers", "~> 7.0"
  gem "simplecov"
  gem "simplecov-lcov"
  gem "webdrivers", "5.3.1"
  gem "coveralls", require: false
end

# Required for memcached
group :production do
  gem "dalli"
  gem "connection_pool", "~> 2.4"
end
