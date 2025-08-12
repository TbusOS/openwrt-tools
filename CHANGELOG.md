# OpenWrt 内核补丁管理工具更新日志

本文档记录了OpenWrt内核补丁管理工具的所有重要变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，并遵循 [语义化版本](https://semver.org/lang/zh-CN/) 规范。

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
