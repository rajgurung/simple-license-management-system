class SubscriptionsController < ApplicationController
  before_action :require_admin
  before_action :set_account

  def index
    @subscriptions = @account.subscriptions.includes(:product).order(created_at: :desc)
  end

  def new
    @subscription = @account.subscriptions.build
    @products = Product.order(:name)
  end

  def create
    @subscription = @account.subscriptions.build(subscription_params)

    if @subscription.save
      redirect_to account_subscriptions_path(@account), notice: "Subscription created successfully"
    else
      @products = Product.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_account
    @account = Account.find(params[:account_id])
  end

  def subscription_params
    params.require(:subscription).permit(:product_id, :number_of_licenses, :issued_at, :expires_at)
  end
end
