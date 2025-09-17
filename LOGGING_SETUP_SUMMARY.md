# 日志配置完成总结

## 已完成的配置

### 1. 生产环境日志配置 (`config/environments/production.rb`)

- ✅ 配置日志输出到文件 `/rails/log/production.log`
- ✅ 支持日志切分功能 (默认保留5个文件，每个最大100MB)
- ✅ 兼容 Logtail 日志聚合服务
- ✅ 支持环境变量配置日志参数

### 2. Docker 配置

#### Dockerfile 更新
- ✅ 创建日志目录 `/rails/log`
- ✅ 设置正确的文件权限
- ✅ 添加日志目录挂载点

#### Docker Compose 配置 (`compose.yml`)
- ✅ 添加日志卷挂载 `app-logs:/rails/log`
- ✅ 为 web 和 worker 服务都配置日志挂载
- ✅ 添加日志相关环境变量

### 3. 日志管理工具

#### 日志管理脚本 (`bin/log-manager`)
- ✅ 实时查看日志
- ✅ 过滤错误日志
- ✅ 查看历史日志
- ✅ 清理旧日志文件
- ✅ 显示日志文件大小

#### 启动脚本更新 (`bin/docker-entrypoint`)
- ✅ 确保日志目录在启动时被创建

### 4. 文档

- ✅ 创建详细的日志配置说明文档 (`docs/logging.md`)

## 环境变量配置

可以通过以下环境变量控制日志行为：

```bash
# 日志级别 (debug, info, warn, error, fatal)
RAILS_LOG_LEVEL=info

# 保留的日志文件数量
RAILS_LOG_ROTATE_COUNT=5

# 单个日志文件最大大小 (MB)
RAILS_LOG_ROTATE_SIZE=100
```

## 使用方法

### 1. 构建和运行

```bash
# 构建镜像
docker build -t finance-manager:0.0.1 .

# 运行服务
docker-compose up -d
```

### 2. 查看日志

```bash
# 进入容器查看日志
docker exec -it <container_name> ./bin/log-manager tail

# 或直接查看日志文件
docker exec -it <container_name> tail -f /rails/log/production.log
```

### 3. 从宿主机查看日志

如果日志目录已挂载到宿主机，可以直接查看：

```bash
# 查看挂载的日志目录
docker volume inspect finance_manager_app-logs

# 查看日志文件
tail -f /var/lib/docker/volumes/finance_manager_app-logs/_data/production.log
```

## 日志文件结构

```
/rails/log/
├── production.log          # 当前日志文件
├── production.log.1        # 第一个切分文件
├── production.log.2        # 第二个切分文件
└── ...                     # 更多历史文件
```

## 注意事项

1. **磁盘空间**: 定期清理旧日志文件，避免磁盘空间不足
2. **权限**: 确保容器内的 rails 用户有日志目录的写入权限
3. **监控**: 建议配置日志监控和告警
4. **备份**: 重要的日志文件建议定期备份

## 故障排除

如果遇到问题，请检查：

1. 日志目录权限
2. 磁盘空间
3. 环境变量配置
4. 容器启动日志

详细说明请参考 `docs/logging.md` 文件。
