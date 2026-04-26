class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  set_current_tenant_through_filter
  around_action :scope_to_tenant
  before_action :authenticate_user!
  before_action :authorize_with_opa

  private

  def scope_to_tenant
    tenant = Tenant.find_by!(subdomain: request.subdomain)
    set_current_tenant(tenant)

    conn = ActiveRecord::Base.connection
    conn.execute("SET ROLE #{ENV.fetch('RLS_ROLE', 'rails_user')}")
    conn.execute("SET app.current_tenant_id = '#{tenant.id}'")

    yield
  ensure
    conn = ActiveRecord::Base.connection
    conn.execute("RESET ROLE")
    conn.execute("RESET app.current_tenant_id")
  end

  def authenticate_user!
    # TODO: Auth0接続後にこの分岐を削除し、super のみにすること。
    # 仮実装: development環境かつAuth0未接続時は、テナントの最初のユーザーで自動ログインする。
    if Rails.env.development? && current_user.nil?
      user = ActsAsTenant.current_tenant&.users&.first
      sign_in(user) if user
    end

    super unless user_signed_in?
  end

  def authorize_with_opa
    return unless user_signed_in?

    opa_action = opa_action_for(action_name)
    resource = controller_name.singularize

    unless OpaClient.allowed?(user: current_user, action: opa_action, resource: resource)
      head :forbidden
    end
  end

  def opa_action_for(action)
    case action
    when "index", "show" then "read"
    when "new", "create" then "create"
    when "edit", "update" then "update"
    when "destroy" then "delete"
    else "read"
    end
  end
end
