require "rails_helper"

RSpec.describe "Files NAS accounts", type: :request do
  let!(:user) do
    create(:user,
           email: "files-nas@example.com",
           password: "password123",
           password_confirmation: "password123",
           username: "files-user")
  end

  let(:browser_headers) { { "Cookie" => browser_cookie } }
  let(:browser_cookie) do
    post "/auth/login", params: { email: user.email, password: "password123" }, as: :json
    expect(response).to have_http_status(:ok)
    response.headers.fetch("Set-Cookie")
  end

  describe "GET /__fh/nas/status" do
    it "syncs legacy NAS credentials into linked accounts" do
      user.smb_username = "legacy_user"
      user.smb_password = "legacy-password"
      user.save!

      expect do
        get "/__fh/nas/status", headers: browser_headers
      end.to change { user.reload.nas_accounts.count }.by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["connected"]).to eq(true)
      expect(body["accounts"]).to contain_exactly(include("username" => "legacy_user"))
      expect(user.reload.nas_accounts.first.password_ciphertext).to eq(user.smb_password_ciphertext)
    end
  end

  describe "POST /__fh/nas/accounts" do
    it "creates a linked NAS account" do
      expect(SmbClient).to receive(:test)
        .with(share: "alpha_user", username: "alpha_user", password: "secret123")
        .and_return(success: true)

      expect do
        post "/__fh/nas/accounts",
             params: { username: "Alpha_User", password: "secret123" },
             headers: browser_headers,
             as: :json
      end.to change(NasAccount, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["account"]).to include("username" => "alpha_user")
      expect(body["accounts"]).to include(include("username" => "alpha_user"))
      expect(user.reload.nas_accounts.find_by!(username: "alpha_user").password).to eq("secret123")
    end

    it "returns a JSON validation error for an invalid username" do
      expect(SmbClient).to receive(:test)
        .with(share: "bad/name", username: "bad/name", password: "secret123")
        .and_return(success: true)

      post "/__fh/nas/accounts",
           params: { username: "bad/name", password: "secret123" },
           headers: browser_headers,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).to include("error" => a_string_including("contains invalid characters"))
    end
  end

  describe "PATCH /__fh/nas/accounts/:id" do
    let!(:account) { create(:nas_account, user: user, username: "alpha-user", plain_password: "old-password") }

    it "updates the password for an existing linked account" do
      old_ciphertext = account.password_ciphertext
      expect(SmbClient).to receive(:test)
        .with(share: "alpha-user", username: "alpha-user", password: "new-password")
        .and_return(success: true)

      patch "/__fh/nas/accounts/#{account.id}",
            params: { password: "new-password" },
            headers: browser_headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(account.reload.password).to eq("new-password")
      expect(account.password_ciphertext).not_to eq(old_ciphertext)
    end
  end

  describe "DELETE /__fh/nas/accounts/:id" do
    let!(:account) { create(:nas_account, user: user, username: "alpha-user") }

    it "removes a linked NAS account" do
      expect do
        delete "/__fh/nas/accounts/#{account.id}", headers: browser_headers
      end.to change { user.reload.nas_accounts.count }.by(-1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["connected"]).to eq(false)
      expect(body["accounts"]).to eq([])
    end
  end

  describe "GET /__fh/nas/browse" do
    let!(:first_account) { create(:nas_account, user: user, username: "alpha-user", plain_password: "alpha-pass") }
    let!(:second_account) { create(:nas_account, user: user, username: "beta-user", plain_password: "beta-pass") }

    it "uses the requested NAS account" do
      expect(SmbClient).to receive(:list)
        .with(share: "beta-user", path: "reports", username: "beta-user", password: "beta-pass")
        .and_return(success: true, items: [{ name: "2026", type: "dir", size: 0 }])

      get "/__fh/nas/browse",
          params: { account_id: second_account.id, path: "reports" },
          headers: browser_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["account"]).to include("id" => second_account.id, "username" => "beta-user")
      expect(body["items"]).to eq([{ "name" => "2026", "type" => "dir", "size" => 0 }])
    end

    it "requires an account id when multiple NAS accounts are linked" do
      get "/__fh/nas/browse", params: { path: "reports" }, headers: browser_headers

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)).to include("error" => "NAS account required")
    end
  end

  describe "POST /__fh/nas/copy" do
    let!(:source_account) { create(:nas_account, user: user, username: "alpha-user", plain_password: "alpha-pass") }
    let!(:destination_account) { create(:nas_account, user: user, username: "beta-user", plain_password: "beta-pass") }

    before do
      allow(NasCopyJob).to receive(:perform_later)
    end

    it "queues a NAS-to-NAS transfer between linked accounts" do
      expect do
        post "/__fh/nas/copy",
             params: {
               account_id: destination_account.id,
               source_account_id: source_account.id,
               source_nas_path: "reports/quarterly.csv",
               nas_path: "archive/2026"
             },
             headers: browser_headers,
             as: :json
      end.to change(NasCopyTransfer, :count).by(1)

      expect(response).to have_http_status(:ok)

      transfer = NasCopyTransfer.order(:created_at).last
      expect(transfer).to have_attributes(
        user_id: user.id,
        nas_account_id: destination_account.id,
        source_nas_account_id: source_account.id,
        source_nas_path: "reports/quarterly.csv",
        local_path: "reports/quarterly.csv",
        nas_path: "archive/2026",
        nas_filename: "quarterly.csv",
        status: "queued"
      )
      expect(NasCopyJob).to have_received(:perform_later).with(transfer.id)

      body = JSON.parse(response.body)
      expect(body).to include(
        "queued" => true,
        "nas_filename" => "quarterly.csv",
        "account" => include("id" => destination_account.id, "username" => "beta-user")
      )
    end
  end
end