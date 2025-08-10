# OpenWrt 内核补丁管理工具 v8.0.0

一个专为 OpenWrt 开发者设计的**混合架构高性能补丁管理平台**，v8.0 是**Git风格快照系统重大版本**，在智能冲突分析基础上新增**全局差异快照系统**和**混合输入架构支持**。

## 🚀 v8.0.0 Git风格快照系统重大版本

- **🔄 Git风格全局快照系统**: 新增 `snapshot-create` 和 `snapshot-diff` 命令，实现类Git的文件变更跟踪
- **🔀 混合输入架构支持**: 统一支持 commit ID 和本地补丁文件两种输入模式
- **⚡ 高性能C助手工具**: 集成C语言编写的 `snapshot_helper`，支持大型代码库的快速处理
- **🚀 内核快照工具 v1.0.0**: 全新发布独立的高性能内核快照系统，87,000个文件仅需2秒处理
- **📱 Git风格用户界面**: 支持create、status、clean等Git风格命令，配备全局配置文件支持
- **🎯 智能索引缓存**: 零文件丢失保证，采用单线程遍历+多线程处理的Git风格设计
- **📊 实时进度显示**: 快照创建过程中显示动态进度条，支持并行处理
- **🛠️ 增强的跨平台兼容性**: 改进的脚本目录检测和 macOS/Linux 兼容性
- **🧠 智能冲突分析器 v7.3**: 继承 AWK 脚本精确分析，生成专业级冲突报告
- **🔧 架构健壮性**: 代码增长到 1202 行，达到混合架构的高性能稳定版
- **🔄 向下兼容**: 保持所有 v7.0 智能分析和 Quilt 管理特性

## 📁 项目结构

```
openwrt-tools/
├── tools/                                    # 🔧 核心工具
│   ├── quilt_patch_manager_final.sh         # v8.0.0 混合架构主工具
│   ├── kernel_snapshot_tool/                # 🚀 内核快照工具 v1.0.0 (重大升级)
│   │   ├── kernel_snapshot                  # 主要可执行文件
│   │   ├── main.c, snapshot_core.c         # 核心源码
│   │   ├── index_cache_simple.c            # 智能索引缓存
│   │   ├── progress_bar.c                   # 进度条显示
│   │   ├── 使用指南.md                      # 详细中文使用指南
│   │   ├── 快速开始示例.md                   # 实际场景示例
│   │   ├── 配置文件示例.conf               # 配置文件模板
│   │   └── CHANGELOG.md                     # 详细更新日志
│   └── snapshot_tool/                       # 📸 Git风格快照系统
│       ├── snapshot_helper.c                # C语言高性能助手
│       ├── Makefile                         # 编译配置
│       └── snapshot_helper                  # 编译后的二进制文件
├── doc/                                      # 📚 分类文档
│   ├── 01_tool_guides/                      # 工具使用指南
│   ├── 02_workflow_guides/                  # 工作流程指南
│   ├── 03_reference_manuals/                # 参考手册
│   ├── 04_summaries/                        # 总结归档
│   └── DOCUMENTATION_INDEX.md               # 文档索引
├── suggest/                                  # 💡 改进建议文档
└── README.md                                # 本文件
```

## 🎯 核心功能

### 🥇 独立内核快照工具 v1.0.0 (推荐使用)
```bash
# Git风格工作流 - 使用全局配置文件 (推荐)
cd tools/kernel_snapshot_tool
./kernel_snapshot create                    # 创建基线快照
./kernel_snapshot status                    # 检查变更状态

# 手动指定目录
./kernel_snapshot create /path/to/kernel linux-6.6
./kernel_snapshot status

# 清理快照数据
./kernel_snapshot clean
```

### 🥈 Git风格快照系统 (v8.0 集成功能)
```bash
# 通过主工具使用快照功能
./tools/quilt_patch_manager_final.sh snapshot-create [dir]

# 检查所有变更 (类Git)
./tools/quilt_patch_manager_final.sh snapshot-diff [dir]

# 将变更列表输出到文件
./tools/quilt_patch_manager_final.sh snapshot-diff > changes.txt
```

