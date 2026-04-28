class DevSessionsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :authorize_with_opa

  def new
    @auth0_configured = auth0_configured?
    @users = ActsAsTenant.current_tenant.users unless @auth0_configured
  end

  def create
    raise ActionController::RoutingError, "Not Found" if auth0_configured?

    user = ActsAsTenant.current_tenant.users.find(params[:user_id])
    sign_in(user)
    redirect_to root_path, notice: "Signed in as #{user.name}."
  end
end
