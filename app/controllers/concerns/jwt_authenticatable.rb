module JwtAuthenticatable
  extend ActiveSupport::Concern

  SECRET_KEY = Rails.application.secret_key_base
  TOKEN_EXPIRY = 24.hours

  included do
    before_action :authenticate_user!
  end

  def authenticate_user!
    token = extract_token_from_header
    payload = decode_token(token)
    @current_user = User.find(payload["user_id"])
  rescue JWT::DecodeError, JWT::ExpiredSignature, ActiveRecord::RecordNotFound
    render json: { error: "Unauthorized" }, status: :unauthorized
  end

  def current_user
    @current_user
  end

  module ClassMethods
    def self.generate_token(user_id)
      payload = {
        user_id: user_id,
        exp: TOKEN_EXPIRY.from_now.to_i,
        iat: Time.now.to_i
      }
      JWT.encode(payload, SECRET_KEY, "HS256")
    end
  end

  def self.generate_token(user_id)
    payload = {
      user_id: user_id,
      exp: TOKEN_EXPIRY.from_now.to_i,
      iat: Time.now.to_i
    }
    JWT.encode(payload, SECRET_KEY, "HS256")
  end

  private

  def extract_token_from_header
    header = request.headers["Authorization"]
    raise JWT::DecodeError, "Missing token" unless header&.start_with?("Bearer ")
    header.split(" ").last
  end

  def decode_token(token)
    JWT.decode(token, SECRET_KEY, true, { algorithm: "HS256" }).first
  end
end

