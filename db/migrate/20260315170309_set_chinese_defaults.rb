class SetChineseDefaults < ActiveRecord::Migration[7.2]
  def change
    change_column_default :families, :currency, from: "USD", to: "CNY"
    change_column_default :families, :locale, from: "en", to: "zh-CN"
    change_column_default :families, :country, from: "US", to: "CN"
    change_column_default :families, :date_format, from: "%m-%d-%Y", to: "%Y-%m-%d"

    reversible do |dir|
      dir.up do
        execute "UPDATE families SET currency='CNY', locale='zh-CN', country='CN', date_format='%Y-%m-%d'"
        execute "UPDATE users SET trend_color_preference='chinese'"
      end
    end
  end
end
