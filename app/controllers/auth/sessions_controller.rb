module Auth
  class SessionsController < ApplicationController
    # POST /auth/login
    def create
      user = User.find_by(email: params[:email]&.downcase)

      if user&.authenticate(params[:password])
        token = JwtAuthenticatable.generate_token(user.id)
        render json: { token: token, user: { id: user.id, email: user.email } }, status: :ok
      else
        render json: { error: "Invalid email or password" }, status: :unauthorized
      end
    end

    # DELETE /auth/logout
    def destroy
      # JWT is stateless; client must discard the token.
      render json: { message: "Logged out successfully" }, status: :ok
    end
  end
end

