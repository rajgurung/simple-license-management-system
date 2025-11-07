class Product < ApplicationRecord
  has_many :subscriptions, dependent: :destroy
  has_many :license_assignments, dependent: :destroy
  has_many :accounts, through: :subscriptions

  validates :name, presence: true, uniqueness: true
end
