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

  resource :settings, only: [ :show, :update ]

  namespace :admin do
    resources :users, only: [ :index, :update ]
  end

  resource :dev_session, only: [ :new, :create ]

  resources :projects do
    resources :tasks
  end

  root "projects#index"
end
