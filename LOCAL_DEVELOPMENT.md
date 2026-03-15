# 本地开发指南

本文档记录了 Maybe 金融管理应用的本地开发和测试配置。

## 快速启动

### 前置要求

- Ruby 3.4.4 (查看 `.ruby-version`)
- Node.js 和 npm
- Docker 和 Docker Compose（用于数据库和缓存）
- PostgreSQL 开发库: `libpq-dev`

### 1. 安装系统依赖

```bash
# Ubuntu/Debian
apt-get update
apt-get install -y libpq-dev
```

### 2. 安装 Ruby 依赖

```bash
bundle install
```

### 3. 启动 Docker 服务（PostgreSQL 和 Redis）

```bash
# 启动 PostgreSQL (端口 5432) 和 Redis (端口 6379)
docker run -d --name postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  postgres:latest

docker run -d --name redis \
  -p 6379:6379 \
  redis:latest
```

或者使用 Docker Compose（位于 `.devcontainer/`）：

```bash
cd .devcontainer
docker-compose up -d
```

### 4. 准备数据库

```bash
export DB_HOST=127.0.0.1
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=postgres

bin/rails db:prepare
```

这将：
- 创建 `maybe_development` 数据库
- 创建 `maybe_test` 数据库
- 运行所有迁移
- 加载初始数据（OAuth 应用）

### 5. 启动应用

```bash
bin/dev
```

这将启动：
- Rails 服务器 (http://localhost:3000)
- Tailwind CSS 监视器
- Sidekiq 后台任务处理

### 6. 访问应用

打开浏览器访问 `http://localhost:3000`

---

## 测试账号

### 已创建的测试账号

| 属性 | 值 |
|------|-----|
| **邮箱** | `test@example.com` |
| **密码** | `TestPass123!` |
| **名字** | Test |
| **姓氏** | User |
| **创建日期** | 2026-03-15 08:33:58 |
| **试用期限** | 14 天 |

### 注册新账号

1. 访问 http://localhost:3000/registration/new
2. 输入邮箱和密码（密码需满足：8+ 字符、大小写字母、数字、特殊符号）
3. 完成入职流程（Setup → Preferences → Goals → Start）
4. 自动进入 14 天免费试用

---

## 环境变量配置

### 数据库配置

在执行 Rails 命令前设置环境变量：

```bash
export DB_HOST=127.0.0.1
export DB_PORT=5432
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=postgres
export POSTGRES_DB=maybe_development
export REDIS_URL=redis://127.0.0.1:6379/1
```

或创建 `.env.local` 文件：

```env
DB_HOST=127.0.0.1
DB_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=maybe_development
REDIS_URL=redis://127.0.0.1:6379/1
```

---

## 常用开发命令

### Rails 命令

```bash
# 运行所有测试
bin/rails test

# 运行特定测试文件
bin/rails test test/models/account_test.rb

# 运行系统测试
bin/rails test:system

# 打开 Rails 控制台
bin/rails console

# 数据库迁移
bin/rails db:migrate
bin/rails db:rollback
bin/rails db:prepare

# 加载 demo 数据
rake demo_data:default
```

### Linting 和格式化

```bash
# Ruby linting
bin/rubocop -f github -a

# ERB linting
bundle exec erb_lint ./app/**/*.erb -a

# JavaScript/TypeScript linting
npm run lint
npm run lint:fix

# 安全分析
bin/brakeman --no-pager
```

### 开发工具

```bash
# 查看组件库
# 访问 http://localhost:3000/lookbook

# 查看邮件预览
# 访问 http://localhost:3000/letter_opener
```

---

## 故障排除

### 问题：i18n 翻译缺失错误

**症状**：注册页面显示 "Translation missing: en.layouts.shared.htmldoc.existing_account"

**解决**：
1. 确保 `config/locales/views/layout/en.yml` 包含必要的翻译键
2. 重启 Rails 服务器以清除缓存

```bash
pkill -f puma
sleep 5
bin/dev
```

### 问题：数据库连接失败

**症状**：`PG::ConnectionBad` 错误

**解决**：
1. 检查 PostgreSQL 容器是否运行：`docker ps | grep postgres`
2. 检查环境变量是否正确设置
3. 验证数据库是否已创建：`bin/rails dbconsole` (需要 psql)

### 问题：Redis 连接失败

**症状**：Sidekiq 启动失败

**解决**：
1. 检查 Redis 容器是否运行：`docker ps | grep redis`
2. 验证 `REDIS_URL` 环境变量是否正确

---

## Docker 容器管理

### 查看运行的容器

```bash
docker ps
```

### 停止所有容器

```bash
docker stop postgres redis
```

### 删除容器

```bash
docker rm postgres redis
```

### 查看容器日志

```bash
docker logs postgres
docker logs redis
```

---

## 数据库操作

### 查询用户信息

```bash
bin/rails runner "puts User.all.map { |u| \"#{u.email} - #{u.first_name} #{u.last_name}\" }"
```

### 重置数据库

```bash
bin/rails db:drop db:create db:migrate
```

### 导出/导入数据库

```bash
# 导出（需要 psql）
pg_dump -h 127.0.0.1 -U postgres maybe_development > backup.sql

# 导入
psql -h 127.0.0.1 -U postgres maybe_development < backup.sql
```

---

## 相关文档

- [CLAUDE.md](./CLAUDE.md) - 项目开发约定和规范
- [README.md](./README.md) - 项目概述和自托管指南
- [docs/hosting/docker.md](./docs/hosting/docker.md) - Docker 部署指南

---

## 更新日期

- **创建日期**：2026-03-15
- **最后更新**：2026-03-15

## 联系和贡献

本指南专为本地开发设置。如有问题或建议，请提交 Pull Request。

