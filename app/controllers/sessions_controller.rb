class SessionsController < ApplicationController
  def new
  end

  def create
    # Find user first, then check admin status to reduce timing attack surface
    user = User.find_by(username: params[:username])

    # Check both admin status and password in one conditional to avoid revealing which failed
    if user&.admin? && user.authenticate(params[:password])
      # Regenerate session to prevent session fixation attacks
      reset_session
      session[:user_id] = user.id
      redirect_to accounts_path, notice: "Logged in successfully"
    else
      flash.now[:alert] = "Invalid username or password"
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    # Clear entire session to prevent session-related attacks
    reset_session
    redirect_to login_path, notice: "Logged out successfully"
  end
end
