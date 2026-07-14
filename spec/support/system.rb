# frozen_string_literal: true

require "capybara/cuprite"

# Cuprite drives headless Chrome over CDP directly (no chromedriver process).
# Ferrum auto-detects the `google-chrome-stable` binary, so no explicit path.
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1400, 900 ],
    headless: true,
    process_timeout: 20,
    timeout: 15,
    browser_options: { "no-sandbox" => nil, "disable-dev-shm-usage" => nil }
  )
end

RSpec.configure do |config|
  config.include Warden::Test::Helpers, type: :system

  config.before(:each, type: :system) { driven_by :cuprite }
  config.after(:each, type: :system) { Warden.test_reset! }

  # System specs need Chrome, so they stay out of the default run. FULL=1 opts
  # them back in (and enables the SimpleCov floor — see spec_helper.rb).
  config.filter_run_excluding(type: :system) unless ENV["FULL"]
end
