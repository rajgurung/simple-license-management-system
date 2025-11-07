class LicenseAssignmentsController < ApplicationController
  before_action :require_admin
  before_action :set_account_and_product
  before_action :check_active_subscription, only: [:bulk_assign, :bulk_unassign]

  def index
    @users = @account.users.order(:name)

    # Get assignments for this product
    @assignments = LicenseAssignment
      .where(account_id: @account.id, product_id: @product.id)
      .includes(:user)

    @assigned_user_ids = @assignments.pluck(:user_id)

    # Get capacity info
    capacity_query = PoolAvailabilityQuery.new(
      account_id: @account.id,
      product_id: @product.id
    )
    @capacity = capacity_query.capacity_details

    # Check if subscription is active
    @has_active_subscription = @account.subscriptions
      .where(product_id: @product.id)
      .where('expires_at > ?', Time.current)
      .exists?
  end

  def bulk_assign
    mode = params[:mode]&.to_sym || :all_or_nothing
    user_ids = Array.wrap(params[:user_ids]).compact.reject(&:blank?)

    if user_ids.empty?
      redirect_to account_product_license_assignments_path(@account, @product),
                  alert: "No users selected for assignment"
      return
    end

    service = Assignments::AssignWithAdvisoryLock.new(
      account_id: @account.id,
      product_id: @product.id,
      user_ids: user_ids,
      mode: mode
    )

    result = service.call

    if result[:outcome] == 'no_capacity'
      redirect_to account_product_license_assignments_path(@account, @product),
                  alert: "No capacity available"
    elsif result[:outcome] == 'partial'
      redirect_to account_product_license_assignments_path(@account, @product),
                  notice: "Partially assigned #{result[:assigned].size} licenses. #{result[:overflow].size} could not be assigned due to capacity."
    else
      redirect_to account_product_license_assignments_path(@account, @product),
                  notice: "Successfully assigned #{result[:assigned].size} licenses"
    end
  rescue Assignments::NoCapacityError => e
    redirect_to account_product_license_assignments_path(@account, @product),
                alert: "No capacity. Requested: #{e.requested}, Available: #{e.available}"
  end

  def bulk_unassign
    user_ids = Array.wrap(params[:user_ids]).compact.reject(&:blank?)

    if user_ids.empty?
      redirect_to account_product_license_assignments_path(@account, @product),
                  alert: "No users selected for unassignment"
      return
    end

    count = LicenseAssignment.where(
      account_id: @account.id,
      product_id: @product.id,
      user_id: user_ids
    ).destroy_all.size

    redirect_to account_product_license_assignments_path(@account, @product),
                notice: "Successfully unassigned #{count} licenses"
  end

  private

  def set_account_and_product
    @account = Account.find(params[:account_id])
    @product = Product.find(params[:product_id])
  end

  def check_active_subscription
    has_active = @account.subscriptions
      .where(product_id: @product.id)
      .where('expires_at > ?', Time.current)
      .exists?

    unless has_active
      redirect_to account_product_license_assignments_path(@account, @product),
                  alert: "Cannot manage licenses - all subscriptions for this product have expired"
    end
  end
end
