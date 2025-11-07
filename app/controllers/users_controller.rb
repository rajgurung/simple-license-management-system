class UsersController < ApplicationController
  before_action :require_admin
  before_action :set_account

  def index
    @users = @account.users.order(:name)
  end

  def new
    @user = @account.users.build
  end

  def create
    @user = @account.users.build(user_params)

    if @user.save
      redirect_to account_users_path(@account), notice: "User added successfully"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_account
    @account = Account.find(params[:account_id])
  end

  def user_params
    params.require(:user).permit(:name, :email)
  end
end
