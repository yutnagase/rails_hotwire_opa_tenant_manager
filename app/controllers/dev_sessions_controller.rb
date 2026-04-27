class DevSessionsController < ActionController::Base
  layout "application"

  before_action :ensure_development!

  def new
    tenant = Tenant.find_by!(subdomain: request.subdomain)
    @users = tenant.users
  end

  def create
    tenant = Tenant.find_by!(subdomain: request.subdomain)
    user = tenant.users.find(params[:user_id])
    sign_in(user)
    redirect_to root_path, notice: "Signed in as #{user.name}."
  end

  private

  def ensure_development!
    raise ActionController::RoutingError, "Not Found" unless Rails.env.development?
  end
end
