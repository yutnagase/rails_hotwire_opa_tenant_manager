require "rails_helper"

RSpec.describe "Projects", type: :request do
  let(:tenant) { create(:tenant, subdomain: "test-co") }
  let(:user) { create(:user, tenant: tenant, role: "admin") }

  before do
    stub_opa_allow
    # RLS用のSET ROLE / RESET ROLEをスタブ化
    allow_any_instance_of(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter).to receive(:execute).and_call_original
    allow_any_instance_of(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter).to receive(:execute).with(/SET ROLE|RESET ROLE|SET app\.current_tenant_id|RESET app\.current_tenant_id/)
  end

  describe "GET /projects" do
    it "returns success for authenticated user" do
      ActsAsTenant.with_tenant(tenant) do
        create(:project, tenant: tenant, name: "My Project")
      end

      sign_in user
      host! "test-co.example.com"
      get projects_path

      expect(response).to have_http_status(:ok)
    end
  end
end
