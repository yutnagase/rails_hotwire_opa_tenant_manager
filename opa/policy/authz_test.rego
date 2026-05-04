package authz

import rego.v1

# admin: 一般リソースの全操作許可
test_admin_allow_read if { allow with input as {"user": {"role": "admin"}, "action": "read", "resource": "project"} }
test_admin_allow_create if { allow with input as {"user": {"role": "admin"}, "action": "create", "resource": "project"} }
test_admin_allow_update if { allow with input as {"user": {"role": "admin"}, "action": "update", "resource": "task"} }
test_admin_allow_delete if { allow with input as {"user": {"role": "admin"}, "action": "delete", "resource": "task"} }

# admin: admin_user リソースの操作許可
test_admin_allow_admin_user_read if { allow with input as {"user": {"role": "admin"}, "action": "read", "resource": "admin_user"} }
test_admin_allow_admin_user_update if { allow with input as {"user": {"role": "admin"}, "action": "update", "resource": "admin_user"} }

# member: read/create/update のみ
test_member_allow_read if { allow with input as {"user": {"role": "member"}, "action": "read", "resource": "project"} }
test_member_allow_create if { allow with input as {"user": {"role": "member"}, "action": "create", "resource": "task"} }
test_member_allow_update if { allow with input as {"user": {"role": "member"}, "action": "update", "resource": "task"} }
test_member_deny_delete if { not allow with input as {"user": {"role": "member"}, "action": "delete", "resource": "task"} }

# member: admin_user リソースは拒否
test_member_deny_admin_user_read if { not allow with input as {"user": {"role": "member"}, "action": "read", "resource": "admin_user"} }
test_member_deny_admin_user_update if { not allow with input as {"user": {"role": "member"}, "action": "update", "resource": "admin_user"} }

# guest: read のみ
test_guest_allow_read if { allow with input as {"user": {"role": "guest"}, "action": "read", "resource": "project"} }
test_guest_deny_create if { not allow with input as {"user": {"role": "guest"}, "action": "create", "resource": "task"} }
test_guest_deny_update if { not allow with input as {"user": {"role": "guest"}, "action": "update", "resource": "task"} }
test_guest_deny_delete if { not allow with input as {"user": {"role": "guest"}, "action": "delete", "resource": "task"} }

# guest: admin_user リソースは拒否
test_guest_deny_admin_user_read if { not allow with input as {"user": {"role": "guest"}, "action": "read", "resource": "admin_user"} }

# 不明なロールは拒否
test_unknown_role_deny if { not allow with input as {"user": {"role": "unknown"}, "action": "read", "resource": "project"} }
