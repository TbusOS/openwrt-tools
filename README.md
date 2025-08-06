# OpenWrt 内核补丁管理工具集

## �� 目录结构

```
/Users/sky/linux-kernel/openwrt/
├── tools/                          # 🔧 工具脚本目录
│   ├── quilt_patch_manager_final.sh # 主要工具 (v5.7) - 智能元数据集成
│   ├── patch_helper_universal.sh    # 通用补丁助手
│   └── patch_helper.sh             # 基础补丁助手
├── doc/                            # 📚 完整文档
│   ├── QUILT_PATCH_MANAGER_GUIDE.md
│   ├── DOCUMENTATION_INDEX.md
│   ├── UBUNTU_COMPATIBILITY_GUIDE.md
│   └── ... (更多文档)
├── openwrt-source/                 # OpenWrt 源码目录
└── README.md                       # 本文件
```

## 🚀 快速开始

### 主要工具 (推荐 v5.7)
```bash
# 演示所有功能
./tools/quilt_patch_manager_final.sh demo

# 🆕 智能补丁兼容性检测 (推荐先执行)
./tools/quilt_patch_manager_final.sh test-patch <commit_id>

# 查看补丁状态
./tools/quilt_patch_manager_final.sh status

# 🆕 网络连接检测和优化
./tools/quilt_patch_manager_final.sh test-network

# 自动制作 CVE 补丁 (已集成兼容性检测)
./tools/quilt_patch_manager_final.sh auto-patch <commit_id> <patch_name>

# 🆕 生成补丁并自动集成元数据 (推荐)
./tools/quilt_patch_manager_final.sh auto-refresh
```

### 补丁管理
```bash
# 应用补丁
./tools/quilt_patch_manager_final.sh push

# 移除补丁  
./tools/quilt_patch_manager_final.sh pop

# 清理补丁和临时文件
./tools/quilt_patch_manager_final.sh clean
```

## 📖 详细文档

查看 `doc/DOCUMENTATION_INDEX.md` 获取完整的工具和文档索引。

## 🎯 支持平台

- ✅ macOS (所有版本)
- ✅ Ubuntu 20.04+ 
- ✅ 其他 Linux 发行版

## 🔧 依赖要求

```bash
# Ubuntu/Debian
sudo apt install -y curl quilt

# macOS
brew install quilt
```
