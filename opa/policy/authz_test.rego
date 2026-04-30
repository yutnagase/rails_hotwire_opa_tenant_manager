package authz

import rego.v1

# admin: 全操作許可
test_admin_allow_read if { allow with input as {"user": {"role": "admin"}, "action": "read"} }
test_admin_allow_create if { allow with input as {"user": {"role": "admin"}, "action": "create"} }
test_admin_allow_update if { allow with input as {"user": {"role": "admin"}, "action": "update"} }
test_admin_allow_delete if { allow with input as {"user": {"role": "admin"}, "action": "delete"} }

# member: read/create/update のみ
test_member_allow_read if { allow with input as {"user": {"role": "member"}, "action": "read"} }
test_member_allow_create if { allow with input as {"user": {"role": "member"}, "action": "create"} }
test_member_allow_update if { allow with input as {"user": {"role": "member"}, "action": "update"} }
test_member_deny_delete if { not allow with input as {"user": {"role": "member"}, "action": "delete"} }

# guest: read のみ
test_guest_allow_read if { allow with input as {"user": {"role": "guest"}, "action": "read"} }
test_guest_deny_create if { not allow with input as {"user": {"role": "guest"}, "action": "create"} }
test_guest_deny_update if { not allow with input as {"user": {"role": "guest"}, "action": "update"} }
test_guest_deny_delete if { not allow with input as {"user": {"role": "guest"}, "action": "delete"} }

# 不明なロールは拒否
test_unknown_role_deny if { not allow with input as {"user": {"role": "unknown"}, "action": "read"} }
