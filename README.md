# 🚀 网心云 Docker 极致一键部署工具 (v5.2.0)

[![Version](https://img.shields.io/badge/version-5.2.0-blue.svg)](https://github.com/SolitaryJune/wxedge-manager/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-linux-lightgrey.svg)](https://www.kernel.org/)

这是一个专为网心云 (wxedge) 设计的极致自动化部署工具。它实现了真正的 **“一键到底”** 体验，整合了 **Docker 自动安装**、**核心路径配置**、**镜像静默部署**、**必装测速脚本** 以及 **磁盘自动监控清理** 功能。

> **核心理念**：只在关键路径上询问用户，确认后立即自动完成所有部署工作，无需二次操作。

---

## ✨ 核心特性

- **🔄 一键到底**：配置完成后自动触发部署流程，无需手动运行额外脚本。
- **🔑 权限前置**：启动即请求 root 权限，全程只需输入一次密码。
- **🛠️ 自动环境搭建**：自动检测并安装 Docker，自动同步系统代理。
- **🎯 核心路径确认**：仅保留“磁盘路径”和“数据目录”的询问，确保安装位置准确。
- **⚡ 全自动化静默**：测速、监控、定时任务、Docker 参数等所有其他项全部自动配置。
- **🛡️ 磁盘智能监控**：每天凌晨 2 点自动检查磁盘，超过 90% 自动清理 `task` 缓存。
- **📦 真正的单文件**：一个 `install.sh` 搞定所有事情。

---

## 🚀 一键部署命令

您可以根据网络环境选择以下任一命令：

### 1. 加速站点链接（推荐大陆用户）
```bash
wget -O install.sh https://git.gushao.club/https://github.com/SolitaryJune/wxedge-manager/raw/main/install.sh && chmod +x install.sh && ./install.sh
```

### 2. 标准 GitHub 链接
```bash
wget -O install.sh https://raw.githubusercontent.com/SolitaryJune/wxedge-manager/main/install.sh && chmod +x install.sh && ./install.sh
```

---

## 📖 运行说明

1. **执行权限**：上述命令会自动下载脚本并赋予执行权限。
2. **核心确认**：
   - **磁盘路径**：脚本会显示磁盘列表并推荐最大容量磁盘，按回车确认或手动输入。
   - **数据目录**：自动根据磁盘路径生成，按回车确认或手动输入。
3. **自动衔接**：在您输入 `y` 确认配置后，脚本将**立即自动开始** Docker 安装、镜像拉取、测速运行、容器启动及定时任务挂载。
4. **日志查看**：部署完成后，日志文件 `wxedge-monitor.log` 将存放在您的数据目录下。

---

## 📋 监控逻辑

- **执行时间**：每天凌晨 02:00。
- **触发条件**：磁盘使用率 > 90%。
- **清理动作**：停止容器 -> 清理 `task` 文件夹 -> 重启容器。

---

## 🔗 项目地址
GitHub: [https://github.com/SolitaryJune/wxedge-manager](https://github.com/SolitaryJune/wxedge-manager)

---
*本项目由 SolitaryJune 开发并维护。*
