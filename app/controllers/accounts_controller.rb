class AccountsController < ApplicationController
  include JwtAuthenticatable

  # GET /account
  def show
    render json: account_json(current_user)
  end

  # PATCH /account
  def update
    if current_user.update(account_params)
      render json: account_json(current_user)
    else
      render json: { error: current_user.errors.full_messages.first }, status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.permit(:username, :smb_username, :smb_password)
  end

  def account_json(user)
    { id: user.id, email: user.email, username: user.username,
      smb_username: user.smb_username, smb_connected: user.smb_connected? }
  end
end
