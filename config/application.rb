require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Middleware that intercepts requests before ActionDispatch::Static for two cases:
#
# 1. *.etl.cnxkit.com flow subdomains (X-ETL-Subdomain header set by nginx):
#    Rewrites PATH_INFO to /__etl_flow__ so the static file server never intercepts it.
#    The original path is preserved in rack env for the trigger.
#
# 2. files.cnxkit.com (X-Files-Host header set by nginx):
#    Prepends /__fh to PATH_INFO so ActionDispatch::Static won't match public/index.html.
#    Rails routes are scoped under /__fh to match.
class EtlSubdomainRouter
  FLOW_PATH   = "/__etl_flow__"
  FILES_PREFIX = "/__fh"

  def initialize(app)
    @app = app
  end

  def call(env)
    if env["HTTP_X_ETL_SUBDOMAIN"].to_s.strip.length.positive?
      env["etl.original_path"] = env["PATH_INFO"]
      env["PATH_INFO"] = FLOW_PATH
    elsif env["HTTP_X_FILES_HOST"].to_s.strip.length.positive?
      env["PATH_INFO"] = FILES_PREFIX + env["PATH_INFO"]
    end
    @app.call(env)
  end
end

module EtlServer
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    config.filter_parameters += [:smb_password]

    config.middleware.insert_before ActionDispatch::Static, EtlSubdomainRouter
    config.middleware.use ActionDispatch::Cookies
  end
end
