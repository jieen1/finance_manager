class Depository < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "checking" => { short: "经常账户", long: "经常账户" },
    "savings" => { short: "储蓄", long: "储蓄账户" },
    "wechat" => { short: "微信", long: "微信账户" },
    "alipay" => { short: "支付宝", long: "支付宝账户" }
  }.freeze

  class << self

    def color
      "#875BF7"
    end

    def classification
      "asset"
    end

    def icon
      "landmark"
    end
  end
end
