class Family::Syncer
  attr_reader :family

  def initialize(family)
    @family = family
  end

  def perform_sync(sync)
    Rails.logger.info("Applying rules for family #{family.id}")
    family.rules.each do |rule|
      rule.apply_later
    end

    # Schedule child syncs
    child_syncables.each do |syncable|
      syncable.sync_later(parent_sync: sync, window_start_date: sync.window_start_date, window_end_date: sync.window_end_date)
    end
  end

  def perform_post_sync
    family.auto_match_transfers!
  end

  private
    def child_syncables
      family.accounts.manual
    end
end
