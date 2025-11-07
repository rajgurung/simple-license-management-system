require 'rails_helper'

RSpec.describe Product, type: :model do
  describe 'validations' do
    it 'is valid with a unique name' do
      product = Product.new(name: 'Test Product')
      expect(product).to be_valid
    end

    it 'is invalid without a name' do
      product = Product.new(name: nil)
      expect(product).not_to be_valid
    end

    it 'is invalid with a duplicate name' do
      Product.create(name: 'Test Product')
      duplicate = Product.new(name: 'Test Product')
      expect(duplicate).not_to be_valid
    end
  end
end
