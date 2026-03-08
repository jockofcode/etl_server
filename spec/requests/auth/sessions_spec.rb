require "rails_helper"

RSpec.describe "Auth::Sessions", type: :request do
  describe "POST /auth/login" do
    let!(:user) { create(:user, email: "test@example.com", password: "password123") }

    context "with valid credentials" do
      it "returns 200 and a JWT token" do
        post "/auth/login", params: { email: "test@example.com", password: "password123" },
                            as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["token"]).to be_present
        expect(body["user"]["email"]).to eq("test@example.com")
      end

      it "is case-insensitive on email" do
        post "/auth/login", params: { email: "TEST@EXAMPLE.COM", password: "password123" },
                            as: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context "with invalid password" do
      it "returns 401" do
        post "/auth/login", params: { email: "test@example.com", password: "wrongpassword" },
                            as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to be_present
      end
    end

    context "with username instead of email" do
      let!(:user_with_username) { create(:user, email: "named@example.com", password: "password123", username: "nameduser") }

      it "returns 200 and a JWT token" do
        post "/auth/login", params: { email: "nameduser", password: "password123" },
                            as: :json

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["token"]).to be_present
        expect(body["user"]["email"]).to eq("named@example.com")
      end

      it "is case-insensitive on username" do
        post "/auth/login", params: { email: "NAMEDUSER", password: "password123" },
                            as: :json

        expect(response).to have_http_status(:ok)
      end
    end

    context "with unknown email" do
      it "returns 401" do
        post "/auth/login", params: { email: "nobody@example.com", password: "password123" },
                            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "DELETE /auth/logout" do
    let!(:user) { create(:user) }

    it "returns 200 with a message" do
      delete "/auth/logout", headers: auth_headers_for(user)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["message"]).to be_present
    end
  end
end

