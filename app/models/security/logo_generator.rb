class Security::LogoGenerator
  # 基于标的名称或代码生成SVG图标
  def self.generate_logo_url(name: nil, symbol: nil, exchange_operating_mic: nil)
    # 优先使用名称，如果没有则使用代码
    text = name.presence || symbol.presence || "?"
    
    # 清理文本，只保留中文、英文、数字和基本符号
    clean_text = text.gsub(/[^\u4e00-\u9fa5a-zA-Z0-9\s]/, '').strip
    
    # 如果文本为空，使用默认值
    clean_text = "?" if clean_text.blank?
    
    # 取前2个字符作为显示文本
    display_text = clean_text.length > 2 ? clean_text[0, 2] : clean_text
    
    # 根据交易所选择背景颜色
    background_color = get_background_color(exchange_operating_mic)
    text_color = get_text_color(background_color)
    
    # 生成SVG数据URI
    svg_content = generate_svg(display_text, background_color, text_color)
    "data:image/svg+xml;base64,#{Base64.strict_encode64(svg_content)}"
  end
  
  private
  
  def self.get_background_color(exchange_operating_mic)
    case exchange_operating_mic
    when "XSHG"  # 上海证券交易所
      "#e74c3c"  # 红色
    when "XSHE"  # 深圳证券交易所  
      "#3498db"  # 蓝色
    when "XHKG"  # 香港交易所
      "#f39c12"  # 橙色
    when "XNYS", "XNAS"  # 美股
      "#2ecc71"  # 绿色
    else
      "#95a5a6"  # 灰色（默认）
    end
  end
  
  def self.get_text_color(background_color)
    # 根据背景颜色选择文字颜色（白色或黑色）
    # 简单的亮度计算
    hex = background_color.gsub('#', '')
    r = hex[0..1].to_i(16)
    g = hex[2..3].to_i(16)
    b = hex[4..5].to_i(16)
    
    # 计算相对亮度
    brightness = (r * 299 + g * 587 + b * 114) / 1000
    
    brightness > 128 ? "#2c3e50" : "#ffffff"
  end
  
  def self.generate_svg(text, background_color, text_color)
    # 生成64x64的SVG图标
    <<~SVG
      <svg width="64" height="64" viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
        <rect width="64" height="64" rx="12" ry="12" fill="#{background_color}"/>
        <text x="32" y="40" font-family="Arial, sans-serif" font-size="20" font-weight="bold" 
              text-anchor="middle" fill="#{text_color}">#{text}</text>
      </svg>
    SVG
  end
end
