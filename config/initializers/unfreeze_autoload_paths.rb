# frozen_string_literal: true

# Work around Rails 7.2 + Ruby 3.4 autoload arrays being frozen across railties
# (e.g., when loading additional engines like Administrate). Unfreeze before
# each engine's set_autoload_paths initializer runs.
Rails::Engine.initializer "unfreeze_autoload_paths", before: :set_autoload_paths do
  ActiveSupport::Dependencies.autoload_paths = ActiveSupport::Dependencies.autoload_paths.dup
  ActiveSupport::Dependencies.autoload_once_paths = ActiveSupport::Dependencies.autoload_once_paths.dup
end
