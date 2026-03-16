# THS (同花顺投资账本) Server-Side Data Sync Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace browser plugin data sync with server-side scheduled jobs that pull trade/position data from THS Investment Book API and import into the finance_manager system via the existing Trade::CreateForm pipeline.

**Architecture:** Three new layers — (1) ThsSession model stores cookies/auth, (2) ThsClient HTTP client calls THS APIs with correct headers, (3) ThsSync::Importer processes raw data into external_records, then creates Trade entries via existing Trade::CreateForm. ExternalRecord model stores raw data with dedup via external_id unique index. Sidekiq-cron job runs daily at 16:00 Beijing time.

**Tech Stack:** Rails 7.2, Sidekiq + sidekiq-cron, Net::HTTP (no new gems), PostgreSQL jsonb

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `db/migrate/xxx_create_ths_sessions.rb` | ThsSession table migration |
| `db/migrate/xxx_create_external_records.rb` | ExternalRecord table migration |
| `app/models/ths_session.rb` | Cookie/auth state management |
| `app/models/external_record.rb` | Raw data store with dedup |
| `app/models/ths_client.rb` | HTTP client for THS APIs (headers from request sample) |
| `app/models/ths_sync/importer.rb` | Orchestrator: fetch → store → import |
| `app/models/ths_sync/trade_mapper.rb` | Map THS raw data → Trade::CreateForm params |
| `app/jobs/ths_sync_job.rb` | Sidekiq job for scheduled sync |
| `app/controllers/ths_sessions_controller.rb` | Web UI for cookie management |
| `app/views/ths_sessions/` | Settings page for THS connection |
| `test/models/ths_client_test.rb` | Unit tests |
| `test/models/ths_sync/importer_test.rb` | Integration tests |
| `test/models/ths_sync/trade_mapper_test.rb` | Mapping tests |
| `test/models/external_record_test.rb` | Dedup tests |

### Modified Files
| File | Change |
|------|--------|
| `config/schedule.yml` | Add ths_sync cron entry |
| `config/routes.rb` | Add ths_sessions resource |
| `app/views/settings/_settings_nav.html.erb` | Add "同花顺同步" nav item |
| `.gitignore` | Add `scripts/ths_*.txt` pattern |

---

## Chunk 1: Database & Models

### Task 1: Create ThsSession Migration & Model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_ths_sessions.rb`
- Create: `app/models/ths_session.rb`
- Create: `test/models/ths_session_test.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails generate migration CreateThsSessions`

Edit the migration:
```ruby
class CreateThsSessions < ActiveRecord::Migration[7.2]
  def change
    create_table :ths_sessions, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true
      t.string :userid, null: false
      t.text :cookies, null: false
      t.string :status, default: "active"  # active, expired, error
      t.datetime :expires_at
      t.datetime :last_synced_at
      t.string :last_error
      t.timestamps
    end

    add_index :ths_sessions, [:family_id, :status]
  end
end
```

- [ ] **Step 2: Run migration**

Run: `bin/rails db:migrate`
Expected: Migration completes, ths_sessions table created

- [ ] **Step 3: Create ThsSession model**

```ruby
# app/models/ths_session.rb
class ThsSession < ApplicationRecord
  belongs_to :family

  scope :active, -> { where(status: "active") }

  validates :userid, presence: true
  validates :cookies, presence: true

  def expired?
    status == "expired" || (expires_at.present? && expires_at < Time.current)
  end

  def mark_expired!(error_msg = nil)
    update!(status: "expired", last_error: error_msg)
  end

  def mark_active!
    update!(status: "active", last_error: nil)
  end

  def record_sync!
    update!(last_synced_at: Time.current)
  end
end
```

- [ ] **Step 4: Write test**

```ruby
# test/models/ths_session_test.rb
require "test_helper"

class ThsSessionTest < ActiveSupport::TestCase
  test "validates required fields" do
    session = ThsSession.new
    assert_not session.valid?
    assert_includes session.errors[:userid], "can't be blank"
    assert_includes session.errors[:cookies], "can't be blank"
  end

  test "expired? returns true when past expires_at" do
    session = ThsSession.new(expires_at: 1.hour.ago)
    assert session.expired?
  end

  test "expired? returns false when within expires_at" do
    session = ThsSession.new(expires_at: 1.hour.from_now, status: "active")
    assert_not session.expired?
  end
end
```

