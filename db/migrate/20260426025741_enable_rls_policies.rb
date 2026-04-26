class EnableRlsPolicies < ActiveRecord::Migration[8.1]
  def up
    # tenant_id カラムを持つテーブル: ENABLE RLS → CREATE POLICY の順序厳守
    %w[users projects tasks].each do |table|
      execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;"
      execute <<~SQL
        CREATE POLICY #{table}_tenant_isolation ON #{table}
          FOR ALL
          USING (tenant_id = current_setting('app.current_tenant_id')::bigint);
      SQL
    end

    # tenants テーブルは id で制御
    execute "ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;"
    execute <<~SQL
      CREATE POLICY tenants_isolation ON tenants
        FOR ALL
        USING (id = current_setting('app.current_tenant_id')::bigint);
    SQL

    # 注意: schema_migrations, ar_internal_metadata にはRLSを適用しない
    # これらはマイグレーション実行に必要なため、スーパーユーザーのみがアクセスする
  end

  def down
    %w[users projects tasks].each do |table|
      execute "DROP POLICY IF EXISTS #{table}_tenant_isolation ON #{table};"
      execute "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY;"
    end

    execute "DROP POLICY IF EXISTS tenants_isolation ON tenants;"
    execute "ALTER TABLE tenants DISABLE ROW LEVEL SECURITY;"
  end
end
