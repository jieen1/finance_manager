class Assistant::Skill::AssetAllocationAnalysis < Assistant::Skill
  class << self
    def name
      "skill_asset_allocation"
    end

    def description
      "分析资产配置。计算各类资产占比（现金/股票/基金/其他），与用户设定的目标配比对比，给出偏离度和调整建议。"
    end
  end

  def call(params = {})
    # 1. 获取账户数据
    accounts = call_tool("get_accounts")

    # 2. 获取持仓数据
    holdings = call_tool("get_holdings")

    # 3. 获取用户记忆中的配置目标
    memory_result = call_tool("memory_search", { "query" => "allocation stock 仓位 配置", "memory_type" => "core" })
    target_memories = memory_result[:results] || []

    # 4. 计算资产分布
    allocation = calculate_allocation(accounts, holdings)

    # 5. 与目标对比
    target = parse_targets(target_memories)
    deviations = calculate_deviations(allocation, target)

    {
      as_of_date: Date.current.to_s,
      total_assets: allocation[:total],
      allocation: allocation[:breakdown],
      concentration_risk: detect_concentration(holdings),
      target_allocation: target,
      deviations: deviations
    }
  end

  private

    def calculate_allocation(accounts, holdings)
      total = 0
      breakdown = { cash: 0, stock: 0, fund: 0, other: 0 }

      # 账户级别分类
      (accounts[:accounts] || []).each do |acct|
        balance = acct[:balance].to_f.abs
        total += balance

        case acct[:type]
        when /depository|checking|savings/i
          breakdown[:cash] += balance
        when /investment|brokerage/i
          # 投资账户的详细分类由持仓决定
        else
          breakdown[:other] += balance
        end
      end

      # 持仓级别分类
      (holdings[:holdings] || []).each do |h|
        amount = h[:amount].to_f.abs
        ticker = h[:ticker].to_s

        if ticker.match?(/ETF|LOF|基金/i) || ticker.match?(/^1[56]\d{4}$/)
          breakdown[:fund] += amount
        else
          breakdown[:stock] += amount
        end
      end

      # 计算百分比
      pct = breakdown.transform_values { |v| total.zero? ? 0 : (v / total * 100).round(1) }

      { total: total, breakdown: pct }
    end

    def parse_targets(memories)
      target = {}
      memories.each do |m|
        value = m[:value].to_s
        if value.match?(/股票.*?(\d+)%|stock.*?(\d+)%/i)
          target[:stock] = ($1 || $2).to_f
        end
        if value.match?(/现金.*?(\d+)%|cash.*?(\d+)%/i)
          target[:cash] = ($1 || $2).to_f
        end
      end
      target
    end

    def calculate_deviations(allocation, target)
      return [] if target.empty?

      deviations = []
      target.each do |type, target_pct|
        current_pct = allocation[:breakdown][type] || 0
        diff = (current_pct - target_pct).round(1)
        if diff.abs > 5
          deviations << {
            type: type,
            current: current_pct,
            target: target_pct,
            deviation: diff,
            action: diff > 0 ? "减持" : "增持"
          }
        end
      end
      deviations
    end

    def detect_concentration(holdings)
      items = holdings[:holdings] || []
      return [] if items.empty?

      total = items.sum { |h| h[:amount].to_f.abs }
      return [] if total.zero?

      items.select { |h|
        pct = h[:amount].to_f.abs / total * 100
        pct > 30
      }.map { |h|
        {
          security: h[:security],
          percentage: (h[:amount].to_f.abs / total * 100).round(1),
          warning: "单一持仓占比过高，建议分散风险"
        }
      }
    end
end
