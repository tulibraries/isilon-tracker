Rails.application.routes.draw do
  devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" }

  devise_scope :user do
    get "/users/sign_out" => "devise/sessions#destroy"
  end

  namespace :admin do
      resources :isilon_folders, except: [ :destroy ]
      resources :isilon_assets, except: [ :destroy, :new ]
      resources :volumes, except: [ :destroy, :edit, :new ]
      resources :aspace_collections
      resources :contentdm_collections
      resources :users, only: [ :index, :show, :new, :create, :edit, :update ]

      root to: "volumes#index"
    end

  resources :isilon_assets
  resources :isilon_folders
  resources :aspace_collections
  resources :contentdm_collections
  resources :migration_statuses, only: [ :index ]
  resources :users, only: [ :index ]

  resources :volumes do
    get :file_tree,          on: :member  # only root folders
    get :file_tree_children, on: :member  # sub-folders + assets
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "volumes#index"
end
