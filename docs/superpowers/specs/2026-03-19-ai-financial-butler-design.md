# AI 财务管家系统设计

> 将财务管理系统从"用户维护的记账工具"升级为"AI 驱动的财务管家"——自动获取数据、自动整理分析、主动帮用户做事。

## 1. 核心理念

**三个原则：**

1. **管家做事，用户检阅** — 系统自动完成 90% 的工作，用户只在必要时确认
2. **渐进式信任** — 低风险操作全自动，高风险操作需确认，信任级别可调
3. **数据安全优先** — 只读取必要的最小数据集，自有服务器处理，不经第三方

## 2. 系统架构

```
┌──────────────────── 数据入口层 ────────────────────┐
│                                                     │
│  鸿蒙App          微信/钉钉         Web 端           │
│  (截屏自动记账)    (机器人记账)      (对话+CSV导入)    │
│       │               │               │             │
└───────┴───────────────┴───────────────┴─────────────┘
                        │
                        ▼
┌──────────────────── Agent 核心引擎 ─────────────────┐
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │          输入处理层 (Input Processor)          │  │
│  │  文字意图识别 │ 图片OCR识别 │ CSV账单解析      │  │
│  │  → 统一输出：结构化请求（记账/查询/指令）      │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │          Agent 决策引擎 (Planner)             │  │
│  │  理解意图 → 拆解步骤 → 选择工具 → 多步执行    │  │
│  │  支持连续调用多个工具完成一个复合任务           │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │          工具注册表 (Tool Registry)            │  │
│  │                                               │  │
│  │  ── 读操作（现有 + 扩展）──                    │  │
│  │  get_transactions    查交易                    │  │
│  │  get_accounts        查账户                    │  │
│  │  get_balance_sheet   查资产负债表              │  │
│  │  get_income_statement 查收支报表               │  │
│  │  get_holdings         查持仓明细（新增）        │  │
│  │  get_asset_allocation 查资产配置比例（新增）    │  │
│  │  get_budgets          查预算及执行情况（新增）  │  │
│  │  get_goals            查财务目标进度（新增）    │  │
│  │  get_subscriptions    查订阅列表（新增）        │  │
│  │                                               │  │
│  │  ── 写操作（新增）──                           │  │
│  │  create_transaction    创建交易记录             │  │
│  │  categorize_transactions 批量分类交易          │  │
│  │  create_budget         创建/调整预算            │  │
│  │  create_goal           创建财务目标             │  │
│  │  update_goal           更新目标进度             │  │
│  │                                               │  │
│  │  ── 分析工具（新增）──                         │  │
│  │  analyze_spending      消费模式分析             │  │
│  │  analyze_investment    投资组合分析             │  │
│  │  detect_anomalies      异常消费检测             │  │
│  │  generate_report       生成财务报告             │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │          定时引擎 (Scheduler)                  │  │
│  │  每日 8:00  处理订阅扣费（已实现）             │  │
│  │  每日 9:00  自动分类昨日新交易                  │  │
│  │  每周一 8:00 生成周报                          │  │
│  │  每月1日 8:00 生成月报 + 检查预算 + 检查目标   │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │          权限控制层 (Permission)               │  │
│  │                                               │  │
│  │  自动执行（无需确认）:                         │  │
│  │    · 创建交易记录（从截屏/机器人/CSV）         │  │
│  │    · 自动分类交易                              │  │
│  │    · 生成分析报告                              │  │
│  │    · 检测异常消费                              │  │
│  │                                               │  │
│  │  需确认（Agent 建议，用户点确认）:             │  │
│  │    · 创建/调整预算                             │  │
│  │    · 设定财务目标                              │  │
│  │    · 批量修改交易分类                          │  │
│  │                                               │  │
│  │  需审批（敏感操作）:                           │  │
│  │    · 删除交易记录                              │  │
│  │    · 修改账户信息                              │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────── 数据层 ─────────────────────────┐
│  现有: 账户│交易│持仓│预算│分类│标签│订阅│规则       │
│  新增: 财务目标(Goal)│Agent报告(Report)│行动项(Todo) │
└─────────────────────────────────────────────────────┘
```

