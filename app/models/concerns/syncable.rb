module Syncable
  extend ActiveSupport::Concern

  included do
    has_many :syncs, as: :syncable, dependent: :destroy
  end

  def syncing?
    syncs.visible.any?
  end

  # Schedules a sync for syncable.
  #
  # Strategy:
  # - If a pending sync exists, expand its window to cover the new request (batching).
  # - If a sync is currently running (syncing), create a new pending sync to run after it.
  #   This ensures structural changes (new trades, transfers) are never silently dropped.
  # - Otherwise, create and enqueue a new sync immediately.
  def sync_later(parent_sync: nil, window_start_date: nil, window_end_date: nil)
    Sync.transaction do
      with_lock do
        pending_sync = self.syncs.where(status: "pending").first

        if pending_sync
          Rails.logger.info("Expanding pending sync window (#{pending_sync.id})")
          pending_sync.expand_window_if_needed(window_start_date, window_end_date)
          pending_sync
        else
          sync = self.syncs.create!(
            parent: parent_sync,
            window_start_date: window_start_date,
            window_end_date: window_end_date
          )
          SyncJob.perform_later(sync)
          sync
        end
      end
    end
  end

  def perform_sync(sync)
    syncer.perform_sync(sync)
  end

  def perform_post_sync
    syncer.perform_post_sync
  end

  def broadcast_sync_complete
    sync_broadcaster.broadcast
  end

  def sync_error
    latest_sync&.error || latest_sync&.children&.map(&:error)&.compact&.first
  end

  def last_synced_at
    latest_sync&.completed_at
  end

  def last_sync_created_at
    latest_sync&.created_at
  end

  private
    def latest_sync
      syncs.ordered.first
    end

    def syncer
      self.class::Syncer.new(self)
    end

    def sync_broadcaster
      self.class::SyncCompleteEvent.new(self)
    end
end
