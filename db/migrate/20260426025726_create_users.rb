class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :auth0_uid, null: false
      t.string :name, null: false
      t.string :email, null: false
      t.string :role, null: false, default: "member"

      t.timestamps
    end

    add_index :users, :auth0_uid, unique: true
  end
end
