# 从交易记录中识别疑似订阅消费，帮用户整理和创建订阅记录。
# 识别逻辑：找出同一商家/描述、相近金额、按月/周/年规律出现的交易。
class Assistant::Skill::SubscriptionDetector < Assistant::Skill
  class << self
    def name
      "skill_detect_subscriptions"
    end

    def description
      "从账单中识别订阅消费。扫描交易记录，找出按月/周/年规律重复出现的消费（如视频会员、音乐会员、云服务等），输出订阅清单。"
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [],
      properties: {
        months: {
          type: "integer",
          description: "扫描最近多少个月的交易（默认6）"
        }
      }
    )
  end

  def call(params = {})
    months = (params["months"] || 6).to_i
    start_date = months.months.ago.beginning_of_month.to_date
    end_date = Date.current

    # 获取所有支出交易
    transactions = family.entries
      .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
      .where("entries.date >= ? AND entries.date <= ?", start_date, end_date)
      .where("entries.amount > 0") # 正数=支出
      .select("entries.name, entries.amount, entries.date, entries.account_id")
      .order(:name, :date)

    # 按名称分组分析
    groups = transactions.group_by { |t| normalize_name(t.name) }

    detected = []
    groups.each do |name, txns|
      next if txns.size < 2 # 至少出现2次才可能是订阅

      analysis = analyze_pattern(name, txns)
      detected << analysis if analysis
    end

    # 获取已有订阅列表用于去重
    existing_subs = family.user_subscriptions.pluck(:name).map { |n| normalize_name(n) }

    detected.each do |sub|
      sub[:already_tracked] = existing_subs.include?(normalize_name(sub[:name]))
    end

    new_subscriptions = detected.reject { |s| s[:already_tracked] }
    existing_subscriptions = detected.select { |s| s[:already_tracked] }

    {
      scan_period: "#{start_date} ~ #{end_date}",
      total_detected: detected.size,
      new_subscriptions: new_subscriptions,
      already_tracked: existing_subscriptions.map { |s| s[:name] },
      summary: build_summary(new_subscriptions)
    }
  end

  private

    def normalize_name(name)
      name.to_s.strip.downcase
        .gsub(/\d{4}[-\/]\d{2}[-\/]\d{2}/, "") # 去掉日期
        .gsub(/\d+月/, "")                        # 去掉月份
        .gsub(/\s+/, " ")
        .strip
    end

    def analyze_pattern(name, txns)
      amounts = txns.map { |t| t.amount.to_f }
      dates = txns.map(&:date).sort

      # 检查金额一致性（允许10%波动）
      avg_amount = amounts.sum / amounts.size
      amount_consistent = amounts.all? { |a| (a - avg_amount).abs / avg_amount < 0.1 }

      return nil unless amount_consistent

      # 检查时间规律性
      intervals = dates.each_cons(2).map { |a, b| (b - a).to_i }
      return nil if intervals.empty?

      avg_interval = intervals.sum.to_f / intervals.size
      cycle = detect_cycle(avg_interval)

      return nil unless cycle

      # 预测下次扣费日期
      last_date = dates.last
      next_date = case cycle
      when "weekly" then last_date + 7.days
      when "monthly" then last_date >> 1
      when "quarterly" then last_date >> 3
      when "yearly" then last_date >> 12
      end

      {
        name: txns.first.name,
        amount: avg_amount.round(2),
        cycle: cycle,
        cycle_label: cycle_label(cycle),
        occurrences: txns.size,
        last_charge: last_date.to_s,
        next_estimated: next_date&.to_s,
        billing_day: last_date.day,
        account_id: txns.first.account_id
      }
    end

    def detect_cycle(avg_days)
      case avg_days
      when 5..9 then "weekly"
      when 25..35 then "monthly"
      when 80..100 then "quarterly"
      when 350..380 then "yearly"
      else nil
      end
    end

    def cycle_label(cycle)
      { "weekly" => "每周", "monthly" => "每月", "quarterly" => "每季度", "yearly" => "每年" }[cycle]
    end

    def build_summary(subs)
      return "未发现新的订阅消费模式" if subs.empty?

      monthly_total = subs.sum do |s|
        case s[:cycle]
        when "weekly" then s[:amount] * 4.33
        when "monthly" then s[:amount]
        when "quarterly" then s[:amount] / 3.0
        when "yearly" then s[:amount] / 12.0
        else 0
        end
      end

      "发现 #{subs.size} 个疑似订阅，预估每月总额 ¥#{monthly_total.round(2)}"
    end
end
