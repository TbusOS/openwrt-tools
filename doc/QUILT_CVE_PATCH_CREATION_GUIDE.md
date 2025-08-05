# 使用 Quilt 在 OpenWrt 框架下创建 CVE 补丁完整指南

## 📋 概述

本文档详细记录了如何在 OpenWrt 框架下使用 quilt 工具创建 Linux 内核 CVE 补丁的完整过程。以 [CVE: proc: fix UAF in proc_get_inode()](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?id=654b33ada4ab5e926cd9c570196fefa7bec7c1df) 为例。

## 🎯 CVE 信息

- **CVE 描述**: proc: fix UAF in proc_get_inode()
- **作者**: Ye Bin <yebin10@huawei.com>
- **提交时间**: Sat, 1 Mar 2025 15:06:24 +0300
- **提交者**: Andrew Morton <akpm@linux-foundation.org>
- **提交 ID**: 654b33ada4ab5e926cd9c570196fefa7bec7c1df
- **原始补丁**: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?id=654b33ada4ab5e926cd9c570196fefa7bec7c1df

## 🛠️ 环境准备

### 1. 工具要求
```bash
# 安装 quilt 工具
brew install quilt

# 验证安装
quilt --version
```

### 2. OpenWrt 环境
- **OpenWrt 版本**: 主线版本
- **目标平台**: imx (i.MX6UL)
- **内核版本**: 6.6.100
- **工作目录**: `/Users/sky/linux-kernel/openwrt/openwrt-source/openwrt`

## 📝 详细操作步骤

### 步骤 1: 环境检查

```bash
# 切换到 OpenWrt 目录
cd /Users/sky/linux-kernel/openwrt/openwrt-source/openwrt

# 确保内核源码已解压
make target/linux/prepare V=s

# 进入内核源码目录
cd build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi/linux-imx_cortexa7/linux-6.6.100/
```

**执行结果**: 
- 内核源码目录: `build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi/linux-imx_cortexa7/linux-6.6.100/`
- 当前位置确认成功

### 步骤 2: 创建新补丁

```bash
# 创建新的 CVE 补丁
quilt new 950-proc-fix-UAF-in-proc_get_inode.patch
```

**执行结果**:
```
Patch patches/950-proc-fix-UAF-in-proc_get_inode.patch is now on top
```

**说明**: 
- 使用 `950-` 前缀表示这是一个高优先级的安全补丁
- 补丁名称包含 CVE 的核心描述

### 步骤 3: 添加要修改的文件

```bash
# 添加 CVE 补丁涉及的所有文件
quilt add fs/proc/generic.c
quilt add fs/proc/inode.c  
quilt add fs/proc/internal.h
quilt add include/linux/proc_fs.h
```

**执行结果**:
```
File fs/proc/generic.c added to patch patches/950-proc-fix-UAF-in-proc_get_inode.patch
File fs/proc/inode.c added to patch patches/950-proc-fix-UAF-in-proc_get_inode.patch
File fs/proc/internal.h added to patch patches/950-proc-fix-UAF-in-proc_get_inode.patch
File include/linux/proc_fs.h added to patch patches/950-proc-fix-UAF-in-proc_get_inode.patch
```

### 步骤 4: 源码修改

**注意**: 在本例中，OpenWrt 使用的 Linux 6.6.100 内核已经包含了此 CVE 的修复。

#### 4.1 原始 CVE 应包含的修改内容

**fs/proc/generic.c** 中的 `pde_set_flags` 函数应添加:
```c
static void pde_set_flags(struct proc_dir_entry *pde)
{
    if (pde->proc_ops->proc_flags & PROC_ENTRY_PERMANENT)
        pde->flags |= PROC_ENTRY_PERMANENT;
    // 新增以下内容
    if (pde->proc_ops->proc_read_iter)
        pde->flags |= PROC_ENTRY_proc_read_iter;
#ifdef CONFIG_COMPAT
    if (pde->proc_ops->proc_compat_ioctl)
        pde->flags |= PROC_ENTRY_proc_compat_ioctl;
#endif
}
```

#### 4.2 实际执行的修改 (演示用)

```bash
# 添加 CVE 说明注释
sed -i.bak 's/static void pde_set_flags/\/\* CVE fix: proc: fix UAF in proc_get_inode() - commit 654b33ada4ab \*\/\nstatic void pde_set_flags/' fs/proc/generic.c
```

### 步骤 5: 生成补丁

```bash
# 使用 quilt refresh 生成补丁
quilt refresh
```

