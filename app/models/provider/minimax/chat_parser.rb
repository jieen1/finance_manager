class Provider::Minimax::ChatParser
  ChatResponse = Provider::LlmConcept::ChatResponse
  ChatMessage = Provider::LlmConcept::ChatMessage
  ChatFunctionRequest = Provider::LlmConcept::ChatFunctionRequest

  def initialize(object)
    @object = object
  end

  def parsed
    ChatResponse.new(
      id: response_id,
      model: response_model,
      messages: messages,
      function_requests: function_requests
    )
  end

  private
    attr_reader :object

    def response_id
      object.dig("id")
    end

    def response_model
      object.dig("model")
    end

    def choice_message
      object.dig("choices", 0, "message")
    end

    def messages
      return [] if choice_message.nil?
      return [] if choice_message.dig("tool_calls").present?

      text = choice_message.dig("content").to_s
      return [] if text.blank?

      [ ChatMessage.new(id: response_id, output_text: text) ]
    end

    def function_requests
      tool_calls = choice_message&.dig("tool_calls")
      return [] unless tool_calls.present?

      tool_calls.map do |tool_call|
        ChatFunctionRequest.new(
          id: tool_call.dig("id"),
          call_id: tool_call.dig("id"),
          function_name: tool_call.dig("function", "name"),
          function_args: tool_call.dig("function", "arguments")
        )
      end
    end
end
