require "rails_helper"

RSpec.describe "Flows", type: :request do
  let(:tmp_dir) { Dir.mktmpdir("flows_request_spec") }
  let!(:user)   { create(:user) }
  let(:headers) { auth_headers_for(user) }

  let(:valid_flow) do
    {
      "START_NODE" => { "name" => "Test Flow", "description" => "desc", "next" => "step1" },
      "step1"      => { "type" => "log_data", "input" => "hello" }
    }
  end

  before { stub_const("FlowStore::FLOWS_DIR", tmp_dir) }
  after  { FileUtils.remove_entry(tmp_dir) }

  describe "authentication" do
    it "returns 401 without a token" do
      get "/flows"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with a bad token" do
      get "/flows", headers: { "Authorization" => "Bearer badtoken" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /flows" do
    it "returns an empty array when no flows exist" do
      get "/flows", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it "returns summaries of existing flows" do
      FlowStore.create("my_flow", valid_flow)
      get "/flows", headers: headers
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["id"]).to eq("my_flow")
    end
  end

  describe "GET /flows/:id" do
    it "returns 200 with flow and chain" do
      FlowStore.create("my_flow", valid_flow)
      get "/flows/my_flow", headers: headers
      body = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(body["flow"]["START_NODE"]["name"]).to eq("Test Flow")
      expect(body["chain"]).to have_key("entry_node")
    end

    it "returns 404 for unknown flow" do
      get "/flows/ghost", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /flows" do
    it "creates a flow and returns 201" do
      post "/flows", params: { id: "new_flow", flow: valid_flow }.to_json,
                     headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["id"]).to eq("new_flow")
    end

    it "returns 409 when id already exists" do
      FlowStore.create("dup", valid_flow)
      post "/flows", params: { id: "dup", flow: valid_flow }.to_json,
                     headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:conflict)
    end

    it "returns 422 for invalid flow data" do
      post "/flows", params: { id: "bad", flow: { "no_start" => {} } }.to_json,
                     headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PUT /flows/:id" do
    it "updates an existing flow" do
      FlowStore.create("updatable", valid_flow)
      updated = valid_flow.deep_merge("START_NODE" => { "name" => "Updated" })
      put "/flows/updatable", params: { flow: updated }.to_json,
                              headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for unknown flow" do
      put "/flows/ghost", params: { flow: valid_flow }.to_json,
                          headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /flows/:id" do
    it "removes the flow and returns 204" do
      FlowStore.create("deletable", valid_flow)
      delete "/flows/deletable", headers: headers
      expect(response).to have_http_status(:no_content)
    end

    it "returns 404 for unknown flow" do
      delete "/flows/ghost", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /flows/copy" do
    it "copies a flow to a new id" do
      FlowStore.create("source", valid_flow)
      post "/flows/copy", params: { source_id: "source", dest_id: "dest" }.to_json,
                          headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["id"]).to eq("dest")
    end

    it "returns 404 when source does not exist" do
      post "/flows/copy", params: { source_id: "ghost", dest_id: "dest" }.to_json,
                          headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:not_found)
    end

    it "returns 409 when dest already exists" do
      FlowStore.create("src", valid_flow)
      FlowStore.create("dst", valid_flow)
      post "/flows/copy", params: { source_id: "src", dest_id: "dst" }.to_json,
                          headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:conflict)
    end
  end
end

