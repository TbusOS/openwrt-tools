# OpenWrt 补丁管理工具说明文档

## 工具概述

`patch_helper.sh` 是一个专为 OpenWrt 开发环境设计的补丁管理工具，可以帮助开发者快速查看、分析和管理内核补丁文件。

## 功能特性

- 📋 **补丁列表** - 显示所有可用的内核补丁及其大小
- 📄 **补丁查看** - 格式化显示补丁内容和元信息
- 🎯 **平台识别** - 自动识别当前平台的补丁目录
- 📊 **统计信息** - 显示补丁数量和文件大小统计

## 安装和使用

### 安装
工具已自动创建在 OpenWrt 根目录，无需额外安装：
```bash
# 确保工具可执行
chmod +x patch_helper.sh
```

### 基本用法

#### 1. 列出所有补丁
```bash
./patch_helper.sh list
```
**输出示例：**
```
=== OpenWrt i.MX6UL 补丁管理助手 ===
📁 i.MX 平台补丁 (patches-6.6):
  100-bootargs.patch    252 bytes
  300-ARM-dts-imx6q-apalis-ixora-add-status-LEDs-aliases.patch  2441 bytes
  950-proc-fix-UAF-in-proc_get_inode-svn.patch  4339 bytes
  999-imx6ul-example-patch.patch  381 bytes
📁 通用内核补丁数量:
  0 个通用补丁
```

#### 2. 查看特定补丁
```bash
./patch_helper.sh view <补丁文件名>
```
**示例：**
```bash
./patch_helper.sh view 950-proc-fix-UAF-in-proc_get_inode-svn.patch
```
**输出示例：**
```
=== OpenWrt i.MX6UL 补丁管理助手 ===
📄 补丁内容: 950-proc-fix-UAF-in-proc_get_inode-svn.patch
----------------------------------------
From 654b33ada4ab5e926cd9c570196fefa7bec7c1df Mon Sep 17 00:00:00 2001
From: Ye Bin <yebin10@huawei.com>
Date: Sat, 1 Mar 2025 15:06:24 +0300
Subject: [PATCH] proc: fix UAF in proc_get_inode()
[补丁内容...]
```

#### 3. 显示帮助信息
```bash
./patch_helper.sh help
# 或者
./patch_helper.sh
```

## 工具结构

### 主要功能模块

#### `list_patches()` 函数
- **功能**：扫描并列出所有补丁文件
- **输出**：文件名、大小、补丁类型分类
- **特点**：自动识别平台特定补丁目录

#### `view_patch()` 函数  
- **功能**：显示指定补丁的完整内容
- **参数**：补丁文件名
- **输出**：格式化的补丁内容
- **错误处理**：文件不存在时的友好提示

#### `show_help()` 函数
- **功能**：显示使用说明和命令示例
- **内容**：所有可用命令和用法说明

### 目录结构支持

工具自动识别以下补丁目录：
```
target/linux/<platform>/patches-<kernel_version>/
```
当前支持的平台：
- **i.MX 平台** (`target/linux/imx/patches-6.6/`)
- **通用内核补丁** (可扩展)

## 补丁类型识别

工具根据文件名前缀自动分类补丁：

| 前缀范围 | 补丁类型 | 描述 |
|---------|---------|------|
| 000-099 | 核心补丁 | 架构和启动相关的关键补丁 |
| 100-199 | 平台补丁 | 特定硬件平台的补丁 |
| 200-299 | 驱动补丁 | 设备驱动相关补丁 |
| 300-399 | 设备树补丁 | 设备树 (DTS) 相关修改 |
| 400-499 | 功能补丁 | 功能增强和新特性 |
| 500-899 | 其他补丁 | 其他类型的补丁 |
| 900-999 | 安全补丁 | CVE 和安全相关补丁 |

## 高级用法

### 结合其他命令使用

#### 搜索特定补丁
```bash
./patch_helper.sh list | grep -i "cve"
./patch_helper.sh list | grep -i "usb"
```

#### 查看补丁统计
```bash
./patch_helper.sh list | wc -l  # 补丁总数
```

#### 查看补丁头部信息
```bash
./patch_helper.sh view <patch_name> | head -20
```

### 补丁验证和分析

#### 检查补丁格式
```bash
# 验证补丁是否符合标准格式
./patch_helper.sh view <patch_name> | grep -E "^From|^Date|^Subject"
```

#### 分析补丁影响范围
```bash
# 查看补丁修改的文件
./patch_helper.sh view <patch_name> | grep -E "^---|\^\+\+\+"
```

## 扩展和定制

### 添加新平台支持

在 `list_patches()` 函数中添加新的平台目录：
```bash
if [ -d "target/linux/新平台/patches-6.6" ]; then
    echo "📁 新平台补丁 (patches-6.6):"
    # 添加扫描逻辑
fi
```

### 添加新功能

可以在主程序逻辑中添加新的命令：
```bash
case "${1:-help}" in
    "list")
        list_patches
        ;;
    "view")
        view_patch "$2"
        ;;
    "新命令")
        新功能函数 "$2"
        ;;
    # ...
esac
```

## 故障排除

### 常见问题

#### 1. 权限错误
```bash
# 解决方案：确保脚本可执行
chmod +x patch_helper.sh
```

#### 2. 找不到补丁
```bash
# 确认补丁文件名正确
ls target/linux/imx/patches-6.6/ | grep <部分文件名>
```

#### 3. 目录不存在
```bash
# 确认在正确的 OpenWrt 根目录中
pwd
ls target/linux/
```

### 调试模式

可以在脚本开头添加调试选项：
```bash
#!/bin/bash
set -x  # 开启调试模式
```

## 最佳实践

### 补丁管理工作流

1. **查看现有补丁**
   ```bash
   ./patch_helper.sh list
   ```

2. **分析相关补丁**
   ```bash
   ./patch_helper.sh view <相关补丁>
   ```

3. **添加新补丁后验证**
   ```bash
   ./patch_helper.sh view <新补丁>
   ```

4. **定期检查补丁状态**
   ```bash
   ./patch_helper.sh list | grep -E "9[0-9][0-9]-"  # 查看安全补丁
   ```

### 命名规范

- 使用描述性的补丁文件名
- 遵循数字前缀分类规范
- 包含关键字便于搜索和识别

## 更新历史

- **v1.0** - 基础功能：列表显示、补丁查看
- **v1.1** - 添加平台自动识别
- **v1.2** - 优化输出格式，添加 emoji 图标

## 联系和支持

此工具作为 OpenWrt CVE 补丁制作流程的配套工具，与以下文档配合使用：
- `CVE_PATCH_WORKFLOW.md` - CVE 补丁制作标准流程
- `SVN_CVE_PATCH_WORKFLOW.md` - SVN 环境下的补丁制作流程

如需扩展功能或报告问题，请参考相关的工作流程文档。
