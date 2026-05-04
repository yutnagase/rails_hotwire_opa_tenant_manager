class SettingsController < ApplicationController
  def show
    @tenant = ActsAsTenant.current_tenant
  end

  def update
    @tenant = ActsAsTenant.current_tenant
    if @tenant.update(tenant_params)
      redirect_to settings_path, notice: "Settings updated."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def tenant_params
    params.require(:tenant).permit(:name)
  end

  def authorize_with_opa
    return unless user_signed_in?

    opa_action = opa_action_for(action_name)

    unless OpaClient.allowed?(user: current_user, action: opa_action, resource: "tenant")
      head :forbidden
    end
  end
end