### 🥉 混合输入智能补丁制作 (v8.0 增强)
```bash
# 使用 Commit ID (传统方式)
./tools/quilt_patch_manager_final.sh auto-patch <commit_id> <patch_name>

# 使用本地补丁文件 (v8.0 新特性)
./tools/quilt_patch_manager_final.sh auto-patch /path/to/local.patch <patch_name>
```

### 🏅 智能冲突分析 (v7.3 继承特性)
```bash
# 智能冲突分析器 - 支持混合输入
./tools/quilt_patch_manager_final.sh test-patch <commit_id|file_path>
```

### 🎯 完整状态管理系统 (继承 v7.0)
```bash
# 总体状态概览
./tools/quilt_patch_manager_final.sh status

# 详细补丁列表
./tools/quilt_patch_manager_final.sh series

# 当前活跃补丁
./tools/quilt_patch_manager_final.sh top

# 应用/撤销补丁
./tools/quilt_patch_manager_final.sh push
./tools/quilt_patch_manager_final.sh pop
```

### 🔧 环境管理 (增强版)
```bash
# 清理缓存和输出目录
./tools/quilt_patch_manager_final.sh clean

# (危险) 重置内核 quilt 状态
./tools/quilt_patch_manager_final.sh reset-env
```

## 🔧 安装与依赖

### 系统要求
- ✅ **macOS** (所有版本)
- ✅ **Ubuntu 20.04+**
- ✅ **其他 Linux 发行版**

### 依赖安装
```bash
# Ubuntu/Debian (v8.0 新增: 编译工具链)
sudo apt install -y curl quilt build-essential

# macOS (v8.0 新增: 编译工具链)
brew install quilt curl
# 确保已安装 Xcode Command Line Tools
xcode-select --install

# CentOS/RHEL (v8.0 新增: 编译工具链)
sudo yum install -y curl quilt gcc make
```

### C助手工具编译 (v8.0 新特性)
```bash
# 编译高性能助手工具 (legacy)
cd tools/snapshot_tool
make

# 编译内核快照工具 v1.0.0 (推荐)
cd tools/kernel_snapshot_tool
make

# 验证编译成功
./kernel_snapshot --help 2>/dev/null && echo "✅ 内核快照工具编译成功"
cd ../snapshot_tool
./snapshot_helper --help 2>/dev/null && echo "✅ C助手工具编译成功"
```

## 📖 文档导航

| 文档类别 | 推荐阅读顺序 | 文档路径 |
|---------|-------------|----------|
| **🔰 新手入门** | 1️⃣ | [`doc/01_tool_guides/QUILT_PATCH_MANAGER_GUIDE.md`](doc/01_tool_guides/QUILT_PATCH_MANAGER_GUIDE.md) |
| **🚀 内核快照工具** | 1️⃣⭐ | [`tools/kernel_snapshot_tool/使用指南.md`](tools/kernel_snapshot_tool/使用指南.md) |
| **⚡ 快速上手** | 2️⃣ | [`doc/02_workflow_guides/QUILT_CVE_PATCH_CREATION_GUIDE.md`](doc/02_workflow_guides/QUILT_CVE_PATCH_CREATION_GUIDE.md) |
| **🎯 快照工具示例** | 2️⃣⭐ | [`tools/kernel_snapshot_tool/快速开始示例.md`](tools/kernel_snapshot_tool/快速开始示例.md) |
| **📋 标准流程** | 3️⃣ | [`doc/02_workflow_guides/CVE_PATCH_WORKFLOW.md`](doc/02_workflow_guides/CVE_PATCH_WORKFLOW.md) |
| **🔧 配置文件模板** | 🛠️ | [`tools/kernel_snapshot_tool/配置文件示例.conf`](tools/kernel_snapshot_tool/配置文件示例.conf) |
| **🔍 最新版本对比** | 4️⃣ | [`doc/01_tool_guides/VERSION_COMPARISON_v7.0_vs_v8.0.md`](doc/01_tool_guides/VERSION_COMPARISON_v7.0_vs_v8.0.md) |
| **🔍 历史版本对比** | 5️⃣ | [`doc/01_tool_guides/VERSION_COMPARISON_v6.0_vs_v7.0.md`](doc/01_tool_guides/VERSION_COMPARISON_v6.0_vs_v7.0.md) |
| **📚 完整索引** | 🔗 | [`doc/DOCUMENTATION_INDEX.md`](doc/DOCUMENTATION_INDEX.md) |