## 3. Roadmap

### Phase 1：Agent 引擎基建

**目标**：把 AI 助手从"只能看"升级为"能做事"，支持多步推理。

#### 3.1.1 升级 Assistant::Responder 支持多步工具调用

现状：AI 只能调用一轮工具，第二轮 LLM 调用不允许再请求工具。
目标：支持最多 5 轮工具调用，让 AI 能完成复合任务。

```
用户: "帮我看看这个月餐饮花了多少，如果超过 2000 就帮我设个预算"
  → Agent 第1步: 调用 get_income_statement 查餐饮支出
  → Agent 第2步: 发现花了 2800，调用 create_budget 创建餐饮预算 2000
  → Agent 回复: "这个月餐饮花了 2800 元，已帮你设定 2000 元/月的餐饮预算"
```

技术方案：
- 修改 `Assistant::Responder#respond` 方法，将单次调用改为循环（最多 5 轮）
- 每轮检查 LLM 返回是否包含 `function_requests`
- 设置总 token 上限防止失控
- 记录每轮工具调用到 `ToolCall::Function` 用于审计

#### 3.1.2 新增写操作工具

**create_transaction** — 创建交易记录
```
参数: account_name, amount, category_name, date, merchant_name, notes
行为: 在指定账户创建 Entry + Transaction
权限: 自动执行
```

**categorize_transactions** — 批量分类交易
```
参数: transaction_ids[], category_name
行为: 批量更新交易分类
权限: 自动执行
```

**create_budget** — 创建预算
```
参数: category_name, amount, month
行为: 创建或更新 Budget + BudgetCategory
权限: 需确认
```

#### 3.1.3 新增读操作工具

**get_holdings** — 查持仓明细（现有 AI 无法看到持仓数据）
```
返回: 所有持仓的证券名、数量、当前价格、市值、盈亏
```

**get_asset_allocation** — 查资产配置
```
返回: 按类型（现金/股票/基金/房产/其他）分组的资产占比
```

**get_budgets** — 查预算执行
```
返回: 所有预算及当月执行进度
```

#### 3.1.4 增强系统提示词

在现有 system prompt 基础上增加：
- 用户财务画像（风险偏好、收入水平、已设目标）
- Agent 行为准则（什么时候该主动做事，什么时候该先问）
- 中文语境优化（A 股术语、人民币格式、中国消费场景）

### Phase 2：便捷记账

**目标**：让记账的操作成本降到最低，接近无感。

#### 3.2.1 鸿蒙 App — 截屏自动记账

**核心流程：**
```
用户在微信/支付宝付款后截屏（1秒）
     ↓
鸿蒙App后台定时任务（每5分钟）
     ↓
photoAccessHelper 查询新截屏
  过滤条件: PhotoSubtype.SCREENSHOT && date_added > 上次扫描时间
     ↓
只拿到最近的新截屏（不碰任何其他照片）
     ↓
上传到自有服务器 POST /api/v1/ocr_entries
     ↓
GPT-4 Vision 识别：金额、商家、时间、支付方式
     ↓
自动创建交易记录 + 自动分类
     ↓
通知用户：已记录 ¥35 餐饮-外卖（可选）
```

**安全设计：**
- 只读 `PhotoSubtype.SCREENSHOT`，普通照片/视频完全不接触
- 时间窗口过滤，只看上次扫描后的新截屏
- 每次最多处理 10 张
- 图片发送到自有服务器，识别完成后不保留原图
- App 端可设置开关，随时关闭自动扫描

**鸿蒙 App 技术栈：**
- HarmonyOS NEXT (API 14+)
- ArkTS + ArkUI
- photoAccessHelper（相册读取）
- backgroundTaskManager（后台定时任务）
- HTTP 请求调用服务端 API

**服务端新增 API：**
```
POST /api/v1/ocr_entries
  请求: multipart/form-data, image file
  处理: GPT-4 Vision OCR → 提取结构化数据 → 创建 Entry
  响应: { entry_id, amount, category, merchant, date }
```

