module Admin
  class UsersController < ApplicationController
    include JwtAuthenticatable
    before_action :require_admin!

    # GET /admin/users
    def index
      users = User.order(:email)
      render json: users.map { |u| user_json(u) }
    end

    # POST /admin/users
    def create
      user = User.new(user_params)
      if user.save
        render json: user_json(user), status: :created
      else
        render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # PATCH /admin/users/:id
    def update
      user = User.find(params[:id])
      attrs = user_params
      attrs.delete(:password) if attrs[:password].blank?
      attrs.delete(:password_confirmation) if attrs[:password_confirmation].blank?
      if user.update(attrs)
        render json: user_json(user)
      else
        render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
      end
    end

    # DELETE /admin/users/:id
    def destroy
      user = User.find(params[:id])
      if user.id == current_user.id
        render json: { error: "Cannot delete your own account" }, status: :unprocessable_entity
        return
      end
      user.destroy
      head :no_content
    end

    private

    def require_admin!
      render json: { error: "Forbidden" }, status: :forbidden unless current_user.is_admin?
    end

    def user_params
      params.require(:user).permit(:email, :password, :password_confirmation, :username, :is_admin)
    end

    def user_json(user)
      {
        id: user.id,
        email: user.email,
        username: user.username,
        is_admin: user.is_admin,
        created_at: user.created_at
      }
    end
  end
end
