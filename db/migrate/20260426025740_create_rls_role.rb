class CreateRlsRole < ActiveRecord::Migration[8.1]
  def up
    role = ENV.fetch("RLS_ROLE", "rails_user")
    role_pw = ENV.fetch("RLS_ROLE_PASSWORD", "rails_password")

    # 1. ROLE作成（NOSUPERUSER / NOBYPASSRLS）
    execute <<~SQL
      DO $$ BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '#{role}') THEN
          CREATE ROLE #{role} WITH LOGIN PASSWORD '#{role_pw}' NOSUPERUSER NOBYPASSRLS;
        END IF;
      END $$;
    SQL

    # 2. テーブル権限付与（GRANTはSET ROLE前に実行すること）
    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{role};"

    # 3. シーケンス権限付与（これがないとINSERT時にnextval()で失敗する）
    execute "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{role};"

    # 4. 今後作成されるオブジェクトにも自動付与
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO #{role};"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO #{role};"
  end

  def down
    role = ENV.fetch("RLS_ROLE", "rails_user")
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM #{role};"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM #{role};"
    execute "REASSIGN OWNED BY #{role} TO postgres;"
    execute "DROP OWNED BY #{role};"
    execute "DROP ROLE IF EXISTS #{role};"
  end
end
