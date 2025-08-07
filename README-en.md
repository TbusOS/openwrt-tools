# OpenWrt Kernel Patch Management Tool v8.0.0

A **hybrid architecture high-performance patch management platform** designed specifically for OpenWrt developers. v8.0 is the **Git-style snapshot system major version**, adding **Global Differential Snapshot System** and **Hybrid Input Architecture Support** on top of intelligent conflict analysis.

## 🚀 v8.0.0 Git-style Snapshot System Major Version

- **🔄 Git-style Global Snapshot System**: Added `snapshot-create` and `snapshot-diff` commands for Git-like file change tracking
- **🔀 Hybrid Input Architecture Support**: Unified support for commit ID and local patch file input modes  
- **⚡ High-Performance C Assistant Tool**: Integrated C-language `snapshot_helper` for fast processing of large codebases
- **📊 Real-time Progress Display**: Dynamic progress bars during snapshot creation with parallel processing support
- **🛠️ Enhanced Cross-platform Compatibility**: Improved script directory detection and macOS/Linux compatibility
- **🧠 Smart Conflict Analysis v7.3**: Inherited AWK script precise analysis, generating professional-grade conflict reports
- **🔧 Architectural Robustness**: Code grown to 1202 lines, achieving hybrid architecture high-performance stable version
- **🔄 Backward Compatibility**: Maintains all v7.0 intelligent analysis and Quilt management features

## 📁 Project Structure

```
openwrt-tools/
├── tools/                                    # 🔧 Core Tools
│   ├── quilt_patch_manager_final.sh         # v8.0.0 Hybrid Architecture Main Tool
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

### 🥇 Git-style Snapshot System (v8.0 Core Breakthrough)
```bash
# Create project snapshot
./tools/quilt_patch_manager_final.sh snapshot-create [dir]

# Check all changes (Git-like)
./tools/quilt_patch_manager_final.sh snapshot-diff [dir]

# Output change list to file
./tools/quilt_patch_manager_final.sh snapshot-diff > changes.txt
```

### 🥈 Hybrid Input Intelligent Patch Creation (v8.0 Enhanced)
```bash
# Using Commit ID (traditional way)
./tools/quilt_patch_manager_final.sh auto-patch <commit_id> <patch_name>

# Using local patch file (v8.0 new feature)
./tools/quilt_patch_manager_final.sh auto-patch /path/to/local.patch <patch_name>
```

### 🥉 Smart Conflict Analysis (v7.3 Inherited Feature)
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
- ✅ **macOS** (All versions)
- ✅ **Ubuntu 20.04+**
- ✅ **Other Linux Distributions**

### Dependency Installation
```bash
# Ubuntu/Debian (v8.0 added: compilation toolchain)
sudo apt install -y curl quilt build-essential

# macOS (v8.0 added: compilation toolchain)
brew install quilt curl
# Ensure Xcode Command Line Tools are installed
xcode-select --install

# CentOS/RHEL (v8.0 added: compilation toolchain)
sudo yum install -y curl quilt gcc make
```

### C Assistant Tool Compilation (v8.0 New Feature)
```bash
# Compile high-performance assistant tool on first use
cd tools/snapshot_tool
make

# Verify compilation success
./snapshot_helper --help 2>/dev/null && echo "✅ C assistant tool compiled successfully"
```

## 📖 Documentation Navigation

| Document Category | Recommended Reading Order | Document Path |
|-------------------|-------------------------|---------------|
| **🔰 Beginner Guide** | 1️⃣ | [`doc/01_tool_guides/QUILT_PATCH_MANAGER_GUIDE.md`](doc/01_tool_guides/QUILT_PATCH_MANAGER_GUIDE.md) |
| **⚡ Quick Start** | 2️⃣ | [`doc/02_workflow_guides/QUILT_CVE_PATCH_CREATION_GUIDE.md`](doc/02_workflow_guides/QUILT_CVE_PATCH_CREATION_GUIDE.md) |
| **📋 Standard Process** | 3️⃣ | [`doc/02_workflow_guides/CVE_PATCH_WORKFLOW.md`](doc/02_workflow_guides/CVE_PATCH_WORKFLOW.md) |
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

### Scenario 2: Large Project Change Tracking (v8.0 New Scenario)
```bash
# Create project baseline snapshot
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

| Feature | v7.0.0 (Final Stable) | v8.0.0 (Hybrid Architecture High-Performance) |
|---------|------------------------|-----------------------------------------------|
| **Positioning** | Enterprise Management Platform | Hybrid Architecture High-Performance Patch Management Platform |
| **Lines of Code** | 927 lines | 1202 lines (+275 lines) |
| **Core Feature** | Smart Conflict Analysis v7.0 | Git-style Snapshot System + Hybrid Input Architecture |
| **Input Support** | Commit ID only | Commit ID + Local Files (Hybrid Input) |
| **Change Tracking** | None | Git-style Global Snapshot System |
| **Performance Optimization** | Bash Optimization | C Assistant Tool + Parallel Processing |
| **Cross-platform Compatibility** | Basic Support | Enhanced macOS/Linux Compatibility |
| **Progress Feedback** | Basic | Real-time Progress Bar + Dynamic Display |
| **Use Cases** | Enterprise Team Collaboration | Large Projects + Enterprise Development Teams |

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