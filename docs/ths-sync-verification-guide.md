# 同花顺数据同步 - 验证测试指南

## 前置条件

1. 浏览器登录 https://tzzb.10jqka.com.cn/pc
2. F12 → Console → 输入 `document.cookie` → 复制完整输出
3. 确保系统中有至少一个 Investment 类型的账户

## 测试清单

### 1. 数据库迁移
```bash
bin/rails db:migrate
```
预期：ths_sessions 和 external_records 两张表创建成功。

### 2. ThsClient 连接测试
```ruby
# bin/rails console
cookies = "你的完整cookie字符串"
userid = cookies.match(/userid=(\d+)/)[1]
family = Family.first
session = ThsSession.create!(family: family, userid: userid, cookies: cookies)
client = ThsClient.new(session)
puts client.alive?  # 预期: true
```

### 3. 获取持仓数据
```ruby
pos = client.stock_position(fund_key: "84360053")
puts pos["ex_data"]["position"].size  # 预期: 大于0
pos["ex_data"]["position"].each { |p| puts "#{p["name"]} #{p["count"]}股 @#{p["price"]}" }
```

### 4. 获取交易记录
```ruby
trades = client.money_history(fund_key: "84360053", page: 1, count: 10)
trades["ex_data"]["list"].each do |t|
  puts "[#{t["entry_date"]}] #{t["name"]} #{t["entry_count"]}股 @#{t["entry_price"]}"
end
```

### 5. 完整同步流程
```ruby
importer = ThsSync::Importer.new(session)
results = importer.sync!
puts results
# 预期: { created: N, skipped: 0, errors: [] }  (N > 0)
```

### 6. 去重验证
```ruby
results2 = ThsSync::Importer.new(session).sync!
puts results2
# 预期: { created: 0, skipped: N, errors: [] }  (第二次全部跳过)
```

### 7. 数据库验证
```ruby
puts "ExternalRecords: #{ExternalRecord.where(family: family).count}"
puts "  imported: #{ExternalRecord.where(family: family, status: 'imported').count}"
puts "  pending: #{ExternalRecord.where(family: family, status: 'pending').count}"
puts "  errored: #{ExternalRecord.where(family: family, status: 'error').count}"

# 查看原始数据保留
rec = ExternalRecord.where(family: family, source: "ths").last
puts rec.raw_data  # 预期: 完整的同花顺原始JSON
puts rec.external_id  # 预期: account_date_time_code_op 格式
```

### 8. Trade 创建验证
```ruby
account = family.accounts.find_by(accountable_type: "Investment")
entries = account.entries.where(entryable_type: "Trade").order(date: :desc).limit(5)
entries.each do |e|
  t = e.entryable
  puts "[#{e.date}] #{t.qty > 0 ? '买入' : '卖出'} #{t.security.ticker}|#{t.security.exchange_operating_mic} #{t.qty.abs}股 @#{t.price} 费用:#{t.fee}"
end
```

### 9. Web UI 测试
1. 访问 设置 → 同花顺同步
2. 粘贴 cookie → 保存 → 预期显示 "会话已保存"
3. 点击 "测试连接" → 预期显示 "连接正常"
4. 点击 "立即同步" → 预期显示 "同步完成: 新建 X, 跳过 Y"
5. 最近同步记录列表应显示条目

### 10. 定时任务验证
```bash
# 确认 schedule.yml 中的 ths_sync 配置
grep -A5 ths_sync config/schedule.yml
```

### 11. 现有功能不受影响
```bash
bin/rails test test/controllers/pages_controller_test.rb test/controllers/transactions_controller_test.rb test/controllers/accounts_controller_test.rb
# 预期: 0 failures, 0 errors
```

## 架构说明

```
数据流:
  同花顺服务器 → ThsClient (HTTP POST) → ThsSync::Importer
    → ExternalRecord (原始数据存储+去重)
    → ThsSync::TradeMapper (数据映射)
    → Trade::CreateForm (现有核心逻辑)
    → Entry + Trade + Security 数据库记录
    → account.sync_later (触发持仓+余额重算)

新增文件:
  app/models/ths_session.rb          - Cookie管理
  app/models/ths_client.rb           - HTTP客户端
  app/models/external_record.rb      - 原始数据存储
  app/models/ths_sync/trade_mapper.rb - 数据映射
  app/models/ths_sync/importer.rb    - 同步编排器
  app/jobs/ths_sync_job.rb           - 定时任务
  app/controllers/ths_sessions_controller.rb - Web管理
  app/views/ths_sessions/index.html.erb      - 设置页面

新增数据库表:
  ths_sessions      - Cookie/认证状态
  external_records  - 原始数据(去重索引: source + external_id)

未修改的核心文件:
  Trade::CreateForm, Security::Resolver, Entry, Trade,
  Holding::Syncer, Balance::Syncer 等全部未改动。
```
