# Skill 是多步编排的高级操作，内部调用多个 Function 完成复杂任务。
# 与 Function 的区别：Function 是原子工具，Skill 是组合流程。
#
# Token 优化策略：
# - Skill 默认 strict_mode=false，允许 LLM 灵活传参
# - params_schema 极简化，只保留最核心的参数
# - 详细的步骤说明不放在 description 里（description 只一句话概述）
# - Skill 内部自己处理参数解析和默认值
class Assistant::Skill < Assistant::Function
  class << self
    def skill?
      true
    end
  end

  def strict_mode?
    false
  end

  private

    def call_tool(tool_name, params = {})
      tool_class = Assistant::ToolRegistry::ALL_TOOLS.find { |t| t.tool_name == tool_name }
      raise "Unknown tool: #{tool_name}" unless tool_class
      tool_class.new(user).call(params)
    end

    def format_amount(amount, currency = nil)
      Money.new(amount, currency || family.currency).format
    end
end
