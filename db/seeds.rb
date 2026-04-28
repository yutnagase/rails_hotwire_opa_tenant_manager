# seed専用: acts_as_tenantのテナントスコープ制約を明示的に外して実行する。
# 本番リクエストパスでは ActsAsTenant.without_tenant は使用しない。
ActsAsTenant.without_tenant do
  # Tenants
  tenant_a = Tenant.create!(name: "Company A", subdomain: "company-a")
  tenant_b = Tenant.create!(name: "Company B", subdomain: "company-b")

  # Seed Admin Users (auth0_uidはAuth0初回ログイン時にemailで紐付けて更新される)
  admin_a = User.create!(
    tenant: tenant_a,
    auth0_uid: "seed|admin_a",
    name: "Admin A",
    email: ENV.fetch("SEED_ADMIN_EMAIL_COMPANY_A"),
    role: "admin",
    seed_admin: true
  )

  admin_b = User.create!(
    tenant: tenant_b,
    auth0_uid: "seed|admin_b",
    name: "Admin B",
    email: ENV.fetch("SEED_ADMIN_EMAIL_COMPANY_B"),
    role: "admin",
    seed_admin: true
  )

  # Projects - Company A
  project_a1 = Project.create!(tenant: tenant_a, name: "Website Redesign")
  project_a2 = Project.create!(tenant: tenant_a, name: "API Development")

  # Projects - Company B
  project_b1 = Project.create!(tenant: tenant_b, name: "Mobile App")

  # Tasks - Company A
  Task.create!(tenant: tenant_a, project: project_a1, user: admin_a, name: "Design mockups",     status: "done")
  Task.create!(tenant: tenant_a, project: project_a1,                name: "Implement frontend", status: "doing")
  Task.create!(tenant: tenant_a, project: project_a1,                name: "Write tests",        status: "todo")
  Task.create!(tenant: tenant_a, project: project_a2,                name: "Design API schema",  status: "doing")
  Task.create!(tenant: tenant_a, project: project_a2,                name: "Setup CI/CD",        status: "todo")

  # Tasks - Company B
  Task.create!(tenant: tenant_b, project: project_b1, user: admin_b, name: "Setup React Native", status: "doing")
  Task.create!(tenant: tenant_b, project: project_b1,                name: "Design screens",     status: "todo")

  puts "Seed completed:"
  puts "  Tenants:  #{Tenant.count}"
  puts "  Users:    #{User.count}"
  puts "  Projects: #{Project.count}"
  puts "  Tasks:    #{Task.count}"
end
