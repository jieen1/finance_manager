class Assistant::ToolRegistry
  # 核心读操作工具 — 每次对话都加载
  CORE_TOOLS = [
    Assistant::Function::GetTransactions,
    Assistant::Function::GetAccounts,
    Assistant::Function::GetBalanceSheet,
    Assistant::Function::GetIncomeStatement
  ].freeze

  # 扩展工具 — 更多读操作 + 写操作
  EXTENDED_TOOLS = [
    Assistant::Function::GetHoldings,
    Assistant::Function::GetSubscriptions,
    Assistant::Function::GetBudgets,
    Assistant::Function::CreateTransaction,
    Assistant::Function::CategorizeTransactions,
    Assistant::Function::CreateBudget,
    Assistant::Function::DeleteTransaction,
    Assistant::Function::MemoryUpdate,
    Assistant::Function::MemorySearch,
    Assistant::Function::ManageTasks
  ].freeze

  # Skill — 多步编排的高级操作（内部调用多个工具）
  SKILL_TOOLS = [
    Assistant::Skill::MonthlyReport,
    Assistant::Skill::AssetAllocationAnalysis,
    Assistant::Skill::QuickEntry,
    Assistant::Skill::SpendingAnomalyDetector,
    Assistant::Skill::FinancialHealthScore,
    Assistant::Skill::SubscriptionDetector
  ].freeze

  ALL_TOOLS = (CORE_TOOLS + EXTENDED_TOOLS + SKILL_TOOLS).freeze

  # 需要确认的写操作
  CONFIRM_TOOLS = %w[create_transaction categorize_transactions create_budget skill_quick_entry].freeze

  # 需要审批的高风险操作
  APPROVE_TOOLS = %w[delete_transaction].freeze

  def initialize(family)
    @family = family
    @configs = family.agent_tool_configs.index_by(&:tool_name)
  end

  attr_reader :family

  def enabled_tools
    ALL_TOOLS.select { |tool_class| enabled?(tool_class) }
  end

  def tool_definitions_for(user)
    enabled_tools.map { |klass| klass.new(user).to_definition }
  end

  def find_tool_class(tool_name)
    ALL_TOOLS.find { |klass| klass.tool_name == tool_name }
  end

  def permission_level(tool_name)
    config = @configs[tool_name]
    return config.permission_level if config.present?
    default_permission(tool_name)
  end

  def enabled?(tool_class)
    config = @configs[tool_class.tool_name]
    return true if config.nil?
    config.enabled?
  end

  def tool_info
    ALL_TOOLS.map do |tool_class|
      config = @configs[tool_class.tool_name]
      is_skill = tool_class.respond_to?(:skill?) && tool_class.skill?
      {
        tool_class: tool_class,
        name: tool_class.tool_name,
        description: tool_class.description.to_s.lines.first&.strip || tool_class.tool_name,
        enabled: config&.enabled? != false,
        permission_level: config&.permission_level || default_permission(tool_class.tool_name),
        write: write_tool?(tool_class.tool_name),
        skill: is_skill
      }
    end
  end

  private

    def default_permission(tool_name)
      if APPROVE_TOOLS.include?(tool_name)
        "approve"
      elsif CONFIRM_TOOLS.include?(tool_name)
        "confirm"
      else
        "auto"
      end
    end

    def write_tool?(tool_name)
      (CONFIRM_TOOLS + APPROVE_TOOLS + %w[memory_update]).include?(tool_name)
    end
end
