class Provider::Minimax < Provider
  include LlmConcept

  Error = Class.new(Provider::Error)

  DEFAULT_MODELS = %w[MiniMax-Text-01 abab6.5s-chat abab5.5s-chat abab5-chat].freeze
  DEFAULT_API_BASE = "https://api.minimax.chat/v1/"

  ChatMessage = Provider::LlmConcept::ChatMessage
  ChatStreamChunk = Provider::LlmConcept::ChatStreamChunk
  ChatResponse = Provider::LlmConcept::ChatResponse
  ChatFunctionRequest = Provider::LlmConcept::ChatFunctionRequest

  def self.models
    custom_model = ENV["MINIMAX_MODEL_NAME"]
    custom_model.present? ? (DEFAULT_MODELS + [ custom_model ]).uniq : DEFAULT_MODELS
  end

  def initialize(api_key)
    api_base = ENV.fetch("MINIMAX_BASE_URL", DEFAULT_API_BASE)
    api_base = "#{api_base}/" unless api_base.end_with?("/")

    @client = ::OpenAI::Client.new(
      access_token: api_key,
      uri_base: api_base
    )
  end

  def supports_model?(model)
    self.class.models.include?(model)
  end

  def auto_categorize(transactions: [], user_categories: [])
    raise Error, "Auto-categorize is not supported for MiniMax provider"
  end

  def auto_detect_merchants(transactions: [], user_merchants: [])
    raise Error, "Auto-detect merchants is not supported for MiniMax provider"
  end

  def chat_response(prompt, model:, instructions: nil, functions: [], function_results: [], streamer: nil, previous_response_id: nil)
    with_provider_response do
      chat_config = ChatConfig.new(
        instructions: instructions,
        functions: functions,
        function_results: function_results
      )

      parameters = {
        model: model,
        messages: chat_config.build_messages(prompt),
        tools: chat_config.tools.presence
      }.compact

      if streamer.present?
        accumulated_content = ""
        accumulated_tool_calls = {}
        response_id = nil
        response_model = nil

        stream_proc = proc do |chunk, _bytesize|
          response_id ||= chunk.dig("id")
          response_model ||= chunk.dig("model")

          delta = chunk.dig("choices", 0, "delta")
          finish_reason = chunk.dig("choices", 0, "finish_reason")

          next if delta.nil?

          if (content = delta.dig("content")).present?
            accumulated_content += content
            streamer.call(ChatStreamChunk.new(type: "output_text", data: content))
          end

          if (tool_call_deltas = delta.dig("tool_calls"))
            tool_call_deltas.each do |tc_delta|
              idx = tc_delta["index"] || 0
              accumulated_tool_calls[idx] ||= { "id" => "", "function" => { "name" => "", "arguments" => "" } }
              accumulated_tool_calls[idx]["id"] += tc_delta["id"].to_s
              accumulated_tool_calls[idx]["function"]["name"] += tc_delta.dig("function", "name").to_s
              accumulated_tool_calls[idx]["function"]["arguments"] += tc_delta.dig("function", "arguments").to_s
            end
          end

          if finish_reason.present?
            messages = accumulated_content.present? ? [ ChatMessage.new(id: response_id, output_text: accumulated_content) ] : []

            function_requests = accumulated_tool_calls.values.map do |tc|
              ChatFunctionRequest.new(
                id: tc["id"],
                call_id: tc["id"],
                function_name: tc.dig("function", "name"),
                function_args: tc.dig("function", "arguments")
              )
            end

            chat_response_obj = ChatResponse.new(
              id: response_id,
              model: response_model,
              messages: messages,
              function_requests: function_requests
            )

            streamer.call(ChatStreamChunk.new(type: "response", data: chat_response_obj))
          end
        end

        client.chat(parameters: parameters.merge(stream: stream_proc))
        nil
      else
        raw_response = client.chat(parameters: parameters)
        ChatParser.new(raw_response).parsed
      end
    end
  end

  private
    attr_reader :client
end
