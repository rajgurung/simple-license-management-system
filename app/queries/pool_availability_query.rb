# Calculates license pool availability for an account+product combination.
#
# This query object provides real-time capacity information by:
# 1. Summing total licenses from ACTIVE subscriptions only (expired subscriptions excluded)
# 2. Counting assigned licenses that belong to active subscriptions
# 3. Computing available capacity (total - assigned)
#
# Uses query-time filtering for subscription expiration (no background jobs needed).
# Includes DISTINCT to prevent double-counting assignments across multiple subscriptions.
#
# @example Check available licenses
#   query = PoolAvailabilityQuery.new(account_id: 1, product_id: 2)
#   query.available_licenses  # => 45
#
# @example Get detailed capacity breakdown
#   query.capacity_details
#   # => { total: 100, used: 55, available: 45 }
class PoolAvailabilityQuery
  attr_reader :account_id, :product_id

  # Initializes the capacity query for a specific account+product pool.
  #
  # @param account_id [Integer] The account ID
  # @param product_id [Integer] The product ID
  def initialize(account_id:, product_id:)
    @account_id = account_id
    @product_id = product_id
  end

  # Returns the number of available (unassigned) licenses.
  #
  # @return [Integer] Number of licenses available for assignment
  #
  # @example
  #   query.available_licenses  # => 45
  def available_licenses
    total_licenses - assigned_licenses
  end

  # Calculates total licenses from active subscriptions.
  #
  # Only counts licenses from subscriptions where expires_at > current time.
  # Multiple active subscriptions for the same account+product are summed together.
  #
  # @return [Integer] Total number of licenses in the pool
  #
  # @example
  #   query.total_licenses  # => 100
  def total_licenses
    Subscription
      .active
      .where(account_id: account_id, product_id: product_id)
      .sum(:number_of_licenses)
  end

  # Counts currently assigned licenses from active subscriptions.
  #
  # Uses DISTINCT to prevent double-counting if a user has assignments across
  # multiple active subscriptions (edge case). Only counts assignments where
  # the associated subscription is still active.
  #
  # @return [Integer] Number of assigned licenses
  #
  # @example
  #   query.assigned_licenses  # => 55
  def assigned_licenses
    LicenseAssignment
      .where(account_id: account_id, product_id: product_id)
      .joins("INNER JOIN subscriptions ON subscriptions.account_id = license_assignments.account_id
              AND subscriptions.product_id = license_assignments.product_id")
      .where('subscriptions.expires_at > ?', Time.current)
      .distinct
      .count
  end

  # Returns detailed capacity breakdown with total, used, and available counts.
  #
  # @return [Hash] Capacity details with keys:
  #   - :total [Integer] Total licenses from active subscriptions
  #   - :used [Integer] Currently assigned licenses
  #   - :available [Integer] Licenses available for assignment
  #
  # @example
  #   query.capacity_details
  #   # => { total: 100, used: 55, available: 45 }
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
