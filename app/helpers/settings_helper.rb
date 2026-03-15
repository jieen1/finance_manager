module SettingsHelper
  SETTINGS_ORDER = [
    { name: "账户设置", path: :settings_profile_path },
    { name: "偏好设置", path: :settings_preferences_path },
    { name: "安全设置", path: :settings_security_path },
    { name: "自托管设置", path: :settings_hosting_path, condition: :self_hosted? },
    { name: "API 密钥", path: :settings_api_key_path },
    { name: "订阅账单", path: :settings_billing_path, condition: :not_self_hosted? },
    { name: "账户管理", path: :accounts_path },
    { name: "导入管理", path: :imports_path },
    { name: "标签管理", path: :tags_path },
    { name: "类别管理", path: :categories_path },
    { name: "规则管理", path: :rules_path },
    { name: "商家管理", path: :family_merchants_path },
    { name: "最新动态", path: :changelog_path },
    { name: "意见反馈", path: :feedback_path }
  ]

  def adjacent_setting(current_path, offset)
    visible_settings = SETTINGS_ORDER.select { |setting| setting[:condition].nil? || send(setting[:condition]) }
    current_index = visible_settings.index { |setting| send(setting[:path]) == current_path }
    return nil unless current_index

    adjacent_index = current_index + offset
    return nil if adjacent_index < 0 || adjacent_index >= visible_settings.size

    adjacent = visible_settings[adjacent_index]

    render partial: "settings/settings_nav_link_large", locals: {
      path: send(adjacent[:path]),
      direction: offset > 0 ? "next" : "previous",
      title: adjacent[:name]
    }
  end

  def settings_section(title:, subtitle: nil, &block)
    content = capture(&block)
    render partial: "settings/section", locals: { title: title, subtitle: subtitle, content: content }
  end

  def settings_nav_footer
    previous_setting = adjacent_setting(request.path, -1)
    next_setting = adjacent_setting(request.path, 1)

    content_tag :div, class: "hidden md:flex flex-row justify-between gap-4" do
      concat(previous_setting)
      concat(next_setting)
    end
  end

  def settings_nav_footer_mobile
    previous_setting = adjacent_setting(request.path, -1)
    next_setting = adjacent_setting(request.path, 1)

    content_tag :div, class: "md:hidden flex flex-col gap-4" do
      concat(previous_setting)
      concat(next_setting)
    end
  end

  private
    def not_self_hosted?
      !self_hosted?
    end
end
