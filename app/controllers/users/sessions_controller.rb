class Users::SessionsController < Devise::SessionsController
  skip_before_action :authorize_with_opa, only: :destroy

  def destroy
    signed_out = (Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name))
    if signed_out
      path = Rails.env.development? ? new_dev_session_path : root_path
      redirect_to path, notice: "Signed out."
    end
  end
end
