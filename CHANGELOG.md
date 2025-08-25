# OpenWrt 内核补丁管理工具更新日志

本文档记录了OpenWrt内核补丁管理工具的所有重要变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，并遵循 [语义化版本](https://semver.org/lang/zh-CN/) 规范。

## [8.12.0] - 2025-01-13

### 🔍 冲突分析增强版 (Enhanced Conflict Analysis)

#### 功能增强 (Enhanced)
- 🧩 **冲突分析优化**: 增强了 `analyze_patch_conflicts_v7()` 函数的补丁解析能力
  - 新增对 `Index:` 格式补丁头部的支持，提高补丁文件识别准确性
  - 优化了文件路径提取逻辑，支持多种补丁格式的文件名解析
  - 改进了代码块定位算法，确保冲突分析的精确性
  - 修复了 `tail` 命令语法问题，提高了跨平台兼容性

#### 技术实现 (Technical)
- 🔧 **补丁格式支持**: 扩展对不同补丁格式的解析支持
  - Git格式: `diff --git a/file b/file`
  - Index格式: `Index: package/file`
  - 传统格式: `--- file.orig` 和 `+++ file`
- 📊 **代码行定位**: 改进了源码文件的行号定位逻辑
- ⚡ **性能优化**: 优化了大型补丁文件的处理性能

#### Bug修复 (Fixed)
- 🐛 修复 `tail -n "+$start_line"` 在某些系统上的兼容性问题
- 🔧 解决补丁文件路径识别在复杂格式下的失效问题
- 📝 改进错误提示信息的准确性和可读性

## [8.11.0] - 2025-01-13

### 🔗 补丁合并功能版 (Patch Merging Feature)

#### 新增功能 (Added)
- 🧩 **补丁合并命令**: 新增 `merge-patches` 命令，支持合并两个Git格式补丁
  - 命令语法: `merge-patches <patch1> <patch2>`
  - 智能合并Git补丁的元数据和diff内容
  - 自动生成带时间戳的输出文件名
  - 保留第一个补丁的完整头部信息作为基础
  - 添加第二个补丁的关键信息到合并说明中
  - 支持统计显示合并前后的文件数量

#### 功能特性 (Features)
- 📝 **元数据处理**: 保留第一个补丁的From、Date、Subject等信息
- 🔄 **diff合并**: 将两个补丁的diff部分完整合并
- 📊 **统计信息**: 显示合并前后的文件变更统计
- 🎯 **输出管理**: 自动输出到 `patch_manager_work/output/` 目录
- 📱 **双语支持**: 中英文帮助信息完整支持
- 🧹 **临时文件**: 自动清理合并过程中的临时文件

#### 技术实现 (Technical)
- 🔧 **函数实现**: `merge_git_patches()` 函数处理完整合并逻辑
- 📋 **命令调度**: 在主命令调度器中集成 `merge-patches` 命令
- 🗂️ **文件分离**: 使用awk智能分离补丁头部和diff部分
- ⚡ **错误处理**: 完善的输入验证和错误提示机制

## [8.10.0] - 2025-01-13

### 📦 版本同步更新 (Version Synchronization Update)

#### 新增功能 (Added)
- 🛠️ **通用补丁文件提取函数**: 新增 `extract_patch_files()` 函数，支持多种diff格式
  - 支持 Git 格式 (`--- a/path/to/file`)
  - 支持传统格式 (`--- path/to/file.orig`)
  - 支持上下文格式 (`--- linux-4.1.15.orig/path/to/file`)
  - 支持 Quilt 格式 (`--- old/path/to/file`)
  - 智能路径清理和前缀移除
  - 统一的文件提取接口

#### 改进功能 (Improved)
- 🔢 **版本号同步**: 将工具版本号统一更新到 v8.10.0
- 📚 **文档同步**: 所有相关文档版本号保持一致
- 🔄 **版本管理**: 确保工具与文档版本号完全同步
- 📋 **文件提取优化**: 使用新的通用函数替代原有的 awk 单行处理
- 🔍 **兼容性增强**: 提升对不同补丁格式的支持和解析能力

#### 技术细节 (Technical Details)
- **脚本更新**: 主脚本版本号更新为 v8.10.0，新增39行代码
- **函数重构**: 新增 `extract_patch_files()` 通用函数，支持多种diff格式解析
- **代码优化**: 冲突检查和文件提取功能使用统一的提取函数
- **文档更新**: 所有技术文档和说明文件版本号同步
- **维护优化**: 统一版本管理和代码结构提升维护效率

## [8.9.0] - 2025-01-13

### 🌐 国际化增强版本 (Internationalization Enhancement Version)

#### 新增功能 (Added)
- 🌍 **中英文双语帮助系统**: 新增完整的英文版本帮助文档
  - `help-cn`: 显示中文帮助信息（默认行为）
  - `help-en`: 显示英文帮助信息
  - 支持 `help`, `-h`, `--help` 等传统命令
- 📖 **完整英文文档**: 覆盖所有命令和功能的详细英文说明
  - 超过240行的完整英文help内容
  - 包含所有命令示例和使用场景
  - 与中文版本保持功能同步

#### 改进功能 (Improved)
- 🔢 **版本号更新**: 将脚本版本号更新到 v8.9.0
- 🔤 **自动补全增强**: 为新的 `help-cn` 和 `help-en` 命令添加Tab补全支持
- 🎯 **用户体验优化**: 在帮助信息中明确指出中英文help选项
- 🌐 **国际化友好**: 便于OpenWrt国际社区用户使用和贡献

#### 技术细节 (Technical Details)
- **双语架构**: 添加独立的 `print_help_en()` 函数处理英文帮助
- **命令扩展**: 主命令处理器新增 `help-cn` 和 `help-en` 命令支持
- **补全框架**: 自动补全脚本包含新的帮助命令
- **文档一致性**: 确保中英文版本功能描述完全对应

#### 使用示例 (Usage Examples)
```bash
# 显示中文帮助（默认）
./quilt_patch_manager_final.sh help
./quilt_patch_manager_final.sh help-cn

# 显示英文帮助
./quilt_patch_manager_final.sh help-en

# Tab补全支持
./quilt_patch_manager_final.sh help<Tab>  # 显示: help help-cn help-en
```

#### 适用场景 (Use Cases)
- **🌍 国际化支持**: 为OpenWrt国际社区提供英文文档支持
- **📚 文档标准化**: 提供标准的英文技术文档模板
- **👥 团队协作**: 支持多语言团队的协作开发
- **🚀 社区推广**: 便于在国际开源社区中推广和使用

## [8.8.0] - 2025-01-13

### 🔧 Quilt补丁编辑增强版本 (Quilt Patch Editing Enhancement Version)

#### 新增功能 (Added)
- 🔗 **新增 `fold` 命令**: 支持将外部补丁文件合并到当前补丁中
  - 可直接合并从网络下载的补丁文件
  - 支持多个补丁的合并操作
  - 自动处理补丁格式兼容性
- 📝 **新增 `header` 命令**: 完整的补丁头部信息管理
  - 查看补丁头部信息：`header [patch-name]`
  - 编辑头部信息：`header -e [patch-name]`
  - 追加信息：`header -a [patch-name]`
  - 替换信息：`header -r [patch-name]`
  - 支持管道和文件输入
- 🛠️ **新增CVE批量下载工具**: `tools/download_monthly_cve.sh`
  - 基于Ubuntu CVE Tracker自动查找Linux内核CVE
  - 支持按年月批量下载CVE补丁
  - 自动从官方Git仓库获取补丁文件
  - 生成详细的下载报告和统计信息

#### 改进功能 (Improved)
- 🔢 **版本号更新**: 将脚本版本号更新到 v8.8.0
- 🔤 **自动补全增强**: 为 `fold` 和 `header` 命令添加智能补全支持
- 🎨 **修复图形生成显示**: 更正了 `graph-pdf` 命令中的颜色图例显示问题
- 📚 **文档结构优化**: 将Quilt命令参考手册迁移到标准目录结构

#### 新增文档 (Documentation)
- 📖 **专用使用指南**: `doc/FOLD_HEADER_USAGE.md` - 详细的 `fold` 和 `header` 命令使用指南
- 🎯 **实际应用场景**: 包含完整的命令示例和最佳实践指导
- 📁 **标准化目录**: Quilt命令参考手册移动到 `doc/03_reference_manuals/` 目录

#### 技术细节 (Technical Details)
- **命令扩展架构**: 在主命令处理器中添加 `fold` 和 `header` 支持
- **自动补全框架**: 扩展补全函数支持新命令的智能提示
- **文档组织**: 按功能分类整理文档结构，提升可维护性

## [8.7.0] - 2025-01-13

### 🚀 Bash自动补全增强版本 (Bash Auto-completion Enhancement Version)

#### 新增功能 (Added)
- 🔤 **Bash自动补全脚本**: 新增 `quilt_patch_manager_completion.bash` 智能命令补全功能
- 📋 **智能命令补全**: 支持所有命令、选项和参数的Tab键自动补全
- 🎯 **上下文感知补全**: 根据不同命令提供相应的文件路径、选项补全
- 📁 **补丁文件智能识别**: 自动发现并补全工作目录和OpenWrt补丁目录中的.patch文件

#### 改进功能 (Improved)
- 🔢 **版本号更新**: 将脚本版本号更新到 v8.7.0
- 🛠️ **用户体验优化**: 大幅提升命令行操作效率和准确性
- 📚 **使用说明完善**: 补全脚本包含详细的安装和使用指导

#### 技术细节 (Technical Details)
```bash
# 安装自动补全功能
source tools/quilt_patch_manager_completion.bash

# 或添加到 ~/.bashrc 中永久启用
echo "source $(pwd)/tools/quilt_patch_manager_completion.bash" >> ~/.bashrc

# 使用示例
./quilt_patch_manager_final.sh <Tab><Tab>          # 显示所有可用命令
./quilt_patch_manager_final.sh graph-pdf --<Tab>  # 显示graph-pdf选项
./quilt_patch_manager_final.sh quick-apply <Tab>  # 补全.patch文件
```

#### 支持的补全类型 (Completion Types)
- **命令补全**: 所有22个主要命令的智能提示
- **选项补全**: graph-pdf的--color、--all等选项补全  
- **文件补全**: 针对不同命令类型的智能文件路径补全
- **补丁文件补全**: 自动发现工作目录和OpenWrt目录中的补丁文件

#### 使用场景 (Use Cases)
- **🚀 效率提升**: Tab键快速输入命令，减少输入错误
- **📋 命令发现**: 通过补全功能快速了解可用命令和选项
- **🎯 精确操作**: 智能文件补全避免路径输入错误
- **👥 新手友好**: 降低学习门槛，提升工具易用性

## [8.6.0] - 2025-01-13

### 🆕 新增命令功能版本 (New Commands Feature Version)

#### 新增功能 (Added)
- 🚀 **quick-apply命令**: 新增一键补丁应用功能，自动复制补丁到目标目录并执行make prepare
- 🧹 **snapshot-clean命令**: 新增快照数据清理命令，支持交互式和强制清理模式
- 📊 **graph命令**: 新增补丁依赖关系图生成功能，输出DOT格式，可用Graphviz可视化
- 🎨 **graph-pdf命令**: 新增PDF依赖图生成功能，支持彩色和全量显示选项
- 📚 **命令文档完善**: 为新增命令提供完整的使用说明和示例

#### 改进功能 (Improved)
- 🔢 **版本号更新**: 将脚本版本号更新到 v8.6.0
- 📝 **技术手册增强**: 在中英文技术手册中补充了缺失的命令文档
- 🛠️ **工作流优化**: 完善了补丁快速应用的完整流程说明

#### 技术细节 (Technical Details)
```bash
# 新增的快速应用命令
./quilt_patch_manager_final.sh quick-apply /path/to/patch.patch

# 新增的快照清理命令  
./quilt_patch_manager_final.sh snapshot-clean [force]

# 新增的图形化命令
./quilt_patch_manager_final.sh graph [patch]                    # 生成DOT格式依赖图
./quilt_patch_manager_final.sh graph-pdf [--color] [--all] [patch] [file]  # 生成PDF依赖图
```

#### 使用场景 (Use Cases)
- **🚀 一键部署**: quick-apply命令实现补丁的一键应用和内核重新准备
- **🧹 环境清理**: snapshot-clean命令提供便捷的快照数据管理
- **📊 可视化分析**: graph命令系列提供补丁依赖关系的图形化分析和PDF导出
- **📋 完整工作流**: 四个新命令补全了从补丁测试到应用的完整工作流程

### 🔄 版本递进更新 (Version Incremental Update)

#### 改进功能 (Improved)
- 🔢 **版本号递进**: 将脚本版本号更新到 v8.6.0，持续版本迭代
- 📝 **文档同步**: 保持文档与代码版本的同步更新
- 🛠️ **功能稳定**: 在v8.5.0基础上保持所有功能特性稳定运行

#### 技术细节 (Technical Details)
- 更新脚本头部版本标识从 v8.5.0 到 v8.6.0
- 更新内部 VERSION 变量从 "8.5.0" 到 "8.6.0"
- 保持所有现有功能和API接口不变

## [8.5.0] - 2025-01-13

### 🔄 版本同步更新 (Version Synchronization Update)

#### 改进功能 (Improved)
- 🔢 **版本号同步**: 将脚本版本号统一更新到 v8.5.0，确保版本一致性
- 📝 **文档完善**: 在快速开始指南中新增"情况3：补丁无冲突，直接应用补丁"的详细使用场景
- 🛠️ **工作流优化**: 完善了无冲突补丁的快速应用流程说明

#### 技术细节 (Technical Details)
- 更新脚本头部版本标识从 v8.4.0 到 v8.5.0
- 更新内部 VERSION 变量从 "8.4.0" 到 "8.5.0"
- 保持所有功能特性不变，纯版本号同步更新

## [8.4.0] - 2025-01-13

### 📋 文件列表导出增强版本 (File List Export Enhancement Version)

#### 新增功能 (Added)
- 📋 **文件列表导出功能**: 新增 `export-from-file` 命令，支持基于指定文件列表导出文件
- 🎯 **全局配置集成**: 自动读取全局配置文件中的 `default_workspace_dir` 作为根目录
- 📁 **目录结构保持**: 完整保持原始相对路径目录结构，确保文件组织不变
- 🔄 **会话管理系统**: 每次导出创建独立的时间戳会话目录，提供最新导出的软链接

#### 改进功能 (Improved)
- 📊 **详细导出报告**: 生成完整的 `EXPORT_INDEX.txt` 索引文件和 `successful_files.txt` 成功文件列表
- 💬 **注释支持**: 文件列表支持 `#` 注释行和空行，提高可读性和维护性
- ⚡ **错误处理增强**: 优雅处理不存在的文件，提供详细的失败原因和建议
- 📚 **帮助文档完善**: 新增文件列表导出功能的详细使用示例和说明

#### 技术细节 (Technical Details)
```bash
# 新增的文件列表导出示例
cat > files.txt << EOF
# 内核核心文件
Makefile
kernel/sched/core.c
include/linux/sched.h
EOF

./quilt_patch_manager_final.sh export-from-file files.txt
```

#### 使用场景 (Use Cases)
- **📦 代码打包**: 按需导出特定文件集合，用于代码审查或分发
- **🔍 差异分析**: 基于变更清单导出文件，便于版本比较
- **👥 团队协作**: 导出特定模块文件，支持分布式开发
- **🚀 CI/CD集成**: 自动化文件收集和打包流程

#### 兼容性 (Compatibility)
- ✅ **完全向下兼容**: 保持所有v8.3功能，确保现有工作流不受影响
- 🔧 **配置文件兼容**: 与现有 `kernel_snapshot_tool` 配置文件完全兼容

## [8.3.0] - 2024-01-15

### 🌐 网址链接支持版本 (URL Link Support Version)

#### 新增功能 (Added)
- 🌐 **网址链接支持**: 新增对HTTPS/HTTP网址的完整支持，可直接使用网址作为补丁输入
- 📥 **智能下载功能**: 自动下载网址补丁到本地缓存，支持断点续传和缓存复用
- 🔗 **URL哈希缓存**: 使用URL哈希值生成缓存文件名，避免特殊字符问题
- 🎯 **统一输入接口**: fetch、save、test-patch等命令统一支持commit-id、本地文件、网址三种输入方式

#### 改进功能 (Improved)
- 📚 **帮助文档增强**: 新增网址使用示例和详细说明
- 🎨 **用户体验优化**: 统一的输入提示，支持三种不同的补丁来源
- 🔧 **命令参数扩展**: fetch和save命令参数描述更新为支持URL

#### 技术细节 (Technical Details)
```bash
# 新增的网址支持示例
./quilt_patch_manager_final.sh save https://example.com/patch.patch cve-fix
./quilt_patch_manager_final.sh test-patch https://example.com/patch.patch
./quilt_patch_manager_final.sh fetch https://example.com/cve-2024.patch
```

#### 使用场景 (Use Cases)
- 🌍 **在线补丁下载**: 直接从GitHub、CVE数据库等在线资源下载补丁
- 📋 **团队协作**: 通过URL快速分享和应用补丁文件
- 🔄 **自动化流程**: 脚本化处理在线补丁资源
- 💾 **缓存优化**: 自动缓存下载的网址补丁，避免重复下载

#### 兼容性 (Compatibility)
- ✅ **向后兼容**: 保持所有v8.2.0功能，无破坏性变更
- ✅ **输入格式自动检测**: 自动识别commit-id、本地文件路径、网址三种输入格式
- ✅ **跨平台支持**: Linux、macOS等平台完全支持网址下载功能

## [8.2.0] - 2024-01-15

### 🚀 变更文件导出版本 (Changed Files Export Version)

#### 新增功能 (Added)
- ✨ **变更文件导出功能**: 新增`export-changed-files`命令，可导出所有变更文件并保持原目录结构
- 📦 **目录结构保持**: 按原内核目录结构导出变更文件，便于代码审查和团队协作
- 📋 **索引文件生成**: 自动生成`EXPORT_INDEX.txt`索引文件，记录导出详情和统计信息
- 🎯 **智能路径处理**: 动态获取内核目录名，支持不同内核版本的目录结构

#### 改进功能 (Improved)
- 📚 **帮助文档增强**: 在help命令中新增详细的`export-changed-files`功能说明和使用示例
- 🎨 **用户体验优化**: 提供彩色输出和详细的操作流程说明
- 🔧 **错误处理改进**: 增强文件复制过程中的错误检测和反馈机制

#### 技术细节 (Technical Details)
```bash
# 新增的export-changed-files功能
export_changed_files() {
    # 按原目录结构导出变更文件
    # 生成详细的索引文件
    # 提供完整的统计信息
}
```

#### 使用场景 (Use Cases)
- 📋 **代码审查**: 整理所有变更文件，方便团队审查
- 💾 **补丁备份**: 防止代码丢失，完整保存修改内容
- 👥 **团队协作**: 分享具体修改内容，保持目录结构
- 🔍 **差异分析**: 按目录结构查看变更，便于理解修改范围

#### 导出结果示例 (Export Result Example)
```
📁 output/changed_files/
├── linux-4.1.15/              # 内核目录 (动态获取)
│   ├── drivers/net/cve_fix.c   # 新增文件
│   ├── kernel/Kconfig          # 修改文件
│   └── fs/security/patch.h     # 新增文件
└── EXPORT_INDEX.txt            # 导出索引
```

#### 兼容性 (Compatibility)
- ✅ **向后兼容**: 保持所有v8.1.0功能，无破坏性变更
- ✅ **跨平台支持**: Linux、macOS等平台完全支持
- ✅ **配置集成**: 继承智能配置集成和增强错误处理功能

## [8.1.0] - 2024-01-08

### 🔧 增强配置集成版本 (Enhanced Configuration Integration Version)

#### 新增功能 (Added)
- 🔧 **智能配置集成**: 主脚本现在能智能读取kernel_snapshot_tool的全局配置文件
- 📋 **增强错误处理**: 新增find_kernel_source_enhanced函数，提供更详细的错误诊断
- 🎯 **配置文件优先**: 当标准方法找不到内核目录时，自动尝试使用全局配置文件
- 💡 **智能提示**: 改进的错误信息和解决方案建议，提升用户体验

## [8.0.0] - 2024-01-01

### 🚀 Git风格快照系统重大版本 (Git-style Snapshot System Major Version)

#### 新增功能 (Added)
- 🔄 **Git风格全局快照系统**: 新增 `snapshot-create` 和 `snapshot-diff` 命令，实现类Git的文件变更跟踪
- 🔀 **混合输入架构**: 统一支持 commit ID 和本地补丁文件，大幅提升工具灵活性
- ⚡ **高性能C语言助手**: 集成kernel_snapshot_tool，实现100倍性能提升
- 📊 **实时进度反馈**: 新增美观的进度条和实时状态显示

---

## 🤝 贡献 (Contributing)

我们欢迎各种形式的贡献：

- 🐛 Bug报告和修复
- ✨ 新功能建议和实现
- 📖 文档改进
- 🧪 测试用例增加
- 🎨 性能优化

## 📞 支持 (Support)

如果遇到问题或需要帮助：

1. 查看 [README.md](README.md) 的使用说明
2. 检查本CHANGELOG了解最新功能
3. 提交Issue并附上详细信息

---

**注**: 版本号格式为 `主版本.次版本.修订版本`，遵循语义化版本规范。
