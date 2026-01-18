# 更新日志

本项目的所有重要更改都将记录在此文件中。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [1.0.0] - 2026-01-18

### 新增
- 🎉 初始版本发布
- ✨ 交互式配置向导 (`setup.sh`)
- 🚀 一键部署脚本 (`deploy.sh`)
- 📊 智能监控清理脚本 (`monitor.sh`)
- 📝 完整的文档和使用说明
- 🔧 可配置的所有参数
- 🐳 Docker代理自动配置
- 🔄 容器启动失败自动重试
- 📈 测速脚本集成
- ⏰ 定时任务自动配置

### 功能特性
- 自动化部署网心云Docker容器
- 定时监控磁盘使用率
- 达到阈值自动清理task目录
- 完善的错误处理和日志记录
- 路径安全验证
- 配置文件备份

### 安全性
- 防止误删根目录
- 敏感配置文件不提交到Git
- Docker代理配置备份

## [未发布]

### 计划中的功能
- [ ] 支持多容器管理
- [ ] Web界面监控
- [ ] 邮件/Webhook告警
- [ ] 日志轮转
- [ ] 配置文件加密
- [ ] 一键卸载脚本

---

[1.0.0]: https://github.com/yourusername/wxedge-manager/releases/tag/v1.0.0
