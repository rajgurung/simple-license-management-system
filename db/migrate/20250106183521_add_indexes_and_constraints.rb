class AddIndexesAndConstraints < ActiveRecord::Migration[8.0]
  def change
    # Add check constraint for positive license count
    execute <<-SQL
      ALTER TABLE subscriptions
      ADD CONSTRAINT check_positive_licenses
      CHECK (number_of_licenses > 0);
    SQL

    # Add check constraint for valid date range
    execute <<-SQL
      ALTER TABLE subscriptions
      ADD CONSTRAINT check_valid_date_range
      CHECK (expires_at > issued_at);
    SQL
  end
end
