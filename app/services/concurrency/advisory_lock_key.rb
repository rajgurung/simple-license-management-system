module Concurrency
  class AdvisoryLockKey
    # Generate a unique lock key for account+product pool
    def self.for_pool(account_id, product_id)
      # Use hashtext to create a stable integer key
      key_string = "#{account_id}-#{product_id}"
      Digest::SHA256.hexdigest(key_string).to_i(16) % (2**31 - 1)
    end
  end
end
