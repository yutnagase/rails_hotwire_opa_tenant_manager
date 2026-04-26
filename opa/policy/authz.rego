package authz

default allow = false

# admin: 全操作可能
allow if input.user.role == "admin"

# member: 読み取り・作成・更新が可能
allow if {
    input.user.role == "member"
    input.action in ["read", "create", "update"]
}

# guest: 読み取りのみ
allow if {
    input.user.role == "guest"
    input.action == "read"
}
