class Assistant::Skill::SpendingAnomalyDetector < Assistant::Skill
  class << self
    def name
      "skill_detect_anomalies"
    end

    def description
      "检测消费异常。扫描最近交易，找出：单笔大额消费、分类支出暴增、重复扣费、异常时间消费等。"
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [],
      properties: {
        days: {
          type: "integer",
          description: "扫描最近多少天（默认30）"
        }
      }
    )
  end

  def call(params = {})
    days = (params["days"] || 30).to_i
    end_date = Date.current
    start_date = end_date - days.days

    # 获取当期和上期交易
    current = call_tool("get_income_statement", {
      "start_date" => start_date.to_s,
      "end_date" => end_date.to_s
    })

    prev_start = start_date - days.days
    previous = call_tool("get_income_statement", {
      "start_date" => prev_start.to_s,
      "end_date" => (start_date - 1.day).to_s
    })

    # 获取最近交易明细
    transactions = call_tool("get_transactions", {
      "page" => 1,
      "order" => "desc",
      "start_date" => start_date.to_s,
      "end_date" => end_date.to_s
    })

    anomalies = []

    # 1. 单笔大额检测
    large_txns = detect_large_transactions(transactions)
    anomalies.concat(large_txns)

    # 2. 分类暴增检测
    category_spikes = detect_category_spikes(current, previous)
    anomalies.concat(category_spikes)

    # 3. 重复扣费检测
    duplicates = detect_duplicates(transactions)
    anomalies.concat(duplicates)

    {
      scan_period: "#{start_date} ~ #{end_date}",
      total_expense: current.dig(:expense, :total),
      anomaly_count: anomalies.size,
      anomalies: anomalies
    }
  end

  private

    def detect_large_transactions(transactions)
      items = transactions[:transactions] || []
      return [] if items.size < 5

      amounts = items.select { |t| t[:classification] == "expense" }.map { |t| t[:amount].to_f }
      return [] if amounts.empty?

      avg = amounts.sum / amounts.size
      threshold = [ avg * 3, 1000 ].max

      items.select { |t|
        t[:classification] == "expense" && t[:amount].to_f > threshold
      }.map { |t|
        {
          type: "large_transaction",
          severity: "warning",
          description: "单笔大额消费: #{t[:formatted_amount]} - #{t[:category] || '未分类'}",
          date: t[:date].to_s,
          amount: t[:formatted_amount]
        }
      }
    end

    def detect_category_spikes(current, previous)
      return [] unless current.dig(:expense, :by_category) && previous.dig(:expense, :by_category)

      current_cats = hash_categories(current[:expense][:by_category])
      prev_cats = hash_categories(previous[:expense][:by_category])

      spikes = []
      current_cats.each do |name, amount|
        prev_amount = prev_cats[name]
        next unless prev_amount && prev_amount > 0

        change = ((amount - prev_amount) / prev_amount * 100).round(1)
        if change > 50
          spikes << {
            type: "category_spike",
            severity: change > 100 ? "critical" : "warning",
            description: "#{name} 支出环比增长 #{change}%（#{format_amount(prev_amount)} → #{format_amount(amount)}）",
            category: name,
            change_percent: change
          }
        end
      end
      spikes
    end

    def detect_duplicates(transactions)
      items = transactions[:transactions] || []

      # 按金额+商家分组，找出短时间内重复的
      groups = items.group_by { |t| [ t[:amount], t[:merchant] || t[:category] ] }

      duplicates = []
      groups.each do |(amount, merchant), txns|
        next if txns.size < 2 || merchant.blank?

        duplicates << {
          type: "possible_duplicate",
          severity: "info",
          description: "#{merchant} 出现 #{txns.size} 笔相同金额（#{txns.first[:formatted_amount]}）",
          count: txns.size,
          amount: txns.first[:formatted_amount]
        }
      end
      duplicates
    end

    def hash_categories(by_category)
      return {} unless by_category.is_a?(Array)
      by_category.each_with_object({}) { |c, h| h[c[:name] || c["name"]] = (c[:total] || c["total"]).to_f }
    end
end
