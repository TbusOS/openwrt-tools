# OpenWrt 内核 CVE 补丁制作工具链 v8.8.0

一个专为 OpenWrt 开发者设计的**混合架构高性能补丁管理平台**，v8.7 在v8.6基础上新增**Bash自动补全功能**。

## 🚀 版本更新历史

### v8.8.0 - Quilt补丁编辑增强版本
- **新增fold/header命令**: 完整的补丁编辑和合并功能
- **CVE批量下载工具**: 自动获取Linux内核CVE补丁的专用脚本
- **自动补全增强**: 为新命令添加智能Tab补全支持
- **文档结构优化**: 标准化参考手册目录组织
- **用户体验提升**: 修复图形生成和界面显示问题

### v8.7.0 - Bash自动补全增强版本

- **🔤 Bash自动补全脚本**: 新增 `quilt_patch_manager_completion.bash` 智能命令补全功能
- **📋 智能命令补全**: 支持所有命令、选项和参数的Tab键自动补全
- **🎯 上下文感知补全**: 根据不同命令提供相应的文件路径、选项补全
- **�� 补丁文件智能识别**: 自动发现并补全工作目录和OpenWrt补丁目录中的.patch文件
- **🛠️ 用户体验优化**: 大幅提升命令行操作效率和准确性
- **👥 新手友好**: 降低学习门槛，通过Tab键快速了解可用命令

### 🔤 自动补全安装与使用

```bash
# 临时启用自动补全（当前终端会话）
source tools/quilt_patch_manager_completion.bash

# 永久启用自动补全（推荐）
echo "source $(pwd)/tools/quilt_patch_manager_completion.bash" >> ~/.bashrc
source ~/.bashrc

# 使用示例
./tools/quilt_patch_manager_final.sh <Tab><Tab>          # 显示所有可用命令
./tools/quilt_patch_manager_final.sh graph-pdf --<Tab>  # 显示graph-pdf选项
./tools/quilt_patch_manager_final.sh quick-apply <Tab>  # 补全.patch文件
```

## 🚀 v8.6.0 新增命令功能版本

- **🚀 quick-apply命令**: 新增一键补丁应用功能，自动复制补丁到目标目录并执行make prepare
- **🧹 snapshot-clean命令**: 新增快照数据清理命令，支持交互式和强制清理模式
- **📊 graph命令**: 新增补丁依赖关系图生成功能，输出DOT格式，可用Graphviz可视化
- **🎨 graph-pdf命令**: 新增PDF依赖图生成功能，支持彩色和全量显示选项
- **📚 命令文档完善**: 为新增命令提供完整的使用说明和示例
- **🔢 版本号更新**: 将脚本版本号更新到 v8.6.0
- **📝 技术手册增强**: 在中英文技术手册中补充了缺失的命令文档
- **🛠️ 工作流优化**: 完善了补丁快速应用的完整流程说明

## 🚀 v8.5.0 版本同步更新

- **🔢 版本号同步**: 将脚本版本号统一更新到 v8.5.0，确保版本一致性
- **📝 文档完善**: 在快速开始指南中新增"情况3：补丁无冲突，直接应用补丁"的详细使用场景
- **🛠️ 工作流优化**: 完善了无冲突补丁的快速应用流程说明
- **📚 技术手册更新**: 补充缺失的 `quick-apply`、`snapshot-clean`、`export-from-file` 等命令文档
- **🔧 功能保持**: 保持所有v8.4功能特性不变，纯版本号同步更新

## 🚀 v8.4.0 文件列表导出增强版本

- **📋 文件列表导出功能**: 新增 `export-from-file` 命令，支持基于指定文件列表导出文件
- **🎯 全局配置集成**: 自动读取全局配置文件中的 `default_workspace_dir` 作为根目录
- **📁 目录结构保持**: 完整保持原始相对路径目录结构，确保文件组织不变
- **📊 详细导出报告**: 生成完整的索引文件和成功文件列表，支持失败原因追踪
- **🔄 会话管理**: 每次导出创建独立的时间戳会话目录，并提供最新导出的软链接
- **💬 注释支持**: 文件列表支持注释行和空行，提高可读性和维护性
- **⚡ 错误处理**: 优雅处理不存在的文件，提供详细的失败原因和建议
- **🔗 向下兼容**: 保持所有v8.3功能，完全向下兼容

