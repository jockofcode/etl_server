module Auth
  class SessionsController < ApplicationController
    # POST /auth/login
    def create
      login    = params[:email]&.downcase
      user     = User.find_by(email: login) || User.find_by(username: login)

      if user&.authenticate(params[:password])
        token = JwtAuthenticatable.generate_token(user.id)
        set_browser_session_cookie(user.id)
        render json: { token: token, user: { id: user.id, email: user.email } }, status: :ok
      else
        render json: { error: "Invalid email or password" }, status: :unauthorized
      end
    end

    # DELETE /auth/logout
    def destroy
      clear_browser_session_cookie
      render json: { message: "Logged out successfully" }, status: :ok
    end

    private

    def set_browser_session_cookie(user_id)
      cookies.signed[:_etl_browser_uid] = {
        value: user_id,
        domain: ".cnxkit.com",
        path: "/",
        secure: Rails.env.production?,
        httponly: true,
        same_site: :lax,
        expires: 30.days
      }
    end

    def clear_browser_session_cookie
      cookies.delete(:_etl_browser_uid, domain: ".cnxkit.com", path: "/")
    end
  end
end

