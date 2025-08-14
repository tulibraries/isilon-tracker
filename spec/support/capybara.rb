# frozen_string_literal: true

require "capybara/cuprite"

Capybara.javascript_driver = :cuprite
Capybara.default_max_wait_time = 5

Capybara.register_driver :cuprite do |app|
  Capybara::Cuprite::Driver.new(
    app,
    timeout: 10,
    window_size: [ 1200, 800 ],
    headless: true
  )
end
