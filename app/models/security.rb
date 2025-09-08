class Security < ApplicationRecord
  include Provided

  before_validation :upcase_symbols

  has_many :trades, dependent: :nullify, class_name: "Trade"
  has_many :prices, dependent: :destroy

  validates :ticker, presence: true
  validates :ticker, uniqueness: { scope: :exchange_operating_mic, case_sensitive: false }

  scope :online, -> { where(offline: false) }

  def current_price
    @current_price ||= find_or_fetch_price
    return nil if @current_price.nil?
    Money.new(@current_price.price, @current_price.currency)
  end

  def to_combobox_option
    option_class = combobox_option_class
    Rails.logger.info("[Security] 使用combobox option类: #{option_class.name} for provider: #{Setting.securities_provider}")
    
    option_class.new(
      symbol: ticker,  # 将ticker映射到symbol属性
      name: name,
      logo_url: logo_url,
      exchange_operating_mic: exchange_operating_mic,
      country_code: country_code
    )
  end

  private
    def upcase_symbols
      self.ticker = ticker.upcase
      self.exchange_operating_mic = exchange_operating_mic.upcase if exchange_operating_mic.present?
    end

    def combobox_option_class
      case Setting.securities_provider
      when "tencent"
        Security::TencentComboboxOption
      else
        Security::SynthComboboxOption
      end
    end
end
