# OpenWrt Quilt 补丁管理工具使用指南 v5.1

## 📋 概述

本工具是专为 OpenWrt 内核补丁制作设计的自动化 bash 脚本，使用 quilt 命令实现 CVE 补丁的快速制作流程。

## 🆕 v5.1 更新日志

### 重大功能新增 - 智能冲突检测 🔍
- 🧪 **补丁兼容性检测**: 新增 `test-patch` 命令，智能检测补丁与当前内核的兼容性
- 🔍 **自动冲突分析**: 自动检测文件存在性、补丁是否已应用、是否存在冲突
- 🛑 **安全防护机制**: 检测到不兼容时自动阻止危险操作，保护内核代码
- 🚦 **智能流程控制**: `auto-patch` 自动集成兼容性检测，提供安全建议
- 📊 **详细检测报告**: 提供文件统计、冲突详情和解决建议

### 智能决策支持
- ✅ **完全兼容**: 检测到无冲突时，可选择自动继续补丁制作
- ⚠️ **冲突警告**: 发现冲突时，用户可选择继续或安全退出
- 🚨 **不兼容阻止**: 缺失关键文件时，自动终止流程并提供建议

## 🆕 v5.0 更新日志 (保留功能)

### 重大功能新增
- 🧹 **补丁清理功能**: 智能清理补丁和临时文件，支持交互式确认
- 📊 **Quilt 常用命令集成**: 内置 status、series、applied、unapplied、top、files、push、pop 等命令
- 🎨 **友好界面显示**: 为所有 quilt 命令提供格式化输出和状态标识
- 🔧 **补丁状态管理**: 一键查看补丁应用状态和详细信息

### v4.0 功能保留
- 🚀 **自动内核目录查找**: 无需手动切换到内核源码目录，脚本自动查找并切换
- 🎯 **简化工作流程**: 所有命令可直接在 OpenWrt 根目录执行
- 🔍 **智能路径检测**: 支持多种 OpenWrt 目录结构的自动识别
- 📂 **减少操作步骤**: 告别复杂的 `cd build_dir/target-*/linux-*/linux-*/` 操作

### 技术改进
- 🔧 **修复输出混乱**: 解决 fetch_patch 函数的日志和返回值混合问题
- 🌈 **颜色显示优化**: 进一步改进终端兼容性

## 🎯 主要功能

### 1. 根据 commit ID 自动抓取原始补丁
- 从 Linux 内核官方仓库下载补丁
- 支持任意有效的 commit ID
- **重要**: `fetch` 命令下载到临时目录，脚本结束后自动清理

### 2. **智能补丁兼容性检测 (🆕 v5.1)**
- 使用 `test-patch` 命令智能检测补丁兼容性
- 自动检测文件存在性和冲突情况
- 提供详细的兼容性报告和解决建议
- **安全机制**: 自动阻止不兼容补丁的应用

### 3. **保存原始补丁到当前目录**
- 使用 `save` 命令直接保存原始补丁到当前目录
- 支持自定义文件名或使用默认的 commit ID 作为文件名
- **持久保存**: 不会被自动删除

### 4. 创建要修改的文件列表
- 自动解析补丁涉及的所有文件
- 生成 `patch_files.txt` 文件列表 (保存在当前目录，不会被删除)

### 5. 添加文件到 quilt 补丁
- 批量添加文件列表到当前 quilt 补丁
- 自动处理文件存在性检查

### 6. 抓取完整的补丁元数据
- 提取作者信息、时间戳
- 提取补丁描述和签名信息
- 生成 `patch_metadata.txt` 元数据文件 (保存在当前目录，不会被删除)

### 7. 自动内核目录管理
- 自动查找 OpenWrt 内核源码目录
- 智能切换到正确的内核目录
- 支持多种目录结构检测

### 8. 生成新的 CVE 补丁
- 基于 quilt 工作流程
- 保留原始补丁的完整信息

### 9. **Quilt 常用命令集成**
- 内置常用 quilt 命令，提供友好的界面
- 自动状态显示和格式化输出
- 支持补丁系列管理和状态查询
- 包含补丁应用/移除功能

### 9. **补丁清理功能 (v5.0 新增)**
- 智能识别并清理各种临时文件
- 交互式确认避免误删
- 支持内核目录和当前目录清理
- 自动清理 quilt 工作目录

