# 贡献指南

感谢您对网心云Docker管理工具的关注！我们欢迎任何形式的贡献。

## 如何贡献

### 报告问题

如果您发现了bug或有功能建议，请：

1. 检查 [Issues](../../issues) 确认问题是否已被报告
2. 如果没有，创建新的 Issue，并提供：
   - 清晰的标题和描述
   - 复现步骤（如果是bug）
   - 预期行为和实际行为
   - 系统环境信息（OS、Docker版本等）
   - 相关日志或截图

### 提交代码

1. Fork 本仓库
2. 创建您的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交您的更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

### 代码规范

- 使用清晰的变量和函数命名
- 添加必要的注释
- 保持代码风格一致
- 测试您的更改

### Pull Request 指南

- 确保代码通过基本测试
- 更新相关文档
- 一个 PR 只做一件事
- 提供清晰的 PR 描述

## 开发环境

### 要求

- Linux 系统（Ubuntu 22.04+ 推荐）
- Docker 20.10+
- Bash 4.0+

### 测试

在提交前，请确保：

1. 配置向导能正常运行
```bash
./setup.sh
```

2. 部署脚本能正常执行（在测试环境）
```bash
sudo ./deploy.sh
```

3. 监控脚本能正常工作
```bash
sudo ./monitor.sh
```

## 行为准则

- 尊重所有贡献者
- 使用友好和包容的语言
- 接受建设性的批评
- 关注对社区最有利的事情

## 问题？

如有任何问题，欢迎在 Issues 中提问。

感谢您的贡献！ 🎉