## 💡 使用场景

### 场景 1: CVE 补丁制作 (最常用 - v8.0 混合输入)
```bash
# 使用 Commit ID (传统方式)
./tools/quilt_patch_manager_final.sh auto-patch 1234567890abcdef CVE-2024-12345

# 使用本地补丁文件 (v8.0 新特性)
./tools/quilt_patch_manager_final.sh auto-patch /tmp/cve.patch CVE-2024-12345
```

### 场景 2: 大型项目变更跟踪 (v8.0 新场景 - 推荐使用独立工具)
```bash
# 方式1: 使用独立内核快照工具 (推荐)
cd tools/kernel_snapshot_tool
./kernel_snapshot create                    # 创建基准快照
# ... 进行各种代码修改 ...
./kernel_snapshot status > all_changes.txt # 输出所有变更

# 方式2: 通过主工具使用
./tools/quilt_patch_manager_final.sh snapshot-create

# 进行各种修改后检查变更
./tools/quilt_patch_manager_final.sh snapshot-diff > all_changes.txt
```

### 场景 3: 企业 SVN 环境
- ✅ 无需 Git 历史依赖
- ✅ 支持多源补丁 (Linux 主线、Android、GitHub、本地文件)
- ✅ 智能冲突预警
- ✅ Git风格变更跟踪 (v8.0 新增)

### 场景 4: 高版本向低版本移植
- ✅ 智能兼容性检测
- ✅ 符号变更预警
- ✅ 模糊匹配支持
- ✅ 高性能差异检测 (v8.0 新增)

## 🆚 版本对比

| 特性 | v7.0.0 (最终稳定版) | v8.0.0 (混合架构高性能版) |
|------|-------------------|-------------------------|
| **定位** | 企业级管理平台 | 混合架构高性能补丁管理平台 |
| **代码行数** | 927 行 | 1202 行 (+275 行) |
| **核心特性** | 智能冲突分析器 v7.0 | Git风格快照系统 + 混合输入架构 |
| **输入支持** | 仅 Commit ID | Commit ID + 本地文件 (混合输入) |
| **变更跟踪** | 无 | Git风格全局快照系统 |
| **性能优化** | Bash 优化 | C语言助手工具 + 并行处理 |
| **跨平台兼容** | 基础支持 | 增强的 macOS/Linux 兼容性 |
| **进度反馈** | 基础 | 实时进度条 + 动态显示 |
| **适用场景** | 企业团队协作 | 大型项目 + 企业级开发团队 |

## 🌟 v8.0 核心优势

1. **🔄 Git风格**: Git风格全局快照系统，类Git的文件变更跟踪能力
2. **🔀 混合输入**: 统一支持 commit ID 和本地补丁文件，大幅提升工具灵活性
3. **⚡ 高性能**: C语言助手工具 + 并行处理，支持大型代码库的快速处理
4. **🧠 智能化**: 继承智能冲突分析器 v7.3，精确定位每个 hunk 冲突
5. **📊 实时反馈**: 动态进度条 + 实时状态显示，改善用户体验
6. **🛠️ 跨平台**: 增强的 macOS/Linux 兼容性，更健壮的平台支持
7. **🏢 企业级**: 混合架构设计，适合大型项目和企业级开发团队

## 🤝 贡献与支持

- **📋 问题反馈**: [GitHub Issues](https://github.com/TbusOS/openwrt-tools/issues)
- **💡 功能建议**: 查看 [`suggest/`](suggest/) 目录
- **📖 文档改进**: 欢迎提交 PR 改进文档

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件。

---

**🎉 立即开始**: 阅读 [`doc/01_tool_guides/QUILT_PATCH_MANAGER_GUIDE.md`](doc/01_tool_guides/QUILT_PATCH_MANAGER_GUIDE.md) 开始您的 CVE 补丁制作之旅！