## 🛠️ 安装和依赖

### 系统要求
- macOS 或 Linux 系统
- bash 4.0+

### 必需依赖
```bash
# 基本工具
curl               # 下载补丁 (必需)
quilt              # 补丁管理 (仅内核源码操作需要)

# macOS 安装
brew install quilt

# Ubuntu/Debian 安装
sudo apt-get install quilt
```

## 📁 重要文件路径说明

### 临时文件路径
- **临时目录**: `/tmp/patch_manager_<进程ID>`
- **示例**: `/tmp/patch_manager_3962`
- **特点**: 脚本结束时自动删除，`fetch` 命令使用

### 持久文件路径 (不会被删除)
- **原始补丁**: `./<commit_id>.patch` 或自定义文件名 (使用 `save` 命令)
- **文件列表**: `./patch_files.txt` (当前目录)
- **元数据**: `./patch_metadata.txt` (当前目录)
- **补丁文件**: `./patches/<补丁名称>.patch` (quilt 管理)

### 内核源码目录
- **路径格式**: `build_dir/target-*/linux-*/linux-*/`
- **示例**: `build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi/linux-imx_cortexa7/linux-6.6.100/`

## 📝 使用方法

### 基本命令格式
```bash
./tools/quilt_patch_manager_final.sh <命令> [参数]
```

### 命令分类

#### 📥 任意目录可运行的命令 (基础功能)
这些命令不需要在特定目录运行，主要用于信息提取和演示：

```bash
# 演示所有功能
./tools/quilt_patch_manager_final.sh demo

# 下载原始补丁到临时目录 (脚本结束后删除)
./tools/quilt_patch_manager_final.sh fetch <commit_id>

# 下载并保存原始补丁到当前目录 (持久保存) - 新功能
./tools/quilt_patch_manager_final.sh save <commit_id> [文件名]

# 提取文件列表到当前目录
./tools/quilt_patch_manager_final.sh extract-files <commit_id>

# 提取元数据到当前目录
./tools/quilt_patch_manager_final.sh extract-metadata <commit_id>
```

#### 🔍 智能补丁兼容性检测 (🆕 v5.1)
这是新增的核心安全功能，可以在应用补丁前检测兼容性，避免损坏内核代码：

```bash
# 智能补丁兼容性检测 (强烈推荐在制作补丁前使用)
./tools/quilt_patch_manager_final.sh test-patch <commit_id>

# 检测结果说明：
# ✅ 完全兼容 - 可以安全应用，支持自动继续制作补丁
# ⚠️  有冲突 - 需要手动解决冲突，用户可选择继续或退出
# 🚨 不兼容 - 缺失必要文件，自动阻止应用，防止代码损坏
```

#### 🔧 补丁制作命令 (自动查找内核目录)
这些命令现在可以在 OpenWrt 根目录直接运行，脚本会自动查找并切换到内核源码目录：

```bash
# ⚠️ 正确的使用顺序 (手动制作补丁)：
# 1. 先创建补丁 (自动查找内核目录)
./tools/quilt_patch_manager_final.sh create-patch <补丁名称> [commit_id]

# 2. 再添加文件到 quilt 补丁 (需要已创建补丁)
./tools/quilt_patch_manager_final.sh add-files <file_list.txt>

# 3. 手动修改内核源码文件 (根据原始补丁内容)
# 4. 生成最终补丁
./tools/quilt_patch_manager_final.sh refresh

# 💡 或者使用自动化完整补丁制作 (推荐)
./tools/quilt_patch_manager_final.sh auto-patch <commit_id> <补丁名称>
```

#### 🧹 清理命令 (v5.0 新增)
```bash
# 清理补丁和临时文件 (交互式确认)
./tools/quilt_patch_manager_final.sh clean
```

#### 📊 Quilt 状态管理命令 (v5.0 新增)
这些命令提供友好的 quilt 状态显示，自动查找内核目录：

```bash
# 显示补丁状态概览
./tools/quilt_patch_manager_final.sh status

# 显示补丁系列列表 (标记已应用/未应用状态)
./tools/quilt_patch_manager_final.sh series

# 显示已应用的补丁
./tools/quilt_patch_manager_final.sh applied

# 显示未应用的补丁
./tools/quilt_patch_manager_final.sh unapplied

# 显示当前顶部补丁
./tools/quilt_patch_manager_final.sh top

# 显示当前补丁涉及的文件
./tools/quilt_patch_manager_final.sh files

# 显示指定补丁涉及的文件
./tools/quilt_patch_manager_final.sh files <补丁名称>
```

