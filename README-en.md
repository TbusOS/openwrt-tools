# OpenWrt Kernel Patch Management Tool v8.1.0

A **hybrid architecture high-performance patch management platform** designed specifically for OpenWrt developers. v8.1 builds on v8.0 with **Smart Configuration Integration** and **Enhanced Error Handling** features.

## 🚀 v8.1.0 Enhanced Configuration Integration Version

- **🔧 Smart Configuration Integration**: Main script now intelligently reads kernel_snapshot_tool global configuration files
- **📋 Enhanced Error Handling**: New find_kernel_source_enhanced function provides detailed error diagnostics
- **🎯 Configuration File Priority**: Auto fallback to global config when standard methods fail to find kernel directories
- **💡 Smart Hints**: Improved error messages with specific solution suggestions
- **🔄 Backward Compatibility**: Maintains all v8.0 features with full backward compatibility

## 🚀 v8.0.0 Git-style Snapshot System Major Version

- **🔄 Git-style Global Snapshot System**: Added `snapshot-create` and `snapshot-diff` commands for Git-like file change tracking
- **🔀 Hybrid Input Architecture Support**: Unified support for commit ID and local patch file input modes  
- **⚡ High-Performance C Assistant Tool**: Integrated C-language `snapshot_helper` for fast processing of large codebases
- **🚀 Kernel Snapshot Tool v1.1.0**: Brand new independent high-performance kernel snapshot system, processes 87,000 files in just 2 seconds
- **🍎 macOS Native Compatibility**: Complete support for macOS platform, including Apple Silicon and Intel Mac
- **📱 Git-style User Interface**: Supports create, status, clean Git-style commands with global configuration file support
- **🎯 Smart Index Caching**: Zero file loss guarantee with single-thread traversal + multi-thread processing Git-style design
- **📊 Real-time Progress Display**: Dynamic progress bars during snapshot creation with parallel processing support
- **🛠️ Enhanced Cross-platform Compatibility**: Improved script directory detection and macOS/Linux compatibility
- **🧠 Smart Conflict Analysis v7.3**: Inherited AWK script precise analysis, generating professional-grade conflict reports
- **🔧 Architectural Robustness**: Code grown to 1202 lines, achieving hybrid architecture high-performance stable version
- **🔄 Backward Compatibility**: Maintains all v7.0 intelligent analysis and Quilt management features

## 📁 Project Structure

```
openwrt-tools/
├── tools/                                    # 🔧 Core Tools
│   ├── quilt_patch_manager_final.sh         # v8.1.0 Hybrid Architecture Main Tool
│   ├── kernel_snapshot_tool/                # 🚀 Kernel Snapshot Tool v1.1.0 (Symbolic Link Support Upgrade)
│   │   ├── kernel_snapshot                  # Main Executable
│   │   ├── main.c, snapshot_core.c         # Core Source Code
│   │   ├── index_cache_simple.c            # Smart Index Caching
│   │   ├── progress_bar.c                   # Progress Bar Display
│   │   ├── 使用指南.md                      # Detailed Chinese Usage Guide
│   │   ├── 快速开始示例.md                   # Quick Start Examples
│   │   ├── 配置文件示例.conf               # Configuration File Template
│   │   └── CHANGELOG.md                     # Detailed Changelog
│   └── snapshot_tool/                       # 📸 Git-style Snapshot System
│       ├── snapshot_helper.c                # C High-Performance Assistant
│       ├── Makefile                         # Compilation Configuration
│       └── snapshot_helper                  # Compiled Binary
├── doc/                                      # 📚 Categorized Documentation
│   ├── 01_tool_guides/                      # Tool Usage Guides
│   ├── 02_workflow_guides/                  # Workflow Process Guides
│   ├── 03_reference_manuals/                # Reference Manuals
│   ├── 04_summaries/                        # Summary Archives
│   └── DOCUMENTATION_INDEX.md               # Documentation Index
├── suggest/                                  # 💡 Improvement Suggestions
└── README.md                                # This File
```

