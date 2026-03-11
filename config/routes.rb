Rails.application.routes.draw do
  # *.etl.cnxkit.com — flow subdomain execution.
  # The EtlSubdomainRouter middleware (runs before ActionDispatch::Static) rewrites
  # any request with an X-ETL-Subdomain header to this internal path, so the static
  # file server never intercepts it. The subdomain = flow ID.
  match "/__etl_flow__", to: "subdomain_flows#show", via: :all

  get "up" => "rails/health#show", as: :rails_health_check

  # files.cnxkit.com routes — EtlSubdomainRouter prepends /__fh to all paths
  # from that host (via X-Files-Host nginx header) so ActionDispatch::Static
  # never serves public/index.html for these requests.
  scope "/__fh" do
    get    "/logout",        to: "files#logout"
    get    "/",              to: "files#index"
    post   "/upload",        to: "files#upload"
    post   "/mkdir",         to: "files#mkdir"
    post   "/move",          to: "files#move"
    get    "/info",          to: "files#info"
    get    "/dirs",          to: "files#dirs"
    get    "/download/*path", to: "files#download", format: false
    delete "/delete/*path",   to: "files#destroy",  format: false

    # NAS (SMB) integration
    get  "/nas/status",           to: "files#nas_status"
    put  "/nas/credentials",      to: "files#nas_credentials"
    get  "/nas/browse",           to: "files#nas_browse"
    post "/nas/copy",             to: "files#nas_copy"
    get  "/nas/download/*path",   to: "files#nas_download",      format: false
    post "/nas/copy-from-nas",    to: "files#nas_copy_from_nas"
    post "/nas/mkdir",            to: "files#nas_mkdir"
  end

  namespace :auth do
    post   "login",  to: "sessions#create"
    delete "logout", to: "sessions#destroy"
  end

  resource  :account, only: %i[show update]
  resources :tokens,  only: %i[index create destroy]

  resources :flows, only: %i[index show create update destroy] do
    collection do
      post "copy", to: "flows#copy"
    end
    member do
      patch "permissions", to: "flows#update_permissions"
    end
  end

  namespace :schema do
    get "commands",   to: "schemas#commands"
    get "transforms", to: "schemas#transforms"
  end

  namespace :admin do
    resources :users, only: %i[index create update destroy]
  end
end
