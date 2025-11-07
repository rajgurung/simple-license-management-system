class AccountsController < ApplicationController
  before_action :require_admin
  before_action :set_account, only: [:show, :edit, :update, :destroy]

  def index
    current_time = ActiveRecord::Base.connection.quote(Time.current)
    @accounts = Account.order(:name)
      .select('accounts.*')
      .select('(SELECT COUNT(*) FROM users WHERE users.account_id = accounts.id) as users_count')
      .select("(SELECT COUNT(*) FROM subscriptions WHERE subscriptions.account_id = accounts.id AND subscriptions.expires_at > #{current_time}) as active_subscriptions_count")
      .select("(SELECT COALESCE(SUM(number_of_licenses), 0) FROM subscriptions WHERE subscriptions.account_id = accounts.id AND subscriptions.expires_at > #{current_time}) as total_licenses")
      .select('(SELECT COUNT(*) FROM license_assignments WHERE license_assignments.account_id = accounts.id) as license_assignments_count')
  end

  def show
    @subscriptions = @account.subscriptions.includes(:product).active
    @expired_subscriptions = @account.subscriptions.includes(:product).expired

    # Preload associations to avoid N+1
    ActiveRecord::Associations::Preloader.new(records: [@account], associations: [:users, :license_assignments]).call

    # Cache product-specific assignment counts for expired section
    @product_assignment_counts = LicenseAssignment
      .where(account_id: @account.id)
      .group(:product_id)
      .count

    # Precompute subscription capacities to avoid N+1 in loop
    product_ids = @subscriptions.pluck(:product_id).uniq

    # Get total licenses per product
    total_licenses_by_product = Subscription
      .active
      .where(account_id: @account.id, product_id: product_ids)
      .group(:product_id)
      .sum(:number_of_licenses)

    # Get used licenses per product
    used_licenses_by_product = LicenseAssignment
      .where(account_id: @account.id, product_id: product_ids)
      .joins("INNER JOIN subscriptions ON subscriptions.account_id = license_assignments.account_id
              AND subscriptions.product_id = license_assignments.product_id")
      .where('subscriptions.expires_at > ?', Time.current)
      .group('license_assignments.product_id')
      .distinct
      .count

    # Build capacity hash for view
    @subscription_capacities = product_ids.each_with_object({}) do |product_id, hash|
      total = total_licenses_by_product[product_id] || 0
      used = used_licenses_by_product[product_id] || 0
      hash[product_id] = { total: total, used: used, available: total - used }
    end

    # Precompute license pool metrics to avoid inline queries in view
    @total_licenses_count = @account.subscriptions.active.sum(:number_of_licenses)

    @used_licenses_count = @account.license_assignments
      .joins("INNER JOIN subscriptions ON subscriptions.account_id = license_assignments.account_id
              AND subscriptions.product_id = license_assignments.product_id")
      .where('subscriptions.expires_at > ?', Time.current)
      .distinct
      .count
  end

  def new
    @account = Account.new
  end

  def create
    @account = Account.new(account_params)

    if @account.save
      redirect_to @account, notice: 'Account was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @account.update(account_params)
      redirect_to @account, notice: 'Account was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @account.destroy
    redirect_to accounts_path, notice: 'Account was successfully deleted.'
  end

  private

  def set_account
    @account = Account.find(params[:id])
  end

  def account_params
    params.require(:account).permit(:name)
  end
end
