module Breadcrumbable
  extend ActiveSupport::Concern

  CONTROLLER_NAME_ZH = {
    "accounts"              => "账户",
    "depositories"          => "存款账户",
    "investments"           => "投资账户",
    "credit_cards"          => "信用卡",
    "loans"                 => "贷款",
    "cryptos"               => "加密货币",
    "properties"            => "房产",
    "vehicles"              => "车辆",
    "other_assets"          => "其他资产",
    "other_liabilities"     => "其他负债",
    "transactions"          => "交易",
    "budgets"               => "预算",
    "budget_categories"     => "预算分类",
    "categories"            => "分类",
    "tags"                  => "标签",
    "imports"               => "导入",
    "holdings"              => "持仓",
    "trades"                => "交易记录",
    "transfers"             => "转账",
    "transfer_matches"      => "转账匹配",
    "valuations"            => "估值",
    "entries"               => "记录",
    "chats"                 => "AI 助手",
    "messages"              => "消息",
    "rules"                 => "规则",
    "securities"            => "证券",
    "holdings"              => "持仓",
    "profiles"              => "个人资料",
    "preferences"           => "偏好设置",
    "api_keys"              => "API 密钥",
    "hostings"              => "自托管设置",
    "family_merchants"      => "商家",
    "family_exports"        => "数据导出",
    "invitations"           => "邀请",
    "invite_codes"          => "邀请码",
    "users"                 => "用户",
    "sessions"              => "登录",
    "registrations"         => "注册",
    "password_resets"       => "重置密码",
    "passwords"             => "密码",
    "mfa"                   => "两步验证",
    "pages"                 => "页面",
    "currencies"            => "货币",
    "impersonation_sessions" => "模拟会话"
  }.freeze

  included do
    before_action :set_breadcrumbs
  end

  private
    # The default, unless specific controller or action explicitly overrides
    def set_breadcrumbs
      zh_name = CONTROLLER_NAME_ZH[controller_name] || controller_name.titleize
      @breadcrumbs = [ [ "首页", root_path ], [ zh_name, nil ] ]
    end
end
