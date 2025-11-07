class Subscription < ApplicationRecord
  belongs_to :account
  belongs_to :product

  validates :number_of_licenses, presence: true, numericality: { greater_than: 0 }
  validates :issued_at, presence: true
  validates :expires_at, presence: true
  validate :expires_after_issued

  # Active subscriptions (not expired)
  scope :active, -> { where('expires_at > ?', Time.current) }

  # Expired subscriptions
  scope :expired, -> { where('expires_at <= ?', Time.current) }

  def active?
    expires_at > Time.current
  end

  def expired?
    expires_at <= Time.current
  end

  def expiring_soon?(days = 7)
    return false if expired?
    expires_at <= days.days.from_now
  end

  def days_until_expiry
    return 0 if expired?
    ((expires_at - Time.current) / 1.day).ceil
  end

  def in_grace_period?
    expires_at > 1.day.ago && expires_at <= Time.current
  end

  private

  def expires_after_issued
    if expires_at.present? && issued_at.present? && expires_at <= issued_at
      errors.add(:expires_at, 'must be after issued date')
    end
  end
end