- [ ] **Step 5: Run test**

Run: `bin/rails test test/models/ths_session_test.rb`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add db/migrate/ app/models/ths_session.rb test/models/ths_session_test.rb
git commit -m "feat: add ThsSession model for THS cookie management"
```

### Task 2: Create ExternalRecord Migration & Model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_external_records.rb`
- Create: `app/models/external_record.rb`
- Create: `test/models/external_record_test.rb`

- [ ] **Step 1: Generate migration**

Run: `bin/rails generate migration CreateExternalRecords`

Edit:
```ruby
class CreateExternalRecords < ActiveRecord::Migration[7.2]
  def change
    create_table :external_records, id: :uuid do |t|
      t.references :family, type: :uuid, null: false, foreign_key: true
      t.string :source, null: false         # "ths", "alipay", "wechat"
      t.string :external_id, null: false    # unique per source
      t.string :record_type, null: false    # "trade", "dividend", "transaction"
      t.jsonb :raw_data, null: false, default: {}
      t.string :status, default: "pending"  # pending, imported, skipped, error
      t.string :error_message
      t.references :entry, type: :uuid, foreign_key: true  # linked after import
      t.timestamps
    end

    add_index :external_records, [:source, :external_id], unique: true
    add_index :external_records, [:family_id, :source, :status]
    add_index :external_records, :status
  end
end
```

- [ ] **Step 2: Run migration**

Run: `bin/rails db:migrate`

- [ ] **Step 3: Create ExternalRecord model**

```ruby
# app/models/external_record.rb
class ExternalRecord < ApplicationRecord
  belongs_to :family
  belongs_to :entry, optional: true

  scope :pending, -> { where(status: "pending") }
  scope :imported, -> { where(status: "imported") }
  scope :errored, -> { where(status: "error") }
  scope :from_ths, -> { where(source: "ths") }

  validates :source, presence: true
  validates :external_id, presence: true, uniqueness: { scope: :source }
  validates :record_type, presence: true

  def mark_imported!(entry)
    update!(status: "imported", entry: entry, error_message: nil)
  end

  def mark_error!(message)
    update!(status: "error", error_message: message)
  end

  def mark_skipped!(reason = nil)
    update!(status: "skipped", error_message: reason)
  end
end
```

- [ ] **Step 4: Write test**

```ruby
# test/models/external_record_test.rb
require "test_helper"

class ExternalRecordTest < ActiveSupport::TestCase
  test "enforces unique external_id per source" do
    family = families(:dylan_family)
    ExternalRecord.create!(
      family: family,
      source: "ths",
      external_id: "test_123",
      record_type: "trade",
      raw_data: { test: true }
    )

    duplicate = ExternalRecord.new(
      family: family,
      source: "ths",
      external_id: "test_123",
      record_type: "trade",
      raw_data: { test: true }
    )
    assert_not duplicate.valid?
  end

  test "allows same external_id across different sources" do
    family = families(:dylan_family)
    ExternalRecord.create!(
      family: family,
      source: "ths",
      external_id: "test_123",
      record_type: "trade",
      raw_data: { test: true }
    )

    different_source = ExternalRecord.new(
      family: family,
      source: "alipay",
      external_id: "test_123",
      record_type: "transaction",
      raw_data: { test: true }
    )
    assert different_source.valid?
  end
end
```

- [ ] **Step 5: Run test**

Run: `bin/rails test test/models/external_record_test.rb`

- [ ] **Step 6: Commit**

```bash
git add db/migrate/ app/models/external_record.rb test/models/external_record_test.rb
git commit -m "feat: add ExternalRecord model with source+external_id unique dedup"
```

---

## Chunk 2: THS HTTP Client

### Task 3: Create ThsClient

**Files:**
- Create: `app/models/ths_client.rb`
- Create: `test/models/ths_client_test.rb`

- [ ] **Step 1: Create ThsClient**

The client must replicate EXACT headers from the browser request sample (scripts/ths_request_sample.txt):

