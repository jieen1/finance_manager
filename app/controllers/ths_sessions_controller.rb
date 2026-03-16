class ThsSessionsController < ApplicationController
  layout "settings"
  before_action :set_breadcrumbs

  def index
    @ths_session = Current.family.ths_sessions.order(created_at: :desc).first
    @recent_records = ExternalRecord.where(family: Current.family)
      .where(source: [ "ths", "ths_position" ])
      .order(created_at: :desc)
      .limit(20)
  end

  def create
    cookies_str = params[:cookies].to_s.strip
    userid = cookies_str.match(/userid=(\d+)/)&.captures&.first

    unless userid
      redirect_to ths_sessions_path, alert: "Cookie 中未找到 userid"
      return
    end

    session = Current.family.ths_sessions.find_or_initialize_by(userid: userid)
    session.assign_attributes(
      cookies: cookies_str,
      status: "active",
      last_error: nil,
      expires_at: 23.hours.from_now
    )

    if session.save
      redirect_to ths_sessions_path, notice: "同花顺会话已保存 (userid: #{userid})"
    else
      redirect_to ths_sessions_path, alert: session.errors.full_messages.join(", ")
    end
  end

  def destroy
    session = Current.family.ths_sessions.find(params[:id])
    session.destroy
    redirect_to ths_sessions_path, notice: "会话已删除"
  end

  def sync_now
    session = Current.family.ths_sessions.find(params[:id])

    begin
      importer = ThsSync::Importer.new(session)
      results = importer.sync!
      redirect_to ths_sessions_path,
        notice: "同步完成: 新建 #{results[:created]}, 跳过 #{results[:skipped]}, 错误 #{results[:errors].size}"
    rescue ThsClient::AuthError => e
      redirect_to ths_sessions_path, alert: "Cookie 已过期: #{e.message}"
    rescue => e
      redirect_to ths_sessions_path, alert: "同步失败: #{e.message}"
    end
  end

  def test_connection
    session = Current.family.ths_sessions.find(params[:id])
    client = ThsClient.new(session)

    if client.alive?
      session.mark_active!
      redirect_to ths_sessions_path, notice: "连接正常"
    else
      redirect_to ths_sessions_path, alert: "连接失败"
    end
  rescue => e
    redirect_to ths_sessions_path, alert: "测试失败: #{e.message}"
  end

  private

  def set_breadcrumbs
    @breadcrumbs = [ [ "首页", root_path ], [ "设置", settings_profile_path ], [ "同花顺同步", nil ] ]
  end
end
