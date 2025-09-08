class Settings::HostingsController < ApplicationController
  layout "settings"

  guard_feature unless: -> { self_hosted? }

  before_action :ensure_admin, only: :clear_cache

  def show
    # 获取当前选择的provider的usage信息（仅对synth有效）
    current_provider_name = Setting.securities_provider.to_sym
    current_provider = Provider::Registry.get_provider(current_provider_name)
    @synth_usage = current_provider_name == :synth ? current_provider&.usage : nil
    
    # 获取所有配置的securities providers（不管是否可用）
    registry = Provider::Registry.for_concept(:securities)
    available_provider_names = registry.send(:available_providers)
    
    @available_providers = available_provider_names.map do |provider_name|
      provider_instance = begin
        registry.get_provider(provider_name)
      rescue Provider::Registry::Error => e
        Rails.logger.warn("[SettingsController] Provider #{provider_name} 获取失败: #{e.message}")
        nil
      end
      
      provider_info = {
        name: provider_name.to_s,
        display_name: provider_name.to_s.humanize,
        available: provider_instance.present?
      }
      
      provider_info
    end
    
  end

  def update
    if hosting_params.key?(:require_invite_for_signup)
      Setting.require_invite_for_signup = hosting_params[:require_invite_for_signup]
    end

    if hosting_params.key?(:require_email_confirmation)
      Setting.require_email_confirmation = hosting_params[:require_email_confirmation]
    end

    if hosting_params.key?(:synth_api_key)
      Setting.synth_api_key = hosting_params[:synth_api_key]
    end

    if hosting_params.key?(:securities_provider)
      Setting.securities_provider = hosting_params[:securities_provider]
    end

    redirect_to settings_hosting_path, notice: t(".success")
  rescue ActiveRecord::RecordInvalid => error
    flash.now[:alert] = t(".failure")
    render :show, status: :unprocessable_entity
  end

  def clear_cache
    DataCacheClearJob.perform_later(Current.family)
    redirect_to settings_hosting_path, notice: t(".cache_cleared")
  end

  private
    def hosting_params
      params.require(:setting).permit(:require_invite_for_signup, :require_email_confirmation, :synth_api_key, :securities_provider)
    end

    def ensure_admin
      redirect_to settings_hosting_path, alert: t(".not_authorized") unless Current.user.admin?
    end
end
