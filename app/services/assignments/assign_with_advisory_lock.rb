require_relative 'no_capacity_error'

module Assignments
  class AssignWithAdvisoryLock
    attr_reader :account_id, :product_id, :user_ids, :mode

    def initialize(account_id:, product_id:, user_ids:, mode: :all_or_nothing)
      @account_id = account_id
      @product_id = product_id
      @user_ids = Array(user_ids).map(&:to_i)
      @mode = mode.to_sym
    end

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

    def acquire_advisory_lock
      lock_key = Concurrency::AdvisoryLockKey.for_pool(account_id, product_id)
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