```ruby
# app/models/ths_client.rb
class ThsClient
  BASE_URL = "https://tzzb.10jqka.com.cn/caishen_httpserver/tzzb"

  BROWSER_HEADERS = {
    "accept" => "application/json, text/plain, */*",
    "accept-language" => "zh-CN,zh;q=0.9",
    "content-type" => "application/x-www-form-urlencoded",
    "sec-ch-ua" => '"Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"',
    "sec-ch-ua-mobile" => "?0",
    "sec-ch-ua-platform" => '"Windows"',
    "sec-fetch-dest" => "empty",
    "sec-fetch-mode" => "cors",
    "sec-fetch-site" => "same-origin",
    "Referer" => "https://tzzb.10jqka.com.cn/pc/index.html"
  }.freeze

  attr_reader :ths_session

  def initialize(ths_session)
    @ths_session = ths_session
  end

  # Get all accounts
  def account_list
    post("/caishen_fund/pc/account/v1/account_list")
  end

  # Get trade history for an account
  def money_history(fund_key:, page: 1, count: 50)
    post("/caishen_fund/pc/account/v1/get_money_history", {
      "fund_key" => fund_key,
      "sort_type" => "entry_date",
      "sort_order" => "1",
      "page" => page.to_s,
      "count" => count.to_s
    })
  end

  # Get current stock positions
  def stock_position(fund_key:)
    post("/caishen_fund/pc/asset/v1/stock_position", {
      "fund_key" => fund_key
    })
  end

  # Test if session is alive
  def alive?
    result = account_list
    result && result["error_code"] == "0"
  rescue
    false
  end

  private

  def post(path, extra_params = {})
    url = URI("#{BASE_URL}#{path}")
    userid = ths_session.userid

    params = {
      "terminal" => "1",
      "version" => "0.0.0",
      "userid" => userid,
      "user_id" => userid
    }.merge(extra_params)

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true
    http.open_timeout = 15
    http.read_timeout = 30

    request = Net::HTTP::Post.new(url.path)
    BROWSER_HEADERS.each { |k, v| request[k] = v }
    request["Cookie"] = ths_session.cookies
    request.body = URI.encode_www_form(params)

    response = http.request(request)

    unless response.body.start_with?("{")
      raise ThsClient::AuthError, "Non-JSON response: #{response.body[0..100]}"
    end

    data = JSON.parse(response.body)

    if data["error_code"] != "0"
      raise ThsClient::ApiError, "THS API error: #{data["error_code"]} - #{data["error_msg"]}"
    end

    data
  rescue JSON::ParserError => e
    raise ThsClient::ParseError, "Invalid JSON: #{e.message}"
  end

  class AuthError < StandardError; end
  class ApiError < StandardError; end
  class ParseError < StandardError; end
end
```

- [ ] **Step 2: Write test with the real cookie**

```ruby
# test/models/ths_client_test.rb
require "test_helper"

class ThsClientTest < ActiveSupport::TestCase
  # Integration test using real cookie from scripts/ths_cookie.txt
  # Skip in CI, run manually: bin/rails test test/models/ths_client_test.rb
  test "live: stock_position returns position data" do
    cookie_file = Rails.root.join("scripts/ths_cookie.txt")
    skip "No THS cookie file" unless cookie_file.exist?

    cookies = cookie_file.read.strip
    userid = cookies.match(/userid=(\d+)/)[1]

    session = ThsSession.new(
      userid: userid,
      cookies: cookies,
      family: families(:dylan_family)
    )

    client = ThsClient.new(session)

    # Use the fund_key from the request sample
    result = client.stock_position(fund_key: "84360053")
    assert_equal "0", result["error_code"]
    assert result["ex_data"]["position"].is_a?(Array)

    # Verify position data structure
    first_pos = result["ex_data"]["position"].first
    assert first_pos["code"].present?
    assert first_pos["name"].present?
    assert first_pos["market"].present?
  end

  test "live: money_history returns trade records" do
    cookie_file = Rails.root.join("scripts/ths_cookie.txt")
    skip "No THS cookie file" unless cookie_file.exist?

    cookies = cookie_file.read.strip
    userid = cookies.match(/userid=(\d+)/)[1]

    session = ThsSession.new(
      userid: userid,
      cookies: cookies,
      family: families(:dylan_family)
    )

    client = ThsClient.new(session)
    result = client.money_history(fund_key: "84360053", page: 1, count: 5)
    assert_equal "0", result["error_code"]
  end
end
```

