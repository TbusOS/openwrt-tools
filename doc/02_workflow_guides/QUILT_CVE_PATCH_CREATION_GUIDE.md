# 使用 v6.0 补丁工具在 OpenWrt 中创建 CVE 补丁 (重构版)

## 📋 概述

本文档将演示如何使用**新版 v6.0 补丁管理工具**，以一种高度自动化的方式在 OpenWrt 框架下创建 Linux 内核 CVE 补丁。我们将彻底告别繁琐的手动 `quilt` 命令。

我们将以 [CVE: proc: fix UAF in proc_get_inode()](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?id=654b33ada4ab5e926cd9c570196fefa7bec7c1df) 为例。

## 🎯 CVE 信息

- **CVE 描述**: `proc: fix UAF in proc_get_inode()`
- **提交 ID**: `654b33ada4ab5e926cd9c570196fefa7bec7c1df`
- **补丁名称 (示例)**: `950-proc-fix-UAF-in-proc_get_inode.patch`

## 🚀 新版工作流程 (v6.0)

新版工具的核心是 `auto-patch` 命令，它将过去繁杂的步骤整合为一体。您不再需要手动进入内核目录，也不再需要手动执行 `quilt new`、`quilt add` 或 `quilt refresh`。

### 步骤 1: 环境准备 (OpenWrt 根目录)

确保您的 OpenWrt 环境已准备就绪。最关键的一步是确保内核源码已经解压。

```bash
# 切换到 OpenWrt 源码根目录
cd /path/to/openwrt

# 确保内核源码已解压 (如果尚未操作)
make target/linux/prepare V=s
```

### 步骤 2: (可选但推荐) 补丁兼容性测试

在正式制作补丁前，先用 `test-patch` 命令检查该 CVE 补丁与您当前内核版本的兼容性。

```bash
# 在 OpenWrt 根目录直接运行
./tools/quilt_patch_manager_final.sh test-patch 654b33ada4ab
```
工具会自动分析并给出报告：是否兼容、是否存在文件冲突等。

### 步骤 3: 一键制作 CVE 补丁 (`auto-patch`)

这是制作补丁的**核心步骤**。只需一行命令，工具即可完成所有后台工作。

```bash
# 在 OpenWrt 根目录直接运行
# 用法: ./script.sh auto-patch <commit_id> <patch_name>
./tools/quilt_patch_manager_final.sh auto-patch 654b33ada4ab 950-proc-fix-UAF-in-proc_get_inode.patch
```

#### 🔄 `auto-patch` 详细执行流程

当您运行上述命令后，工具将自动执行以下四个步骤：

**🔍 步骤 1/4: 自动兼容性测试**
```
[INFO] --- 步骤 1/4: 兼容性测试 ---
[INFO] 测试 commit 654b33ada4ab 的补丁兼容性...
[SUCCESS] 找到内核源码目录: /path/to/openwrt/build_dir/target-mips_24kc_musl/linux-ath79_generic/linux-5.15.162
[INFO] 开始干跑 (dry-run) 测试...
[SUCCESS] 🎉 补丁完全兼容！
```
- 自动从 `git.kernel.org` 下载原始补丁并缓存
- 执行 `patch --dry-run` 测试兼容性
- 如果有冲突，会显示详细的冲突文件和行号

**🆕 步骤 2/4: 创建补丁并添加文件**
```
[INFO] --- 步骤 2/4: 创建补丁并添加文件 ---
[INFO] 准备创建新补丁: 950-proc-fix-UAF-in-proc_get_inode.patch
[SUCCESS] 补丁 '950-proc-fix-UAF-in-proc_get_inode.patch' 创建成功
[INFO] 提取 commit 654b33ada4ab 涉及的文件列表...
[SUCCESS] 找到 1 个文件，已保存到: patch_manager_work/outputs/patch_files.txt
[SUCCESS] 批量添加 1 个文件完成。
```
- 自动执行 `quilt new` 创建新补丁
- 提取补丁涉及的所有文件 (如 `fs/proc/inode.c`)
- 使用 `quilt add` 批量添加文件到补丁管理

**⏸️ 步骤 3/4: 等待手动修改**
```
[INFO] --- 步骤 3/4: 等待手动修改 ---
[WARNING] 补丁已创建，文件已添加。现在是手动修改代码以解决冲突的最佳时机。
[INFO] 修改完成后，按 Enter键继续以生成最终补丁...
```
- 此时工具暂停等待您的操作
- 您可以进入内核目录手动修改代码：
  ```bash
  cd build_dir/target-*/linux-*/linux-*/
  # 编辑相关文件，如: vim fs/proc/inode.c
  # 应用您需要的修改，解决冲突或适配代码
  ```
