require 'rails_helper'

RSpec.describe Assignments::AssignWithAdvisoryLock do
  let(:account) { Account.create(name: 'Test Account') }
  let(:product) { Product.create(name: 'Test Product') }
  let!(:subscription) do
    Subscription.create(
      account: account,
      product: product,
      number_of_licenses: 10,
      issued_at: 1.month.ago,
      expires_at: 1.month.from_now
    )
  end

  let(:user1) { User.create(account: account, name: 'User 1', email: 'user1@test.com') }
  let(:user2) { User.create(account: account, name: 'User 2', email: 'user2@test.com') }
  let(:user3) { User.create(account: account, name: 'User 3', email: 'user3@test.com') }

  context 'core functionality' do
    describe 'successful assignment' do
      it 'assigns licenses to users' do
        service = described_class.new(
          account_id: account.id,
          product_id: product.id,
          user_ids: [user1.id, user2.id],
          mode: :all_or_nothing
        )

        result = service.call

        expect(result[:outcome]).to eq('full')
        expect(result[:assigned]).to contain_exactly(user1.id, user2.id)
        expect(result[:overflow]).to be_empty
        expect(LicenseAssignment.count).to eq(2)
      end

      it 'uses advisory locks' do
        service = described_class.new(
          account_id: account.id,
          product_id: product.id,
          user_ids: [user1.id],
          mode: :all_or_nothing
        )

        expect(ActiveRecord::Base.connection).to receive(:execute).with(/pg_advisory_xact_lock/).and_call_original
        service.call
      end
    end

    describe 'capacity enforcement' do
      context 'with :all_or_nothing mode' do
        it 'raises NoCapacityError when exceeding capacity' do
          # Create 10 existing assignments (fill capacity)
          10.times do |i|
            u = User.create(account: account, name: "Existing #{i}", email: "existing#{i}@test.com")
            LicenseAssignment.create(account: account, product: product, user: u)
          end

          service = described_class.new(
            account_id: account.id,
            product_id: product.id,
            user_ids: [user1.id],
            mode: :all_or_nothing
          )

          expect { service.call }.to raise_error(Assignments::NoCapacityError) do |error|
            expect(error.requested).to eq(1)
            expect(error.available).to eq(0)
          end
        end

        it 'rolls back transaction on capacity error' do
          10.times do |i|
            u = User.create(account: account, name: "Existing #{i}", email: "existing#{i}@test.com")
            LicenseAssignment.create(account: account, product: product, user: u)
          end

          initial_count = LicenseAssignment.count

          service = described_class.new(
            account_id: account.id,
            product_id: product.id,
            user_ids: [user1.id],
            mode: :all_or_nothing
          )

          begin
            service.call
          rescue Assignments::NoCapacityError
            # Expected
          end

          expect(LicenseAssignment.count).to eq(initial_count)
        end
      end

      context 'with :partial_fill mode' do
        it 'assigns up to available capacity' do
          # Use 7 of 10 licenses
          7.times do |i|
            u = User.create(account: account, name: "Existing #{i}", email: "existing#{i}@test.com")
            LicenseAssignment.create(account: account, product: product, user: u)
          end

          service = described_class.new(
            account_id: account.id,
            product_id: product.id,
            user_ids: [user1.id, user2.id, user3.id],  # Try to assign 3, but only 3 available
            mode: :partial_fill
          )

          result = service.call

          expect(result[:outcome]).to eq('full')
          expect(result[:assigned].size).to eq(3)
          expect(result[:overflow]).to be_empty
          expect(LicenseAssignment.count).to eq(10)
        end

        it 'returns overflow users when partially filled' do
          # Use 9 of 10 licenses
          9.times do |i|
            u = User.create(account: account, name: "Existing #{i}", email: "existing#{i}@test.com")
            LicenseAssignment.create(account: account, product: product, user: u)
          end

          service = described_class.new(
            account_id: account.id,
            product_id: product.id,
            user_ids: [user1.id, user2.id, user3.id],  # Try 3, can only assign 1
            mode: :partial_fill
          )

          result = service.call

          expect(result[:outcome]).to eq('partial')
          expect(result[:assigned].size).to eq(1)
          expect(result[:overflow].size).to eq(2)
        end
      end
    end

    describe 'duplicate prevention' do
      it 'filters out users who already have licenses' do
        LicenseAssignment.create(account: account, product: product, user: user1)

        service = described_class.new(
          account_id: account.id,
          product_id: product.id,
          user_ids: [user1.id, user2.id],
          mode: :all_or_nothing
        )

        result = service.call

        expect(result[:assigned]).to contain_exactly(user2.id)  # Only user2 assigned
        expect(LicenseAssignment.where(user: user1).count).to eq(1)  # user1 still has only 1
      end
    end

    describe 'input validation' do
      it 'raises ArgumentError for unknown mode' do
        service = described_class.new(
          account_id: account.id,
          product_id: product.id,
          user_ids: [user1.id],
          mode: :invalid_mode
        )

        expect { service.call }.to raise_error(ArgumentError, 'Unknown mode: invalid_mode')
      end
    end
  end

  context 'multiple subscriptions' do
    describe 'license counting with multiple active subscriptions' do
      it 'correctly counts licenses when account has multiple active subscriptions' do
        # Create a second active subscription for the same product
        Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 10,
          issued_at: 2.weeks.ago,
          expires_at: 2.months.from_now
        )

        # Now we have 2 subscriptions: total of 20 licenses (10 + 10)
        # Create 10 users total
        all_users = 10.times.map do |i|
          User.create(account: account, name: "User #{i}", email: "user_#{i}@test.com")
        end

        # First, assign 5 of them
        first_five_ids = all_users.first(5).map(&:id)
        service1 = described_class.new(
          account_id: account.id,
          product_id: product.id,
          user_ids: first_five_ids,
          mode: :all_or_nothing
        )

        result1 = service1.call
        expect(result1[:outcome]).to eq('full')
        expect(result1[:assigned].size).to eq(5)
        expect(LicenseAssignment.count).to eq(5)

        # Now send ALL 10 user IDs (5 already assigned + 5 new)
        # This mimics the real-world scenario where the UI sends all selected users
        # The service should be smart enough to:
        # 1. Filter out the 5 already assigned
        # 2. Only assign the 5 new ones
        # 3. Not fail due to double-counting bug
        all_user_ids = all_users.map(&:id)

        service2 = described_class.new(
          account_id: account.id,
          product_id: product.id,
          user_ids: all_user_ids,  # Sending all 10 IDs (5 existing + 5 new)
          mode: :all_or_nothing
        )

        # This should succeed because:
        # - 5 are already assigned (filtered out)
        # - 5 are new (eligible for assignment)
        # - We have 20 total licenses, only using 10
        result2 = service2.call
        expect(result2[:outcome]).to eq('full')
        expect(result2[:assigned].size).to eq(5)  # Only 5 new ones assigned
        expect(LicenseAssignment.count).to eq(10)  # Total of 10 assignments now
      end
    end

    describe 'capacity calculation with multiple subscriptions' do
      it 'handles capacity correctly with multiple subscriptions and partial usage' do
        # Subscription 1: 10 licenses (from let block)
        # Subscription 2: 5 licenses
        Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 5,
          issued_at: 1.week.ago,
          expires_at: 3.months.from_now
        )

        # Total: 15 licenses available
        # Assign 12 users
        users = 12.times.map do |i|
          User.create(account: account, name: "User #{i}", email: "user_#{i}@test.com")
        end

        service = described_class.new(
          account_id: account.id,
          product_id: product.id,
          user_ids: users.map(&:id),
          mode: :all_or_nothing
        )

        result = service.call
        expect(result[:outcome]).to eq('full')
        expect(result[:assigned].size).to eq(12)
        expect(LicenseAssignment.count).to eq(12)

        # Now try to assign 4 more (should fail: 12 + 4 = 16, exceeds 15)
        more_users = 4.times.map do |i|
          User.create(account: account, name: "Extra #{i}", email: "extra_#{i}@test.com")
        end

        service2 = described_class.new(
          account_id: account.id,
          product_id: product.id,
          user_ids: more_users.map(&:id),
          mode: :all_or_nothing
        )

        expect { service2.call }.to raise_error(Assignments::NoCapacityError) do |error|
          expect(error.requested).to eq(4)
          expect(error.available).to eq(3)  # 15 total - 12 used = 3 available
        end
      end
    end
  end

  context 'structured logging' do
    describe 'event logging' do
      it 'logs assignment start event' do
        log_messages = []
        allow(Rails.logger).to receive(:info) do |message|
          log_messages << message
        end

        service = described_class.new(
          account_id: account.id,
          product_id: product.id,
          user_ids: [user1.id],
          mode: :all_or_nothing
        )

        service.call

        start_event = log_messages.map { |m| JSON.parse(m) }.find { |e| e['event'] == 'license_assignment_start' }
        expect(start_event).not_to be_nil
        expect(start_event['account_id']).to eq(account.id)
        expect(start_event['product_id']).to eq(product.id)
        expect(start_event['requested_user_ids']).to eq(1)
        expect(start_event['mode']).to eq('all_or_nothing')
      end

      it 'logs filter event with counts' do
        # Create one existing assignment
        LicenseAssignment.create(account: account, product: product, user: user1)

        log_messages = []
        allow(Rails.logger).to receive(:info) do |message|
          log_messages << message
        end

        service = described_class.new(
          account_id: account.id,
          product_id: product.id,
          user_ids: [user1.id, user2.id],  # user1 already assigned, user2 new
          mode: :all_or_nothing
        )

        service.call

        filter_event = log_messages.map { |m| JSON.parse(m) }.find { |e| e['event'] == 'license_assignment_filter' }
        expect(filter_event).not_to be_nil
        expect(filter_event['requested']).to eq(2)
        expect(filter_event['filtered_out']).to eq(1)
        expect(filter_event['eligible']).to eq(1)
      end

      it 'logs capacity check event' do
        log_messages = []
        allow(Rails.logger).to receive(:info) do |message|
          log_messages << message
        end

        service = described_class.new(
          account_id: account.id,
          product_id: product.id,
          user_ids: [user1.id, user2.id],
          mode: :all_or_nothing
        )

        service.call

        capacity_event = log_messages.map { |m| JSON.parse(m) }.find { |e| e['event'] == 'license_assignment_capacity_check' }
        expect(capacity_event).not_to be_nil
        expect(capacity_event['requested']).to eq(2)
        expect(capacity_event['available']).to eq(10)
      end

      it 'logs success event with outcome' do
        log_messages = []
        allow(Rails.logger).to receive(:info) do |message|
          log_messages << message
        end

        service = described_class.new(
          account_id: account.id,
          product_id: product.id,
          user_ids: [user1.id, user2.id],
          mode: :all_or_nothing
        )

        service.call

        success_event = log_messages.map { |m| JSON.parse(m) }.find { |e| e['event'] == 'license_assignment_success' }
        expect(success_event).not_to be_nil
        expect(success_event['assigned_count']).to eq(2)
        expect(success_event['overflow_count']).to eq(0)
        expect(success_event['outcome']).to eq('full')
      end

      it 'logs no capacity event when exceeding limit' do
        # Fill all 10 licenses
        10.times do |i|
          u = User.create(account: account, name: "Existing #{i}", email: "existing#{i}@test.com")
          LicenseAssignment.create(account: account, product: product, user: u)
        end

        log_messages = []
        allow(Rails.logger).to receive(:info) do |message|
          log_messages << message
        end

        service = described_class.new(
          account_id: account.id,
          product_id: product.id,
          user_ids: [user1.id],
          mode: :all_or_nothing
        )

        expect { service.call }.to raise_error(Assignments::NoCapacityError)

        no_capacity_event = log_messages.map { |m| JSON.parse(m) }.find { |e| e['event'] == 'license_assignment_no_capacity' }
        expect(no_capacity_event).not_to be_nil
        expect(no_capacity_event['requested']).to eq(1)
        expect(no_capacity_event['available']).to eq(0)
        expect(no_capacity_event['mode']).to eq('all_or_nothing')
      end
    end

    describe 'log format' do
      it 'logs all events in JSON format with required fields' do
        log_messages = []
        allow(Rails.logger).to receive(:info) do |message|
          log_messages << message
        end

        service = described_class.new(
          account_id: account.id,
          product_id: product.id,
          user_ids: [user1.id],
          mode: :all_or_nothing
        )

        service.call

        # Verify we got multiple log messages
        expect(log_messages.size).to be >= 4

        # Verify each message is valid JSON with required fields
        log_messages.each do |message|
          log_data = JSON.parse(message)
          expect(log_data).to have_key('ts')
          expect(log_data).to have_key('level')
          expect(log_data).to have_key('svc')
          expect(log_data).to have_key('env')
          expect(log_data).to have_key('event')
          expect(log_data['svc']).to eq('license_management')
        end
      end
    end
  end
end
