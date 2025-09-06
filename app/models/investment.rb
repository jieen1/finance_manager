class Investment < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "股票" => { short: "股票", long: "股票" },
    "基金" => { short: "基金", long: "基金" },
    "期货" => { short: "期货", long: "期货" }
  }.freeze

  class << self
    def color
      "#1570EF"
    end

    def classification
      "asset"
    end

    def icon
      "line-chart"
    end
  end
end
