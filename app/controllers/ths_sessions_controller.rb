class ThsSessionsController < ApplicationController
  layout "settings"
  before_action :set_breadcrumbs

  def index
    @ths_session = Current.family.ths_sessions.order(created_at: :desc).first
    @investment_accounts = Current.family.accounts.where(accountable_type: "Investment", status: "active")
    @ths_fund_accounts = load_ths_fund_accounts
    @recent_records = ExternalRecord.where(family: Current.family)
      .where(source: [ "ths", "ths_position" ])
      .order(created_at: :desc)
      .limit(20)
    @cron_jobs = load_ths_cron_jobs
  end

  def create
    cookies_str = params[:cookies].to_s.strip

    # Build fund_key → account_id mappings from form params
    mappings = {}
    (params[:fund_mappings] || {}).each do |fund_key, account_id|
      mappings[fund_key] = account_id if account_id.present?
    end

    if cookies_str.present?
      # New cookie or cookie update
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
        expires_at: 23.hours.from_now,
        fund_account_mappings: mappings
      )
    elsif @ths_session = Current.family.ths_sessions.order(created_at: :desc).first
      # Only updating account mappings, no new cookie
      session = @ths_session
      session.fund_account_mappings = mappings
    else
      redirect_to ths_sessions_path, alert: "请先配置 Cookie"
      return
    end

    if session.save
      redirect_to ths_sessions_path, notice: "同花顺设置已保存"
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

    start_date = case params[:sync_scope]
    when "30d" then Date.current - 30
    when "90d" then Date.current - 90
    when "1y"  then Date.current - 365
    when "full" then Date.new(2020, 1, 1)
    else Date.current - 3  # incremental
    end

    begin
      importer = ThsSync::Importer.new(session)
      results = importer.sync!(start_date: start_date)
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

  def load_ths_fund_accounts
    return [] unless @ths_session&.persisted? && !@ths_session.expired?

    client = ThsClient.new(@ths_session)
    data = client.account_list
    # THS returns accounts in ex_data.common (broker accounts) and ex_data.manual (manual accounts)
    all_accounts = (data.dig("ex_data", "common") || []) + (data.dig("ex_data", "manual") || [])
    all_accounts.map do |a|
      fund_key = a["fund_key"].presence || a["manual_id"].presence
      name = a["manualname"].presence || a["brokername"].presence || fund_key
      { fund_key: fund_key, name: name }
    end.select { |a| a[:fund_key].present? }
  rescue => e
    Rails.logger.warn("[ThsSessions] Failed to load THS accounts: #{e.message}")
    []
  end

  def load_ths_cron_jobs
    Sidekiq::Cron::Job.all
      .select { |j| j.klass == "ThsSyncJob" }
      .map do |job|
        {
          name: job.name,
          description: job.description.presence || job.name,
          cron: job.cron,
          enabled: job.status == "enabled",
          last_run: job.last_enqueue_time.presence,
          next_run: Fugit::Cron.parse(job.cron)&.next_time&.to_t
        }
      end
  rescue => e
    Rails.logger.warn("[ThsSessions] Failed to load cron jobs: #{e.message}")
    []
  end
end