## 🎯 Core Features

### 🥇 Independent Kernel Snapshot Tool v1.1.0 (Recommended) 🔗New Symbolic Link Support + 🍎 macOS Native Support
```bash
# Git-style workflow - using global configuration file (recommended)
cd tools/kernel_snapshot_tool
./kernel_snapshot create                    # Create baseline snapshot (supports symbolic links)
./kernel_snapshot status                    # Check change status (includes symbolic link changes)

# Manual directory specification
./kernel_snapshot create /path/to/kernel linux-6.6
./kernel_snapshot status

# Clean snapshot data
./kernel_snapshot clean

# 🍎 macOS Exclusive Optimizations:
# ✨ Native Apple Silicon/Intel Mac support
# ⚡ Adaptive CPU core detection (fixed 4 cores, overridable with -t parameter)
# 🔧 Optimized memory detection mechanism, avoiding system API conflicts
# 📁 macOS path compatibility (supports _NSGetExecutablePath)

# New Features:
# ✨ Complete symbolic link support - Smart handling like Git
# 🔍 Intelligent link detection - Precise identification and recursive processing of linked directories
# ⚡ Performance optimization - Lightweight hashing for symbolic links, avoiding SHA256 computation overhead
```

### 🥈 Git-style Snapshot System (v8.0 Integrated Feature)
```bash
# Using snapshot functionality through main tool
./tools/quilt_patch_manager_final.sh snapshot-create [dir]

# Check all changes (Git-like)
./tools/quilt_patch_manager_final.sh snapshot-diff [dir]

# Output change list to file
./tools/quilt_patch_manager_final.sh snapshot-diff > changes.txt
```

### 🥉 Hybrid Input Intelligent Patch Creation (v8.0 Enhanced)
```bash
# Using Commit ID (traditional way)
./tools/quilt_patch_manager_final.sh auto-patch <commit_id> <patch_name>

# Using local patch file (v8.0 new feature)
./tools/quilt_patch_manager_final.sh auto-patch /path/to/local.patch <patch_name>
```

### 🏅 Smart Conflict Analysis (v7.3 Inherited Feature)
```bash
# Smart conflict analyzer - supports hybrid input
./tools/quilt_patch_manager_final.sh test-patch <commit_id|file_path>
```

### 🎯 Complete Status Management System (Inherited from v7.0)
```bash
# Overall status overview
./tools/quilt_patch_manager_final.sh status

# Detailed patch list
./tools/quilt_patch_manager_final.sh series

# Current active patch
./tools/quilt_patch_manager_final.sh top

# Apply/Undo patches
./tools/quilt_patch_manager_final.sh push
./tools/quilt_patch_manager_final.sh pop
```

### 🔧 Environment Management (Enhanced)
```bash
# Clean cache and output directories
./tools/quilt_patch_manager_final.sh clean

# (Dangerous) Reset kernel quilt state
./tools/quilt_patch_manager_final.sh reset-env
```

## 🔧 Installation & Dependencies

### System Requirements
- ✅ **macOS** (All versions, including Apple Silicon M1/M2/M3)
- ✅ **Ubuntu 20.04+**
- ✅ **Other Linux Distributions**

### Dependency Installation
```bash
# Ubuntu/Debian (v8.0 added: compilation toolchain)
sudo apt install -y curl quilt build-essential

# macOS (v8.0 added: compilation toolchain + native compatibility)
brew install quilt curl
# Ensure Xcode Command Line Tools are installed
xcode-select --install

# CentOS/RHEL (v8.0 added: compilation toolchain)
sudo yum install -y curl quilt gcc make
```

