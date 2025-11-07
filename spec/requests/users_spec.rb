require 'rails_helper'

RSpec.describe 'Users', type: :request do
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

  describe 'GET /accounts/:account_id/users' do
    it 'lists users for the account' do
      get account_users_path(account)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /accounts/:account_id/users/new' do
    it 'renders new user form' do
      get new_account_user_path(account)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /accounts/:account_id/users' do
    context 'with valid params' do
      it 'creates a new user' do
        expect {
          post account_users_path(account), params: {
            user: {
              name: 'Test User',
              email: 'testuser@example.com'
            }
          }
        }.to change(User, :count).by(1)

        expect(response).to redirect_to(account_users_path(account))
        expect(flash[:notice]).to eq('User added successfully')
      end
    end

    context 'with invalid params' do
      it 'does not create user and re-renders form' do
        expect {
          post account_users_path(account), params: {
            user: {
              name: '',
              email: ''
            }
          }
        }.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
