Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Authentication
  resource :session, only: [:new, :create, :destroy]
  get "/login", to: "sessions#new"
  post "/login", to: "sessions#create"
  delete "/logout", to: "sessions#destroy"

  # Root path
  root "accounts#index"

  # Products (global catalog)
  resources :products, only: [:index, :new, :create, :edit, :update]

  # Accounts with nested resources
  resources :accounts do
    resources :users, only: [:index, :new, :create]
    resources :subscriptions, only: [:index, :new, :create]

    resources :products, only: [] do
      resources :license_assignments, only: [:index] do
        collection do
          post :bulk_assign
          post :bulk_unassign
        end
      end
    end
  end
end