### C Assistant Tool Compilation (v8.0 New Feature + 🍎 macOS Native Support)
```bash
# Compile legacy high-performance assistant tool
cd tools/snapshot_tool
make

# Compile Kernel Snapshot Tool v1.1.0 (recommended + macOS native support)
cd tools/kernel_snapshot_tool
make                                        # Auto-detects platform and applies optimized compilation flags

# Verify compilation success
./kernel_snapshot --help 2>/dev/null && echo "✅ Kernel snapshot tool compiled successfully"
cd ../snapshot_tool
./snapshot_helper --help 2>/dev/null && echo "✅ C assistant tool compiled successfully"

# 🍎 macOS Compilation Verification
# Compilation on macOS automatically applies the following optimizations:
# - Removes -march=native (avoids compatibility issues)
# - Uses macOS-specific system APIs
# - Optimizes memory and CPU detection mechanisms
```

## 📖 Documentation Navigation

| Document Category | Recommended Reading Order | Document Path |
|-------------------|-------------------------|---------------|
| **🔰 Beginner Guide** | 1️⃣ | [`doc/01_tool_guides/QUILT_PATCH_MANAGER_GUIDE.md`](doc/01_tool_guides/QUILT_PATCH_MANAGER_GUIDE.md) |
| **🚀 Kernel Snapshot Tool** | 1️⃣⭐ | [`tools/kernel_snapshot_tool/使用指南.md`](tools/kernel_snapshot_tool/使用指南.md) |
| **⚡ Quick Start** | 2️⃣ | [`doc/02_workflow_guides/QUILT_CVE_PATCH_CREATION_GUIDE.md`](doc/02_workflow_guides/QUILT_CVE_PATCH_CREATION_GUIDE.md) |
| **🎯 Snapshot Tool Examples** | 2️⃣⭐ | [`tools/kernel_snapshot_tool/快速开始示例.md`](tools/kernel_snapshot_tool/快速开始示例.md) |
| **📋 Standard Process** | 3️⃣ | [`doc/02_workflow_guides/CVE_PATCH_WORKFLOW.md`](doc/02_workflow_guides/CVE_PATCH_WORKFLOW.md) |
| **🔧 Configuration Template** | 🛠️ | [`tools/kernel_snapshot_tool/配置文件示例.conf`](tools/kernel_snapshot_tool/配置文件示例.conf) |
| **🔍 Latest Version Comparison** | 4️⃣ | [`doc/01_tool_guides/VERSION_COMPARISON_v7.0_vs_v8.0.md`](doc/01_tool_guides/VERSION_COMPARISON_v7.0_vs_v8.0.md) |
| **🔍 Historical Version Comparison** | 5️⃣ | [`doc/01_tool_guides/VERSION_COMPARISON_v6.0_vs_v7.0.md`](doc/01_tool_guides/VERSION_COMPARISON_v6.0_vs_v7.0.md) |
| **📚 Complete Index** | 🔗 | [`doc/DOCUMENTATION_INDEX.md`](doc/DOCUMENTATION_INDEX.md) |

## 💡 Use Cases

### Scenario 1: CVE Patch Creation (Most Common - v8.0 Hybrid Input)
```bash
# Using Commit ID (traditional way)
./tools/quilt_patch_manager_final.sh auto-patch 1234567890abcdef CVE-2024-12345

# Using local patch file (v8.0 new feature)
./tools/quilt_patch_manager_final.sh auto-patch /tmp/cve.patch CVE-2024-12345
```

### Scenario 2: Large Project Change Tracking (v8.0 New Scenario - Recommended Independent Tool)
```bash
# Method 1: Using independent kernel snapshot tool (recommended)
cd tools/kernel_snapshot_tool
./kernel_snapshot create                    # Create baseline snapshot
# ... make various code modifications ...
./kernel_snapshot status > all_changes.txt # Output all changes

# Method 2: Using main tool
./tools/quilt_patch_manager_final.sh snapshot-create

# Check changes after various modifications
./tools/quilt_patch_manager_final.sh snapshot-diff > all_changes.txt
```

### Scenario 3: Enterprise SVN Environment
- ✅ No Git history dependency required
- ✅ Supports multi-source patches (Linux mainline, Android, GitHub, local files)
- ✅ Intelligent conflict warnings
- ✅ Git-style change tracking (v8.0 new)

