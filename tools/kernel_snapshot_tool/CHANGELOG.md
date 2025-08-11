# 更新日志 (Changelog)

本文档记录了内核快照工具的所有重要变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，并遵循 [语义化版本](https://semver.org/lang/zh-CN/) 规范。

## [1.1.0] - 2024-01-15

### 🔗 符号链接支持 (Symbolic Link Support)

#### 新增功能 (Added)
- ✨ **完整符号链接支持**: 像Git一样智能处理符号链接，确保不丢失任何文件状态信息
- 🔍 **智能链接检测**: 使用`S_ISLNK()`精确识别符号链接，避免误判
- 📁 **递归目录处理**: 符号链接指向目录时自动递归扫描目录内容
- 🎯 **目标路径哈希**: 基于`readlink()`的轻量级哈希算法，避免不必要的文件内容读取
- 🛡️ **断链处理**: 妥善处理指向不存在目标的"悬空"符号链接
- ⚡ **性能优化**: 符号链接使用简单字符串哈希(31进制)，避免SHA256计算开销

#### 改进功能 (Improved)
- 🔧 **文件类型检测增强**: 函数`process_file_entry()`和`calculate_fast_hash()`现在支持`S_ISLNK()`检测
- 📊 **更准确的统计**: 符号链接现在正确计入文件总数和处理统计
- 🔄 **目录遍历优化**: `scan_directory_recursive()`增强对符号链接指向目录的处理

#### 技术细节 (Technical Details)
```c
// 新增符号链接处理逻辑
if (S_ISLNK(st.st_mode)) {
    char link_target[MAX_PATH_LEN];
    ssize_t link_len = readlink(file_path, link_target, sizeof(link_target) - 1);
    // 使用31进制字符串哈希算法
    uint32_t simple_hash = 0;
    for (int i = 0; i < link_len; i++) {
        simple_hash = simple_hash * 31 + (unsigned char)link_target[i];
    }
}
```

#### 兼容性 (Compatibility)
- ✅ **向后兼容**: 现有快照文件格式不受影响
- ✅ **跨平台**: 在Linux、macOS等POSIX系统上正常工作
- ✅ **性能保持**: 不影响普通文件的处理性能

#### 应用场景 (Use Cases)
- 🐧 **Linux内核开发**: 正确处理内核源码中的符号链接(如arch/include链接)
- 📦 **软件包构建**: 支持包含符号链接的复杂项目结构
- 🔒 **系统配置管理**: 跟踪/etc目录中的配置文件符号链接变更
- 🛠️ **CVE补丁制作**: 确保补丁不会丢失符号链接信息

## [1.0.0] - 2024-01-08

### 🎉 首次发布

#### 新增功能 (Added)
- ⚡ **高性能快照创建**: 87,000个文件仅需2秒处理完成
- 🛡️ **零文件丢失保证**: 采用单线程遍历+多线程处理的Git风格设计
- 🔍 **精确变更检测**: 完整支持文件增加(A)、修改(M)、删除(D)检测
- 📊 **详细统计报告**: 提供文件数量、处理速度、完整率等详细信息
- 🧬 **Git兼容模式**: 支持SHA1哈希算法(`-g`选项)
- 🔧 **多线程优化**: 可配置工作线程数(`-t`选项)
- 📝 **详细日志**: 支持详细输出模式(`-v`选项)
- 🚫 **文件排除**: 支持排除指定模式的文件(`-e`选项)

#### 核心组件 (Core Components)
- `main.c`: 主程序入口和命令行参数处理
- `snapshot_core.c`: 核心快照创建功能
- `snapshot_core.h`: 数据结构和函数声明
- `snapshot_diff.c`: 高效差异分析算法

#### 工具和集成 (Tools & Integration)
- `Makefile`: 完整的编译配置，支持发布/调试版本
- `examples/quilt_integration.sh`: quilt补丁管理系统集成脚本
- 内置测试套件: `make test`
- 性能基准测试: `make benchmark`

#### 性能表现 (Performance)
- **快照创建**: 87,929个文件 → 2.1秒
- **差异分析**: 87,000个文件对比 → 1.0秒  
- **内存效率**: 每10万文件约100MB内存使用
- **CPU利用率**: 多核并行处理，CPU使用率可达700%+

#### 算法优化 (Algorithm Optimizations)
- **文件遍历**: O(n)单线程递归遍历，确保零遗漏
- **内容处理**: 多线程并行哈希计算
- **差异分析**: O(n+m)双指针算法替代O(n²)线性查找
- **哈希计算**: 支持快速多项式哈希和Git兼容SHA1

#### 平台支持 (Platform Support)
- ✅ Linux (ext4, xfs, btrfs)
- ✅ macOS (APFS, HFS+)
- ✅ 网络文件系统 (性能稍降)

#### 文档和示例 (Documentation & Examples)
- 📚 完整的README.md文档
- 🛠️ quilt集成工作流示例
- 🧪 测试用例和使用示例
- 📄 MIT开源许可证

### 技术细节 (Technical Details)

#### 设计原则
1. **可靠性优先**: 绝对不允许文件丢失
2. **性能优化**: 充分利用现代多核CPU
3. **内存高效**: 流式处理支持大型项目
4. **Git兼容**: 与现有工具生态集成

#### 核心算法
```c
// 高效差异检测 - 双指针技术 O(n+m)
while (new_idx < new_count && old_idx < old_count) {
    int cmp = strcmp(new_entry->path, old_entry->path);
    if (cmp == 0) {
        if (hash_different) report_modified();
    } else if (cmp < 0) {
        report_added();
    } else {
        report_deleted();  
    }
}
```

#### 质量保证
- 零编译警告
- 内存泄露检测
- 边界条件测试
- 多平台验证

---

## 🔮 未来计划 (Future Plans)

### [1.1.0] - 计划中
- [ ] 增量快照支持
- [ ] JSON格式输出选项
- [ ] 文件内容预览功能
- [ ] Web界面(可选)

### [1.2.0] - 规划中
- [ ] 分布式快照同步
- [ ] 压缩存储支持
- [ ] 历史快照管理
- [ ] API接口支持

---

## 🤝 贡献 (Contributing)

我们欢迎各种形式的贡献：

- 🐛 Bug报告和修复
- ✨ 新功能建议和实现
- 📖 文档改进
- 🧪 测试用例增加
- 🎨 性能优化

请查看 [README.md](README.md) 了解详细的贡献指南。

---

## 📞 支持 (Support)

如果遇到问题或需要帮助：

1. 查看 [README.md](README.md) 的故障排除部分
2. 运行 `make test` 验证基本功能
3. 使用 `./kernel_snapshot -v` 获取详细日志
4. 提交Issue并附上错误信息

---

**注**: 版本号格式为 `主版本.次版本.修订版本`，遵循语义化版本规范。