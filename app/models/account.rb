class Account < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_many :license_assignments, dependent: :destroy
  has_many :products, through: :subscriptions

  validates :name, presence: true
end
