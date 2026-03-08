require "etl_engine"
require "cgi"

class SubdomainFlowsController < ApplicationController
  # Permission-checked flow execution endpoint.
  #
  # URL structure:
  #   <owner>.etl.cnxkit.com/<flow-id>.<ext>
  #
  # Access rules (checked in order):
  #   1. Flow is public (START_NODE.permissions.public == true) → anyone may run it
  #   2. Requester is the subdomain owner → allowed
  #   3. Requester's username is in START_NODE.permissions.shared_with → allowed
  #   4. Otherwise → 401 (API) or redirect (browser)
  #
  # Requester identity:
  #   Authorization: Bearer <token>  — any user's API token
  #   ?token=<token>                 — any user's API token (query param fallback)
  #   _etl_browser_uid cookie        — signed browser session cookie set at login

  def show
    flow_id = flow_id_from_path
    return render json: { error: "No flow specified in path" }, status: :bad_request if flow_id.blank?

    flow_data = FlowStore.find(flow_id)
    requester = identify_requester

    unless flow_permitted?(flow_data, requester)
      handle_permission_failure(requester)
      return
    end

    result = EtlEngine::Engine.run_file(
      FlowStore.flow_path(flow_id),
      trigger: build_trigger
    )

    send_flow_response(result)
  rescue FlowStore::FlowNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue EtlEngine::FlowError => e
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  # Returns the User making the request, or nil for anonymous requests.
  # Checks any user's API token first, then the browser session cookie.
  def identify_requester
    provided = bearer_token || params[:token]
    if provided.present?
      token_record = ApiToken.find_by(token: provided)
      if token_record
        token_record.update_column(:last_used_at, Time.current)
        return token_record.user
      end
      return nil
    end

    cookie_uid = cookies.signed[:_etl_browser_uid]
    User.find_by(id: cookie_uid) if cookie_uid.present?
  end

  # Returns true if the requester is permitted to run this flow.
  def flow_permitted?(flow_data, requester)
    perms = flow_data.dig("START_NODE", "permissions") || {}

    return true if perms["public"] == true

    return false unless requester

    # Owner always has access
    return true if requester.username.to_s == etl_subdomain.to_s

    # Explicitly shared users have access
    Array(perms["shared_with"]).map(&:to_s).include?(requester.username.to_s)
  end

  # Renders a JSON error or redirects depending on whether this is an API or browser request.
  def handle_permission_failure(requester)
    if bearer_token.present? || params[:token].present?
      render json: { error: "Unauthorized" }, status: :unauthorized
      return
    end

    if requester
      # Logged in but not permitted to run this flow
      redirect_to "https://etl.cnxkit.com/?flash=unauthorized#/flows", allow_other_host: true
    else
      # Not logged in — send to login with a return URL
      flow_url = "https://#{etl_subdomain}.etl.cnxkit.com#{request.env.fetch('etl.original_path', '/')}"
      redirect_to "https://etl.cnxkit.com/?redirect=#{CGI.escape(flow_url)}#/login", allow_other_host: true
    end
  end

  # Extracts a Bearer token from the Authorization header.
  def bearer_token
    header = request.headers["Authorization"]
    header.split(" ", 2).last if header&.start_with?("Bearer ")
  end

  # User/namespace from the subdomain — e.g. "jockofcode" in jockofcode.etl.cnxkit.com.
  # Nginx sets X-ETL-Subdomain via a regex named capture on server_name.
  # Falls back to parsing request.host for local/test environments.
  def etl_subdomain
    request.headers["X-ETL-Subdomain"].presence ||
      request.host.match(/\A([a-z0-9]([a-z0-9\-]*[a-z0-9])?)\.etl\.cnxkit\.com\z/)&.captures&.first
  end

  # Flow ID from the request path, with any file extension stripped.
  def flow_id_from_path
    path = request.env.fetch("etl.original_path", "/")
    return nil if path == "/" || path.blank?

    basename = File.basename(path)
    flow_id  = basename.delete_suffix(File.extname(basename))
    flow_id if flow_id.match?(/\A[a-z0-9]([a-z0-9\-]*[a-z0-9])?\z/)
  end

  # Builds the trigger hash available inside the flow as {{trigger.*}}.
  def build_trigger
    {
      "subdomain" => etl_subdomain,
      "method"    => request.method,
      "path"      => request.env.fetch("etl.original_path", "/"),
      "query"     => request.query_parameters.to_h,
      "headers"   => extract_request_headers,
      "body"      => parse_request_body
    }
  end

  def extract_request_headers
    request.headers.env
      .select  { |k, _| k.start_with?("HTTP_") }
      .transform_keys { |k| k.delete_prefix("HTTP_").downcase.tr("_", "-") }
  end

  def parse_request_body
    body = request.body.read
    return nil if body.blank?
    JSON.parse(body)
  rescue JSON::ParserError
    body
  end

  def send_flow_response(result)
    response_data = result[:response] || {}
    status        = response_data[:status] || 200
    body          = response_data[:body]
    flow_headers  = response_data[:headers] || {}

    flow_headers.each do |key, value|
      response.set_header(key, value.to_s) unless key.casecmp("content-type").zero?
    end

    # Extension in the request path (e.g. ".html") takes priority over the
    # flow's declared Content-Type header, which itself takes priority over
    # the body-type fallback.
    content_type = extension_content_type ||
                   flow_headers.find { |k, _| k.casecmp("content-type").zero? }&.last

    if content_type
      render body: body.to_s, content_type: content_type, status: status
    elsif body.is_a?(Hash) || body.is_a?(Array)
      render json: body, status: status
    elsif body.is_a?(String)
      render plain: body, status: status
    else
      render json: body, status: status
    end
  end

  # Returns a MIME type string for the file extension in the request path,
  # or nil if there is no extension or it is not a recognised type.
  # e.g. ".html" → "text/html", ".json" → "application/json"
  def extension_content_type
    path = request.env.fetch("etl.original_path", "/")
    ext  = File.extname(File.basename(path))
    return nil if ext.blank?

    Rack::Mime.mime_type(ext, nil)
  end
end
