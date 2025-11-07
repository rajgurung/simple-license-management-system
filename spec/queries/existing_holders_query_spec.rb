require 'rails_helper'

RSpec.describe ExistingHoldersQuery do
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

  describe '#user_ids' do
    it 'returns user IDs with active license assignments' do
      user1 = User.create(account: account, name: 'User 1', email: 'user1@test.com')
      user2 = User.create(account: account, name: 'User 2', email: 'user2@test.com')

      LicenseAssignment.create(account: account, product: product, user: user1)
      LicenseAssignment.create(account: account, product: product, user: user2)

      expect(query.user_ids).to contain_exactly(user1.id, user2.id)
    end

    it 'returns empty array when no assignments' do
      expect(query.user_ids).to be_empty
    end
  end

  describe '#exclude_from' do
    it 'removes already assigned user IDs from array' do
      user1 = User.create(account: account, name: 'User 1', email: 'user1@test.com')
      user2 = User.create(account: account, name: 'User 2', email: 'user2@test.com')
      user3 = User.create(account: account, name: 'User 3', email: 'user3@test.com')

      LicenseAssignment.create(account: account, product: product, user: user1)

      result = query.exclude_from([user1.id, user2.id, user3.id])
      expect(result).to contain_exactly(user2.id, user3.id)
    end
  end
end
