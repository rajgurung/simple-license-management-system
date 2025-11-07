class RemoveArchivedAtFromSubscriptions < ActiveRecord::Migration[8.0]
  def change
    remove_column :subscriptions, :archived_at, :datetime
  end
end