#### 3.2.2 微信企业号机器人

**流程：**
```
用户发给机器人: "午饭 外卖 35" 或发一张消费截图
     ↓
企业微信 webhook 回调到服务端
     ↓
AI 识别意图：
  文字 → NLP 提取金额、分类
  图片 → GPT-4 Vision OCR
     ↓
自动创建交易记录
     ↓
回复: "已记录：餐饮-外卖 ¥35"
```

#### 3.2.3 CSV 智能导入

增强现有 CSV 导入功能：
- 支持微信账单 CSV 格式自动识别
- 支持支付宝账单 CSV 格式自动识别
- AI 自动映射字段（不需要手动选列）
- 与已有交易自动去重（按金额+时间+商家匹配）
- AI 自动分类所有导入的交易

### Phase 3：自动化运转

**目标**：系统自己跑起来，用户打开就看到干净的数据和分析。

#### 3.3.1 自动分类引擎

每日定时任务，对前一天所有未分类交易：
- 调用现有 `AutoCategorizeJob` 批量分类
- 对无法自动分类的交易，标记为"待确认"
- 用户下次打开系统时，只需确认少量标记的交易

#### 3.3.2 自动报告生成

**周报**（每周一自动生成）：
- 本周收支概览
- 与上周对比
- 异常消费标记（某类支出同比增长超 50%）
- 投资持仓变动

**月报**（每月 1 日自动生成）：
- 月度收支明细（按分类）
- 资产配置分析（各类资产占比及变动）
- 预算执行情况
- 财务目标进度
- AI 洞察和建议

**技术实现：**
- 新建 `AgentReport` 模型存储报告
- `GenerateWeeklyReportJob` / `GenerateMonthlyReportJob` 定时任务
- 报告内容由 AI 基于数据生成结构化 Markdown
- Web 端新增"管家报告"页面展示

#### 3.3.3 异常检测

每日扫描：
- 单笔大额消费（超过月均消费的 3 倍）
- 分类支出暴增（某类消费同比上月增长 50%+）
- 重复扣费（同商家、同金额、短时间内多次）
- 结果标记到交易记录上，不主动打扰用户

### Phase 4：财务规划与目标追踪

**目标**：帮用户建立财务规划习惯，AI 做规划和追踪。

#### 3.4.1 财务目标系统

新建 `FinancialGoal` 模型：
```ruby
# 字段设计
name            # 目标名称，如"建立6个月应急金"
goal_type       # 类型：savings(存钱), reduction(减持), budget(控支出)
target_amount   # 目标金额
current_amount  # 当前进度（自动计算）
target_date     # 目标日期
status          # active, completed, paused
strategy        # AI 生成的执行策略（JSON）
milestones      # 里程碑（JSON 数组）
```

**使用场景：**
```
用户: "帮我制定一个存 10 万应急金的计划"
Agent:
  1. 调用 get_income_statement 分析月均收支
  2. 调用 get_asset_allocation 查看当前现金比例
  3. 计算每月可存金额
  4. 调用 create_goal 创建目标 + 里程碑
  5. 回复详细的执行计划
```

#### 3.4.2 资产配置分析

基于持仓和账户数据，自动计算：
- 资产类别占比（现金/股票/基金/房产/保险/其他）
- 与标准模型对比（如 "你的年龄段建议股票占比 40-60%"）
- 集中度风险（单只股票占比过高）
- 历史配置变化趋势

#### 3.4.3 目标自动追踪

- 每月月报中包含目标进度
- Agent 对话中可随时查询目标状态
- 目标偏离时在月报中提出调整建议（不主动打扰）

## 4. 新增数据模型

### 4.1 AgentReport（Agent 报告）

```ruby
create_table :agent_reports, id: :uuid do |t|
  t.references :family, null: false, foreign_key: true, type: :uuid
  t.string :report_type, null: false  # weekly, monthly, custom
  t.string :title, null: false
  t.text :content, null: false        # Markdown 格式
  t.jsonb :metadata                   # 报告相关的结构化数据
  t.date :period_start
  t.date :period_end
  t.timestamps
end
```

