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

      it 'shows no capacity alert when zero capacity available' do
        # Fill all 10 licenses
        10.times do |i|
          u = User.create(account: account, name: "Existing #{i}", email: "existing#{i}@test.com")
          LicenseAssignment.create(account: account, product: product, user: u)
        end

        initial_count = LicenseAssignment.count

        # Try to assign 2 more users with partial_fill mode
        post bulk_assign_account_product_license_assignments_path(account, product), params: {
          user_ids: [user1.id, user2.id],
          mode: 'partial_fill'
        }

        expect(response).to redirect_to(account_product_license_assignments_path(account, product))
        expect(flash[:alert]).to include('No capacity available')
        expect(LicenseAssignment.count).to eq(initial_count)  # No new assignments created
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

  describe 'Edge case: All users already have licenses (idempotent assignment)' do
    it 'shows notice when all requested users already have licenses assigned' do
      # Pre-assign licenses to both users
      LicenseAssignment.create(account: account, product: product, user: user1)
      LicenseAssignment.create(account: account, product: product, user: user2)

      initial_count = LicenseAssignment.count

      post bulk_assign_account_product_license_assignments_path(account, product), params: {
        user_ids: [user1.id, user2.id],
        mode: 'all_or_nothing'
      }

      expect(response).to redirect_to(account_product_license_assignments_path(account, product))
      expect(flash[:notice]).to include('already have licenses assigned')
      expect(LicenseAssignment.count).to eq(initial_count)  # No new assignments created
    end

    it 'handles partial already-assigned scenario correctly' do
      # Pre-assign license to user1 only
      LicenseAssignment.create(account: account, product: product, user: user1)

      post bulk_assign_account_product_license_assignments_path(account, product), params: {
        user_ids: [user1.id, user2.id],
        mode: 'all_or_nothing'
      }

      expect(response).to redirect_to(account_product_license_assignments_path(account, product))
      expect(flash[:notice]).to include('Successfully assigned 1')  # Only user2 assigned
      expect(LicenseAssignment.where(user: user1).count).to eq(1)  # Still just one assignment for user1
      expect(LicenseAssignment.where(user: user2).count).to eq(1)  # New assignment for user2
    end
  end

  describe 'Edge case: Partial fill mode with overflow details' do
    it 'shows specific overflow details when some users cannot be assigned' do
      # Use 8 of 10 licenses
      8.times do |i|
        u = User.create(account: account, name: "Existing #{i}", email: "existing#{i}@test.com")
        LicenseAssignment.create(account: account, product: product, user: u)
      end

      # Try to assign 3 users (only 2 should succeed due to capacity limit)
      post bulk_assign_account_product_license_assignments_path(account, product), params: {
        user_ids: [user1.id, user2.id, user3.id],
        mode: 'partial_fill'
      }

      expect(response).to redirect_to(account_product_license_assignments_path(account, product))
      expect(flash[:notice]).to match(/Partially assigned 2 licenses/)
      expect(flash[:notice]).to match(/1 could not be assigned due to capacity/)
      expect(LicenseAssignment.count).to eq(10)  # 8 existing + 2 new = 10 total
    end
  end

  describe 'Authorization: require_admin before filter' do
    context 'when user is not logged in' do
      before do
        delete logout_path  # Log out the admin
      end

      it 'redirects to login for index action' do
        get account_product_license_assignments_path(account, product)
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to include('Please log in as admin')
      end

      it 'redirects to login for bulk_assign action' do
        post bulk_assign_account_product_license_assignments_path(account, product), params: {
          user_ids: [user1.id]
        }
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to include('Please log in as admin')
      end

      it 'redirects to login for bulk_unassign action' do
        post bulk_unassign_account_product_license_assignments_path(account, product), params: {
          user_ids: [user1.id]
        }
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to include('Please log in as admin')
      end
    end

    context 'when user is logged in but not an admin' do
      let(:regular_user) do
        User.create(
          name: 'Regular User',
          email: 'regular@test.com',
          admin: false,
          username: 'regular',
          password: 'password123',
          account: account
        )
      end

      before do
        delete logout_path  # Log out the admin
        post login_path, params: {
          username: 'regular',
          password: 'password123'
        }
      end

      it 'redirects to login when accessing license assignments' do
        get account_product_license_assignments_path(account, product)
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to include('Please log in as admin')
      end

      it 'redirects to login when attempting bulk_assign' do
        post bulk_assign_account_product_license_assignments_path(account, product), params: {
          user_ids: [user1.id]
        }
        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to include('Please log in as admin')
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
