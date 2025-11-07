require 'rails_helper'

RSpec.describe User, type: :model do
  let(:account) { Account.create(name: 'Test Account') }

  describe 'validations' do
    it 'is valid with name and email' do
      user = User.new(account: account, name: 'John Doe', email: 'john@example.com')
      expect(user).to be_valid
    end

    it 'is invalid without a name' do
      user = User.new(account: account, email: 'john@example.com')
      expect(user).not_to be_valid
    end

    it 'is invalid without an email' do
      user = User.new(account: account, name: 'John Doe')
      expect(user).not_to be_valid
    end

    it 'is invalid with duplicate email' do
      User.create(account: account, name: 'John', email: 'john@example.com')
      duplicate = User.new(account: account, name: 'Jane', email: 'john@example.com')
      expect(duplicate).not_to be_valid
    end
  end

  describe 'admin authentication' do
    context 'when admin is true' do
      it 'requires username' do
        user = User.new(
          account: account,
          name: 'Admin',
          email: 'admin@test.com',
          admin: true,
          password: 'password123'
        )
        expect(user).not_to be_valid
        expect(user.errors[:username]).to be_present
      end

      it 'requires password on creation' do
        user = User.new(
          account: account,
          name: 'Admin',
          email: 'admin@test.com',
          admin: true,
          username: 'admin'
        )
        expect(user).not_to be_valid
      end

      it 'creates valid admin with credentials' do
        user = User.create(
          name: 'Admin',
          email: 'admin@test.com',
          admin: true,
          username: 'admin',
          password: 'password123'
        )
        expect(user).to be_valid
        expect(user.admin?).to be true
        expect(user.authenticate('password123')).to eq(user)
        expect(user.authenticate('wrong')).to be false
      end
    end

    context 'when admin is false' do
      it 'does not require username or password' do
        user = User.create(account: account, name: 'Regular', email: 'regular@test.com', admin: false)
        expect(user).to be_valid
      end
    end
  end
end