### 4.2 FinancialGoal（财务目标）

```ruby
create_table :financial_goals, id: :uuid do |t|
  t.references :family, null: false, foreign_key: true, type: :uuid
  t.string :name, null: false
  t.string :goal_type, null: false    # savings, reduction, budget
  t.decimal :target_amount, precision: 19, scale: 4
  t.decimal :current_amount, precision: 19, scale: 4, default: 0
  t.string :currency, null: false
  t.date :target_date
  t.string :status, default: "active" # active, completed, paused
  t.jsonb :strategy                   # AI 生成的策略
  t.jsonb :milestones                 # 里程碑数组
  t.text :notes
  t.timestamps
end
```

### 4.3 AgentAction（Agent 行动日志）

```ruby
create_table :agent_actions, id: :uuid do |t|
  t.references :family, null: false, foreign_key: true, type: :uuid
  t.string :action_type, null: false  # create_transaction, categorize, etc.
  t.string :status, null: false       # pending, approved, executed, rejected
  t.jsonb :params                     # 操作参数
  t.jsonb :result                     # 执行结果
  t.string :source                    # chat, scheduler, ocr, webhook
  t.timestamps
end
```

## 5. Agent 工具详细设计

### 5.1 写操作工具

#### create_transaction

```json
{
  "name": "create_transaction",
  "description": "在指定账户创建一笔交易记录。用于手动记账、OCR识别后记账等场景。",
  "params_schema": {
    "type": "object",
    "properties": {
      "account_name": { "type": "string", "description": "账户名称" },
      "amount": { "type": "number", "description": "金额，正数为支出，负数为收入" },
      "category_name": { "type": "string", "description": "分类名称，如餐饮、交通" },
      "date": { "type": "string", "description": "日期 YYYY-MM-DD" },
      "merchant_name": { "type": "string", "description": "商家名称（可选）" },
      "notes": { "type": "string", "description": "备注（可选）" }
    },
    "required": ["account_name", "amount", "date"]
  },
  "permission_level": "auto"
}
```

#### create_budget

```json
{
  "name": "create_budget",
  "description": "为指定分类创建月度预算。如果该月已有预算则更新金额。",
  "params_schema": {
    "type": "object",
    "properties": {
      "category_name": { "type": "string" },
      "amount": { "type": "number", "description": "预算金额" },
      "month": { "type": "string", "description": "月份 YYYY-MM" }
    },
    "required": ["category_name", "amount", "month"]
  },
  "permission_level": "confirm"
}
```

#### create_goal

```json
{
  "name": "create_goal",
  "description": "创建一个财务目标，如存钱目标、减持目标等。",
  "params_schema": {
    "type": "object",
    "properties": {
      "name": { "type": "string" },
      "goal_type": { "type": "string", "enum": ["savings", "reduction", "budget"] },
      "target_amount": { "type": "number" },
      "target_date": { "type": "string", "description": "目标日期 YYYY-MM-DD" },
      "notes": { "type": "string" }
    },
    "required": ["name", "goal_type", "target_amount"]
  },
  "permission_level": "confirm"
}
```

### 5.2 分析工具

#### analyze_spending

```json
{
  "name": "analyze_spending",
  "description": "分析指定时间段的消费模式，包括分类排名、同比/环比变化、异常检测。",
  "params_schema": {
    "type": "object",
    "properties": {
      "start_date": { "type": "string" },
      "end_date": { "type": "string" },
      "compare_with": { "type": "string", "enum": ["previous_period", "same_period_last_year"] }
    },
    "required": ["start_date", "end_date"]
  }
}
```

#### analyze_investment

```json
{
  "name": "analyze_investment",
  "description": "分析投资组合：持仓分布、收益归因、集中度风险、与目标配置的偏离。",
  "params_schema": {
    "type": "object",
    "properties": {
      "include_history": { "type": "boolean", "description": "是否包含历史变化" }
    }
  }
}
```

#### generate_report

