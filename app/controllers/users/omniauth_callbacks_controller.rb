class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  skip_before_action :verify_authenticity_token, only: :auth0

  def auth0
    auth = request.env["omniauth.auth"]
    tenant = Tenant.find_by!(subdomain: request.subdomain)

    @user = User.from_omniauth(auth, tenant)
    sign_in_and_redirect @user, event: :authentication
  end

  def failure
    redirect_to root_path, alert: "Authentication failed."
  end
end
