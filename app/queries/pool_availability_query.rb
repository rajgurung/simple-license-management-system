class PoolAvailabilityQuery
  attr_reader :account_id, :product_id

  def initialize(account_id:, product_id:)
    @account_id = account_id
    @product_id = product_id
  end

  def available_licenses
    total_licenses - assigned_licenses
  end

  def total_licenses
    Subscription
      .active
      .where(account_id: account_id, product_id: product_id)
      .sum(:number_of_licenses)
  end

  def assigned_licenses
    LicenseAssignment
      .where(account_id: account_id, product_id: product_id)
      .joins("INNER JOIN subscriptions ON subscriptions.account_id = license_assignments.account_id
              AND subscriptions.product_id = license_assignments.product_id")
      .where('subscriptions.expires_at > ?', Time.current)
      .distinct
      .count
  end

  def capacity_details
    total = total_licenses
    used = assigned_licenses
    {
      total: total,
      used: used,
      available: total - used
    }
  end
end
