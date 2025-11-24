Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  namespace :web do
    get "dashboard", to: "dashboard#index"

    resources :products, only: [ :index, :show, :new, :create, :edit, :update ] do
      collection do
        get :search
      end
      resources :stock_movements, only: [ :new, :create ], module: :products
    end

    resources :orders, only: [ :index, :show, :new, :create ] do
      post :cancel, on: :member
    end

    resources :customers, only: [ :index ]
    resources :purchases, only: [ :index ]
  end

  root "web/dashboard#index"

  # Defines the root path route ("/")
  # root "posts#index"
end