## 🚀 v8.3.0 网址链接支持版本

- **🌐 网址链接支持**: 新增对HTTPS/HTTP网址的完整支持，可直接使用网址作为补丁输入
- **📥 智能下载功能**: 自动下载网址补丁到本地缓存，支持断点续传和缓存复用
- **🎯 统一输入接口**: fetch、save、test-patch等命令统一支持commit-id、本地文件、网址三种输入方式
- **🔗 URL哈希缓存**: 使用URL哈希值生成缓存文件名，避免特殊字符问题
- **📦 变更文件导出**: 继承export-changed-files功能，可导出所有变更文件并保持原目录结构
- **🔧 智能配置集成**: 继承智能读取kernel_snapshot_tool的全局配置文件功能
- **🔄 向下兼容**: 保持所有v8.0功能，完全向下兼容

## 🚀 v8.0.0 Git风格快照系统重大版本

- **🔄 Git风格全局快照系统**: 新增 `snapshot-create` 和 `snapshot-diff` 命令，实现类Git的文件变更跟踪
- **🔀 混合输入架构支持**: 统一支持 commit ID 和本地补丁文件两种输入模式
- **⚡ 高性能C助手工具**: 集成C语言编写的 `snapshot_helper`，支持大型代码库的快速处理
- **🚀 内核快照工具 v1.1.0**: 全新发布独立的高性能内核快照系统，87,000个文件仅需2秒处理
- **🍎 macOS 原生兼容性**: 完整支持 macOS 平台，包括 Apple Silicon 和 Intel Mac
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
│   ├── quilt_patch_manager_final.sh         # v8.4.0 混合架构主工具 (新增export-from-file功能)
│   ├── kernel_snapshot_tool/                # 🚀 内核快照工具 v1.1.0 (符号链接支持升级)
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

### 🥇 独立内核快照工具 v1.1.0 (推荐使用) 🔗新增符号链接支持 + 🍎 macOS 原生支持
```bash
# Git风格工作流 - 使用全局配置文件 (推荐)
cd tools/kernel_snapshot_tool
./kernel_snapshot create                    # 创建基线快照 (支持符号链接)
./kernel_snapshot status                    # 检查变更状态 (包括符号链接变更)

# 手动指定目录
./kernel_snapshot create /path/to/kernel linux-6.6
./kernel_snapshot status

# 清理快照数据
./kernel_snapshot clean

# 🍎 macOS 专属优化:
# ✨ 原生 Apple Silicon/Intel Mac 支持
# ⚡ 自适应 CPU 核心检测 (固定4核，可通过-t参数覆盖)
# 🔧 优化的内存检测机制，避免系统API冲突
# 📁 macOS 路径兼容性 (支持 _NSGetExecutablePath)

# 新功能特性:
# ✨ 完整符号链接支持 - 像Git一样智能处理符号链接
# 🔍 智能链接检测 - 精确识别并递归处理符号链接指向的目录
# ⚡ 性能优化 - 符号链接使用轻量级哈希，避免SHA256计算开销
```

### 🥈 Git风格快照系统 (v8.0 集成功能)
```bash
# 通过主工具使用快照功能
./tools/quilt_patch_manager_final.sh snapshot-create [dir]

# 检查所有变更 (类Git)
./tools/quilt_patch_manager_final.sh snapshot-diff [dir]

# 将变更列表输出到文件
./tools/quilt_patch_manager_final.sh snapshot-diff > changes.txt

# 🆕 v8.2.0 导出变更文件 (保持目录结构)
./tools/quilt_patch_manager_final.sh export-changed-files
```

#### 📦 v8.2.0 新功能：变更文件导出

**export-changed-files** 功能可将所有变更文件按原目录结构导出，便于：

- **📋 代码审查**: 整理所有变更文件，方便团队审查
- **💾 补丁备份**: 防止代码丢失，完整保存修改内容  
- **👥 团队协作**: 分享具体修改内容，保持目录结构
- **🔍 差异分析**: 按目录结构查看变更，便于理解修改范围

**导出结果示例:**
```
📁 output/changed_files/
├── linux-4.1.15/              # 内核目录 (动态获取)
│   ├── drivers/net/cve_fix.c   # 新增文件
│   ├── kernel/Kconfig          # 修改文件
│   └── fs/security/patch.h     # 新增文件
└── EXPORT_INDEX.txt            # 导出索引
```

