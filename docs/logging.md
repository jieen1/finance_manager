# 日志配置说明

## 概述

本应用已配置为在生产环境中将日志输出到文件，并支持日志切分功能。日志文件存储在 `/rails/log` 目录中。

## 日志配置

### 环境变量

可以通过以下环境变量控制日志行为：

- `RAILS_LOG_LEVEL`: 日志级别 (默认: info)
- `RAILS_LOG_ROTATE_COUNT`: 保留的日志文件数量 (默认: 5)
- `RAILS_LOG_ROTATE_SIZE`: 单个日志文件最大大小，单位MB (默认: 100)

### 日志文件

- 主日志文件: `/rails/log/production.log`
- 切分后的日志文件: `/rails/log/production.log.1`, `/rails/log/production.log.2`, 等等

## Docker 部署

### 日志目录挂载

在 `compose.yml` 中，日志目录已配置为 Docker 卷：

```yaml
volumes:
  - app-logs:/rails/log
```

### 查看日志

#### 方法1: 使用日志管理脚本

```bash
# 进入容器
docker exec -it <container_name> bash

# 使用日志管理脚本
./bin/log-manager tail          # 实时查看日志
./bin/log-manager tail-error    # 只查看错误日志
./bin/log-manager view          # 查看最近100行日志
./bin/log-manager size          # 显示日志文件大小
./bin/log-manager clean         # 清理旧日志
```

#### 方法2: 直接查看日志文件

```bash
# 进入容器
docker exec -it <container_name> bash

# 查看日志
tail -f /rails/log/production.log
tail -n 100 /rails/log/production.log
```

#### 方法3: 从宿主机查看

如果日志目录已挂载到宿主机：

```bash
# 查看日志文件
tail -f /path/to/mounted/logs/production.log
```

## 日志切分

当日志文件达到指定大小时，会自动进行切分：

1. 当前日志文件重命名为 `production.log.1`
2. 创建新的 `production.log` 文件
3. 保留指定数量的历史日志文件
4. 超出数量的旧日志文件会被自动删除

## 日志级别

支持的日志级别：

- `debug`: 详细的调试信息
- `info`: 一般信息 (默认)
- `warn`: 警告信息
- `error`: 错误信息
- `fatal`: 致命错误

## 日志格式

日志格式包含以下信息：

- 时间戳
- 日志级别
- 请求ID (如果可用)
- 消息内容

示例：
```
2024-01-15T10:30:45.123Z [INFO] [request_id=abc123] Started GET "/accounts" for 127.0.0.1
```

## 监控和告警

建议配置日志监控：

1. 监控错误日志数量
2. 设置磁盘空间告警
3. 配置日志聚合服务 (如 Logtail)

## 故障排除

### 日志文件权限问题

如果遇到权限问题，确保容器内的用户有写入权限：

```bash
# 检查权限
ls -la /rails/log/

# 修复权限 (如果需要)
chown -R rails:rails /rails/log/
```

### 磁盘空间不足

定期清理旧日志：

```bash
# 使用脚本清理
./bin/log-manager clean

# 或手动清理
find /rails/log -name "*.log.*" -mtime +7 -delete
```

### 日志不输出

检查以下配置：

1. 确认 `RAILS_ENV=production`
2. 检查日志目录权限
3. 查看应用启动日志
4. 确认日志级别设置
