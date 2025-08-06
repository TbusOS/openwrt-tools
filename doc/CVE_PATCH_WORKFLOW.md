# OpenWrt CVE 补丁制作标准流程 (v6.0 工具版)

## 概述

本文档介绍在 OpenWrt 框架下制作 Linux 内核 CVE 补丁的**新版标准流程**。该流程基于 `quilt_patch_manager_final.sh` v6.0+ 版本，旨在通过自动化工具取代繁琐的手动操作，确保补丁制作的效率和规范性。

## 示例 CVE

- **CVE**: `proc: fix UAF in proc_get_inode()`
- **Commit ID**: `654b33ada4ab5e926cd9c570196fefa7bec7c1df`

## 新版标准制作流程 (v6.0+)

旧的手动流程（手动下载、手动修改、手动生成补丁、手动粘贴头部）已被淘汰。新版标准流程的核心是使用 `auto-patch` 命令。

### 步骤 1: 准备环境

在 OpenWrt 根目录下，确保内核源码已解压。

```bash
# 在 OpenWrt 源码根目录
make target/linux/prepare V=s
```

### 步骤 2: (可选但推荐) 运行兼容性测试

在制作任何补丁前，先用工具的 `test-patch` 功能检查其与当前内核的兼容性。

```bash
# 在 OpenWrt 根目录运行
./tools/quilt_patch_manager_final.sh test-patch 654b33ada4ab
```
> 工具会给出详细报告，告知是否存在文件缺失或代码冲突。

### 步骤 3: 执行一键式补丁制作

使用 `auto-patch` 命令完成绝大部分工作。

```bash
# 在 OpenWrt 根目录运行
./tools/quilt_patch_manager_final.sh auto-patch 654b33ada4ab 950-proc-fix-UAF-in-proc_get_inode.patch
```

工具会自动处理：
- 创建 quilt 补丁
- 添加所有相关文件
- **暂停并等待用户进行必要的手动修改** (如果 `test-patch` 提示有冲突)

### 步骤 4: 生成并获取最终补丁

当您根据提示完成手动修改后（如果需要），按 `Enter` 键，工具将：
- 自动生成补丁 (`quilt refresh`)。
- **自动注入完整的元数据头** (作者、日期、提交信息等)。
- 将最终成品拷贝到 `output/` 目录。

### 步骤 5: 部署补丁

将 `output/` 目录中生成的规范化补丁，拷贝到目标平台的补丁目录。

```bash
# 示例
cp output/950-proc-fix-UAF-in-proc_get_inode.patch target/linux/imx/patches-6.6/
```

### 步骤 6: 验证

您可以直接查看最终生成的补丁文件，确认其头部信息是否完整。

```bash
cat output/950-proc-fix-UAF-in-proc_get_inode.patch | head
```
**预期输出应包含:**
```patch
From 654b33ada4ab5e926cd9c570196fefa7bec7c1df Mon Sep 17 00:00:00 2001
From: Ye Bin <yebin10@huawei.com>
Date: Sat, 1 Mar 2025 15:06:24 +0300
Subject: [PATCH] proc: fix UAF in proc_get_inode()

[完整的漏洞描述和修复说明]
...
```

## 补丁制作要点

1.  **自动化优先**: 始终优先使用 `auto-patch` 命令，避免手动操作引入的错误。
2.  **元数据完整性**: 新工具自动保证 `From:`, `Date:`, `Subject:` 等元数据的完整性，这是 CVE 补丁的强制要求。
3.  **命名规范**: 遵循 OpenWrt 的补丁命名规范（如 `950-` 前缀用于安全补丁）。
4.  **先测试再制作**: `test-patch` 是保证补丁质量的关键第一步。
5.  **产物隔离**: 所有中间文件和最终产物都在 `output/` 目录，保持工作区整洁。

---
**文档版本**: 2.0 (v6.0 工具版)
**更新时间**: 2024-08-05
