class AddSeedAdminToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :seed_admin, :boolean, null: false, default: false

    # auth0_uidのunique制約をtenant_idとの複合uniqueに変更
    # seedユーザーはプレースホルダーuidを持つため、グローバルuniqueだと衝突する
    remove_index :users, :auth0_uid
    add_index :users, [ :auth0_uid, :tenant_id ], unique: true
  end
end
