class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :name, null: false
      t.string :status, null: false, default: "todo"

      t.timestamps
    end
  end
end
