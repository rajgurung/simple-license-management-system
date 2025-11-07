require 'rails_helper'

RSpec.describe LicenseAssignment, type: :model do
  let(:account) { Account.create(name: 'Test Account') }
  let(:product) { Product.create(name: 'Test Product') }
  let(:user) { User.create(account: account, name: 'Test User', email: 'test@example.com') }

  describe 'validations' do
    it 'is valid with account, product, and user' do
      assignment = LicenseAssignment.new(account: account, product: product, user: user)
      expect(assignment).to be_valid
    end

    it 'prevents duplicate assignments' do
      LicenseAssignment.create(account: account, product: product, user: user)
      duplicate = LicenseAssignment.new(account: account, product: product, user: user)
      expect(duplicate).not_to be_valid
    end

    it 'allows same user for different products' do
      LicenseAssignment.create(account: account, product: product, user: user)
      other_product = Product.create(name: 'Other Product')
      assignment = LicenseAssignment.new(account: account, product: other_product, user: user)
      expect(assignment).to be_valid
    end
  end

  describe '.active scope' do
    let!(:subscription) do
      Subscription.create(
        account: account,
        product: product,
        number_of_licenses: 10,
        issued_at: 1.month.ago,
        expires_at: 1.month.from_now
      )
    end

    let!(:active_assignment) do
      LicenseAssignment.create(account: account, product: product, user: user)
    end

    it 'includes assignments with active subscriptions' do
      expect(LicenseAssignment.active.pluck(:id)).to include(active_assignment.id)
    end

    context 'with expired subscription' do
      let(:expired_product) { Product.create(name: 'Expired Product') }
      let!(:expired_subscription) do
        Subscription.create(
          account: account,
          product: expired_product,
          number_of_licenses: 5,
          issued_at: 2.months.ago,
          expires_at: 1.month.ago
        )
      end

      let(:other_user) { User.create(account: account, name: 'Other', email: 'other@example.com') }
      let!(:expired_assignment) do
        LicenseAssignment.create(account: account, product: expired_product, user: other_user)
      end

      it 'excludes assignments with expired subscriptions' do
        expect(LicenseAssignment.active.pluck(:id)).not_to include(expired_assignment.id)
      end
    end
  end
end
