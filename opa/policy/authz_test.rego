package authz

import rego.v1

# === tenant ===
test_tenant_admin_read if { allow with input as {"user": {"role": "admin"}, "action": "read", "resource": "tenant"} }
test_tenant_admin_update if { allow with input as {"user": {"role": "admin"}, "action": "update", "resource": "tenant"} }
test_tenant_member_read if { allow with input as {"user": {"role": "member"}, "action": "read", "resource": "tenant"} }
test_tenant_member_deny_update if { not allow with input as {"user": {"role": "member"}, "action": "update", "resource": "tenant"} }
test_tenant_guest_read if { allow with input as {"user": {"role": "guest"}, "action": "read", "resource": "tenant"} }
test_tenant_guest_deny_update if { not allow with input as {"user": {"role": "guest"}, "action": "update", "resource": "tenant"} }

# === project ===
test_project_admin_read if { allow with input as {"user": {"role": "admin"}, "action": "read", "resource": "project"} }
test_project_admin_create if { allow with input as {"user": {"role": "admin"}, "action": "create", "resource": "project"} }
test_project_admin_update if { allow with input as {"user": {"role": "admin"}, "action": "update", "resource": "project"} }
test_project_admin_delete if { allow with input as {"user": {"role": "admin"}, "action": "delete", "resource": "project"} }
test_project_member_read if { allow with input as {"user": {"role": "member"}, "action": "read", "resource": "project"} }
test_project_member_create if { allow with input as {"user": {"role": "member"}, "action": "create", "resource": "project"} }
test_project_member_update if { allow with input as {"user": {"role": "member"}, "action": "update", "resource": "project"} }
test_project_member_deny_delete if { not allow with input as {"user": {"role": "member"}, "action": "delete", "resource": "project"} }
test_project_guest_read if { allow with input as {"user": {"role": "guest"}, "action": "read", "resource": "project"} }
test_project_guest_deny_create if { not allow with input as {"user": {"role": "guest"}, "action": "create", "resource": "project"} }
test_project_guest_deny_update if { not allow with input as {"user": {"role": "guest"}, "action": "update", "resource": "project"} }
test_project_guest_deny_delete if { not allow with input as {"user": {"role": "guest"}, "action": "delete", "resource": "project"} }

# === task ===
test_task_admin_read if { allow with input as {"user": {"role": "admin"}, "action": "read", "resource": "task"} }
test_task_admin_create if { allow with input as {"user": {"role": "admin"}, "action": "create", "resource": "task"} }
test_task_admin_update if { allow with input as {"user": {"role": "admin"}, "action": "update", "resource": "task"} }
test_task_admin_delete if { allow with input as {"user": {"role": "admin"}, "action": "delete", "resource": "task"} }
test_task_member_read if { allow with input as {"user": {"role": "member"}, "action": "read", "resource": "task"} }
test_task_member_create if { allow with input as {"user": {"role": "member"}, "action": "create", "resource": "task"} }
test_task_member_update if { allow with input as {"user": {"role": "member"}, "action": "update", "resource": "task"} }
test_task_member_deny_delete if { not allow with input as {"user": {"role": "member"}, "action": "delete", "resource": "task"} }
test_task_guest_read if { allow with input as {"user": {"role": "guest"}, "action": "read", "resource": "task"} }
test_task_guest_deny_create if { not allow with input as {"user": {"role": "guest"}, "action": "create", "resource": "task"} }
test_task_guest_deny_update if { not allow with input as {"user": {"role": "guest"}, "action": "update", "resource": "task"} }
test_task_guest_deny_delete if { not allow with input as {"user": {"role": "guest"}, "action": "delete", "resource": "task"} }

# === user ===
test_user_admin_read if { allow with input as {"user": {"role": "admin"}, "action": "read", "resource": "user"} }
test_user_admin_update if { allow with input as {"user": {"role": "admin"}, "action": "update", "resource": "user"} }
test_user_member_read if { allow with input as {"user": {"role": "member"}, "action": "read", "resource": "user"} }
test_user_member_deny_update if { not allow with input as {"user": {"role": "member"}, "action": "update", "resource": "user"} }
test_user_guest_read if { allow with input as {"user": {"role": "guest"}, "action": "read", "resource": "user"} }
test_user_guest_deny_update if { not allow with input as {"user": {"role": "guest"}, "action": "update", "resource": "user"} }

# === unknown role ===
test_unknown_role_deny if { not allow with input as {"user": {"role": "unknown"}, "action": "read", "resource": "project"} }
