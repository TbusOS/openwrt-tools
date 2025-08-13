# OpenWrt 内核补丁管理工具 - 快速入门指南

## 📋 目录

1. [前期准备](#前期准备)
2. [补丁获取与测试](#补丁获取与测试)
3. [两种制作流程](#两种制作流程)
   - [情况一：已知修改文件的补丁制作](#情况一已知修改文件的补丁制作)
   - [情况二：冲突补丁的制作（使用快照）](#情况二冲突补丁的制作使用快照)

---

## 前期准备

### 配置全局工作目录

编辑配置文件：`kernel_snapshot_tool/.kernel_snapshot.conf`

```bash
default_workspace_dir=/home/zhangbh/CVE/test/test-kernel/xx/build_dir/linux-imx6ul_imx6_pax/linux-4.1.15
```

### 编译工具

```bash
cd kernel_snapshot_tool
make
```

---

## 补丁获取与测试

### 1. 下载补丁

```bash
./quilt_patch_manager_final.sh save 654b33ada4ab5e926cd9c570196fefa7bec7c1df
```

### 2. 测试补丁兼容性

```bash
./quilt_patch_manager_final.sh test-patch 654b33ada4ab5e926cd9c570196fefa7bec7c1df
```

**测试目的：**
- 检查target目标架构下是否存在补丁相关文件
- 检查build_dir内核目录下的代码是否与补丁存在冲突

**示例输出：**
```
[INFO] 测试 '654b33ada4ab5e926cd9c570196fefa7bec7c1df' 的补丁兼容性...
[SUCCESS] ✅ 未发现与现有补丁的文件冲突。
[WARNING] ⚠️  补丁存在冲突或问题！正在启动智能分析器...
```

**查看冲突分析报告：**
```bash
cat patch_manager_work/outputs/test-patch-report-654b33a.log
```

### 3. 提取补丁信息（可选 - CVE补丁需要）

#### 提取修改文件列表
```bash
./quilt_patch_manager_final.sh extract-files patch_manager_work/outputs/654b33ada4ab5e926cd9c570196fefa7bec7c1df.patch
```

#### 提取补丁元数据
```bash
./quilt_patch_manager_final.sh extract-metadata patch_manager_work/outputs/654b33ada4ab5e926cd9c570196fefa7bec7c1df.patch
```

---

## 两种制作流程

根据不同情况选择合适的工作流程：

---

## 情况一：已知修改文件的补丁制作

> **适用场景：** 已经明确要修改哪些文件，只是不确定具体修改内容的情况

### 步骤 1: 创建新补丁

```bash
./quilt_patch_manager_final.sh create-patch my.patch
```

### 步骤 2: 查看当前状态

```bash
./quilt_patch_manager_final.sh status
```

**输出示例：**
```
📦 补丁总数: 585
✅ 已应用: 585  
❌ 未应用: 0
🔝 顶部补丁: patches/my.patch
```

### 步骤 3: 添加要跟踪的文件

```bash
./quilt_patch_manager_final.sh add-files patch_manager_work/outputs/patch_files.txt
```

### 步骤 4: 验证跟踪文件

```bash
./quilt_patch_manager_final.sh files
```

**输出示例：**
```
fs/proc/generic.c
fs/proc/inode.c
fs/proc/internal.h
include/linux/proc_fs.h
```

### 步骤 5: 修改代码

```bash
# 在此步骤修改相关文件
# ... 编辑代码 ...
```

### 步骤 6: 生成补丁

#### 生成纯净内核补丁
```bash
./quilt_patch_manager_final.sh refresh
```

#### 生成带元数据的CVE补丁
```bash
./quilt_patch_manager_final.sh refresh-with-header
```

**最终输出：** `patch_manager_work/outputs/my.patch`

---

## 情况二：冲突补丁的制作（使用快照）

> **适用场景：** 补丁存在冲突，且修改文件数量与原补丁不同（通常是内核版本不匹配）

### 步骤 1: 创建基线快照

```bash
./quilt_patch_manager_final.sh snapshot-create
```

### 步骤 2: 检查快照状态

```bash
./quilt_patch_manager_final.sh snapshot-status
```

**初始状态示例：**
```
✅ 没有变更

📈 变更统计:
  🆕 新增文件: 0
  ✏️  修改文件: 0
  🗑️  删除文件: 0
  ✅ 未变更: 37739
```

### 步骤 3: 修改代码

```bash
# 根据补丁内容修改相关文件
# ... 编辑代码 ...
```

### 步骤 4: 查看变更状态

```bash
./quilt_patch_manager_final.sh snapshot-status
```

**修改后状态示例：**
```
📝 修改的文件:
M	init/main.c

🆕 新增的文件:
A	a.c

📈 变更统计:
  🆕 新增文件: 1
  ✏️  修改文件: 1
  📊 总变更: 2
```

### 步骤 5: 列出变更文件

```bash
./quilt_patch_manager_final.sh snapshot-list-changes
```

**输出：** 变更文件列表保存到 `patch_manager_work/changed_files.txt`

### 步骤 6: 导出变更文件（可选）

```bash
./quilt_patch_manager_final.sh export-changed-files
```

**查看导出结构：**
```bash
tree patch_manager_work/outputs/changed_files
```

**输出示例：**
```
patch_manager_work/outputs/changed_files/
├── EXPORT_INDEX.txt
└── linux-4.1.15
    ├── a.c
    └── init
        └── main.c
```

### 步骤 7: 准备编译环境

```bash
# 在 OpenWrt 根目录下执行
make distclean
cp configs/xx .config
make menuconfig
make V=s target/linux/prepare
```

### 步骤 8: 制作补丁

接下来按照 [情况一](#情况一已知修改文件的补丁制作) 的步骤制作补丁：

1. 创建补丁文件
2. 添加跟踪文件（使用 `patch_manager_work/changed_files.txt`）
3. 生成最终补丁

---

## 📚 相关命令参考

| 命令 | 描述 |
|------|------|
| `save <commit_id>` | 下载并保存补丁 |
| `test-patch <commit_id>` | 测试补丁兼容性 |
| `extract-files <patch>` | 提取补丁修改的文件列表 |
| `extract-metadata <patch>` | 提取补丁元数据 |
| `create-patch <name>` | 创建新的空补丁 |
| `add-files <file_list>` | 添加文件到补丁跟踪 |
| `refresh` | 生成纯净补丁 |
| `refresh-with-header` | 生成带元数据的补丁 |
| `snapshot-create` | 创建快照基线 |
| `snapshot-status` | 查看快照状态 |
| `snapshot-list-changes` | 列出变更文件 |
| `export-changed-files` | 导出变更文件 |

---

## 🎯 工作流程选择建议

- **使用情况一** 当：
  - 补丁兼容性测试通过
  - 明确知道要修改的文件
  - 补丁冲突较少

- **使用情况二** 当：
  - 补丁存在显著冲突
  - 需要修改的文件与原补丁不同
  - 内核版本差异较大
  - 需要精确跟踪所有变更

---

## 📄 输出文件说明

| 文件路径 | 描述 |
|----------|------|
| `patch_manager_work/outputs/my.patch` | 最终生成的补丁文件 |
| `patch_manager_work/outputs/patch_files.txt` | 补丁修改的文件列表 |
| `patch_manager_work/outputs/patch_metadata.txt` | 补丁元数据信息 |
| `patch_manager_work/outputs/test-patch-report-*.log` | 补丁兼容性测试报告 |
| `patch_manager_work/changed_files.txt` | 快照变更文件列表 |
| `patch_manager_work/outputs/changed_files/` | 导出的变更文件目录 |
