require "rails_helper"

RSpec.describe "Files", type: :request do
  let!(:user) do
    create(:user,
           email: "files@example.com",
           password: "password123",
           password_confirmation: "password123",
           username: "files-user")
  end

  describe "GET /__fh/" do
    it "renders inline CSS and JS for the files host page" do
      post "/auth/login", params: { email: user.email, password: "password123" }, as: :json

      expect(response).to have_http_status(:ok)
      cookie = response.headers["Set-Cookie"]
      expect(cookie).to include("_etl_browser_uid")

      get "/__fh/", headers: { "Cookie" => cookie }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("<style>")
      expect(response.body).to include("*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }")
      expect(response.body).to include(".win-minimized { height: 34px !important; min-height: 34px; }")
      expect(response.body).to include(".win-resize-handle { position: absolute; right: 0; bottom: 0; width: 18px; height: 18px; cursor: nwse-resize; z-index: 5; }")
      expect(response.body).to include(".sidebar-item.sidebar-subitem { padding-left: 1.9rem; font-size: 0.78rem; }")
      expect(response.body).to include("<script>")
      expect(response.body).to include("function esc(s) {")
      expect(response.body).to include("function toggleWindowMinimise(event, id) {")
      expect(response.body).to include("function toggleWindowMaximise(event, id) {")
      expect(response.body).to include("function startWinResize(e, id) {")
      expect(response.body).to include("function setNasAccounts(accounts) {")
      expect(response.body).to include("function renderHomeSidebarWindows() {")
      expect(response.body).to include("function focusSidebarWindow(winId) {")
      expect(response.body).to include("function openNasManager() {")
      expect(response.body).to include("function openNasAccountWindow(accountId, path = '') {")
      expect(response.body).to include("function imagePreviewUrl(ws, itemPath) {")
      expect(response.body).to include("function changeNasCopyAccount(accountId) {")
      expect(response.body).to include("src.winType === 'nas' && dest.type === 'nas'")
      expect(response.body).to include("?account_id=' + encodeURIComponent(ws.accountId || '') + '&inline=1'")
      expect(response.body).to include("onclick=\"toggleWindowMinimise(event,'${id}')\"")
      expect(response.body).to include("onclick=\"toggleWindowMaximise(event,'${id}')\"")
      expect(response.body).to include("<div class=\"win-resize-handle\" onmousedown=\"startWinResize(event,'${id}')\" aria-hidden=\"true\"></div>")
      expect(response.body).to include("Manage NAS Accounts")
      expect(response.body).to include("id=\"homeSidebarWindows\"")
      expect(response.body).to include("id=\"nasSidebarAccounts\"")
      expect(response.body).to include("id=\"nasManageModal\"")
      expect(response.body).to include("id=\"nasCopyAccountSelect\"")
      expect(response.body).not_to include(%(<link rel="stylesheet" href="/files.css">))
      expect(response.body).not_to include(%(<script src="/files.js"></script>))
      expect(response.body).not_to include("id=\"nasConnectBtn\"")
    end
  end
end