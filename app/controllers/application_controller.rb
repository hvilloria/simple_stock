class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  include Pundit::Authorization

  # Require authentication for all actions
  before_action :authenticate_user!

  # Pundit: handle unauthorized access
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def user_not_authorized
    flash[:alert] = "No tenés permiso para realizar esta acción."
    redirect_to(request.referrer || authenticated_root_path)
  end
end