- [ ] **Step 3: Run live test**

Run: `bin/rails test test/models/ths_client_test.rb`
Expected: Tests pass (or skip if no cookie file)

- [ ] **Step 4: Commit**

```bash
git add app/models/ths_client.rb test/models/ths_client_test.rb
git commit -m "feat: add ThsClient HTTP client with browser-identical headers"
```

---

## Chunk 3: Trade Mapper & Importer

### Task 4: Create ThsSync::TradeMapper

**Files:**
- Create: `app/models/ths_sync/trade_mapper.rb`
- Create: `test/models/ths_sync/trade_mapper_test.rb`

- [ ] **Step 1: Create mapper**

Maps THS raw data to Trade::CreateForm parameters. Based on the actual response in ths_request_sample.txt:

```ruby
# app/models/ths_sync/trade_mapper.rb
module ThsSync
  class TradeMapper
    MARKET_TO_EXCHANGE = {
      "1" => "XSHE",   # Shenzhen
      "2" => "XSHG",   # Shanghai
      "15" => "XHKG",  # Hong Kong
      "3" => "XNAS",   # NASDAQ
      "4" => "XNYS"    # NYSE
    }.freeze

    MARKET_TO_CURRENCY = {
      "1" => "CNY",
      "2" => "CNY",
      "15" => "HKD",
      "3" => "USD",
      "4" => "USD"
    }.freeze

    OP_TO_TYPE = {
      "1" => "buy",
      "2" => "sell",
      "5" => "buy",
      "35" => "sell"   # reverse repo maturity
    }.freeze

    # Generate a unique external_id for dedup
    def self.external_id(record)
      parts = [
        record["account_id"] || record["fund_key"] || "default",
        record["entry_date"],
        record["entry_time"],
        record["code"],
        record["op"]
      ].map { |v| v.to_s.strip }
      parts.join("_")
    end

    # Classify what type of record this is
    def self.record_type(record)
      case record["op"].to_s
      when "6" then "dividend"
      when "1", "2", "5", "35" then "trade"
      else "unknown"
      end
    end

    # Map raw THS record to Trade::CreateForm params
    def self.to_trade_params(record, account_id:)
      op = record["op"].to_s
      trade_type = OP_TO_TYPE[op]
      return nil unless trade_type

      market = record["market"].to_s
      exchange = MARKET_TO_EXCHANGE[market] || "XSHG"
      currency = MARKET_TO_CURRENCY[market] || "CNY"
      code = record["code"].to_s.strip

      return nil if code.blank? || code == "00000"

      qty = record["entry_count"].to_f.abs
      return nil if qty.zero?

      {
        account_id: account_id,
        date: record["entry_date"],
        type: trade_type,
        ticker: "#{code}|#{exchange}",
        qty: qty,
        price: record["entry_price"].to_f,
        fee: record["fee_total"].to_f,
        currency: currency,
        fee_currency: "CNY"
      }
    end
  end
end
```

- [ ] **Step 2: Write test**

```ruby
# test/models/ths_sync/trade_mapper_test.rb
require "test_helper"

class ThsSync::TradeMapperTest < ActiveSupport::TestCase
  test "maps buy record correctly" do
    record = {
      "op" => "1", "code" => "000001", "name" => "平安银行",
      "market" => "1", "entry_date" => "2026-03-15",
      "entry_time" => "09:30:00", "entry_count" => "100",
      "entry_price" => "12.50", "entry_money" => "1250",
      "fee_total" => "5.00", "account_id" => "acc1"
    }

    params = ThsSync::TradeMapper.to_trade_params(record, account_id: "uuid-123")
    assert_equal "buy", params[:type]
    assert_equal "000001|XSHE", params[:ticker]
    assert_equal 100.0, params[:qty]
    assert_equal 12.50, params[:price]
    assert_equal 5.0, params[:fee]
    assert_equal "CNY", params[:currency]
  end

  test "maps HK stock correctly" do
    record = {
      "op" => "1", "code" => "09926", "market" => "15",
      "entry_date" => "2026-03-15", "entry_time" => "10:00:00",
      "entry_count" => "5000", "entry_price" => "120.00",
      "entry_money" => "600000", "fee_total" => "150.00"
    }

    params = ThsSync::TradeMapper.to_trade_params(record, account_id: "uuid-123")
    assert_equal "09926|XHKG", params[:ticker]
    assert_equal "HKD", params[:currency]
  end

  test "returns nil for dividend records" do
    record = { "op" => "6", "code" => "000001" }
    assert_nil ThsSync::TradeMapper.to_trade_params(record, account_id: "x")
  end

  test "returns nil for zero quantity" do
    record = {
      "op" => "1", "code" => "000001", "market" => "1",
      "entry_date" => "2026-03-15", "entry_time" => "09:30:00",
      "entry_count" => "0", "entry_price" => "10", "fee_total" => "0"
    }
    assert_nil ThsSync::TradeMapper.to_trade_params(record, account_id: "x")
  end

  test "external_id is deterministic" do
    record = {
      "account_id" => "acc1", "entry_date" => "2026-03-15",
      "entry_time" => "09:30:00", "code" => "000001", "op" => "1"
    }
    id1 = ThsSync::TradeMapper.external_id(record)
    id2 = ThsSync::TradeMapper.external_id(record)
    assert_equal id1, id2
    assert_equal "acc1_2026-03-15_09:30:00_000001_1", id1
  end
end
```