#### 📌 Quilt 补丁应用/移除命令 (v5.0 新增)
```bash
# 应用下一个补丁
./tools/quilt_patch_manager_final.sh push

# 应用指定补丁
./tools/quilt_patch_manager_final.sh push <补丁名称>

# 应用所有补丁
./tools/quilt_patch_manager_final.sh push -a

# 移除当前补丁
./tools/quilt_patch_manager_final.sh pop

# 移除指定补丁
./tools/quilt_patch_manager_final.sh pop <补丁名称>

# 移除所有补丁
./tools/quilt_patch_manager_final.sh pop -a

# 生成/更新补丁文件 (将修改写入补丁)
./tools/quilt_patch_manager_final.sh refresh
```

**🎯 重要改进**: 不再需要手动执行 `cd build_dir/target-*/linux-*/linux-*/`！

## 🔍 test-patch 命令详细说明 (🆕 v5.1)

### 功能概述
`test-patch` 是新增的智能补丁兼容性检测命令，能够在应用补丁前安全地检测其与当前内核的兼容性，避免损坏内核代码。

### 基本用法
```bash
# 检测补丁兼容性
./tools/quilt_patch_manager_final.sh test-patch <commit_id>

# 示例
./tools/quilt_patch_manager_final.sh test-patch 654b33ada4ab5e926cd9c570196fefa7bec7c1df
```

### 检测流程 (5个步骤)
1. **📥 下载原始补丁** - 从内核官方仓库获取补丁
2. **📂 检查内核目录** - 自动定位 OpenWrt 内核源码
3. **🔍 分析补丁文件** - 提取补丁涉及的所有文件
4. **📋 检查文件存在性** - 验证目标文件是否存在
5. **🧪 干运行补丁测试** - 使用 patch --dry-run 安全测试

### 兼容性结果类型

#### ✅ 完全兼容 (退出码 0)
- 所有文件存在且无冲突
- 可以安全应用补丁
- 提供自动创建 OpenWrt 补丁的选项

#### ⚠️ 有冲突 (退出码 1)
- 文件存在但内容有冲突
- 需要手动解决冲突
- 提供冲突详情和解决建议

#### 🚨 不兼容 (退出码 2)
- 缺失关键文件
- 内核版本不匹配
- 自动阻止应用，防止代码损坏

### 输出示例

#### 完全兼容的情况
```bash
🎉 结果: 补丁完全兼容 - 可以直接应用

✅ 补丁测试详情:
  checking file fs/proc/generic.c
  checking file fs/proc/inode.c
  checking file fs/proc/internal.h
  checking file include/linux/proc_fs.h

💡 建议: 可以安全地应用此补丁
   • 使用 auto-patch 命令自动创建 OpenWrt 补丁
   • 或按照手动流程逐步创建补丁

🤔 是否要立即创建 OpenWrt 补丁? (y/N):
```

#### 有冲突的情况
```bash
⚠️ 结果: 补丁有冲突 - 需要手动解决

🔍 冲突详情:
  patching file fs/proc/generic.c
  Hunk #1 FAILED at 123.
  1 out of 1 hunk FAILED

⚠️ 建议: 存在冲突，需要手动处理
   • 检查冲突的具体内容
   • 手动修改相关文件以解决冲突
   • 使用手动补丁创建流程
   • 考虑修改补丁内容以适配当前内核

🛑 警告: 不要直接应用此补丁，会导致代码损坏
```

### 最佳实践
1. **总是先检测**: 在制作补丁前，总是使用 `test-patch` 检测兼容性
2. **安全退出**: 如果检测到不兼容，立即停止并检查内核版本
3. **解决冲突**: 对于有冲突的补丁，先手动解决冲突再使用手动流程
4. **自动继续**: 对于完全兼容的补丁，可选择自动继续创建 OpenWrt 补丁

## 🚀 save 命令详细说明

