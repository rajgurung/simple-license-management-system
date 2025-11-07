class CreateLicenseAssignments < ActiveRecord::Migration[8.0]
  def change
    create_table :license_assignments do |t|
      t.references :account, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :license_assignments, [:account_id, :product_id, :user_id],
              unique: true, name: 'index_license_assignments_on_account_product_user'
  end
end
