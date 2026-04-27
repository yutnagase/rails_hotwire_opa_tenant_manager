require "rails_helper"

RSpec.describe "Tasks", type: :request do
  let(:tenant) { create(:tenant, subdomain: "test-co") }
  let(:user) { create(:user, tenant: tenant, role: "admin") }
  let(:project) { ActsAsTenant.with_tenant(tenant) { create(:project, tenant: tenant) } }
  let(:task) { ActsAsTenant.with_tenant(tenant) { create(:task, tenant: tenant, project: project, status: "todo") } }

  before do
    stub_opa_allow
    allow_any_instance_of(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter).to receive(:execute).and_call_original
    allow_any_instance_of(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter).to receive(:execute).with(/SET ROLE|RESET ROLE|SET app\.current_tenant_id|RESET app\.current_tenant_id/)
    sign_in user
    host! "test-co.example.com"
  end

  describe "GET /projects/:project_id/tasks" do
    it "returns success" do
      project # ensure created
      get project_tasks_path(project)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /projects/:project_id/tasks/:id" do
    it "returns success" do
      get project_task_path(project, task)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH /projects/:project_id/tasks/:id" do
    it "updates the task status" do
      patch project_task_path(project, task), params: { task: { status: "doing" } }
      expect(task.reload.status).to eq("doing")
    end
  end

  context "when OPA denies access" do
    before { stub_opa_deny }

    it "returns forbidden" do
      get project_tasks_path(project)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
