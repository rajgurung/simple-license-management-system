class MakeAccountIdOptionalForAdminUsers < ActiveRecord::Migration[8.0]
  def change
    # Remove existing foreign key constraint
    remove_foreign_key :users, :accounts

    # Remove existing email index (currently unique across all users)
    remove_index :users, :email

    # Make account_id nullable
    change_column_null :users, :account_id, true

    # Re-add foreign key constraint that allows NULL
    add_foreign_key :users, :accounts

    # Add composite unique index for regular users (email + account_id)
    # This ensures email is unique within an account for non-admin users
    add_index :users, [:email, :account_id],
              unique: true,
              where: "admin = false",
              name: "index_users_on_email_and_account_id_where_not_admin"

    # Add unique index for admin users (email only, no account_id)
    # This ensures email is globally unique for admin users
    add_index :users, :email,
              unique: true,
              where: "admin = true",
              name: "index_users_on_email_where_admin"
  end
end
