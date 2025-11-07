require 'rails_helper'

RSpec.describe 'LicenseAssignments', type: :request do
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

  let!(:admin_user) do
    User.create(
      name: 'Admin User',
      email: 'admin@test.com',
      admin: true,
      username: 'admin',
      password: 'password123'
    )
  end

  let(:user1) { User.create(account: account, name: 'User 1', email: 'user1@test.com') }
  let(:user2) { User.create(account: account, name: 'User 2', email: 'user2@test.com') }
  let(:user3) { User.create(account: account, name: 'User 3', email: 'user3@test.com') }

  before do
    post login_path, params: {
      username: 'admin',
      password: 'password123'
    }
  end

  describe 'GET /accounts/:account_id/products/:product_id/license_assignments' do
    it 'shows license assignment interface' do
      get account_product_license_assignments_path(account, product)
      expect(response).to have_http_status(:ok)
    end

    it 'displays capacity details' do
      3.times do |i|
        user = User.create(account: account, name: "User #{i}", email: "user#{i}@test.com")
        LicenseAssignment.create(account: account, product: product, user: user)
      end

      get account_product_license_assignments_path(account, product)
      expect(response.body).to include('7')  # Available licenses
    end
  end

  describe 'POST /accounts/:account_id/products/:product_id/license_assignments/bulk_assign' do
    context 'with all_or_nothing mode' do
      context 'when capacity is sufficient' do
        it 'assigns licenses to all users' do
          post bulk_assign_account_product_license_assignments_path(account, product), params: {
            user_ids: [user1.id, user2.id],
            mode: 'all_or_nothing'
          }

          expect(response).to redirect_to(account_product_license_assignments_path(account, product))
          expect(LicenseAssignment.count).to eq(2)
          expect(flash[:notice]).to include('Successfully assigned')
        end
      end

      context 'when capacity is exceeded' do
        it 'shows error and does not assign' do
          # Fill capacity
          10.times do |i|
            u = User.create(account: account, name: "Existing #{i}", email: "existing#{i}@test.com")
            LicenseAssignment.create(account: account, product: product, user: u)
          end

          initial_count = LicenseAssignment.count

          post bulk_assign_account_product_license_assignments_path(account, product), params: {
            user_ids: [user1.id],
            mode: 'all_or_nothing'
          }

          expect(response).to redirect_to(account_product_license_assignments_path(account, product))
          expect(LicenseAssignment.count).to eq(initial_count)
          expect(flash[:alert]).to match(/No capacity/)
        end
      end
    end

    context 'with partial_fill mode' do
      it 'assigns up to available capacity' do
        # Use 9 of 10 licenses
        9.times do |i|
          u = User.create(account: account, name: "Existing #{i}", email: "existing#{i}@test.com")
          LicenseAssignment.create(account: account, product: product, user: u)
        end

        post bulk_assign_account_product_license_assignments_path(account, product), params: {
          user_ids: [user1.id, user2.id, user3.id],
          mode: 'partial_fill'
        }

        expect(response).to redirect_to(account_product_license_assignments_path(account, product))
        expect(LicenseAssignment.count).to eq(10)
        expect(flash[:notice]).to match(/Partially assigned/)
      end

      it 'assigns all when capacity is sufficient' do
        post bulk_assign_account_product_license_assignments_path(account, product), params: {
          user_ids: [user1.id, user2.id],
          mode: 'partial_fill'
        }

        expect(response).to redirect_to(account_product_license_assignments_path(account, product))
        expect(LicenseAssignment.count).to eq(2)
        expect(flash[:notice]).to include('Successfully assigned')
      end
    end

    context 'with empty user_ids' do
      it 'shows error' do
        post bulk_assign_account_product_license_assignments_path(account, product), params: {
          user_ids: [],
          mode: 'all_or_nothing'
        }

        expect(response).to redirect_to(account_product_license_assignments_path(account, product))
        expect(flash[:alert]).to match(/No users selected/)
      end
    end

    context 'duplicate prevention' do
      it 'does not create duplicate assignments' do
        LicenseAssignment.create(account: account, product: product, user: user1)

        post bulk_assign_account_product_license_assignments_path(account, product), params: {
          user_ids: [user1.id, user2.id],
          mode: 'all_or_nothing'
        }

        expect(LicenseAssignment.where(user: user1).count).to eq(1)
        expect(LicenseAssignment.where(user: user2).count).to eq(1)
      end
    end
  end

  describe 'POST /accounts/:account_id/products/:product_id/license_assignments/bulk_unassign' do
    before do
      LicenseAssignment.create(account: account, product: product, user: user1)
      LicenseAssignment.create(account: account, product: product, user: user2)
    end

    context 'with valid user_ids' do
      it 'unassigns licenses' do
        expect {
          post bulk_unassign_account_product_license_assignments_path(account, product), params: {
            user_ids: [user1.id, user2.id]
          }
        }.to change(LicenseAssignment, :count).by(-2)

        expect(response).to redirect_to(account_product_license_assignments_path(account, product))
        expect(flash[:notice]).to include('Successfully unassigned')
      end
    end

    context 'with empty user_ids' do
      it 'shows error' do
        post bulk_unassign_account_product_license_assignments_path(account, product), params: {
          user_ids: []
        }

        expect(response).to redirect_to(account_product_license_assignments_path(account, product))
        expect(flash[:alert]).to match(/No users selected/)
      end
    end

    context 'with non-existent assignments' do
      it 'only removes existing assignments' do
        initial_count = LicenseAssignment.count

        post bulk_unassign_account_product_license_assignments_path(account, product), params: {
          user_ids: [user1.id, user3.id]  # user3 has no assignment
        }

        expect(LicenseAssignment.count).to eq(initial_count - 1)
      end
    end
  end

  describe 'Expired subscription handling' do
    context 'when subscription has expired' do
      before do
        subscription.update(expires_at: 1.day.ago)
      end

      it 'blocks bulk_assign and shows error' do
        post bulk_assign_account_product_license_assignments_path(account, product), params: {
          user_ids: [user1.id],
          mode: 'all_or_nothing'
        }

        expect(response).to redirect_to(account_product_license_assignments_path(account, product))
        expect(flash[:alert]).to match(/expired/)
        expect(LicenseAssignment.count).to eq(0)
      end

      it 'blocks bulk_unassign and shows error' do
        # Create assignment while subscription was active
        subscription.update(expires_at: 1.month.from_now)
        LicenseAssignment.create(account: account, product: product, user: user1)
        subscription.update(expires_at: 1.day.ago)

        post bulk_unassign_account_product_license_assignments_path(account, product), params: {
          user_ids: [user1.id]
        }

        expect(response).to redirect_to(account_product_license_assignments_path(account, product))
        expect(flash[:alert]).to match(/expired/)
        expect(LicenseAssignment.count).to eq(1)  # Not unassigned
      end

      it 'shows warning on index page' do
        get account_product_license_assignments_path(account, product)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Subscription Expired')
        expect(response.body).to include('License management is disabled')
      end
    end

    context 'when subscription is active' do
      it 'allows bulk_assign' do
        post bulk_assign_account_product_license_assignments_path(account, product), params: {
          user_ids: [user1.id],
          mode: 'all_or_nothing'
        }

        expect(response).to redirect_to(account_product_license_assignments_path(account, product))
        expect(flash[:notice]).to include('Successfully assigned')
        expect(LicenseAssignment.count).to eq(1)
      end

      it 'does not show expiration warning on index page' do
        get account_product_license_assignments_path(account, product)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('Subscription Expired')
      end
    end
  end
end
