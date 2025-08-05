# OpenWrt CVE 补丁制作标准流程

## 概述
本文档介绍在 OpenWrt 框架下制作 Linux 内核 CVE 补丁的标准流程，确保补丁包含完整的原始作者信息和正确的格式。

## 示例 CVE
- **CVE 链接**: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?id=654b33ada4ab5e926cd9c570196fefa7bec7c1df
- **问题**: proc 文件系统中的 UAF (Use-After-Free) 漏洞
- **作者**: Ye Bin <yebin10@huawei.com>
- **日期**: 2025-03-01 15:06:24 +0300

## 标准制作流程

### 1. 获取原始 CVE 补丁信息
```bash
# 下载原始补丁内容
curl -s "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/patch/?id=654b33ada4ab5e926cd9c570196fefa7bec7c1df" > cve_original.patch

# 分析补丁头部信息
head -20 cve_original.patch

# 查看影响的文件列表
grep "^diff --git\|^---\|^+++" cve_original.patch
```

### 2. 准备内核源码环境
```bash
# 在 OpenWrt 环境中展开内核源码
make target/linux/prepare V=s

# 或者强制展开（在 macOS 等环境中）
FORCE=1 make target/linux/prepare V=s
```

### 3. 手动应用补丁修改
```bash
# 进入内核源码目录
cd build_dir/target-*/linux-*/linux-*

# 根据 CVE 补丁内容手动修改相关文件
# 例如：修改 fs/proc/generic.c, fs/proc/inode.c 等
```

### 4. 生成 OpenWrt 格式补丁
```bash
# 使用 quilt 或 git 生成补丁
quilt new 950-proc-fix-UAF-in-proc_get_inode.patch
quilt add fs/proc/generic.c fs/proc/inode.c fs/proc/internal.h include/linux/proc_fs.h
# 进行修改...
quilt refresh

# 或者使用 git diff 生成
git diff > ../950-proc-fix-UAF-in-proc_get_inode.patch
```

### 5. 添加完整的补丁头部信息
确保补丁包含以下信息：
```patch
From 654b33ada4ab5e926cd9c570196fefa7bec7c1df Mon Sep 17 00:00:00 2001
From: Ye Bin <yebin10@huawei.com>
Date: Sat, 1 Mar 2025 15:06:24 +0300
Subject: [PATCH] proc: fix UAF in proc_get_inode()

[完整的漏洞描述和修复说明]

Signed-off-by: Ye Bin <yebin10@huawei.com>
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>
---
 fs/proc/generic.c         | 10 ++++++++++
 fs/proc/inode.c           |  6 +++---
 fs/proc/internal.h        | 14 ++++++++++++++
 include/linux/proc_fs.h   |  7 +++++--
 4 files changed, 31 insertions(+), 6 deletions(-)
```

### 6. 放置补丁文件
```bash
# 将补丁放置到正确的目录
cp 950-proc-fix-UAF-in-proc_get_inode.patch target/linux/<platform>/patches-<kernel_version>/

# 例如：
cp 950-proc-fix-UAF-in-proc_get_inode.patch target/linux/imx/patches-6.6/
```

### 7. 验证补丁
```bash
# 使用补丁管理工具验证
./patch_helper.sh view 950-proc-fix-UAF-in-proc_get_inode.patch

# 或者直接查看
cat target/linux/imx/patches-6.6/950-proc-fix-UAF-in-proc_get_inode.patch
```

## 补丁命名规范
- 使用数字前缀表示优先级：
  - 000-099: 架构相关的关键补丁
  - 100-199: 平台特定补丁
  - 900-999: CVE 安全补丁
- 描述性文件名：`950-proc-fix-UAF-in-proc_get_inode.patch`

## 注意事项
1. **保留原始作者信息**：必须包含完整的作者姓名、邮箱和时间戳
2. **完整的描述**：保留原始的漏洞描述和修复说明
3. **处理冲突**：如果补丁应用时有冲突，需要手动解决并测试
4. **版本适配**：确保补丁适用于当前 OpenWrt 使用的内核版本
5. **测试验证**：应用补丁后进行编译和功能测试

## 常用命令参考
```bash
# 列出现有补丁
ls -la target/linux/<platform>/patches-<version>/

# 应用单个补丁测试
patch -p1 < target/linux/<platform>/patches-<version>/950-*.patch

# 撤销补丁
patch -R -p1 < target/linux/<platform>/patches-<version>/950-*.patch
```

## 生成的示例补丁
参见：`target/linux/imx/patches-6.6/950-proc-fix-UAF-in-proc_get_inode.patch`

该补丁修复了 proc 文件系统中的 Use-After-Free 漏洞，包含完整的原始作者信息和详细的修复说明。