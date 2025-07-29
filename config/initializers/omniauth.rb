if Rails.env.development?
  OmniAuth.config.request_validation_phase = proc { |_env| true }
end
