require "test_helper"

class SyncableTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    @account = accounts(:investment)
    @account.syncs.delete_all
  end

  # -----------------------------------------------------------------------
  # sync_later: no existing sync → create and enqueue
  # -----------------------------------------------------------------------
  test "creates and enqueues sync when none exists" do
    assert_difference "@account.syncs.count", 1 do
      assert_enqueued_with(job: SyncJob) do
        @account.sync_later
      end
    end

    sync = @account.syncs.last
    assert_equal "pending", sync.status
    assert_nil sync.window_start_date
  end

  test "creates windowed sync when window params given and no existing sync" do
    assert_difference "@account.syncs.count", 1 do
      assert_enqueued_with(job: SyncJob) do
        @account.sync_later(window_start_date: Date.current, window_end_date: Date.current)
      end
    end

    sync = @account.syncs.last
    assert_equal Date.current, sync.window_start_date
    assert_equal Date.current, sync.window_end_date
  end

  # -----------------------------------------------------------------------
  # sync_later: pending sync exists → expand window, do NOT create new job
  # -----------------------------------------------------------------------
  test "expands pending sync window instead of creating duplicate" do
    existing = @account.syncs.create!(window_start_date: Date.current, window_end_date: Date.current)

    assert_no_difference "@account.syncs.count" do
      assert_no_enqueued_jobs(only: SyncJob) do
        @account.sync_later(window_start_date: 2.days.ago.to_date, window_end_date: Date.current)
      end
    end

    assert_equal 2.days.ago.to_date, existing.reload.window_start_date
  end

  test "pending full sync absorbs windowed request (full sync stays full)" do
    # A pending full sync (no window) should not be narrowed by a windowed request
    existing = @account.syncs.create!(window_start_date: nil, window_end_date: nil)

    assert_no_difference "@account.syncs.count" do
      @account.sync_later(window_start_date: Date.current, window_end_date: Date.current)
    end

    existing.reload
    assert_nil existing.window_start_date, "Full sync window should remain nil"
  end

  # -----------------------------------------------------------------------
  # sync_later: sync currently RUNNING (syncing) → queue a new pending sync
  # -----------------------------------------------------------------------
  test "queues new pending sync when a sync is already running" do
    running_sync = @account.syncs.create!(status: "syncing", window_start_date: nil, window_end_date: nil)

    assert_difference "@account.syncs.count", 1 do
      assert_enqueued_with(job: SyncJob) do
        @account.sync_later(window_start_date: Date.current, window_end_date: Date.current)
      end
    end

    new_sync = @account.syncs.where(status: "pending").first
    assert_not_nil new_sync
    assert_equal Date.current, new_sync.window_start_date
  end

  test "multiple calls while syncing result in only one new pending sync" do
    @account.syncs.create!(status: "syncing", window_start_date: nil, window_end_date: nil)

    # First call while syncing → creates pending
    @account.sync_later(window_start_date: Date.current, window_end_date: Date.current)
    # Second call while syncing → expands the pending, does not create another
    assert_no_difference "@account.syncs.count" do
      @account.sync_later(window_start_date: 1.day.ago.to_date, window_end_date: Date.current)
    end

    pending_syncs = @account.syncs.where(status: "pending")
    assert_equal 1, pending_syncs.count
    assert_equal 1.day.ago.to_date, pending_syncs.first.window_start_date
  end
end
