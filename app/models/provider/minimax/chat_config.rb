class Provider::Minimax::ChatConfig
  def initialize(instructions: nil, functions: [], function_results: [])
    @instructions = instructions
    @functions = functions
    @function_results = function_results
  end

  def tools
    return [] if functions.empty?

    functions.map do |fn|
      {
        type: "function",
        function: {
          name: fn[:name],
          description: fn[:description],
          parameters: fn[:params_schema]
        }
      }
    end
  end

  def build_messages(prompt)
    messages = []
    messages << { role: "system", content: instructions } if instructions.present?
    messages << { role: "user", content: prompt }

    if function_results.any?
      tool_calls = function_results.map do |fn_result|
        {
          id: fn_result[:call_id],
          type: "function",
          function: {
            name: fn_result[:function_name].to_s,
            arguments: fn_result[:function_arguments].to_s
          }
        }
      end

      messages << { role: "assistant", content: nil, tool_calls: tool_calls }

      function_results.each do |fn_result|
        messages << {
          role: "tool",
          tool_call_id: fn_result[:call_id],
          content: fn_result[:output].to_json
        }
      end
    end

    messages
  end

  private
    attr_reader :instructions, :functions, :function_results
end