- [ ] **Step 3: Run test**

Run: `bin/rails test test/models/ths_sync/trade_mapper_test.rb`

- [ ] **Step 4: Commit**

```bash
git add app/models/ths_sync/ test/models/ths_sync/
git commit -m "feat: add ThsSync::TradeMapper for THS data → Trade params mapping"
```

### Task 5: Create ThsSync::Importer

**Files:**
- Create: `app/models/ths_sync/importer.rb`
- Create: `test/models/ths_sync/importer_test.rb`

- [ ] **Step 1: Create importer**

```ruby
# app/models/ths_sync/importer.rb
module ThsSync
  class Importer
    attr_reader :ths_session, :family, :results

    def initialize(ths_session)
      @ths_session = ths_session
      @family = ths_session.family
      @results = { created: 0, skipped: 0, errors: [] }
    end

    def sync!
      client = ThsClient.new(ths_session)

      # Step 1: Get accounts
      account_data = client.account_list
      accounts = account_data.dig("ex_data", "list") || []

      if accounts.empty?
        # Fallback: try stock_position with known fund_key
        sync_positions(client, fund_key: nil)
        sync_trades(client, fund_key: nil)
      else
        accounts.each do |ths_account|
          fund_key = ths_account["fund_key"] || ths_account["manual_id"]
          sync_trades(client, fund_key: fund_key) if fund_key
        end
      end

      ths_session.record_sync!
      results
    rescue ThsClient::AuthError => e
      ths_session.mark_expired!(e.message)
      raise
    end

    private

    def sync_trades(client, fund_key:)
      page = 1
      loop do
        params = { fund_key: fund_key || "", page: page, count: 50 }
        data = client.money_history(**params)

        records = data.dig("ex_data", "list") || []
        break if records.empty?

        records.each { |record| store_and_import(record) }

        break if records.size < 50
        page += 1
        break if page > 100 # safety limit
      end
    rescue ThsClient::ApiError => e
      results[:errors] << "money_history failed: #{e.message}"
    end

    def sync_positions(client, fund_key:)
      # Positions are stored as raw data for reference, not imported as trades
      data = client.stock_position(fund_key: fund_key || "")
      positions = data.dig("ex_data", "position") || []

      positions.each do |pos|
        ExternalRecord.find_or_create_by(
          source: "ths_position",
          external_id: "position_#{Date.current}_#{pos["code"]}"
        ) do |r|
          r.family = family
          r.record_type = "position"
          r.raw_data = pos
          r.status = "imported" # positions are informational
        end
      end
    rescue ThsClient::ApiError => e
      results[:errors] << "stock_position failed: #{e.message}"
    end

    def store_and_import(record)
      ext_id = ThsSync::TradeMapper.external_id(record)
      rec_type = ThsSync::TradeMapper.record_type(record)

      ext_record = ExternalRecord.find_or_initialize_by(
        source: "ths",
        external_id: ext_id
      )

      if ext_record.persisted? && ext_record.status == "imported"
        results[:skipped] += 1
        return
      end

      # Store raw data (even if we skip import)
      ext_record.assign_attributes(
        family: family,
        record_type: rec_type,
        raw_data: record,
        status: "pending"
      )
      ext_record.save!

      # Only import trade types
      if rec_type == "trade"
        import_trade(ext_record, record)
      else
        ext_record.mark_skipped!("record_type=#{rec_type}, not imported")
      end
    rescue => e
      results[:errors] << "#{ext_id}: #{e.message}"
    end

    def import_trade(ext_record, record)
      account = find_investment_account
      return ext_record.mark_error!("No investment account found") unless account

      params = ThsSync::TradeMapper.to_trade_params(record, account_id: account.id)
      return ext_record.mark_skipped!("unmappable record") unless params

      form = Trade::CreateForm.new(**params.merge(account: account))
      entry = form.create

      if entry.persisted?
        ext_record.mark_imported!(entry)
        results[:created] += 1
      else
        ext_record.mark_error!(entry.errors.full_messages.join(", "))
        results[:errors] << "#{ext_record.external_id}: #{entry.errors.full_messages.join(", ")}"
      end
    end

    def find_investment_account
      @investment_account ||= family.accounts
        .where(accountable_type: "Investment")
        .where(status: "active")
        .first
    end
  end
end
```

