class Assistant::Function::MemoryUpdate < Assistant::Function
  class << self
    def name
      "memory_update"
    end

    def description
      "更新用户的核心记忆。用于记住用户的偏好、风险配置、财务目标等长期信息。"
    end
  end

  def params_schema
    build_schema(
      required: %w[key value],
      properties: {
        key: {
          type: "string",
          description: "记忆键名，如 risk_profile, savings_goal, investment_preference"
        },
        value: {
          type: "string",
          description: "记忆内容"
        }
      }
    )
  end

  def call(params = {})
    memory = family.agent_memories.find_or_initialize_by(
      memory_type: "core",
      key: params["key"]
    )
    memory.value = params["value"]
    memory.save!

    { success: true, key: memory.key, value: memory.value }
  end
end
