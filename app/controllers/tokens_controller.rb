class TokensController < ApplicationController
  include JwtAuthenticatable

  # GET /tokens
  def index
    tokens = current_user.api_tokens.order(created_at: :desc)
    render json: tokens.map { |t| token_summary(t) }
  end

  # POST /tokens
  # Body: { name: "my-app" }
  # Returns the raw token value in this response only — it is not retrievable again.
  def create
    token = current_user.api_tokens.build(name: params[:name])
    if token.save
      render json: token_summary(token).merge(token: token.token), status: :created
    else
      render json: { error: token.errors.full_messages.first }, status: :unprocessable_entity
    end
  end

  # DELETE /tokens/:id
  def destroy
    token = current_user.api_tokens.find(params[:id])
    token.destroy
    head :no_content
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Token not found" }, status: :not_found
  end

  private

  def token_summary(token)
    {
      id:           token.id,
      name:         token.name,
      last_used_at: token.last_used_at,
      created_at:   token.created_at
    }
  end
end
