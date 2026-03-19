class Assistant::Function::MemorySearch < Assistant::Function
  class << self
    def name
      "memory_search"
    end

    def description
      "搜索归档记忆和核心记忆。用于回忆之前的分析结果、用户偏好、历史对话要点等。"
    end
  end

  def params_schema
    build_schema(
      required: %w[query],
      properties: {
        query: {
          type: "string",
          description: "搜索关键词"
        },
        memory_type: {
          type: "string",
          enum: %w[core archival all],
          description: "搜索范围：core=核心记忆, archival=归档记忆, all=全部（默认all）"
        }
      }
    )
  end

  def call(params = {})
    scope = family.agent_memories
    memory_type = params["memory_type"] || "all"

    case memory_type
    when "core"
      scope = scope.core
    when "archival"
      scope = scope.archival
    end

    results = scope.search(params["query"]).limit(10)

    {
      results: results.map { |m|
        { type: m.memory_type, key: m.key, value: m.value, updated_at: m.updated_at.to_s }
      },
      count: results.size
    }
  end
end
