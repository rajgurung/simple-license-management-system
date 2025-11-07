# Identifies users who already hold active licenses for an account+product combination.
#
# This query object is used to implement idempotent license assignments by:
# 1. Finding all existing license holders with active subscriptions
# 2. Filtering them out from requested assignments to prevent duplicates
#
# Only considers licenses backed by ACTIVE subscriptions (expires_at > current time).
# Uses DISTINCT to handle edge cases where users might have multiple assignments.
#
# @example Find existing license holders
#   query = ExistingHoldersQuery.new(account_id: 1, product_id: 2)
#   query.user_ids  # => [10, 11, 12]
#
# @example Filter out existing holders from a request
#   requested_users = [10, 11, 12, 13, 14]
#   eligible_users = query.exclude_from(requested_users)
#   # => [13, 14]  (users 10, 11, 12 already have licenses)
class ExistingHoldersQuery
  attr_reader :account_id, :product_id

  # Initializes the query for a specific account+product pool.
  #
  # @param account_id [Integer] The account ID
  # @param product_id [Integer] The product ID
  def initialize(account_id:, product_id:)
    @account_id = account_id
    @product_id = product_id
  end

  # Returns user IDs of all users who currently hold active licenses.
  #
  # Only includes users whose license assignments are backed by active
  # subscriptions (expires_at > current time). Expired subscription licenses
  # are excluded.
  #
  # @return [Array<Integer>] User IDs of current license holders
  #
  # @example
  #   query.user_ids  # => [10, 11, 12]
  def user_ids
    LicenseAssignment
      .where(account_id: account_id, product_id: product_id)
      .joins("INNER JOIN subscriptions ON subscriptions.account_id = license_assignments.account_id
              AND subscriptions.product_id = license_assignments.product_id")
      .where('subscriptions.expires_at > ?', Time.current)
      .distinct
      .pluck(:user_id)
  end

  # Filters out existing license holders from a list of user IDs.
  #
  # Returns only the user IDs that do NOT currently hold licenses,
  # making assignment operations idempotent.
  #
  # @param user_ids_array [Array<Integer>] User IDs to filter
  # @return [Array<Integer>] User IDs that don't have licenses yet
  #
  # @example
  #   query.exclude_from([10, 11, 12, 13, 14])
  #   # => [13, 14]  (assuming 10, 11, 12 already have licenses)
  def exclude_from(user_ids_array)
    user_ids_array - user_ids
  end
end
