# OpenWrt 补丁管理工具链文档索引 v6.0.0

## 📚 概述

本目录包含了 OpenWrt 内核 CVE 补丁制作的完整文档体系。所有文档均围绕核心工具 `quilt_patch_manager_final.sh` v6.0.0 版本构建，该版本采用**工作流驱动**的设计理念，旨在实现最大程度的自动化。

## 🚀 v6.0.0 版本核心变化

- **架构演进**: 从"工具箱模式"彻底转变为"自动化工作流模式"。
- **核心命令**: 引入 `auto-patch` 作为一键式补丁制作命令，取代了过去繁琐的多步手动操作。
- **代码重构**: 代码行数从 3500+ 精简至 600+，极大提升了可读性和可维护性。
- **自动元数据**: `refresh-with-header` 命令确保了所有补丁在生成时自动注入完整的元数据。
- **文档重组**: 所有文档已按类别归档到不同的子目录中。

## 🔧 核心工具

### `quilt_patch_manager_final.sh` - v6.0.0

这是当前**唯一推荐**使用的核心工具，它集成了补丁制作所需的所有功能。

- **支持系统**: macOS, Ubuntu 20.04+, Linux
- **核心功能**:
  - `auto-patch`: 一键式自动化 CVE 补丁制作工作流。
  - `test-patch`: 智能补丁兼容性检测。
  - `refresh-with-header`: 自动注入元数据的补丁生成。
  - **环境管理**: `clean` 和 `reset-env`。
  - **Quilt 通用命令**: 支持直接调用 `status`, `series`, `diff` 等原生 quilt 命令。
  - **网络与缓存**: 内置网络连接优化和补丁缓存机制。

**基本用法**:
```bash
# 🥇 推荐：一键式制作补丁
./tools/quilt_patch_manager_final.sh auto-patch <commit_id> <patch_name>

# 🥈 备用：运行兼容性测试
./tools/quilt_patch_manager_final.sh test-patch <commit_id>

# 🥉 查看 quilt 状态
./tools/quilt_patch_manager_final.sh status
```

## 📖 完整文档体系

### 📂 01_tool_guides/ - 工具使用指南

- **📄 `QUILT_PATCH_MANAGER_GUIDE.md`**
  - **核心文档**。详细介绍了 `quilt_patch_manager_final.sh` v6.0.0 的所有功能、核心理念、使用方法和废弃命令列表。
- **📄 `VERSION_COMPARISON_v5.7_vs_v6.0.md`**
  - 详细对比了 v5.7.0 和 v6.0.0 两个版本在架构、功能、效率和代码质量上的巨大差异，解释了为何新版更优越。
- **📄 `PATCH_HELPER_GUIDE.md`**
  - (历史文档) 描述了旧版 `patch_helper` 工具的用法。

### 📂 02_workflow_guides/ - 工作流程指南

- **📄 `QUILT_CVE_PATCH_CREATION_GUIDE.md`**
  - 使用新版工具 `auto-patch` 制作 CVE 补丁的**标准实战教程**。
- **📄 `CVE_PATCH_WORKFLOW.md`**
  - 定义了基于新版工具的**标准化补丁制作工作流程**。
- **📄 `openwrt_kernel_patching_guide.md`**
  - OpenWrt 内核打补丁的基础概念和流程介绍。
- **📄 `SVN_CVE_PATCH_WORKFLOW.md`**
  - (历史文档) 描述了在 SVN 环境下手动制作补丁的旧流程。

### 📂 03_reference_manuals/ - 参考手册

- **📄 `OPENWRT_TARGET_LINUX_COMMANDS.md`**
  - OpenWrt 目标 `make` 命令的参考。
- **📄 `OPENWRT_TARGET_LINUX_QUICK_REFERENCE.md`**
  - 常用 Linux 命令速查。
- **📄 `QUILT_STATUS_EXPLANATION.md`**
  - (历史文档) 深入解释 quilt 的状态管理机制。
- **📄 `UBUNTU_COMPATIBILITY_GUIDE.md`**
  - 在 Ubuntu 环境下使用相关工具的兼容性指南。

### 📂 04_summaries/ - 总结与归档

- **📄 `SOLUTION_SUMMARY.md`**
  - 项目的解决方案总结。
- **📄 `openwrt_imx6ul_summary.md`**
  - i.MX6UL 平台在 OpenWrt 中的支持情况总结。

---

**总结**: 这套文档体系为 v6.0.0 的 `quilt_patch_manager_final.sh` 工具提供了全面的支持，从高层的工作流，到具体的使用指南，再到技术参考，一应俱全。强烈建议从 `01_tool_guides/QUILT_PATCH_MANAGER_GUIDE.md` 开始阅读。
