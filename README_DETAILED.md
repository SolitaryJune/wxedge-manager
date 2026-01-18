# 网心云Docker管理工具

一套完整的网心云Docker部署、监控和自动清理解决方案。

## 功能特性

- ✅ **自动化部署**：一键配置代理、拉取镜像、创建容器
- ✅ **智能监控**：定时检测磁盘使用率，自动触发清理
- ✅ **安全清理**：停止容器 → 清理task目录 → 重启容器
- ✅ **错误处理**：完善的错误检查、重试机制和日志记录
- ✅ **测速集成**：可选的测速脚本自动部署
- ✅ **配置化管理**：所有参数可通过配置文件调整

## 文件结构

```
wxedge-manager/
├── setup.sh               # 配置向导（首次运行）
├── config.sh.example      # 配置文件示例
├── config.sh              # 配置文件（由setup.sh生成）
├── deploy.sh              # 部署脚本
├── monitor.sh             # 监控清理脚本（定时执行）
└── README.md              # 使用说明（本文件）
```

## 快速开始

### 第一步：运行配置向导

使用交互式配置向导（推荐）：

```bash
./setup.sh
```

配置向导会引导您完成所有配置项的设置，包括：
- 路径配置（监控路径、数据目录、清理路径）
- Docker配置（镜像、代理、网络、重启策略）
- 监控配置（阈值、超时、重试）
- 测速脚本配置
- 定时任务配置

**或者手动配置：**

```bash
cp config.sh.example config.sh
vim config.sh  # 修改配置项
```

### 第二步：运行部署脚本

```bash
chmod +x deploy.sh
sudo ./deploy.sh
```

部署脚本会：
1. 检查环境（Docker、wget等）
2. 显示配置信息并要求确认
3. 配置Docker代理
4. 拉取网心云镜像
5. 创建并启动容器
6. 部署测速脚本（可选）
7. 设置定时任务

### 第三步：验证部署

```bash
# 查看容器状态
sudo docker ps | grep wxedge

# 查看容器日志
sudo docker logs -f wxedge

# 手动测试监控脚本
sudo ./monitor.sh

# 查看监控日志
tail -f /var/log/wxedge-monitor.log
```

## 配置说明

### 路径配置

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `MONITOR_PATH` | 监控的磁盘挂载点 | `/vol2` |
| `WXEDGE_DATA_DIR` | 网心云数据存储目录 | `/vol2/1000/WXY/.onething_data` |
| `CLEAN_PATH` | 需要清理的task目录 | `/vol2/1000/WXY/.onething_data/task` |
| `LOG_FILE` | 监控日志文件路径 | `/var/log/wxedge-monitor.log` |

### Docker配置

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `DOCKER_CONTAINER` | 容器名称 | `wxedge` |
| `DOCKER_IMAGE` | 镜像名称 | `onething1/wxedge:3.0.2` |
| `DOCKER_PROXY` | 代理地址 | `http://127.0.0.1:7890` |
| `DOCKER_VOLUME` | 挂载配置 | `${WXEDGE_DATA_DIR}:/onething` |
| `DOCKER_NETWORK` | 网络模式 | `host` |
| `DOCKER_RESTART` | 重启策略 | `unless-stopped` |

### 监控配置

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `THRESHOLD_PERCENT` | 磁盘使用率阈值（%） | `90` |
| `STOP_TIMEOUT` | 容器停止超时（秒） | `30` |
| `MAX_RETRY` | 容器启动最大重试次数 | `3` |
| `RETRY_INTERVAL` | 重试间隔（秒） | `5` |

### 定时任务配置

| 配置项 | 说明 | 默认值 |
|--------|------|--------|
| `CRON_SCHEDULE` | 监控执行时间（cron格式） | `0 2 * * *`（每天凌晨2点） |

## 使用指南

### 手动执行监控

```bash
# 正常模式（仅在超过阈值时清理）
sudo ./monitor.sh

# 强制模式（无论阈值如何都清理）
sudo ./monitor.sh force
```

### 查看日志

```bash
# 实时查看监控日志
tail -f /var/log/wxedge-monitor.log

# 查看容器日志
sudo docker logs -f wxedge

# 查看最近的监控记录
grep "监控脚本开始执行" /var/log/wxedge-monitor.log | tail -10
```

### 管理容器