```json
{
  "name": "generate_report",
  "description": "生成指定类型的财务报告并保存。",
  "params_schema": {
    "type": "object",
    "properties": {
      "report_type": { "type": "string", "enum": ["weekly", "monthly", "custom"] },
      "period_start": { "type": "string" },
      "period_end": { "type": "string" }
    },
    "required": ["report_type"]
  },
  "permission_level": "auto"
}
```

## 6. OCR 记账 API 设计

### 6.1 服务端 API

```
POST /api/v1/ocr_entries
Content-Type: multipart/form-data

参数:
  image: 图片文件（截屏）
  source: "harmonyos_app" | "wechat_bot" | "web"

处理流程:
  1. 接收图片
  2. 调用 GPT-4 Vision API，prompt:
     "分析这张消费截图，提取以下信息（JSON格式）：
      amount（金额），merchant（商家名），date（日期），
      payment_method（支付方式），category（消费类别）。
      如果不是消费相关截图，返回 {is_expense: false}"
  3. 解析 AI 返回的 JSON
  4. 如果 is_expense == false，返回 204 No Content
  5. 如果是消费截图，创建 Entry + Transaction
  6. 返回创建的记录

响应:
  201 Created: { entry_id, amount, category, merchant, date }
  204 No Content: 非消费截图，已忽略
  422 Unprocessable: 识别失败
```

### 6.2 鸿蒙 App 设计

**功能页面：**
- 首页：最近记账记录列表 + 今日/本周/本月消费统计
- 设置：服务器地址、API Key、自动扫描开关、扫描频率
- 手动记账：快速输入金额+分类（备用）

**后台任务：**
```typescript
// 每5分钟执行一次
async function scanNewScreenshots() {
  const lastScanTime = await getLastScanTime();

  // 只查询截屏，不碰其他照片
  const screenshots = await photoAccessHelper.getAssets({
    predicates: new DataSharePredicates()
      .equalTo('subtype', PhotoSubtype.SCREENSHOT)
      .greaterThan('date_added', lastScanTime),
    fetchColumns: ['display_name', 'date_added', 'size', 'uri']
  });

  for (const screenshot of screenshots) {
    // 上传到服务器 OCR 识别
    const result = await uploadForOCR(screenshot);
    if (result.status === 201) {
      showNotification(`已记录: ${result.category} ¥${result.amount}`);
    }
  }

  await setLastScanTime(Date.now());
}
```

## 7. 多步 Agent 引擎技术设计

### 7.1 Responder 升级

```ruby
# app/models/assistant/responder.rb 改造要点

class Assistant::Responder
  MAX_TOOL_ROUNDS = 5  # 最多5轮工具调用

  def respond(message)
    messages = build_conversation(message)
    round = 0

    loop do
      response = call_llm(messages)

      if response.function_requests.any? && round < MAX_TOOL_ROUNDS
        # 执行工具调用
        results = fulfill_tool_calls(response.function_requests)
        # 将结果加入对话继续
        messages << tool_results_message(results)
        round += 1
      else
        # 最终回复
        save_assistant_message(response)
        break
      end
    end
  end
end
```

### 7.2 权限控制

```ruby
# app/models/assistant/tool_permission.rb

class Assistant::ToolPermission
  LEVELS = {
    auto: [],           # 自动执行，不需要确认
    confirm: [:create_budget, :create_goal, :update_goal, :categorize_batch],
    approve: [:delete_transaction, :modify_account]
  }

  def self.can_auto_execute?(tool_name)
    !LEVELS[:confirm].include?(tool_name.to_sym) &&
    !LEVELS[:approve].include?(tool_name.to_sym)
  end
end
```

### 7.3 工具执行器

```ruby
# app/models/assistant/function/create_transaction.rb

class Assistant::Function::CreateTransaction < Assistant::Function
  def call(params)
    account = family.accounts.find_by!(name: params["account_name"])
    category = family.categories.find_or_create_by!(name: params["category_name"]) if params["category_name"]

    entry = account.entries.create!(
      date: Date.parse(params["date"]),
      name: params["merchant_name"] || params["category_name"] || "手动记账",
      amount: params["amount"],
      currency: account.currency,
      entryable: Transaction.new(category: category)
    )

    { success: true, entry_id: entry.id, amount: entry.amount, category: category&.name }
  end
end
```

