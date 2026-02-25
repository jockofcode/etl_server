Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :auth do
    post   "login",  to: "sessions#create"
    delete "logout", to: "sessions#destroy"
  end

  resources :flows, only: %i[index show create update destroy] do
    collection do
      post "copy", to: "flows#copy"
    end
  end

  namespace :schema do
    get "commands",   to: "schemas#commands"
    get "transforms", to: "schemas#transforms"
  end
end
