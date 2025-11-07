class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :email, null: false
      t.boolean :admin, null: false, default: false
      t.string :username
      t.string :password_digest

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :username, unique: true, where: "admin = true"
  end
end
