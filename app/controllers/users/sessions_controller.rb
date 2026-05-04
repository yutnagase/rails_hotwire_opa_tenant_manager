class Users::SessionsController < Devise::SessionsController
  skip_before_action :authorize_with_opa, only: :destroy

  def destroy
    signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))
    if signed_out
      if auth0_configured?
        redirect_to auth0_logout_url, allow_other_host: true
      else
        redirect_to new_dev_session_path, notice: "Signed out."
      end
    end
  end

  private

  def auth0_logout_url
    return_to = root_url
    "https://#{ENV.fetch('AUTH0_DOMAIN')}/v2/logout?client_id=#{ENV.fetch('AUTH0_CLIENT_ID')}&returnTo=#{CGI.escape(return_to)}"
  end
end