## 8. 实施计划

### Phase 1：Agent 引擎基建（预计 2-3 周）

| 步骤 | 内容 | 依赖 |
|------|------|------|
| 1.1 | 升级 Responder 支持多步工具调用 | 无 |
| 1.2 | 实现 create_transaction 工具 | 1.1 |
| 1.3 | 实现 get_holdings、get_asset_allocation 工具 | 1.1 |
| 1.4 | 实现 categorize_transactions 工具 | 1.1 |
| 1.5 | 增强 system prompt（中文财务语境） | 1.1 |
| 1.6 | 实现权限控制层 | 1.2 |
| 1.7 | 测试：多步对话场景验证 | 全部 |

### Phase 2：便捷记账（预计 3-4 周）

| 步骤 | 内容 | 依赖 |
|------|------|------|
| 2.1 | 服务端 OCR API（/api/v1/ocr_entries） | Phase 1 |
| 2.2 | 鸿蒙 App：项目搭建 + 相册截屏扫描 | 2.1 |
| 2.3 | 鸿蒙 App：后台定时任务 + 自动上传 | 2.2 |
| 2.4 | 鸿蒙 App：首页展示 + 设置页 | 2.3 |
| 2.5 | 微信企业号机器人（文字+图片记账） | 2.1 |
| 2.6 | 微信/支付宝 CSV 智能导入 | Phase 1 |

### Phase 3：自动化运转（预计 2 周）

| 步骤 | 内容 | 依赖 |
|------|------|------|
| 3.1 | 每日自动分类任务 | Phase 1 |
| 3.2 | AgentReport 模型 + 报告页面 | 无 |
| 3.3 | 周报/月报自动生成任务 | 3.2 + Phase 1 |
| 3.4 | 异常消费检测 | Phase 1 |

### Phase 4：财务规划（预计 2-3 周）

| 步骤 | 内容 | 依赖 |
|------|------|------|
| 4.1 | FinancialGoal 模型 + CRUD | 无 |
| 4.2 | create_goal / update_goal Agent 工具 | 4.1 + Phase 1 |
| 4.3 | 资产配置分析工具 | Phase 1 |
| 4.4 | 目标自动追踪（月报集成） | 4.1 + Phase 3 |

## 9. 对话示例

### 日常记账
```
用户: 今天中午在海底捞吃了 280
Agent: 已记录：餐饮 ¥280，商家：海底捞，日期：2026-03-19
```

### 复合任务
```
用户: 帮我看看这个月的消费情况，有没有什么异常
Agent:
  [调用 get_income_statement 2026-03-01 ~ 2026-03-19]
  [调用 analyze_spending 对比上月]

  本月已消费 ¥8,450，主要分布：
  · 餐饮 ¥3,200（占比 38%，比上月增长 45% ⚠️）
  · 交通 ¥1,800（占比 21%，正常）
  · 购物 ¥2,100（占比 25%，正常）
  · 其他 ¥1,350

  ⚠️ 异常：餐饮支出比上月增长 45%（上月 ¥2,200），
  主要是 3 月有 4 次聚餐消费，每次 300-500 元。

  需要我帮你设定一个餐饮预算吗？
```

### 财务规划
```
用户: 我想在年底前把股票仓位从 90% 降到 60%
Agent:
  [调用 get_asset_allocation]
  [调用 get_holdings]

  当前资产配置：
  · 股票 ¥580,000（92%）
  · 现金 ¥12,300（2%）
  · 其他 ¥38,000（6%）

  要降到 60%，需要从股票转出约 ¥200,000 到现金或其他资产。

  建议分 8 个月执行（每月减持约 ¥25,000），避免集中卖出。
  已创建目标：「股票仓位降至60%」，目标日期 2026-12-31。

  我会在每月报告中跟踪进度。
```