### 🥉 混合输入智能补丁制作 (v8.3 增强)
```bash
# 使用 Commit ID (传统方式)
./tools/quilt_patch_manager_final.sh auto-patch <commit_id> <patch_name>

# 使用本地补丁文件 (v8.0 新特性)
./tools/quilt_patch_manager_final.sh auto-patch /path/to/local.patch <patch_name>

# 🆕 v8.3.0 使用网址链接 (最新特性)
./tools/quilt_patch_manager_final.sh auto-patch https://example.com/cve-fix.patch <patch_name>
```

#### 🌐 v8.3.0 新功能：网址链接支持

**网址支持的命令示例:**
```bash
# 保存网址补丁到输出目录
./tools/quilt_patch_manager_final.sh save https://github.com/user/repo/commit/abc123.patch cve-2024-fix

# 测试网址补丁兼容性
./tools/quilt_patch_manager_final.sh test-patch https://example.com/security-fix.patch

# 获取网址补丁到缓存
./tools/quilt_patch_manager_final.sh fetch https://patchwork.kernel.org/patch/123456.patch
```

**适用场景:**
- **🌍 在线资源**: 直接从GitHub、CVE数据库、邮件列表下载补丁
- **👥 团队协作**: 通过URL快速分享和应用补丁文件  
- **🔄 自动化**: 脚本化处理在线补丁资源，支持CI/CD集成
- **💾 缓存优化**: 自动缓存网址补丁，避免重复下载

#### 📋 v8.4.0 新功能：基于文件列表的导出功能

**文件列表导出命令:**
```bash
# 基于指定文件列表导出文件
./tools/quilt_patch_manager_final.sh export-from-file /path/to/file_list.txt

# 示例：创建文件列表
cat > my_files.txt << EOF
# 内核核心文件
Makefile
kernel/sched/core.c
include/linux/sched.h
drivers/net/ethernet/intel/e1000/e1000_main.c

# 注释行和空行会被自动忽略
fs/ext4/file.c
mm/memory.c
EOF

# 执行导出
./tools/quilt_patch_manager_final.sh export-from-file my_files.txt
```

**导出特性:**
- **🎯 全局配置**: 自动读取 `tools/kernel_snapshot_tool/.kernel_snapshot.conf` 中的 `default_workspace_dir`
- **📁 结构保持**: 完整保持原始相对路径目录结构
- **📊 详细报告**: 生成 `EXPORT_INDEX.txt` 和 `successful_files.txt` 索引文件
- **🔄 会话管理**: 按时间戳创建独立导出会话，提供 `latest` 软链接
- **💬 注释支持**: 文件列表支持 `#` 注释行和空行
- **⚡ 错误处理**: 优雅处理不存在的文件，提供详细失败原因

**适用场景:**
- **📦 代码打包**: 按需导出特定文件集合，用于代码审查或分发
- **🔍 差异分析**: 基于变更清单导出文件，便于版本比较
- **👥 团队协作**: 导出特定模块文件，支持分布式开发
- **🚀 CI/CD集成**: 自动化文件收集和打包流程

### 🏅 智能冲突分析 (v7.3 继承特性)
```bash
# 智能冲突分析器 - 支持三种输入方式 (v8.3.0)
./tools/quilt_patch_manager_final.sh test-patch <commit_id|file_path|url>
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
- ✅ **macOS** (所有版本，包括 Apple Silicon M1/M2/M3)
- ✅ **Ubuntu 20.04+**
- ✅ **其他 Linux 发行版**

### 依赖安装
```bash
# Ubuntu/Debian (v8.0 新增: 编译工具链)
sudo apt install -y curl quilt build-essential

# macOS (v8.0 新增: 编译工具链 + 原生兼容性)
brew install quilt curl
# 确保已安装 Xcode Command Line Tools
xcode-select --install

# CentOS/RHEL (v8.0 新增: 编译工具链)
sudo yum install -y curl quilt gcc make
```

### C助手工具编译 (v8.0 新特性 + 🍎 macOS 原生支持)
```bash
# 编译高性能助手工具 (legacy)
cd tools/snapshot_tool
make

# 编译内核快照工具 v1.1.0 (推荐 + macOS原生支持)
cd tools/kernel_snapshot_tool
make                                        # 自动检测平台并应用优化编译标志

