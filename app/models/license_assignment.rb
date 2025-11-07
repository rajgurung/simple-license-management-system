class LicenseAssignment < ApplicationRecord
  belongs_to :account
  belongs_to :product
  belongs_to :user

  validates :account_id, presence: true
  validates :product_id, presence: true
  validates :user_id, presence: true
  validates :user_id, uniqueness: { scope: [:account_id, :product_id] }

  # Active assignments (linked to active subscriptions)
  scope :active, -> {
    joins(:account, :product)
      .joins("INNER JOIN subscriptions ON subscriptions.account_id = license_assignments.account_id
              AND subscriptions.product_id = license_assignments.product_id")
      .where('subscriptions.expires_at > ?', Time.current)
      .distinct
  }

  # Assignments in grace period
  scope :in_grace, -> {
    joins(:account, :product)
      .joins("INNER JOIN subscriptions ON subscriptions.account_id = license_assignments.account_id
              AND subscriptions.product_id = license_assignments.product_id")
      .where('subscriptions.expires_at > ? AND subscriptions.expires_at <= ?', 1.day.ago, Time.current)
      .distinct
  }
end
