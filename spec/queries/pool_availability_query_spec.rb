require 'rails_helper'

RSpec.describe PoolAvailabilityQuery do
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

  let(:query) { described_class.new(account_id: account.id, product_id: product.id) }

  describe '#total_licenses' do
    it 'returns sum of active subscription licenses' do
      expect(query.total_licenses).to eq(10)
    end

    it 'only counts active subscriptions' do
      Subscription.create(
        account: account,
        product: product,
        number_of_licenses: 5,
        issued_at: 2.months.ago,
        expires_at: 1.month.ago  # expired
      )
      expect(query.total_licenses).to eq(10)  # Only active subscription
    end
  end

  describe '#assigned_licenses' do
    it 'returns count of active assignments' do
      user1 = User.create(account: account, name: 'User 1', email: 'user1@test.com')
      user2 = User.create(account: account, name: 'User 2', email: 'user2@test.com')

      LicenseAssignment.create(account: account, product: product, user: user1)
      LicenseAssignment.create(account: account, product: product, user: user2)

      expect(query.assigned_licenses).to eq(2)
    end
  end

  describe '#available_licenses' do
    it 'returns total minus assigned' do
      user = User.create(account: account, name: 'User', email: 'user@test.com')
      LicenseAssignment.create(account: account, product: product, user: user)

      expect(query.available_licenses).to eq(9)  # 10 - 1
    end
  end

  describe '#capacity_details' do
    it 'returns hash with total, used, and available' do
      3.times do |i|
        user = User.create(account: account, name: "User #{i}", email: "user#{i}@test.com")
        LicenseAssignment.create(account: account, product: product, user: user)
      end

      details = query.capacity_details
      expect(details[:total]).to eq(10)
      expect(details[:used]).to eq(3)
      expect(details[:available]).to eq(7)
    end
  end
end