### 基本用法
```bash
# 使用默认文件名 (commit_id.patch)
./tools/quilt_patch_manager_final.sh save 654b33ada4ab5e926cd9c570196fefa7bec7c1df

# 使用自定义文件名
./tools/quilt_patch_manager_final.sh save 654b33ada4ab5e926cd9c570196fefa7bec7c1df proc-uaf-fix.patch

# 不带 .patch 扩展名 (会自动添加)
./tools/quilt_patch_manager_final.sh save 654b33ada4ab5e926cd9c570196fefa7bec7c1df proc-uaf-fix
```

### 输出示例
```bash
$ ./quilt_patch_manager_final.sh save 654b33ada4ab5e926cd9c570196fefa7bec7c1df
[SUCCESS] 原始补丁已保存到: 654b33ada4ab5e926cd9c570196fefa7bec7c1df.patch
[INFO] 文件大小: 6371 字节
[INFO] 文件位置: /current/directory/654b33ada4ab5e926cd9c570196fefa7bec7c1df.patch
```

### 与 fetch 命令的区别
| 命令 | 保存位置 | 持久性 | 用途 |
|------|----------|--------|------|
| `fetch` | 临时目录 | 脚本结束时删除 | 内部处理使用 |
| `save` | 当前目录 | 永久保存 | 用户保存原始补丁 |

## 🚀 完整工作流程示例

### 场景：为 OpenWrt 制作 proc UAF CVE 补丁

#### 步骤 1: 演示功能了解工具 (任意目录)
```bash
cd /any/directory
./quilt_patch_manager_final.sh demo
```
**输出**:
- 临时目录: `/tmp/patch_manager_<PID>/` (自动清理)
- 持久文件: `patch_files.txt`, `patch_metadata.txt`, `demo_*.patch` (保留)

#### 步骤 2: 保存原始补丁 (任意目录) - 新功能
```bash
# 保存原始补丁供参考
./quilt_patch_manager_final.sh save 654b33ada4ab5e926cd9c570196fefa7bec7c1df proc-uaf-original.patch

# 提取文件列表
./quilt_patch_manager_final.sh extract-files 654b33ada4ab5e926cd9c570196fefa7bec7c1df

# 提取元数据信息
./quilt_patch_manager_final.sh extract-metadata 654b33ada4ab5e926cd9c570196fefa7bec7c1df
```

#### 步骤 3: 直接执行自动化补丁制作 🆕 v4.0
```bash
# 现在可以直接在 OpenWrt 根目录运行，无需手动切换目录！
./quilt_patch_manager_final.sh auto-patch 654b33ada4ab5e926cd9c570196fefa7bec7c1df 950-proc-fix-UAF
```
**🎯 重大改进**: 脚本会自动查找并切换到内核源码目录！

#### 步骤 4: 手动修改源码文件
根据工具提示和生成的文件列表，手动修改相应的源码文件

#### 步骤 5: 完成补丁生成
按回车继续，工具会自动生成最终补丁

## 📊 输出文件详细说明

### 1. 原始补丁文件 (新功能)
**位置**: 当前执行目录
**命名**: `<commit_id>.patch` 或自定义名称
**内容**: 完整的原始内核补丁
**获取**: 使用 `save` 命令
**示例**:
```bash
# 默认命名
654b33ada4ab5e926cd9c570196fefa7bec7c1df.patch

# 自定义命名
proc-uaf-fix.patch
```

### 2. patch_files.txt (持久文件)
**位置**: 当前执行目录
**内容示例**:
```
fs/proc/generic.c
fs/proc/inode.c
fs/proc/internal.h
include/linux/proc_fs.h
```
**说明**: 包含补丁涉及的所有文件路径，不会被自动删除

### 3. patch_metadata.txt (持久文件)
**位置**: 当前执行目录
**内容示例**:
```
# ======================================
# CVE 补丁元数据信息
# ======================================
# 生成时间: Mon Aug  4 22:30:00 CST 2025
# Commit ID: 654b33ada4ab5e926cd9c570196fefa7bec7c1df
# 原始补丁 URL: https://git.kernel.org/...

## 基本信息
作者: From: Ye Bin <yebin10@huawei.com>
日期: Date: Sat, 1 Mar 2025 15:06:24 +0300
主题: Subject: [PATCH] proc: fix UAF in proc_get_inode()

## 补丁描述
Fix race between rmmod and /proc/XXX's inode instantiation.
...

## 签名和标签信息
Signed-off-by: Ye Bin <yebin10@huawei.com>
Cc: stable@vger.kernel.org
```
**说明**: 包含完整的补丁信息，不会被自动删除