- [ ] **Step 2: Write integration test with live data**

```ruby
# test/models/ths_sync/importer_test.rb
require "test_helper"

class ThsSync::ImporterTest < ActiveSupport::TestCase
  test "live: sync! creates external records and trades" do
    cookie_file = Rails.root.join("scripts/ths_cookie.txt")
    skip "No THS cookie file" unless cookie_file.exist?

    cookies = cookie_file.read.strip
    userid = cookies.match(/userid=(\d+)/)[1]
    family = families(:dylan_family)

    # Ensure an investment account exists
    account = family.accounts.find_by(accountable_type: "Investment")
    unless account
      investment = Investment.create!
      account = family.accounts.create!(
        name: "华宝投资测试",
        accountable: investment,
        balance: 0,
        currency: "CNY"
      )
    end

    session = ThsSession.create!(
      family: family,
      userid: userid,
      cookies: cookies
    )

    importer = ThsSync::Importer.new(session)
    results = importer.sync!

    puts "Sync results: #{results.inspect}"
    puts "External records: #{ExternalRecord.from_ths.count}"
    puts "Created trades: #{results[:created]}"
    puts "Skipped: #{results[:skipped]}"
    puts "Errors: #{results[:errors]}"

    # Verify external records were created
    assert ExternalRecord.from_ths.count > 0, "Should create external records"

    # Verify dedup: running again should skip all
    results2 = ThsSync::Importer.new(session).sync!
    assert_equal 0, results2[:created], "Second sync should create 0 new records"
    assert results2[:skipped] > 0, "Second sync should skip existing records"
  end
end
```

- [ ] **Step 3: Run integration test**

Run: `bin/rails test test/models/ths_sync/importer_test.rb`
Expected: Creates records on first run, skips on second run

- [ ] **Step 4: Commit**

```bash
git add app/models/ths_sync/ test/models/ths_sync/
git commit -m "feat: add ThsSync::Importer with external_record dedup pipeline"
```

---

## Chunk 4: Scheduled Job & Settings UI

### Task 6: Create ThsSyncJob

**Files:**
- Create: `app/jobs/ths_sync_job.rb`
- Modify: `config/schedule.yml`

- [ ] **Step 1: Create job**

```ruby
# app/jobs/ths_sync_job.rb
class ThsSyncJob < ApplicationJob
  queue_as :scheduled

  def perform
    ThsSession.active.find_each do |session|
      next if session.expired?

      begin
        importer = ThsSync::Importer.new(session)
        results = importer.sync!
        Rails.logger.info("[ThsSync] Session #{session.userid}: #{results.inspect}")
      rescue ThsClient::AuthError => e
        Rails.logger.warn("[ThsSync] Session #{session.userid} expired: #{e.message}")
      rescue => e
        Rails.logger.error("[ThsSync] Session #{session.userid} error: #{e.message}")
        session.update!(last_error: e.message)
      end
    end
  end
end
```

- [ ] **Step 2: Add to schedule.yml**