### Scenario 4: High-to-Low Version Porting
- ✅ Intelligent compatibility detection
- ✅ Symbol change warnings
- ✅ Fuzzy matching support
- ✅ High-performance difference detection (v8.0 new)

## 🆚 Version Comparison

| Feature | v7.0.0 (Final Stable) | v8.0.0 (Hybrid Architecture High-Performance) | v8.1.0 (Enhanced Configuration Integration) |
|---------|------------------------|-----------------------------------------------|---------------------------------------------|
| **Positioning** | Enterprise Management Platform | Hybrid Architecture High-Performance Patch Management Platform | Smart Configuration Integration Patch Management Platform |
| **Lines of Code** | 927 lines | 1202 lines (+275 lines) | 1320 lines (+118 lines) |
| **Core Feature** | Smart Conflict Analysis v7.0 | Git-style Snapshot System + Hybrid Input Architecture | + Smart Configuration Integration + Enhanced Error Handling |
| **Configuration Integration** | None | Basic Support | Smart Global Configuration File Reading |
| **Error Handling** | Basic | Improved Error Messages | Detailed Diagnostics + Solution Suggestions |
| **Input Support** | Commit ID only | Commit ID + Local Files (Hybrid Input) | Hybrid Input + Configuration File Paths |
| **Change Tracking** | None | Git-style Global Snapshot System | Git-style Global Snapshot System |
| **Performance Optimization** | Bash Optimization | C Assistant Tool + Parallel Processing | C Assistant Tool + Parallel Processing |
| **Cross-platform Compatibility** | Basic Support | Enhanced macOS/Linux Compatibility | Enhanced macOS/Linux Compatibility |
| **Progress Feedback** | Basic | Real-time Progress Bar + Dynamic Display | Real-time Progress Bar + Dynamic Display |
| **Use Cases** | Enterprise Team Collaboration | Large Projects + Enterprise Development Teams | Large Projects + Enterprise Development Teams |

## 🌟 v8.1 New Advantages

1. **🔧 Smart Configuration**: Auto-reads kernel_snapshot_tool config files without manual path specification
2. **📋 Enhanced Diagnostics**: find_kernel_source_enhanced function provides detailed error diagnostic information
3. **💡 Smart Hints**: Improved error messages include specific solution suggestions
4. **🎯 Configuration Priority**: Graceful fallback mechanism with config files as backup path discovery solution
5. **🔄 Full Compatibility**: Maintains all v8.0 features with no breaking changes

## 🌟 v8.0 Core Advantages

1. **🔄 Git-style**: Git-style global snapshot system with Git-like file change tracking capabilities
2. **🔀 Hybrid Input**: Unified support for commit ID and local patch files, greatly enhancing tool flexibility
3. **⚡ High-Performance**: C assistant tool + parallel processing, supporting fast processing of large codebases
4. **🧠 Intelligence**: Inherited Smart Conflict Analysis v7.3, precisely locating each hunk conflict
5. **📊 Real-time Feedback**: Dynamic progress bars + real-time status display, improving user experience
6. **🛠️ Cross-platform**: Enhanced macOS/Linux compatibility with more robust platform support
7. **🏢 Enterprise-Grade**: Hybrid architecture design suitable for large projects and enterprise development teams

## 🤝 Contributing & Support

- **📋 Issue Reports**: [GitHub Issues](https://github.com/TbusOS/openwrt-tools/issues)
- **💡 Feature Suggestions**: Check the [`suggest/`](suggest/) directory
- **📖 Documentation Improvements**: Welcome to submit PRs for documentation improvements

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**🎉 Get Started Now**: Read [`doc/01_tool_guides/QUILT_PATCH_MANAGER_GUIDE.md`](doc/01_tool_guides/QUILT_PATCH_MANAGER_GUIDE.md) to begin your hybrid architecture high-performance CVE patch management journey!