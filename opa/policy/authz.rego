package authz

default allow = false

import rego.v1

# admin_user リソースは admin のみ操作可能
allow if {
    input.resource == "admin_user"
    input.user.role == "admin"
}

# admin: 全操作可能（admin_user以外）
allow if {
    input.resource != "admin_user"
    input.user.role == "admin"
}

# member: 読み取り・作成・更新が可能（admin_user以外）
allow if {
    input.resource != "admin_user"
    input.user.role == "member"
    input.action in ["read", "create", "update"]
}

# guest: 読み取りのみ（admin_user以外）
allow if {
    input.resource != "admin_user"
    input.user.role == "guest"
    input.action == "read"
}