# 验证编译成功
./kernel_snapshot --help 2>/dev/null && echo "✅ 内核快照工具编译成功"
cd ../snapshot_tool
./snapshot_helper --help 2>/dev/null && echo "✅ C助手工具编译成功"

# 🍎 macOS 编译验证
# 在 macOS 上编译会自动应用以下优化:
# - 移除 -march=native (避免兼容性问题)
# - 使用 macOS 特定的系统API
# - 优化内存和CPU检测机制
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

| 特性 | v7.0.0 (最终稳定版) | v8.0.0 (混合架构高性能版) | v8.1.0 (增强配置集成版) | v8.2.0 (变更文件导出版) | v8.3.0 (网址链接支持版) |
|------|-------------------|-------------------------|----------------------|----------------------|----------------------|
| **定位** | 企业级管理平台 | 混合架构高性能补丁管理平台 | 智能配置集成补丁管理平台 | 变更文件导出补丁管理平台 | 网址链接支持补丁管理平台 |
| **代码行数** | 927 行 | 1202 行 (+275 行) | 1320 行 (+118 行) | 1441 行 (+121 行) | 1547 行 (+106 行) |
| **核心特性** | 智能冲突分析器 v7.0 | Git风格快照系统 + 混合输入架构 | + 智能配置集成 + 增强错误处理 | + 变更文件导出 + 代码审查支持 | + 网址链接支持 + 统一输入接口 |
| **配置集成** | 无 | 基础支持 | 智能读取全局配置文件 | 智能读取全局配置文件 | 智能读取全局配置文件 |
| **错误处理** | 基础 | 改进的错误提示 | 详细诊断 + 解决方案建议 | 详细诊断 + 解决方案建议 | 详细诊断 + 解决方案建议 |
| **文件导出** | 无 | 无 | 无 | export-changed-files 功能 | export-changed-files 功能 |
| **网址支持** | 无 | 无 | 无 | 无 | HTTPS/HTTP 网址下载 + 缓存 |
| **输入支持** | 仅 Commit ID | Commit ID + 本地文件 (混合输入) | 混合输入 + 配置文件路径 | 混合输入 + 配置文件路径 | Commit ID + 本地文件 + 网址 (三合一) |
| **变更跟踪** | 无 | Git风格全局快照系统 | Git风格全局快照系统 | Git风格全局快照系统 | Git风格全局快照系统 |
| **性能优化** | Bash 优化 | C语言助手工具 + 并行处理 | C语言助手工具 + 并行处理 | C语言助手工具 + 并行处理 | C语言助手工具 + 并行处理 |
| **跨平台兼容** | 基础支持 | 增强的 macOS/Linux 兼容性 | 增强的 macOS/Linux 兼容性 | 增强的 macOS/Linux 兼容性 | 增强的 macOS/Linux 兼容性 |
| **进度反馈** | 基础 | 实时进度条 + 动态显示 | 实时进度条 + 动态显示 | 实时进度条 + 动态显示 | 实时进度条 + 动态显示 |
| **代码审查支持** | 无 | 无 | 无 | 变更文件导出 + 目录结构保持 | 变更文件导出 + 目录结构保持 |
| **适用场景** | 企业团队协作 | 大型项目 + 企业级开发团队 | 大型项目 + 企业级开发团队 | 代码审查 + 团队协作 + 企业级开发 | 在线协作 + 自动化 + 企业级开发 |

## 🌟 v8.3 新增优势

1. **🌐 网址链接支持**: 全面支持HTTPS/HTTP网址作为补丁输入，实现统一输入接口
2. **📥 智能下载缓存**: 自动下载网址补丁到本地，支持URL哈希缓存和重复利用
3. **🎯 三合一输入**: 统一支持Commit ID、本地文件、网址链接三种输入方式
4. **🌍 在线资源整合**: 直接从GitHub、CVE数据库、邮件列表等在线资源获取补丁
5. **🔄 自动化友好**: 支持CI/CD脚本化处理在线补丁资源，提升开发效率
6. **📦 变更文件导出**: 继承export-changed-files功能，支持代码审查和团队协作
7. **🔧 智能配置集成**: 继承v8.1.0所有配置优化和错误诊断功能
8. **🔄 完全兼容**: 保持所有v8.0功能，无破坏性变更

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