- 修改完成后回到原目录按 Enter 继续

**🎉 步骤 4/4: 生成最终补丁**
```
[INFO] --- 步骤 4/4: 生成带元数据的最终补丁 ---
[INFO] 🔄 [核心] 刷新补丁并注入来自 commit '654b33ada4ab' 的元数据...
[INFO] 元数据头已提取, 正在生成纯代码 diff...
[SUCCESS] 🎉 补丁已成功生成: /path/to/patches/950-proc-fix-UAF-in-proc_get_inode.patch
[SUCCESS] 📄 最终补丁已拷贝到: patch_manager_work/outputs/950-proc-fix-UAF-in-proc_get_inode.patch
[SUCCESS] 🎉 自动化流程完成!
```
- 自动提取原始补丁的元数据 (作者、日期、描述)
- 执行 `quilt refresh` 生成代码差异
- 将元数据和代码差异合并成最终补丁
- 补丁同时保存在内核目录和输出目录

**工具在后台会自动完成以下所有操作:**
1.  **查找内核目录**: 自动定位到 `build_dir/.../linux-x.x.x`。
2.  **创建新补丁**: 自动执行 `quilt new`。
3.  **添加文件**: 自动下载原始补丁，解析涉及的文件，并执行 `quilt add`。

### 步骤 4: 等待手动修改 (如果需要)

在完成上述自动化步骤后，脚本会暂停并显示以下信息：
> `补丁已创建，文件已添加。现在是手动修改代码以解决冲突的最佳时机。`
> `修改完成后，按 Enter 键继续以生成最终补丁...`

此时，如果 `test-patch` 报告了冲突，或者您需要对补丁进行适配，您可以：
1.  打开一个新的终端。
2.  `cd` 进入内核源码目录（路径在 `auto-patch` 的输出日志中可以看到）。
3.  手动编辑需要修改的文件。

如果您在上游找到的补丁是完全兼容的，那么**通常不需要任何手动修改**。

### 步骤 5: 生成最终补丁

在您完成手动修改（或无需修改）后，回到运行脚本的终端，直接按 `Enter` 键。

工具会自动执行 `refresh-with-header`，完成以下操作：
1.  **生成补丁**: 执行 `quilt refresh` 生成代码的 diff。
2.  **注入元数据**: **自动**从原始 commit 抓取作者、日期、提交信息等完整的元数据，并将其注入到补丁文件的头部。
3.  **拷贝补丁**: 将最终生成的、包含完整元数据的补丁文件拷贝到 OpenWrt 根目录下的 `output/` 文件夹中。

**执行结果**:
您会在 `output/` 目录下找到最终的补丁文件 `950-proc-fix-UAF-in-proc_get_inode.patch`。

### 步骤 6: 部署补丁

最后，将生成好的补丁从 `output` 目录拷贝到您的目标补丁目录。

```bash
# 示例
cp output/950-proc-fix-UAF-in-proc_get_inode.patch target/linux/imx/patches-6.6/
```

## ✨ 新旧流程对比

| 环节 | 旧流程 (手动 Quilt) | 新流程 (v6.0 工具) | 优势 |
| :--- | :--- | :--- | :--- |
| **目录切换** | `cd build_dir/.../linux-x.x.x` | 在 OpenWrt 根目录执行 | 简化操作 |
| **创建补丁** | `quilt new ...` | `auto-patch` 自动完成 | 自动化 |
| **添加文件** | `quilt add file1`, `quilt add file2`... | `auto-patch` 自动完成 | 自动化，防遗漏 |
| **代码修改** | 手动修改 | 手动修改 | (相同) |
| **生成补丁** | `quilt refresh` | `auto-patch` 流程中按回车即可 | 自动化 |
| **元数据** | 手动打开文件，复制粘贴 | `auto-patch` 自动注入 | **核心优势**，保证信息完整无误 |
| **最终产物** | 在内核 `patches` 目录 | 在 `output` 目录，清晰隔离 | 易于管理 |

## ✅ 补丁元数据确认

使用新工具生成的补丁，会自动包含所有必需的元数据，无需手动检查和添加：

- ✅ **作者**: `From: Ye Bin <yebin10@huawei.com>`
- ✅ **时间戳**: `Date: Sat, 1 Mar 2025 15:06:24 +0300`
- ✅ **提交信息**: 完整的原始提交信息
- ✅ **签名信息**: `Signed-off-by` 等

---
**文档版本**: 2.0 (v6.0 工具版)  
**更新时间**: 2024-08-05
