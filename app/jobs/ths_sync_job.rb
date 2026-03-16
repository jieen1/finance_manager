class ThsSyncJob < ApplicationJob
  queue_as :scheduled

  def perform
    ThsSession.active.find_each do |session|
      next if session.expired?

      begin
        importer = ThsSync::Importer.new(session)
        results = importer.sync!
        Rails.logger.info("[ThsSync] userid=#{session.userid}: created=#{results[:created]} skipped=#{results[:skipped]} errors=#{results[:errors].size}")
      rescue ThsClient::AuthError => e
        Rails.logger.warn("[ThsSync] userid=#{session.userid} expired: #{e.message}")
      rescue => e
        Rails.logger.error("[ThsSync] userid=#{session.userid} error: #{e.class} #{e.message}")
        session.update!(last_error: e.message)
      end
    end
  end
end
