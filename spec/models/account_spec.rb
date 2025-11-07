require 'rails_helper'

RSpec.describe Account, type: :model do
  describe 'associations' do
    it 'has many users' do
      account = Account.create(name: 'Test Account')
      user = User.create(account: account, name: 'Test User', email: 'test@example.com')
      expect(account.users).to include(user)
    end

    it 'has many subscriptions' do
      account = Account.create(name: 'Test Account')
      product = Product.create(name: 'Test Product')
      subscription = Subscription.create(
        account: account,
        product: product,
        number_of_licenses: 10,
        issued_at: Time.current,
        expires_at: 1.year.from_now
      )
      expect(account.subscriptions).to include(subscription)
    end
  end

  describe 'validations' do
    it 'is valid with a name' do
      account = Account.new(name: 'Test Account')
      expect(account).to be_valid
    end

    it 'is invalid without a name' do
      account = Account.new(name: nil)
      expect(account).not_to be_valid
    end
  end
end