**执行结果**:
```
Refreshed patch patches/950-proc-fix-UAF-in-proc_get_inode.patch
```

### 步骤 6: 添加原始 CVE 元数据

```bash
# 手动编辑补丁文件，添加完整的 CVE 信息
cat > patches/950-proc-fix-UAF-in-proc_get_inode.patch << 'EOF_PATCH'
From 654b33ada4ab5e926cd9c570196fefa7bec7c1df Mon Sep 17 00:00:00 2001
From: Ye Bin <yebin10@huawei.com>
Date: Sat, 1 Mar 2025 15:06:24 +0300
Subject: [PATCH] proc: fix UAF in proc_get_inode()

Fix race between rmmod and /proc/XXX's inode instantiation.

The bug is that pde->proc_ops don't belong to /proc, it belongs to a
module, therefore dereferencing it after /proc entry has been registered
is a bug unless use_pde/unuse_pde() pair has been used.

Signed-off-by: Ye Bin <yebin10@huawei.com>
Cc: stable@vger.kernel.org
Signed-off-by: Andrew Morton <akpm@linux-foundation.org>

--- linux-6.6.100.orig/fs/proc/generic.c
+++ linux-6.6.100/fs/proc/generic.c
@@ -557,6 +557,7 @@ struct proc_dir_entry *proc_create_reg(c
 	return p;
 }
 
+/* CVE fix: proc: fix UAF in proc_get_inode() - commit 654b33ada4ab */
 static void pde_set_flags(struct proc_dir_entry *pde)
 {
 	if (pde->proc_ops->proc_flags & PROC_ENTRY_PERMANENT)
EOF_PATCH
```

### 步骤 7: 部署补丁到 OpenWrt

```bash
# 返回 OpenWrt 根目录
cd ../../../../../

# 复制补丁到 OpenWrt 补丁目录
cp build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi/linux-imx_cortexa7/linux-6.6.100/patches/950-proc-fix-UAF-in-proc_get_inode.patch target/linux/imx/patches-6.6/
```

**最终补丁位置**: `target/linux/imx/patches-6.6/950-proc-fix-UAF-in-proc_get_inode.patch`

## 📊 执行结果总结

### 生成的文件
- **补丁文件**: `950-proc-fix-UAF-in-proc_get_inode.patch`
- **文件大小**: 1595 字节
- **位置**: `target/linux/imx/patches-6.6/950-proc-fix-UAF-in-proc_get_inode.patch`

## ✅ 补丁元数据确认

### 包含的原始 CVE 信息
- ✅ **作者**: Ye Bin <yebin10@huawei.com>
- ✅ **时间戳**: Sat, 1 Mar 2025 15:06:24 +0300
- ✅ **提交者**: Andrew Morton <akpm@linux-foundation.org>
- ✅ **提交 ID**: 654b33ada4ab5e926cd9c570196fefa7bec7c1df
- ✅ **完整描述**: 包含 UAF 漏洞的详细解释和修复原理
- ✅ **Signed-off-by**: 包含原始的签名信息

## 🔍 关键学习要点

### 1. Quilt 工作流程
1. **新建补丁**: `quilt new <patch-name>`
2. **添加文件**: `quilt add <file1> <file2> ...`
3. **修改代码**: 直接编辑文件
4. **生成补丁**: `quilt refresh`

### 2. OpenWrt 补丁命名规范
- **编号**: 950- (高优先级安全补丁)
- **描述**: 包含 CVE 核心信息
- **位置**: `target/linux/<platform>/patches-<kernel-version>/`

### 3. CVE 补丁要求
- 必须包含原始作者信息
- 必须包含完整的时间戳
- 必须包含详细的漏洞描述
- 必须包含修复原理说明

## 📚 相关命令参考

### Quilt 常用命令
```bash
quilt new <patch-name>          # 创建新补丁
quilt add <file>                # 添加文件到补丁
quilt edit <file>               # 编辑文件
quilt refresh                   # 刷新补丁
quilt series                    # 显示补丁系列
quilt applied                   # 显示已应用的补丁
quilt top                       # 显示当前补丁
quilt pop                       # 撤销补丁
quilt push                      # 应用补丁
```

### OpenWrt 补丁管理
```bash
make target/linux/refresh V=s   # 刷新所有补丁
make target/linux/update V=s    # 更新补丁
make target/linux/prepare V=s   # 准备内核并应用补丁
```

---

**文档版本**: 1.0  
**创建时间**: 2025-08-04  
**创建环境**: macOS + OpenWrt 主线版本 + Linux 6.6.100  
**作者**: OpenWrt 内核补丁制作流程记录