### 4. patches/<补丁名称>.patch (quilt 管理)
**位置**: 内核源码目录的 `patches/` 子目录
**说明**: 最终生成的 OpenWrt 格式补丁文件

### 5. /tmp/patch_manager_<PID>/ (临时目录)
**位置**: 系统临时目录
**内容**: `fetch` 命令下载的临时补丁文件
**重要**: 脚本结束时自动删除，无法持久保存

## ⚠️ 重要注意事项

### 1. 临时文件 vs 持久文件对比

| 文件类型 | 命令 | 保存位置 | 清理机制 | 用途 |
|----------|------|----------|----------|------|
| 临时文件 | `fetch` | `/tmp/patch_manager_<PID>/` | 自动删除 | 内部处理 |
| 持久文件 | `save` | 当前目录 | 永久保存 | 用户保存 |
| 持久文件 | `extract-*` | 当前目录 | 永久保存 | 信息提取 |

### 2. 如何选择使用 fetch vs save

**使用 `fetch`**:
- 只需要内部处理，不需要保存文件
- 配合其他命令使用 (`extract-files`, `extract-metadata`)

**使用 `save`**:
- 需要保留原始补丁文件供后续参考
- 想要离线查看补丁内容
- 需要与其他工具配合使用原始补丁

### 3. 文件权限
确保脚本有执行权限：
```bash
chmod +x quilt_patch_manager_final.sh
```

### 4. 网络要求
- 需要能够访问 `git.kernel.org`
- 下载失败时会显示具体错误信息

## 🔧 高级用法

### 1. 批量保存多个补丁
```bash
commits=("commit1" "commit2" "commit3")
for commit in "${commits[@]}"; do
    ./quilt_patch_manager_final.sh save $commit "${commit}_patch.patch"
done
```

### 2. 🔍 推荐工作流程：安全补丁制作 (v5.1 新增)
```bash
commit_id="654b33ada4ab5e926cd9c570196fefa7bec7c1df"

# 第1步: 智能兼容性检测 (强烈推荐)
./quilt_patch_manager_final.sh test-patch $commit_id

# 根据检测结果选择后续操作：
# ✅ 完全兼容 -> 可选择自动继续或手动制作
# ⚠️  有冲突 -> 手动制作，需要解决冲突
# 🚨 不兼容 -> 停止，检查内核版本或寻找其他补丁

# 第2步: 如果兼容，保存原始补丁供参考
./quilt_patch_manager_final.sh save $commit_id original.patch

# 第3步: 提取补丁信息
./quilt_patch_manager_final.sh extract-files $commit_id
./quilt_patch_manager_final.sh extract-metadata $commit_id

# 第4步: 自动制作补丁 (如果兼容性检测通过)
./quilt_patch_manager_final.sh auto-patch $commit_id 950-proc-fix-UAF

# 现在有了完整的补丁分析包
ls -la *.patch *.txt
```

### 3. 组合使用 save 和 extract 命令 (传统方式)
```bash
commit_id="654b33ada4ab5e926cd9c570196fefa7bec7c1df"

# 保存原始补丁
./quilt_patch_manager_final.sh save $commit_id original.patch

# 提取信息
./quilt_patch_manager_final.sh extract-files $commit_id
./quilt_patch_manager_final.sh extract-metadata $commit_id

# 现在有了完整的补丁分析包
ls -la *.patch *.txt
```

### 4. 验证补丁文件完整性
```bash
# 保存补丁后验证
saved_patch="proc-uaf-fix.patch"
./quilt_patch_manager_final.sh save 654b33ada4ab5e926cd9c570196fefa7bec7c1df $saved_patch

# 检查文件大小和内容
ls -la $saved_patch
head -10 $saved_patch
```

## 🐛 故障排除

### 1. save 命令失败
**问题**: 无法保存补丁到当前目录
**可能原因**: 
- 网络连接问题
- 当前目录权限不足
- commit ID 无效

**解决方案**:
```bash
# 检查网络连接
curl -I https://git.kernel.org

# 检查目录权限
ls -la .

# 验证 commit ID
./quilt_patch_manager_final.sh fetch <commit_id>
```

