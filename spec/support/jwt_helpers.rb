module JwtHelpers
  def auth_headers_for(user)
    token = JwtAuthenticatable.generate_token(user.id)
    { "Authorization" => "Bearer #{token}" }
  end
end

RSpec.configure do |config|
  config.include JwtHelpers, type: :request
end

