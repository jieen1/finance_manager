class UserSubscriptionsController < ApplicationController
  before_action :set_subscription, only: %i[edit update destroy toggle_status]

  def index
    @breadcrumbs = [ [ "首页", root_path ], [ "订阅管理", nil ] ]
    @user_subscriptions = Current.family.user_subscriptions.alphabetically
    @monthly_total = @user_subscriptions.active.sum(&:monthly_cost)
    @yearly_total = @user_subscriptions.active.sum(&:yearly_cost)

    render layout: "settings"
  end

  def new
    @user_subscription = UserSubscription.new(
      family: Current.family,
      currency: Current.family.currency,
      billing_cycle: "monthly",
      billing_day: Date.current.day > 28 ? 1 : Date.current.day,
      next_billing_date: Date.current,
      color: UserSubscription::COLORS.sample
    )
  end

  def create
    @user_subscription = UserSubscription.new(subscription_params.merge(family: Current.family))

    if @user_subscription.save
      respond_to do |format|
        format.html { redirect_to user_subscriptions_path, notice: "订阅已创建" }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, user_subscriptions_path) }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @user_subscription.update(subscription_params)
      respond_to do |format|
        format.html { redirect_to user_subscriptions_path, notice: "订阅已更新" }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, user_subscriptions_path) }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user_subscription.destroy!
    redirect_to user_subscriptions_path, notice: "订阅已删除"
  end

  def toggle_status
    new_status = @user_subscription.active? ? "paused" : "active"
    @user_subscription.update!(status: new_status)
    redirect_to user_subscriptions_path
  end

  private

    def set_subscription
      @user_subscription = Current.family.user_subscriptions.find(params[:id])
    end

    def subscription_params
      params.require(:user_subscription).permit(
        :name, :amount, :currency, :billing_cycle, :billing_day,
        :next_billing_date, :account_id, :category_id, :notes, :color
      )
    end
end