Append to `config/schedule.yml`:
```yaml
ths_sync:
  cron: "0 8 * * 1-5" # 4:00 PM Beijing time (8:00 AM UTC) Monday through Friday
  class: "ThsSyncJob"
  queue: "scheduled"
  description: "Syncs trade data from THS Investment Book after market close"
```

- [ ] **Step 3: Commit**

```bash
git add app/jobs/ths_sync_job.rb config/schedule.yml
git commit -m "feat: add ThsSyncJob with daily 4PM Beijing cron schedule"
```

### Task 7: Create ThsSessions Controller & Settings UI

**Files:**
- Create: `app/controllers/ths_sessions_controller.rb`
- Create: `app/views/ths_sessions/index.html.erb`
- Modify: `config/routes.rb`
- Modify: `app/views/settings/_settings_nav.html.erb`

- [ ] **Step 1: Add route**

In `config/routes.rb`, inside the main routes block (not api namespace):
```ruby
resources :ths_sessions, only: [:index, :create, :destroy] do
  member do
    post :sync_now
    post :test_connection
  end
end
```

- [ ] **Step 2: Create controller**

```ruby
# app/controllers/ths_sessions_controller.rb
class ThsSessionsController < ApplicationController
  layout "settings"
  before_action :set_breadcrumbs

  def index
    @ths_session = Current.family.ths_sessions.order(created_at: :desc).first
    @recent_records = ExternalRecord.from_ths
      .where(family: Current.family)
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
      redirect_to ths_sessions_path, alert: "Cookie 已过期，请重新登录: #{e.message}"
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
    @breadcrumbs = [["首页", root_path], ["设置", settings_profile_path], ["同花顺同步", nil]]
  end
end
```

- [ ] **Step 3: Create view**

```erb
<%# app/views/ths_sessions/index.html.erb %>

<% content_for :page_title do %>
  同花顺数据同步
<% end %>

<div class="space-y-6">
  <%# Session Management %>
  <div class="aurora-card" style="padding:20px 22px">
    <h2 class="text-lg font-medium mb-4">同花顺账户连接</h2>

    <% if @ths_session&.persisted? %>
      <div class="flex items-center justify-between mb-4 p-3 rounded-lg" style="background:var(--aurora-bg-3)">
        <div>
          <p class="text-sm font-medium text-primary">UserID: <%= @ths_session.userid %></p>
          <p class="text-xs text-secondary">
            状态:
            <% if @ths_session.expired? %>
              <span style="color:var(--aurora-rose)">已过期</span>
            <% else %>
              <span style="color:var(--aurora-em)">正常</span>
            <% end %>
            <% if @ths_session.last_synced_at %>
              · 上次同步: <%= time_ago_in_words(@ths_session.last_synced_at) %>前
            <% end %>
          </p>
          <% if @ths_session.last_error.present? %>
            <p class="text-xs mt-1" style="color:var(--aurora-rose)"><%= @ths_session.last_error %></p>
          <% end %>
        </div>
        <div class="flex gap-2">
          <%= button_to "测试连接", test_connection_ths_session_path(@ths_session), method: :post, class: "aurora-btn-ghost text-xs" %>
          <%= button_to "立即同步", sync_now_ths_session_path(@ths_session), method: :post, class: "aurora-btn-primary text-xs" %>
          <%= button_to "删除", ths_session_path(@ths_session), method: :delete, class: "aurora-btn-ghost text-xs", style: "color:var(--aurora-rose)" %>
        </div>
      </div>
    <% end %>

    <%= form_with url: ths_sessions_path, method: :post, local: true do |f| %>
      <div class="space-y-3">
        <div>
          <label class="text-sm font-medium text-primary block mb-1">
            <%= @ths_session ? "更新" : "添加" %> Cookie
          </label>
          <p class="text-xs text-secondary mb-2">
            浏览器登录 tzzb.10jqka.com.cn → F12 → Console → 输入 document.cookie → 复制粘贴到下方
          </p>
          <%= f.text_area :cookies, rows: 3, class: "w-full text-xs rounded-lg p-3 font-mono",
              style: "background:var(--aurora-bg-3);border:1px solid var(--aurora-bd-h);color:var(--aurora-t0)",
              placeholder: "粘贴完整 cookie 字符串..." %>
        </div>
        <%= f.submit "保存", class: "aurora-btn-primary text-sm" %>
      </div>
    <% end %>
  </div>

  <%# Recent sync records %>
  <div class="aurora-card" style="padding:20px 22px">
    <h2 class="text-lg font-medium mb-4">最近同步记录</h2>

    <% if @recent_records.any? %>
      <div class="space-y-1">
        <% @recent_records.each do |rec| %>
          <div class="flex items-center justify-between p-2 rounded-lg text-sm aurora-entry-row">
            <div>
              <span class="font-medium text-primary"><%= rec.raw_data["name"] || rec.raw_data["code"] || rec.external_id %></span>
              <span class="text-xs text-secondary ml-2"><%= rec.record_type %></span>
            </div>
            <div class="flex items-center gap-3">
              <span class="text-xs" style="color:<%= rec.status == "imported" ? "var(--aurora-em)" : rec.status == "error" ? "var(--aurora-rose)" : "var(--aurora-t2)" %>">
                <%= rec.status %>
              </span>
              <span class="text-xs text-secondary"><%= time_ago_in_words(rec.created_at) %>前</span>
            </div>
          </div>
        <% end %>
      </div>
    <% else %>
      <p class="text-sm text-secondary">暂无同步记录</p>
    <% end %>
  </div>
</div>
```