### 2. 文件名冲突
**问题**: 保存时文件已存在
**解决**: 使用不同的文件名或先删除现有文件
```bash
# 使用时间戳避免冲突
./quilt_patch_manager_final.sh save $commit_id "patch_$(date +%Y%m%d_%H%M%S).patch"
```

### 3. add-files 命令失败 🆕 v5.0
**问题**: 脚本提示"请先创建 quilt 补丁，使用: quilt new <patch_name>"
**原因**: 在没有 quilt 环境时直接使用 add-files 命令

**✅ 正确的解决方案**:
```bash
# 方法1: 使用 create-patch 先创建补丁
./tools/quilt_patch_manager_final.sh create-patch my-patch-name

# 然后再添加文件
./tools/quilt_patch_manager_final.sh add-files patch_files.txt

# 方法2: 直接使用自动化命令 (推荐)
./tools/quilt_patch_manager_final.sh auto-patch <commit_id> <patch_name>
```

### 4. 自动内核目录查找失败 🆕 v4.0
**问题**: 脚本提示"未找到 OpenWrt 内核源码目录"
**可能原因**:
- 尚未执行 `make target/linux/prepare` 解压内核
- 目录结构不是标准的 OpenWrt 结构
- 权限不足

**解决方案**:
```bash
# 1. 首先解压内核源码
make target/linux/prepare V=s

# 2. 检查内核目录是否存在
find . -name "linux-*" -type d | grep build_dir

# 3. 手动验证内核目录
ls -la build_dir/target-*/linux-*/linux-*/Makefile

# 4. 如果仍有问题，手动切换到内核目录后运行
cd build_dir/target-*/linux-*/linux-*/
/path/to/quilt_patch_manager_final.sh <command>
```

## 📚 相关文档

- [OpenWrt 官方文档](https://openwrt.org/docs/)
- [Quilt 官方文档](https://savannah.nongnu.org/projects/quilt)
- [Linux 内核补丁指南](https://www.kernel.org/doc/html/latest/process/submitting-patches.html)

## 🎯 最佳实践

### 1. 推荐工作流程
1. 使用 `save` 命令保存原始补丁供参考
2. 使用 `extract-files` 和 `extract-metadata` 提取分析信息
3. 在内核源码目录使用 `auto-patch` 完成补丁制作
4. 使用 `quilt` 命令验证补丁状态

### 2. 文件管理建议
- 为重要的 CVE 补丁创建专门的目录
- 使用有意义的文件名而不是 commit ID
- 保留原始补丁、文件列表和元数据作为完整包

### 3. 命令选择指南
- **需要保存文件**: 使用 `save`
- **只需内部处理**: 使用 `fetch`
- **信息提取**: 使用 `extract-*`
- **完整流程**: 使用 `auto-patch`

---

**版本**: 4.0  
**更新时间**: 2025-08-04  
**适用系统**: macOS / Linux  
**作者**: OpenWrt 补丁管理工具开发团队

## 📋 更新日志

### v4.0 (2025-08-04) 🚀 重大更新
- 🚀 **自动内核目录查找**: 脚本自动查找并切换到 OpenWrt 内核源码目录
- 🎯 **简化工作流程**: 所有命令可直接在 OpenWrt 根目录执行
- 🔍 **智能路径检测**: 支持多种 OpenWrt 目录结构的自动识别
- 📂 **告别手动切换**: 无需执行 `cd build_dir/target-*/linux-*/linux-*/`
- 🔧 **修复输出混乱**: 解决 fetch_patch 函数的日志和返回值混合问题
- 🌈 **颜色显示优化**: 进一步改进终端兼容性

### v3.0 (2025-08-04)
- ✅ **新增 save 命令**: 支持保存原始补丁到当前目录
- ✅ 支持自定义文件名或使用默认 commit ID 作为文件名
- ✅ 自动添加 .patch 扩展名
- ✅ 在 auto-patch 流程中自动保存原始补丁供参考
- ✅ 完善帮助信息，明确区分临时文件和持久文件
- ✅ 更新演示功能，展示 save 命令的使用

### v2.0 (2025-08-04)
- ✅ 完善帮助信息，详细说明临时目录机制
- ✅ 增加彩色输出和更好的用户界面
- ✅ 明确区分临时文件和持久文件

### v1.0 (2025-08-04)
- ✅ 初始版本，支持基本的补丁管理功能
