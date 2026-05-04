class CreateRlsRole < ActiveRecord::Migration[8.1]
  # ROLE作成はマイグレーションの責務ではなくインフラレイヤーで行う
  # 開発環境: docker-entrypoint-initdb.d/01_create_rls_role.sql
  # 本番環境: IaC等で管理
  def up
    role = ENV.fetch("RLS_ROLE", "rails_user")

    # 1. テーブル権限付与（GRANTはSET ROLE前に実行すること）
    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{role};"

    # 2. シーケンス権限付与（これがないとINSERT時にnextval()で失敗する）
    execute "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{role};"

    # 3. 今後作成されるオブジェクトにも自動付与
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO #{role};"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO #{role};"
  end

  def down
    role = ENV.fetch("RLS_ROLE", "rails_user")
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM #{role};"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM #{role};"
    execute "REASSIGN OWNED BY #{role} TO postgres;"
    execute "DROP OWNED BY #{role};"
  end
end
