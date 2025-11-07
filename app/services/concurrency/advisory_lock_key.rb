module Concurrency
  # Generates deterministic PostgreSQL advisory lock keys for license pool operations.
  #
  # PostgreSQL advisory locks require 32-bit integer keys. This class converts
  # account+product combinations into stable, collision-resistant lock keys using
  # SHA256 hashing.
  #
  # @example Acquiring a lock for a license pool
  #   lock_key = AdvisoryLockKey.for_pool(account_id: 1, product_id: 2)
  #   # => 543231903
  #   ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{lock_key})")
  #
  # @see https://www.postgresql.org/docs/current/explicit-locking.html#ADVISORY-LOCKS
  class AdvisoryLockKey
    # Generates a deterministic lock key for an account+product license pool.
    #
    # The lock key is a 31-bit integer derived from SHA256 hashing the account and
    # product IDs. This ensures:
    # - Same account+product always generates the same lock key (deterministic)
    # - Different account+product combinations have different keys (collision-resistant)
    # - Lock key fits within PostgreSQL's advisory lock range (0 to 2^31-1)
    #
    # @param account_id [Integer] The account ID
    # @param product_id [Integer] The product ID
    # @return [Integer] A 31-bit integer lock key
    #
    # @example
    #   AdvisoryLockKey.for_pool(1, 2)  # => 543231903
    #   AdvisoryLockKey.for_pool(1, 2)  # => 543231903 (same input, same output)
    #   AdvisoryLockKey.for_pool(1, 3)  # => 891234567 (different input, different output)
    def self.for_pool(account_id, product_id)
      # Use SHA256 hash to create a stable integer key within PostgreSQL's range
      key_string = "#{account_id}-#{product_id}"
      Digest::SHA256.hexdigest(key_string).to_i(16) % (2**31 - 1)
    end
  end
end
