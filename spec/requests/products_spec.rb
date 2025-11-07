require 'rails_helper'

RSpec.describe 'Products', type: :request do
  let!(:admin_user) do
    User.create(
      name: 'Admin User',
      email: 'admin@test.com',
      admin: true,
      username: 'admin',
      password: 'password123'
    )
  end

  let!(:product) { Product.create(name: 'vLex Colombia', description: 'Legal research database') }

  before do
    post login_path, params: {
      username: 'admin',
      password: 'password123'
    }
  end

  describe 'GET /products' do
    it 'lists all products' do
      get products_path
      expect(response).to have_http_status(:ok)
    end

    context 'with subscriptions' do
      let(:account) { Account.create(name: 'Test Account') }

      it 'displays products without subscriptions' do
        get products_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('No subscriptions')
      end

      it 'displays expired subscription date' do
        Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 10,
          issued_at: 2.months.ago,
          expires_at: 2.days.ago
        )

        get products_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Expired')
      end

      it 'displays expiring soon warning' do
        Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 10,
          issued_at: 1.month.ago,
          expires_at: 5.days.from_now
        )

        get products_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('5 days')
      end

      it 'displays active subscription date' do
        Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 10,
          issued_at: Time.current,
          expires_at: 6.months.from_now
        )

        get products_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('2026')
      end

      it 'displays earliest expiry when multiple subscriptions exist' do
        # Create multiple subscriptions with different expiry dates
        Subscription.create(
          account: account,
          product: product,
          number_of_licenses: 10,
          issued_at: Time.current,
          expires_at: 1.year.from_now
        )

        earliest_sub = Subscription.create(
          account: Account.create(name: 'Another Account'),
          product: product,
          number_of_licenses: 5,
          issued_at: 1.month.ago,
          expires_at: 3.days.from_now
        )

        get products_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(earliest_sub.expires_at.strftime("%b %d, %Y"))
      end
    end
  end

  describe 'GET /products/new' do
    it 'renders new product form' do
      get new_product_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /products' do
    context 'with valid params' do
      it 'creates a new product' do
        expect {
          post products_path, params: {
            product: {
              name: 'vLex España',
              description: 'Spanish legal database'
            }
          }
        }.to change(Product, :count).by(1)

        expect(response).to redirect_to(products_path)
        follow_redirect!
        expect(response.body).to include('Product created successfully')
      end
    end

    context 'with invalid params' do
      it 'does not create a product without name' do
        expect {
          post products_path, params: {
            product: {
              name: '',
              description: 'Test description'
            }
          }
        }.not_to change(Product, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'does not create a duplicate product' do
        expect {
          post products_path, params: {
            product: {
              name: product.name,
              description: 'Duplicate product'
            }
          }
        }.not_to change(Product, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'GET /products/:id/edit' do
    it 'renders edit product form' do
      get edit_product_path(product)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Edit Product')
      expect(response.body).to include(product.name)
    end

    it 'finds the correct product' do
      get edit_product_path(product)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(product.description)
    end
  end

  describe 'PATCH /products/:id' do
    context 'with valid params' do
      it 'updates the product' do
        patch product_path(product), params: {
          product: {
            name: 'Updated Product Name',
            description: 'Updated description'
          }
        }

        product.reload
        expect(product.name).to eq('Updated Product Name')
        expect(product.description).to eq('Updated description')
        expect(response).to redirect_to(products_path)
        follow_redirect!
        expect(response.body).to include('Product updated successfully')
      end

      it 'updates only the name' do
        original_description = product.description

        patch product_path(product), params: {
          product: {
            name: 'New Name Only'
          }
        }

        product.reload
        expect(product.name).to eq('New Name Only')
        expect(product.description).to eq(original_description)
      end

      it 'updates only the description' do
        original_name = product.name

        patch product_path(product), params: {
          product: {
            description: 'New description only'
          }
        }

        product.reload
        expect(product.name).to eq(original_name)
        expect(product.description).to eq('New description only')
      end
    end

    context 'with invalid params' do
      it 'does not update with blank name' do
        original_name = product.name

        patch product_path(product), params: {
          product: {
            name: '',
            description: 'Some description'
          }
        }

        product.reload
        expect(product.name).to eq(original_name)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'does not update with duplicate name' do
        other_product = Product.create(name: 'vLex Costa Rica', description: 'Another product')
        original_name = product.name

        patch product_path(product), params: {
          product: {
            name: other_product.name
          }
        }

        product.reload
        expect(product.name).to eq(original_name)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'shows error messages when update fails' do
        patch product_path(product), params: {
          product: {
            name: ''
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Name')
      end
    end
  end
end
