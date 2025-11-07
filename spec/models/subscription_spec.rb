require 'rails_helper'

RSpec.describe Subscription, type: :model do
  let(:account) { Account.create(name: 'Test Account') }
  let(:product) { Product.create(name: 'Test Product') }

  describe 'validations' do
    it 'is valid with all required fields' do
      subscription = Subscription.new(
        account: account,
        product: product,
        number_of_licenses: 10,
        issued_at: Time.current,
        expires_at: 1.year.from_now
      )
      expect(subscription).to be_valid
    end

    it 'is invalid with zero licenses' do
      subscription = Subscription.new(
        account: account,
        product: product,
        number_of_licenses: 0,
        issued_at: Time.current,
        expires_at: 1.year.from_now
      )
      expect(subscription).not_to be_valid
    end

    it 'is invalid with negative licenses' do
      subscription = Subscription.new(
        account: account,
        product: product,
        number_of_licenses: -5,
        issued_at: Time.current,
        expires_at: 1.year.from_now
      )
      expect(subscription).not_to be_valid
    end

    it 'is invalid when expires_at is before issued_at' do
      subscription = Subscription.new(
        account: account,
        product: product,
        number_of_licenses: 10,
        issued_at: 1.day.from_now,
        expires_at: Time.current
      )
      expect(subscription).not_to be_valid
    end
  end

  describe 'scopes' do
    let!(:active_sub) do
      Subscription.create(
        account: account,
        product: product,
        number_of_licenses: 10,
        issued_at: 1.month.ago,
        expires_at: 1.month.from_now
      )
    end

    let!(:recently_expired_sub) do
      Subscription.create(
        account: account,
        product: Product.create(name: 'Product 2'),
        number_of_licenses: 5,
        issued_at: 2.months.ago,
        expires_at: 12.hours.ago
      )
    end

    let!(:expired_sub) do
      Subscription.create(
        account: account,
        product: Product.create(name: 'Product 3'),
        number_of_licenses: 3,
        issued_at: 3.months.ago,
        expires_at: 2.days.ago
      )
    end

    let!(:expiring_soon_sub) do
      Subscription.create(
        account: account,
        product: Product.create(name: 'Product 4'),
        number_of_licenses: 7,
        issued_at: 1.month.ago,
        expires_at: 3.days.from_now
      )
    end

    describe '.active' do
      it 'returns only active subscriptions' do
        expect(Subscription.active).to include(active_sub, expiring_soon_sub)
        expect(Subscription.active).not_to include(recently_expired_sub, expired_sub)
      end
    end

    describe '.expired' do
      it 'returns all expired subscriptions (including recently expired)' do
        expect(Subscription.expired).to include(recently_expired_sub, expired_sub)
        expect(Subscription.expired).not_to include(active_sub, expiring_soon_sub)
      end
    end
  end

  describe 'instance methods' do
    it '#active? returns true for active subscription' do
      subscription = Subscription.create(
        account: account,
        product: product,
        number_of_licenses: 10,
        issued_at: Time.current,
        expires_at: 1.month.from_now
      )
      expect(subscription.active?).to be true
    end

    it '#active? returns false for expired subscription' do
      subscription = Subscription.create(
        account: account,
        product: product,
        number_of_licenses: 10,
        issued_at: 2.months.ago,
        expires_at: 1.month.ago
      )
      expect(subscription.active?).to be false
    end

    it '#expired? returns true for expired subscription' do
      subscription = Subscription.create(
        account: account,
        product: product,
        number_of_licenses: 10,
        issued_at: 2.months.ago,
        expires_at: 1.hour.ago
      )
      expect(subscription.expired?).to be true
    end

    it '#expired? returns false for active subscription' do
      subscription = Subscription.create(
        account: account,
        product: product,
        number_of_licenses: 10,
        issued_at: Time.current,
        expires_at: 1.month.from_now
      )
      expect(subscription.expired?).to be false
    end

    it '#expiring_soon? returns true for subscription expiring within 7 days' do
      subscription = Subscription.create(
        account: account,
        product: product,
        number_of_licenses: 10,
        issued_at: 1.month.ago,
        expires_at: 3.days.from_now
      )
      expect(subscription.expiring_soon?).to be true
    end

    it '#expiring_soon? returns false for subscription expiring beyond 7 days' do
      subscription = Subscription.create(
        account: account,
        product: product,
        number_of_licenses: 10,
        issued_at: 1.month.ago,
        expires_at: 10.days.from_now
      )
      expect(subscription.expiring_soon?).to be false
    end

    it '#expiring_soon? returns false for expired subscription' do
      subscription = Subscription.create(
        account: account,
        product: product,
        number_of_licenses: 10,
        issued_at: 2.months.ago,
        expires_at: 1.day.ago
      )
      expect(subscription.expiring_soon?).to be false
    end

    it '#days_until_expiry returns correct number of days' do
      subscription = Subscription.create(
        account: account,
        product: product,
        number_of_licenses: 10,
        issued_at: 1.month.ago,
        expires_at: 5.days.from_now
      )
      expect(subscription.days_until_expiry).to eq(5)
    end

    it '#days_until_expiry returns 0 for expired subscription' do
      subscription = Subscription.create(
        account: account,
        product: product,
        number_of_licenses: 10,
        issued_at: 2.months.ago,
        expires_at: 1.day.ago
      )
      expect(subscription.days_until_expiry).to eq(0)
    end
  end
end
