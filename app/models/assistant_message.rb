class AssistantMessage < Message
  validates :ai_model, presence: true

  def role
    "assistant"
  end

  def append_text!(text)
    self.content += text
    save!
  end

  # 过滤掉模型返回的 <think>...</think> 思考过程标签
  def display_content
    return "" if content.blank?
    content.gsub(/<think>.*?<\/think>/m, "").strip
  end
end
