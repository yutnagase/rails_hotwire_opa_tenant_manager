class Admin::UsersController < ApplicationController
  before_action :set_user, only: :update

  def index
    @users = User.order(:name)
  end

  def update
    if @user.seed_admin?
      redirect_to admin_users_path, alert: "Seed admin role cannot be changed."
      return
    end

    if @user.update(user_params)
      redirect_to admin_users_path, notice: "Role updated."
    else
      redirect_to admin_users_path, alert: @user.errors.full_messages.join(", ")
    end
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:role)
  end

  def opa_action_for(action)
    case action
    when "index" then "read"
    when "update" then "update"
    else super
    end
  end

  def authorize_with_opa
    return unless user_signed_in?

    opa_action = opa_action_for(action_name)

    unless OpaClient.allowed?(user: current_user, action: opa_action, resource: "admin_user")
      head :forbidden
    end
  end
end
