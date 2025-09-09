class Trend
  include ActiveModel::Validations

  DIRECTIONS = %w[up down].freeze
  COLOR_PREFERENCES = %w[traditional chinese].freeze

  attr_reader :current, :previous, :favorable_direction, :color_preference

  validates :current, presence: true

  def initialize(current:, previous:, favorable_direction: nil, color_preference: nil)
    @current = current
    @previous = previous || 0
    @favorable_direction = (favorable_direction.presence_in(DIRECTIONS) || "up").inquiry
    @color_preference = (color_preference.presence_in(COLOR_PREFERENCES) || "traditional").inquiry

    validate!
  end

  def direction
    if current == previous
      "flat"
    elsif current > previous
      "up"
    else
      "down"
    end.inquiry
  end

  def color
    case direction
    when "up"
      if color_preference.chinese?
        # 中国习惯：红色表示涨
        red_hex
      else
        # 传统习惯：绿色表示涨
        favorable_direction.down? ? red_hex : green_hex
      end
    when "down"
      if color_preference.chinese?
        # 中国习惯：绿色表示跌
        green_hex
      else
        # 传统习惯：红色表示跌
        favorable_direction.down? ? green_hex : red_hex
      end
    else
      gray_hex
    end
  end

  def icon
    if direction.flat?
      "minus"
    elsif direction.up?
      "arrow-up"
    else
      "arrow-down"
    end
  end

  def value
    current - previous
  end

  def percent
    return 0.0 if previous.zero? && current.zero?
    return Float::INFINITY if previous.zero?

    change = (current - previous).to_f

    (change / previous.to_f * 100).round(1)
  end

  def percent_formatted
    if percent.finite?
      "#{percent.round(1)}%"
    else
      percent > 0 ? "＋∞" : "-∞"
    end
  end

  def as_json
    {
      value: value,
      percent: percent,
      percent_formatted: percent_formatted,
      current: current,
      previous: previous,
      color: color,
      icon: icon
    }
  end

  private
    def red_hex
      "var(--color-destructive)"
    end

    def green_hex
      "var(--color-success)"
    end

    def gray_hex
      "var(--color-gray)"
    end
end
