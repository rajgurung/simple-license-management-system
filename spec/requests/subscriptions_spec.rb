require 'rails_helper'

RSpec.describe 'Subscriptions', type: :request do
  let(:account) { Account.create(name: 'Test Account') }
  let(:product) { Product.create(name: 'Test Product') }
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

  describe 'GET /accounts/:account_id/subscriptions' do
    it 'lists subscriptions for the account' do
      get account_subscriptions_path(account)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /accounts/:account_id/subscriptions/new' do
    it 'renders new subscription form' do
      get new_account_subscription_path(account)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /accounts/:account_id/subscriptions' do
    context 'with valid params' do
      it 'creates a new subscription' do
        expect {
          post account_subscriptions_path(account), params: {
            subscription: {
              product_id: product.id,
              number_of_licenses: 10,
              issued_at: Time.current,
              expires_at: 1.year.from_now
            }
          }
        }.to change(Subscription, :count).by(1)

        expect(response).to redirect_to(account_subscriptions_path(account))
        expect(flash[:notice]).to eq('Subscription created successfully')
      end
    end

    context 'with invalid params' do
      it 'does not create subscription and re-renders form' do
        expect {
          post account_subscriptions_path(account), params: {
            subscription: {
              product_id: nil,
              number_of_licenses: nil
            }
          }
        }.not_to change(Subscription, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
