package authz

default allow = false

import rego.v1

# --- tenant ---
# 全ロール: read可
allow if {
    input.resource == "tenant"
    input.action == "read"
}
# admin: update可
allow if {
    input.resource == "tenant"
    input.action == "update"
    input.user.role == "admin"
}

# --- project ---
# 全ロール: read可
allow if {
    input.resource == "project"
    input.action == "read"
}
# admin/member: create/update可
allow if {
    input.resource == "project"
    input.action in ["create", "update"]
    input.user.role in ["admin", "member"]
}
# admin: delete可
allow if {
    input.resource == "project"
    input.action == "delete"
    input.user.role == "admin"
}

# --- task ---
# 全ロール: read可
allow if {
    input.resource == "task"
    input.action == "read"
}
# admin/member: create/update可
allow if {
    input.resource == "task"
    input.action in ["create", "update"]
    input.user.role in ["admin", "member"]
}
# admin: delete可
allow if {
    input.resource == "task"
    input.action == "delete"
    input.user.role == "admin"
}

# --- user ---
# 全ロール: read可
allow if {
    input.resource == "user"
    input.action == "read"
}
# admin: update可
allow if {
    input.resource == "user"
    input.action == "update"
    input.user.role == "admin"
}
