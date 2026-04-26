# seed専用: acts_as_tenantのテナントスコープ制約を明示的に外して実行する。
# 本番リクエストパスでは ActsAsTenant.without_tenant は使用しない。
ActsAsTenant.without_tenant do
  # Tenants
  tenant_a = Tenant.create!(name: "Company A", subdomain: "company-a")
  tenant_b = Tenant.create!(name: "Company B", subdomain: "company-b")

  # Users - Company A
  admin_a  = User.create!(tenant: tenant_a, auth0_uid: "auth0|admin_a",  name: "Admin A",  email: "admin@company-a.example",  role: "admin")
  member_a = User.create!(tenant: tenant_a, auth0_uid: "auth0|member_a", name: "Member A", email: "member@company-a.example", role: "member")
  guest_a  = User.create!(tenant: tenant_a, auth0_uid: "auth0|guest_a",  name: "Guest A",  email: "guest@company-a.example",  role: "guest")

  # Users - Company B
  admin_b = User.create!(tenant: tenant_b, auth0_uid: "auth0|admin_b", name: "Admin B", email: "admin@company-b.example", role: "admin")

  # Projects - Company A
  project_a1 = Project.create!(tenant: tenant_a, name: "Website Redesign")
  project_a2 = Project.create!(tenant: tenant_a, name: "API Development")

  # Projects - Company B
  project_b1 = Project.create!(tenant: tenant_b, name: "Mobile App")

  # Tasks - Company A
  Task.create!(tenant: tenant_a, project: project_a1, user: admin_a,  name: "Design mockups",     status: "done")
  Task.create!(tenant: tenant_a, project: project_a1, user: member_a, name: "Implement frontend", status: "doing")
  Task.create!(tenant: tenant_a, project: project_a1,                 name: "Write tests",        status: "todo")
  Task.create!(tenant: tenant_a, project: project_a2, user: member_a, name: "Design API schema",  status: "doing")
  Task.create!(tenant: tenant_a, project: project_a2,                 name: "Setup CI/CD",        status: "todo")

  # Tasks - Company B
  Task.create!(tenant: tenant_b, project: project_b1, user: admin_b, name: "Setup React Native", status: "doing")
  Task.create!(tenant: tenant_b, project: project_b1,                name: "Design screens",     status: "todo")

  puts "Seed completed:"
  puts "  Tenants:  #{Tenant.count}"
  puts "  Users:    #{User.count}"
  puts "  Projects: #{Project.count}"
  puts "  Tasks:    #{Task.count}"
end
