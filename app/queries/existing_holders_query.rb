class ExistingHoldersQuery
  attr_reader :account_id, :product_id

  def initialize(account_id:, product_id:)
    @account_id = account_id
    @product_id = product_id
  end

  def user_ids
    LicenseAssignment
      .where(account_id: account_id, product_id: product_id)
      .joins("INNER JOIN subscriptions ON subscriptions.account_id = license_assignments.account_id
              AND subscriptions.product_id = license_assignments.product_id")
      .where('subscriptions.expires_at > ?', Time.current)
      .distinct
      .pluck(:user_id)
  end

  def exclude_from(user_ids_array)
    user_ids_array - user_ids
  end
end
