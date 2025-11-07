require 'rails_helper'

RSpec.describe 'Accounts', type: :request do
  let(:account) { Account.create(name: 'Test Account') }
  let!(:admin_user) do
    User.create(
      name: 'Admin User',
      email: 'admin@test.com',
      admin: true,
      username: 'admin',
      password: 'password123'
    )
  end

  before do
    post login_path, params: {
      username: 'admin',
      password: 'password123'
    }
  end

  describe 'GET /accounts' do
    it 'lists all accounts' do
      get accounts_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /accounts/:id' do
    it 'shows account details' do
      get account_path(account)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /accounts/new' do
    it 'renders new account form' do
      get new_account_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /accounts' do
    context 'with valid params' do
      it 'creates a new account' do
        expect {
          post accounts_path, params: {
            account: { name: 'New Account' }
          }
        }.to change(Account, :count).by(1)

        expect(response).to redirect_to(Account.last)
      end
    end

    context 'with invalid params' do
      it 'does not create account' do
        expect {
          post accounts_path, params: {
            account: { name: '' }
          }
        }.not_to change(Account, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /accounts/:id/edit' do
    it 'renders edit form' do
      get edit_account_path(account)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH /accounts/:id' do
    context 'with valid params' do
      it 'updates the account' do
        patch account_path(account), params: {
          account: { name: 'Updated Name' }
        }

        expect(account.reload.name).to eq('Updated Name')
        expect(response).to redirect_to(account)
      end
    end

    context 'with invalid params' do
      it 'does not update account' do
        original_name = account.name

        patch account_path(account), params: {
          account: { name: '' }
        }

        expect(account.reload.name).to eq(original_name)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE /accounts/:id' do
    it 'deletes the account' do
      account_to_delete = Account.create(name: 'Account to Delete')

      expect {
        delete account_path(account_to_delete)
      }.to change(Account, :count).by(-1)

      expect(response).to redirect_to(accounts_path)
    end
  end

  describe 'GET /accounts/:id license counts' do
    let(:product) { Product.create(name: 'Test Product') }
    let(:user1) { User.create(account: account, name: 'User 1', email: 'user1@test.com') }
    let(:user2) { User.create(account: account, name: 'User 2', email: 'user2@test.com') }
    let(:user3) { User.create(account: account, name: 'User 3', email: 'user3@test.com') }

    context 'license pool count' do
      it 'excludes expired subscriptions from license pool total' do
        # Active subscription with 10 licenses
        active_sub = Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 10,
          issued_at: 1.month.ago,
          expires_at: 1.month.from_now
        )

        # Expired subscription with 5 licenses (should NOT be counted in total)
        expired_sub = Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 5,
          issued_at: 3.months.ago,
          expires_at: 1.day.ago
        )

        # Assign 2 licenses (they match the active subscription in JOIN)
        LicenseAssignment.create(account: account, product: product, user: user1)
        LicenseAssignment.create(account: account, product: product, user: user2)

        get account_path(account)
        expect(response).to have_http_status(:ok)

        # Should show 2/10 (only active subscription total)
        # Not 2/15 (which would include expired subscription's 5 licenses)
        expect(response.body).to include('2/10')
        expect(response.body).not_to include('2/15')
      end

      it 'shows 0/10 when active subscription has no assignments' do
        # Active subscription with 10 licenses
        active_sub = Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 10,
          issued_at: 1.month.ago,
          expires_at: 1.month.from_now
        )

        # Don't create any assignments

        get account_path(account)
        expect(response).to have_http_status(:ok)

        # Should show 0/10 (no assignments, 10 active licenses)
        expect(response.body).to include('0/10')
      end

      it 'handles multiple active subscriptions correctly with distinct count' do
        # Two active subscriptions for same product
        sub1 = Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 10,
          issued_at: 1.month.ago,
          expires_at: 1.month.from_now
        )

        sub2 = Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 10,
          issued_at: 2.weeks.ago,
          expires_at: 2.months.from_now
        )

        # Assign 5 licenses (each assignment matches BOTH subscriptions in JOIN)
        LicenseAssignment.create(account: account, product: product, user: user1)
        LicenseAssignment.create(account: account, product: product, user: user2)
        LicenseAssignment.create(account: account, product: product, user: user3)

        get account_path(account)
        expect(response).to have_http_status(:ok)

        # Should show 3/20 (distinct count, not double-counted)
        # Without .distinct it would show 6/20
        expect(response.body).to include('3/20')
      end
    end

    context 'per-product counts' do
      it 'shows correct per-product counts using PoolAvailabilityQuery' do
        # Active subscription
        active_sub = Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 10,
          issued_at: 1.month.ago,
          expires_at: 1.month.from_now
        )

        # Expired subscription for same product
        expired_sub = Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 5,
          issued_at: 3.months.ago,
          expires_at: 1.day.ago
        )

        # Assign 3 licenses
        LicenseAssignment.create(account: account, product: product, user: user1)
        LicenseAssignment.create(account: account, product: product, user: user2)
        LicenseAssignment.create(account: account, product: product, user: user3)

        get account_path(account)
        expect(response).to have_http_status(:ok)

        # Per-product count should show 3/10 (only active subscription)
        expect(response.body).to include('3/10 licenses')
      end

      it 'shows correct per-product counts with multiple active subscriptions' do
        product2 = Product.create(name: 'Product 2')

        # Product 1: Two active subscriptions (10 + 5 = 15 licenses)
        sub1 = Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 10,
          issued_at: 1.month.ago,
          expires_at: 1.month.from_now
        )

        sub2 = Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 5,
          issued_at: 2.weeks.ago,
          expires_at: 2.months.from_now
        )

        # Assign 7 licenses to product 1
        7.times do |i|
          u = User.create(account: account, name: "User #{i}", email: "user#{i}@test.com")
          LicenseAssignment.create(account: account, product: product, user: u)
        end

        get account_path(account)
        expect(response).to have_http_status(:ok)

        # Should show 7/15 (distinct count with multiple subscriptions)
        expect(response.body).to include('7/15 licenses')
      end
    end

    context 'expired subscriptions section' do
      it 'shows historical data for expired subscriptions' do
        product2 = Product.create(name: 'Expired Product')

        # Expired subscription
        expired_sub = Subscription.create(
          account: account,
          product: product2,
          number_of_licenses: 5,
          issued_at: 3.months.ago,
          expires_at: 1.day.ago
        )

        # Assign 3 licenses (historical assignments)
        LicenseAssignment.create(account: account, product: product2, user: user1)
        LicenseAssignment.create(account: account, product: product2, user: user2)
        LicenseAssignment.create(account: account, product: product2, user: user3)

        get account_path(account)
        expect(response).to have_http_status(:ok)

        # Expired section should show 3/5 (historical count)
        expect(response.body).to include('Expired Subscriptions')
        # The count appears in the expired section, we just verify it renders
        expect(response.body).to include(product2.name)
      end
    end
  end
end
