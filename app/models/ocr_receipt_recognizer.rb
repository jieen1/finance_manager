# 使用 LLM Vision API 识别消费截图，提取结构化记账数据。
# 支持微信支付、支付宝、银行 App 等消费截图。
class OcrReceiptRecognizer
  PROMPT = <<~PROMPT
    分析这张消费截图，提取以下信息并以 JSON 格式返回：

    {
      "is_expense": true/false,
      "amount": 数字（消费金额，不含货币符号），
      "merchant": "商家名称",
      "date": "YYYY-MM-DD",
      "category": "消费分类（餐饮/交通/购物/娱乐/医疗/教育/居家/通讯/其他）",
      "payment_method": "支付方式（微信支付/支付宝/银行卡/现金/其他）",
      "description": "简短描述"
    }

    规则：
    - 如果不是消费相关截图（如聊天截图、新闻等），返回 {"is_expense": false}
    - 金额必须是数字，不要包含 ¥ 或 $ 符号
    - 日期格式必须是 YYYY-MM-DD
    - 只返回 JSON，不要其他文字
  PROMPT

  def initialize(family)
    @family = family
  end

  def recognize(image_path)
    return nil unless File.exist?(image_path)

    image_data = File.read(image_path)
    base64_image = Base64.strict_encode64(image_data)
    mime_type = detect_mime_type(image_path)

    response = call_vision_api(base64_image, mime_type)
    parse_response(response)
  end

  private

    def call_vision_api(base64_image, mime_type)
      provider = find_vision_provider
      raise "未配置视觉模型，请在模型配置中添加 vision 角色的提供商" unless provider

      llm_provider = provider.to_provider
      model = provider.primary_model

      # 使用 OpenAI 兼容的 vision API 格式
      client = ::OpenAI::Client.new(
        access_token: provider.api_key,
        uri_base: provider.api_endpoint.end_with?("/") ? provider.api_endpoint : "#{provider.api_endpoint}/"
      )

      response = client.chat(parameters: {
        model: model,
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: PROMPT },
              { type: "image_url", image_url: { url: "data:#{mime_type};base64,#{base64_image}" } }
            ]
          }
        ],
        max_tokens: 500
      })

      response.dig("choices", 0, "message", "content")
    end

    def find_vision_provider
      # 优先找 vision 角色的提供商
      provider = @family.llm_providers.enabled.by_role("vision").first
      return provider if provider

      # fallback: 用 main 提供商（很多模型也支持 vision）
      @family.llm_providers.enabled.by_role("main").first
    end

    def parse_response(text)
      return nil if text.blank?

      # 提取 JSON（LLM 可能在 JSON 外面包了 markdown code block）
      json_str = text[/\{.*\}/m]
      return nil if json_str.blank?

      data = JSON.parse(json_str)
      return nil unless data["is_expense"]

      {
        amount: data["amount"].to_f,
        merchant: data["merchant"],
        date: data["date"],
        category: data["category"],
        payment_method: data["payment_method"],
        description: data["description"]
      }
    rescue JSON::ParserError
      nil
    end

    def detect_mime_type(path)
      ext = File.extname(path).downcase
      case ext
      when ".png" then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".gif" then "image/gif"
      when ".webp" then "image/webp"
      else "image/png"
      end
    end
end
