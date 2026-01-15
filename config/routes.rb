Rails.application.routes.draw do
  # Devise routes (solo sessions, sin registro)
  devise_for :users, skip: [ :registrations ]

  # Root depende de si el usuario está logueado
  authenticated :user do
    root to: "web/dashboard#index", as: :authenticated_root
  end

  # Usuarios no autenticados van al login
  devise_scope :user do
    root to: "devise/sessions#new"
  end

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
    resources :suppliers
    resources :purchases, only: [ :index, :new, :create, :show, :edit, :update ] do
      member do
        post :mark_as_paid
        patch :cancel
      end
    end
  end
end