```bash
# 查看容器状态
sudo docker ps -a | grep wxedge

# 停止容器
sudo docker stop wxedge

# 启动容器
sudo docker start wxedge

# 重启容器
sudo docker restart wxedge

# 查看容器详细信息
sudo docker inspect wxedge
```

### 管理定时任务

```bash
# 查看当前定时任务
sudo crontab -l

# 编辑定时任务
sudo crontab -e

# 删除定时任务（找到包含monitor.sh的行并删除）
sudo crontab -e
```

### 测速脚本

如果在 `config.sh` 中设置了 `RUN_SPEED_TEST_ON_DEPLOY="true"`，部署时会自动运行测速脚本。

手动运行测速：
```bash
./build_and_run_docker.sh --threads 8 --speed-limit 10
```

## 工作流程

### 监控清理流程

```
1. 定时任务触发（每天凌晨2点）
   ↓
2. 检查磁盘使用率
   ↓
3. 是否超过阈值？
   ├─ 否 → 记录日志，结束
   └─ 是 → 继续
       ↓
4. 停止网心云容器
   ↓
5. 清理task目录
   ↓
6. 启动网心云容器（带重试）
   ↓
7. 记录清理前后的空间变化
   ↓
8. 结束
```

### 安全机制

1. **路径验证**：防止误删根目录或系统目录
2. **容器状态检查**：确保容器正常停止和启动
3. **重试机制**：容器启动失败时自动重试
4. **错误日志**：所有错误都会记录到日志文件
5. **配置确认**：部署前要求用户确认配置

## 故障排查

### 容器无法启动

```bash
# 查看容器日志
sudo docker logs wxedge

# 检查数据目录权限
ls -la /vol2/1000/WXY/.onething_data

# 尝试手动启动
sudo docker start wxedge
```

### 清理未生效

```bash
# 检查清理路径是否正确
ls -la /vol2/1000/WXY/.onething_data/task

# 查看监控日志中的错误信息
grep ERROR /var/log/wxedge-monitor.log

# 手动强制清理
sudo ./monitor.sh force
```

### 定时任务未执行

```bash
# 检查crontab是否正确配置
sudo crontab -l | grep monitor.sh

# 检查cron服务是否运行
sudo systemctl status cron

# 查看系统日志
sudo grep CRON /var/log/syslog
```

### 镜像拉取失败

```bash
# 检查代理是否可用
curl -x http://127.0.0.1:7890 https://www.google.com

# 检查Docker代理配置
cat /etc/docker/daemon.json

# 手动测试拉取
sudo docker pull onething1/wxedge:3.0.2
```

## 注意事项

1. **路径确认**：部署前务必确认所有路径配置正确
2. **代理配置**：确保Docker代理地址可用
3. **权限要求**：脚本需要sudo权限
4. **备份数据**：首次部署前建议备份重要数据
5. **监控日志**：定期检查日志文件，防止磁盘占满
6. **镜像版本**：确认网心云镜像名称和版本号

## 高级配置

### 修改清理阈值

编辑 `config.sh`：
```bash
THRESHOLD_PERCENT=85  # 改为85%触发清理
```

### 修改定时任务时间

编辑 `config.sh`：
```bash
CRON_SCHEDULE="0 3 * * *"  # 改为每天凌晨3点
```

重新运行部署脚本或手动更新crontab。

### 添加多个监控路径

可以复制 `monitor.sh` 并修改配置，为不同路径创建独立的监控任务。

### 自定义Docker参数

编辑 `config.sh`：
```bash
DOCKER_EXTRA_ARGS="--memory=2g --cpus=2"  # 限制内存和CPU
```

## 卸载

```bash
# 停止并删除容器
sudo docker stop wxedge
sudo docker rm wxedge

# 删除镜像（可选）
sudo docker rmi onething1/wxedge:3.0.2

# 删除定时任务
sudo crontab -e  # 删除包含monitor.sh的行

# 删除脚本目录（可选）
rm -rf /path/to/wxedge-manager

# 恢复Docker配置（可选）
sudo cp /etc/docker/daemon.json.backup.* /etc/docker/daemon.json
sudo systemctl restart docker
```

## 更新日志

### v1.0
- 初始版本
- 支持网心云Docker部署
- 支持磁盘监控和自动清理
- 支持测速脚本集成
- 支持定时任务配置

## 许可证

MIT License

## 支持

如有问题，请检查日志文件或提交Issue。
