source "https://rubygems.org"

gem "active_model_serializers"
gem "administrate"
gem "bootsnap", require: false
gem "bootstrap"
gem "cssbundling-rails"
gem "csv"
gem "jbuilder"
gem "jsbundling-rails"
gem "puma", ">= 5.0"
gem "rails", "~> 7.2.2"
gem "sprockets-rails"
gem "sqlite3", ">= 2.1"
gem "stimulus-rails"
gem "turbo-rails"
gem "tzinfo-data", platforms: %i[ windows jruby ]
# gem "image_processing", "~> 1.2"

group :development, :test do
  gem "brakeman", require: false
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "pry"
  gem "pry-byebug"
  gem "pry-rails"
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "better_errors"
  gem "spring"
  gem "spring-watcher-listen"
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "factory_bot_rails"
  gem "orderly"
  gem "rails-controller-testing"
  gem "rspec-activemodel-mocks"
  gem "rspec-rails"
  gem "selenium-webdriver"
  gem "shoulda-matchers", "~> 6.5"
  gem "simplecov"
  gem "simplecov-lcov"
  gem "webdrivers", "5.3.1"
end

gem "devise", "~> 4.9"
# Required for memcached
group :production do
  gem "dalli"
  gem "connection_pool"
end

gem "pg", "~> 1.5"

gem "okcomputer", "~> 1.19"
