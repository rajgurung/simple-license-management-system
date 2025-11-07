class User < ApplicationRecord
  belongs_to :account, optional: true
  has_many :license_assignments, dependent: :destroy
  has_many :products, through: :license_assignments

  has_secure_password validations: false

  validates :name, presence: true
  validates :email, presence: true
  validates :admin, inclusion: { in: [true, false] }

  # Account association rules
  validates :account_id, presence: true, unless: :admin?
  validates :account_id, absence: true, if: :admin?

  # Email uniqueness - handled by partial indexes in database:
  # - For admin users: globally unique (partial index where admin = true)
  # - For regular users: unique per account (composite index on [email, account_id] where admin = false)
  validates :email, uniqueness: { scope: :account_id, conditions: -> { where(admin: false) } }, unless: :admin?
  validates :email, uniqueness: { conditions: -> { where(admin: true) } }, if: :admin?

  # Admin users require username and password
  validates :username, presence: true, uniqueness: true, if: :admin?
  validates :password, presence: true, if: ->(user) { user.admin? && user.new_record? }

  def admin?
    admin
  end
end
