class Settings::BillingsController < ApplicationController
  layout "settings"

  before_action -> { redirect_to root_path if self_hosted? }

  def show
    @family = Current.family
  end
end
