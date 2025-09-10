module Account::Chartable
  extend ActiveSupport::Concern

  def favorable_direction
    classification == "asset" ? "up" : "down"
  end

  def balance_series(period: Period.last_30_days, view: :balance, interval: nil, user: nil)
    raise ArgumentError, "Invalid view type" unless [ :balance, :cash_balance, :holdings_balance ].include?(view.to_sym)

    @balance_series ||= {}

    # 使用 Current.user 的偏好设置生成缓存键，保证一致性
    memo_key = [ period.start_date, period.end_date, interval, Current.user&.trend_color_preference ].compact.join("_")

    builder = (@balance_series[memo_key] ||= Balance::ChartSeriesBuilder.new(
      account_ids: [ id ],
      currency: self.currency,
      period: period,
      favorable_direction: favorable_direction,
      interval: interval
    ))

    builder.send("#{view}_series")
  end

  def sparkline_series(user: nil)
    # 使用 Current.user 的偏好设置，保持向后兼容
    preference = user&.trend_color_preference || Current.user&.trend_color_preference
    cache_key = family.build_cache_key("#{id}_sparkline_#{preference}", invalidate_on_data_updates: true)

    Rails.cache.fetch(cache_key, expires_in: 24.hours) do
      balance_series
    end
  end
end
