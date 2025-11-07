require_relative 'no_capacity_error'

module Assignments
  # Assigns licenses to users with concurrency-safe operations using PostgreSQL advisory locks.
  #
  # This service ensures atomic license assignments across multiple application servers by:
  # 1. Acquiring a PostgreSQL advisory lock for the account+product pool
  # 2. Filtering out users who already have licenses (idempotency)
  # 3. Checking available capacity against active subscriptions
  # 4. Performing bulk license assignments within a database transaction
  #
  # The service supports two assignment modes:
  # - :all_or_nothing - Assigns all requested licenses or rolls back (strict capacity enforcement)
  # - :partial_fill - Assigns up to available capacity, returns overflow users
  #
  # @example Assign licenses in all-or-nothing mode
  #   service = AssignWithAdvisoryLock.new(
  #     account_id: 1,
  #     product_id: 2,
  #     user_ids: [10, 11, 12],
  #     mode: :all_or_nothing
  #   )
  #   result = service.call
  #   # => { assigned: [10, 11, 12], overflow: [], outcome: 'full' }
  #
  # @example Assign licenses with partial fill mode
  #   service = AssignWithAdvisoryLock.new(
  #     account_id: 1,
  #     product_id: 2,
  #     user_ids: [10, 11, 12, 13, 14],
  #     mode: :partial_fill
  #   )
  #   result = service.call  # Only 3 licenses available
  #   # => { assigned: [10, 11, 12], overflow: [13, 14], outcome: 'partial' }
  #
  # @raise [NoCapacityError] In :all_or_nothing mode when insufficient licenses available
  class AssignWithAdvisoryLock
    attr_reader :account_id, :product_id, :user_ids, :mode

    # Initializes the license assignment service.
    #
    # @param account_id [Integer] The account ID requesting licenses
    # @param product_id [Integer] The product ID for which to assign licenses
    # @param user_ids [Integer, Array<Integer>] Single user ID or array of user IDs to assign licenses to
    # @param mode [Symbol] Assignment mode - :all_or_nothing (default) or :partial_fill
    #
    # @example
    #   AssignWithAdvisoryLock.new(
    #     account_id: 1,
    #     product_id: 2,
    #     user_ids: [10, 11],
    #     mode: :all_or_nothing
    #   )
    def initialize(account_id:, product_id:, user_ids:, mode: :all_or_nothing)
      @account_id = account_id
      @product_id = product_id
      @user_ids = Array(user_ids).map(&:to_i)
      @mode = mode.to_sym
    end

    # Executes the license assignment operation.
    #
    # This method:
    # 1. Acquires a PostgreSQL advisory lock to prevent race conditions
    # 2. Filters out users who already hold licenses (idempotent operation)
    # 3. Checks available capacity from active subscriptions
    # 4. Assigns licenses based on the configured mode
    # 5. Emits structured logs for observability
    #
    # @return [Hash] Assignment result with keys:
    #   - :assigned [Array<Integer>] User IDs that received licenses
    #   - :overflow [Array<Integer>] User IDs that couldn't be assigned (partial_fill mode only)
    #   - :outcome [String] Result status: 'full', 'partial', or 'no_capacity'
    #
    # @raise [NoCapacityError] In :all_or_nothing mode when requested > available
    #
    # @example Successful assignment
    #   result = service.call
    #   result[:assigned]  # => [10, 11, 12]
    #   result[:overflow]  # => []
    #   result[:outcome]   # => 'full'
    #
    # @example Partial assignment
    #   result = service.call  # mode: :partial_fill
    #   result[:assigned]  # => [10, 11]
    #   result[:overflow]  # => [12]
    #   result[:outcome]   # => 'partial'
    def call
      result = nil

      log_event("license_assignment_start",
        account_id: account_id,
        product_id: product_id,
        requested_user_ids: user_ids.size,
        mode: mode
      )

      ActiveRecord::Base.transaction do
        # Step 1: Acquire advisory lock for this pool
        acquire_advisory_lock

        # Step 2: Filter out users who already have licenses
        eligible_user_ids = filter_existing_holders
        filtered_count = user_ids.size - eligible_user_ids.size

        log_event("license_assignment_filter",
          account_id: account_id,
          product_id: product_id,
          requested: user_ids.size,
          filtered_out: filtered_count,
          eligible: eligible_user_ids.size
        )

        # Step 3: Check capacity
        available = calculate_available_capacity
        requested = eligible_user_ids.size

        log_event("license_assignment_capacity_check",
          account_id: account_id,
          product_id: product_id,
          requested: requested,
          available: available
        )

        # Step 4: Handle capacity constraints based on mode
        case mode
        when :all_or_nothing
          if requested > available
            log_event("license_assignment_no_capacity",
              account_id: account_id,
              product_id: product_id,
              requested: requested,
              available: available,
              mode: mode
            )
            raise NoCapacityError.new(requested: requested, available: available)
          end
          users_to_assign = eligible_user_ids
        when :partial_fill
          users_to_assign = eligible_user_ids.first(available)
        else
          raise ArgumentError, "Unknown mode: #{mode}"
        end

        # Step 5: Bulk insert assignments
        if users_to_assign.any?
          assignments_data = users_to_assign.map do |user_id|
            {
              account_id: account_id,
              product_id: product_id,
              user_id: user_id,
              created_at: Time.current,
              updated_at: Time.current
            }
          end

          LicenseAssignment.insert_all(assignments_data)
        end

        result = {
          assigned: users_to_assign,
          overflow: eligible_user_ids - users_to_assign,
          outcome: determine_outcome(requested, users_to_assign.size, available)
        }

        log_event("license_assignment_success",
          account_id: account_id,
          product_id: product_id,
          assigned_count: users_to_assign.size,
          overflow_count: result[:overflow].size,
          outcome: result[:outcome]
        )
      end

      result
    rescue NoCapacityError => e
      # Re-raise to be handled by controller
      raise e
    end

    private

    # SAFE SQL INTERPOLATION: Lock key is a deterministic 31-bit integer generated from
    # SHA256 hash of database IDs (account_id, product_id). No user input involved.
    # The Concurrency::AdvisoryLockKey.for_pool method ensures the value is always a
    # controlled integer within PostgreSQL's advisory lock range (0 to 2^31-1).
    # See: app/services/concurrency/advisory_lock_key.rb for implementation details.
    def acquire_advisory_lock
      lock_key = Concurrency::AdvisoryLockKey.for_pool(account_id, product_id)
      # brakeman:ignore:SQL - Lock key is a controlled integer from hash, not user input
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{lock_key})")
    end

    def filter_existing_holders
      existing = ExistingHoldersQuery.new(
        account_id: account_id,
        product_id: product_id
      ).user_ids

      user_ids - existing
    end

    def calculate_available_capacity
      PoolAvailabilityQuery.new(
        account_id: account_id,
        product_id: product_id
      ).available_licenses
    end

    def determine_outcome(requested, assigned, available)
      if assigned == 0
        'no_capacity'
      elsif assigned < requested
        'partial'
      else
        'full'
      end
    end

    def log_event(event, **data)
      Rails.logger.info({
        ts: Time.current.iso8601,
        level: "info",
        svc: "license_management",
        env: Rails.env,
        event: event,
        **data
      }.to_json)
    end
  end
end
