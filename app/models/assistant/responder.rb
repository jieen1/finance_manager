class Assistant::Responder
  MAX_TOOL_ROUNDS = 5

  def initialize(message:, instructions:, function_tool_caller:, llm:)
    @message = message
    @instructions = instructions
    @function_tool_caller = function_tool_caller
    @llm = llm
  end

  def on(event_name, &block)
    listeners[event_name.to_sym] << block
  end

  def respond(previous_response_id: nil)
    round = 0
    current_response_id = previous_response_id
    accumulated_function_results = []

    loop do
      round += 1
      pending_function_requests = nil

      streamer = proc do |chunk|
        case chunk.type
        when "output_text"
          emit(:output_text, chunk.data)
        when "response"
          response = chunk.data

          if response.function_requests.any? && round < MAX_TOOL_ROUNDS
            pending_function_requests = response
          else
            emit(:response, { id: response.id })
          end
        end
      end

      get_llm_response(
        streamer: streamer,
        function_results: accumulated_function_results,
        previous_response_id: current_response_id
      )

      if pending_function_requests
        function_tool_calls = function_tool_caller.fulfill_requests(pending_function_requests.function_requests)

        emit(:response, {
          id: pending_function_requests.id,
          function_tool_calls: function_tool_calls
        })

        accumulated_function_results = function_tool_calls.map(&:to_result)
        current_response_id = pending_function_requests.id
      else
        break
      end
    end
  end

  private
    attr_reader :message, :instructions, :function_tool_caller, :llm

    def get_llm_response(streamer:, function_results: [], previous_response_id: nil)
      response = llm.chat_response(
        message.content,
        model: message.ai_model,
        instructions: instructions,
        functions: function_tool_caller.function_definitions,
        function_results: function_results,
        streamer: streamer,
        previous_response_id: previous_response_id
      )

      unless response.success?
        raise response.error
      end

      response.data
    end

    def emit(event_name, payload = nil)
      listeners[event_name.to_sym].each { |block| block.call(payload) }
    end

    def listeners
      @listeners ||= Hash.new { |h, k| h[k] = [] }
    end
end
