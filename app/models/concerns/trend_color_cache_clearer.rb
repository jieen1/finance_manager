module TrendColorCacheClearer
  extend ActiveSupport::Concern

  included do
    after_update :clear_trend_color_cache, if: :saved_change_to_trend_color_preference?
  end

  private

  def clear_trend_color_cache
    # 清除所有相关的缓存
    Rails.cache.delete_matched("*sparkline*")
    Rails.cache.delete_matched("*trend*")
    
    # 清除实例变量缓存
    family.accounts.find_each do |account|
      account.instance_variable_set(:@balance_series, nil)
    end
  end
end