- [ ] **Step 4: Add Family association**

Add to `app/models/family.rb`:
```ruby
has_many :ths_sessions, dependent: :destroy
has_many :external_records, dependent: :destroy
```

- [ ] **Step 5: Add settings nav item**

In `app/views/settings/_settings_nav.html.erb`, add to the general section items array:
```ruby
{ label: "同花顺同步", path: ths_sessions_path, icon: "refresh-cw" },
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/ths_sessions_controller.rb app/views/ths_sessions/ config/routes.rb app/views/settings/_settings_nav.html.erb app/models/family.rb
git commit -m "feat: add THS session management UI in settings"
```

### Task 8: Protect sensitive files in gitignore

- [ ] **Step 1: Update .gitignore**

Append:
```
scripts/ths_cookie.txt
scripts/ths_request_sample.txt
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: gitignore THS cookie and request sample files"
```

---

## Chunk 5: End-to-End Testing & Verification

### Task 9: Full integration test with live data

- [ ] **Step 1: Run full test suite**

Run: `bin/rails test test/models/ths_client_test.rb test/models/ths_sync/trade_mapper_test.rb test/models/ths_sync/importer_test.rb test/models/ths_session_test.rb test/models/external_record_test.rb`
Expected: All tests pass

- [ ] **Step 2: Test via Rails console**

```ruby
# Load cookie
cookies = File.read("scripts/ths_cookie.txt").strip
userid = cookies.match(/userid=(\d+)/)[1]
family = Family.first

# Create session
session = ThsSession.create!(family: family, userid: userid, cookies: cookies)

# Test client
client = ThsClient.new(session)
puts client.alive? # => true

# Test position fetch
pos = client.stock_position(fund_key: "84360053")
puts "Positions: #{pos["ex_data"]["position"].size}"

# Run import
importer = ThsSync::Importer.new(session)
results = importer.sync!
puts results.inspect

# Verify database
puts "External records: #{ExternalRecord.from_ths.count}"
puts "Pending: #{ExternalRecord.from_ths.pending.count}"
puts "Imported: #{ExternalRecord.from_ths.imported.count}"
puts "Errored: #{ExternalRecord.from_ths.errored.count}"

# Verify trades created
puts "Trades in account: #{family.accounts.find_by(accountable_type: 'Investment')&.entries&.count}"
```

- [ ] **Step 3: Test web UI**

1. Start server: `bin/dev`
2. Navigate to Settings → 同花顺同步
3. Paste cookie, save
4. Click "测试连接"
5. Click "立即同步"
6. Verify sync records appear

- [ ] **Step 4: Take screenshots for verification**

Screenshots needed:
1. Settings page showing THS session connected
2. Sync results after clicking "立即同步"
3. Recent sync records list
4. Rails console showing ExternalRecord counts
5. Rails console showing created trades
6. Account detail page showing synced trades

- [ ] **Step 5: Create verification report**

Create `docs/ths-sync-verification-report.md` with test results.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "feat: complete THS data sync system with verification"
```
