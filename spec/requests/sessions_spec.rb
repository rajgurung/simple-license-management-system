require 'rails_helper'

RSpec.describe 'Sessions', type: :request do
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

  describe 'GET /login' do
    it 'renders the login page' do
      get login_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /login' do
    context 'with valid credentials' do
      it 'logs in the user and redirects to accounts' do
        post login_path, params: {
          username: 'admin',
          password: 'password123'
        }

        expect(session[:user_id]).to eq(admin_user.id)
        expect(response).to redirect_to(accounts_path)
      end
    end

    context 'with invalid username' do
      it 'renders login page with error' do
        post login_path, params: {
          username: 'nonexistent',
          password: 'password123'
        }

        expect(session[:user_id]).to be_nil
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with invalid password' do
      it 'renders login page with error' do
        post login_path, params: {
          username: 'admin',
          password: 'wrongpassword'
        }

        expect(session[:user_id]).to be_nil
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE /logout' do
    it 'logs out the user and redirects to login' do
      # Simulate logged in user
      post login_path, params: {
        username: 'admin',
        password: 'password123'
      }

      delete logout_path
      expect(session[:user_id]).to be_nil
      expect(response).to redirect_to(login_path)
    end
  end
end
