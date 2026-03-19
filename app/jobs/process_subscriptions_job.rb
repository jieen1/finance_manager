class ProcessSubscriptionsJob < ApplicationJob
  queue_as :low_priority

  def perform
    UserSubscription.due_on(Date.current).find_each do |subscription|
      subscription.charge!
      Rails.logger.info "[ProcessSubscriptionsJob] Charged subscription: #{subscription.name} (#{subscription.id})"
    rescue => e
      Rails.logger.error "[ProcessSubscriptionsJob] Failed to charge subscription #{subscription.id}: #{e.message}"
    end
  end
end
