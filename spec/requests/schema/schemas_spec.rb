require "rails_helper"

RSpec.describe "Schema::Schemas", type: :request do
  let!(:user)   { create(:user) }
  let(:headers) { auth_headers_for(user) }

  describe "authentication" do
    it "returns 401 without a token for commands" do
      get "/schema/commands"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 without a token for transforms" do
      get "/schema/transforms"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /schema/commands" do
    it "returns 200 with all command schemas" do
      get "/schema/commands", headers: headers
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body.keys).to match_array(%w[
        transform_data check_data for_each_item
        respond_with_success respond_with_error
        send_to_url log_data
        return_data_to_iterator return_error_to_iterator
      ])
    end

    it "includes fields for each command type" do
      get "/schema/commands", headers: headers
      body = JSON.parse(response.body)
      expect(body["log_data"]["fields"]).to have_key("input")
      expect(body["send_to_url"]["fields"]).to have_key("url")
    end
  end

  describe "GET /schema/transforms" do
    it "returns 200 with transforms grouped by category" do
      get "/schema/transforms", headers: headers
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body.keys).to include("math", "logic", "text", "lists", "maps", "type_conversions", "dates", "encoding")
    end

    it "includes transforms within each category" do
      get "/schema/transforms", headers: headers
      body = JSON.parse(response.body)
      expect(body["math"].keys).to include("add", "subtract")
      expect(body["encoding"].keys).to include("base64_encode", "json_decode")
    end
  end
end

