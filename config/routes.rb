Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users,
    controllers: {
      omniauth_callbacks: "users/omniauth_callbacks",
      sessions: "users/sessions"
    },
    skip: [ :registrations, :passwords, :confirmations ]

  devise_scope :user do
    delete "sign_out", to: "users/sessions#destroy", as: :destroy_user_session
  end

  # Auth0コールバック用ルート
  get "/auth/auth0/callback" => "users/omniauth_callbacks#auth0"

  resources :projects, only: [ :index ] do
    resources :tasks, only: [ :index, :show, :update ]
  end

  root "projects#index"
end
