# Quilt 命令全集参考手册

本文档提供了 Quilt 补丁管理工具的完整命令参考，包含每个命令的功能说明、语法格式和使用示例。

## 📖 目录

- [补丁创建与管理](#补丁创建与管理)
- [补丁应用与撤销](#补丁应用与撤销)
- [补丁状态查询](#补丁状态查询)
- [文件管理](#文件管理)
- [补丁编辑](#补丁编辑)
- [补丁信息](#补丁信息)
- [补丁导入导出](#补丁导入导出)
- [高级功能](#高级功能)

---

## 补丁创建与管理

### `quilt new`
**功能**: 创建一个新的补丁文件
**语法**: `quilt new patch-name.patch`
**说明**: 在补丁系列的末尾创建一个新的空补丁，并将其设为当前补丁

```bash
# 创建一个新补丁
quilt new fix-memory-leak.patch

# 创建带路径的补丁
quilt new drivers/fix-network-driver.patch
```

### `quilt delete`
**功能**: 删除指定的补丁
**语法**: `quilt delete [patch-name]`
**说明**: 删除补丁文件，如果未指定补丁名，删除当前顶层补丁

```bash
# 删除当前补丁
quilt delete

# 删除指定补丁
quilt delete fix-memory-leak.patch
```

### `quilt rename`
**功能**: 重命名补丁
**语法**: `quilt rename new-patch-name.patch`
**说明**: 重命名当前顶层补丁

```bash
# 重命名当前补丁
quilt rename better-fix-memory-leak.patch
```

---

## 补丁应用与撤销

### `quilt push`
**功能**: 应用补丁到工作目录
**语法**: `quilt push [-a] [-q] [-f] [patch-name|number]`
**选项**:
- `-a, --all`: 应用所有未应用的补丁
- `-q, --quiet`: 静默模式
- `-f, --force`: 强制应用，即使有冲突

```bash
# 应用下一个补丁
quilt push

# 应用所有补丁
quilt push -a

# 强制应用下一个补丁
quilt push -f

# 应用到指定补丁
quilt push fix-memory-leak.patch
```

### `quilt pop`
**功能**: 撤销补丁的应用
**语法**: `quilt pop [-a] [-q] [-f] [patch-name|number]`
**选项**:
- `-a, --all`: 撤销所有已应用的补丁
- `-q, --quiet`: 静默模式
- `-f, --force`: 强制撤销

```bash
# 撤销当前顶层补丁
quilt pop

# 撤销所有补丁
quilt pop -a

# 撤销到指定补丁
quilt pop fix-network-driver.patch
```

### `quilt goto`
**功能**: 应用或撤销补丁直到指定补丁成为顶层补丁
**语法**: `quilt goto patch-name`
**说明**: 自动push或pop到指定补丁位置

```bash
# 跳转到指定补丁
quilt goto fix-memory-leak.patch
```

---

## 补丁状态查询

### `quilt series`
**功能**: 显示所有补丁的列表
**语法**: `quilt series [-v]`
**选项**:
- `-v, --verbose`: 显示详细信息，包括应用状态

```bash
# 显示所有补丁
quilt series

# 显示详细信息
quilt series -v
```

### `quilt applied`
**功能**: 显示已应用的补丁列表
**语法**: `quilt applied [patch-name]`
**说明**: 如果指定补丁名，显示到该补丁为止的所有已应用补丁

```bash
# 显示所有已应用的补丁
quilt applied

# 显示到指定补丁的已应用补丁
quilt applied fix-memory-leak.patch
```

### `quilt unapplied`
**功能**: 显示未应用的补丁列表
**语法**: `quilt unapplied [patch-name]`
**说明**: 如果指定补丁名，显示从该补丁开始的所有未应用补丁

```bash
# 显示所有未应用的补丁
quilt unapplied

# 显示从指定补丁开始的未应用补丁
quilt unapplied fix-network-driver.patch
```

### `quilt top`
**功能**: 显示当前顶层补丁
**语法**: `quilt top`
**说明**: 显示补丁栈顶部的补丁名称

```bash
# 显示当前顶层补丁
quilt top
```

### `quilt previous`
**功能**: 显示当前补丁的前一个补丁
**语法**: `quilt previous [patch-name]`

```bash
# 显示前一个补丁
quilt previous
```

### `quilt next`
**功能**: 显示当前补丁的下一个补丁
**语法**: `quilt next [patch-name]`

```bash
# 显示下一个补丁
quilt next
```

---

## 文件管理

### `quilt add`
**功能**: 将文件添加到当前补丁
**语法**: `quilt add file1 [file2 ...]`
**说明**: 在修改文件之前必须先将其添加到补丁中

```bash
# 添加单个文件
quilt add drivers/network.c

# 添加多个文件
quilt add drivers/network.c include/network.h

# 添加目录下所有文件
quilt add drivers/*
```

### `quilt remove`
**功能**: 从当前补丁中移除文件
**语法**: `quilt remove file1 [file2 ...]`
**说明**: 从补丁中移除文件，但不删除文件本身

```bash
# 从补丁中移除文件
quilt remove drivers/network.c
```

### `quilt files`
**功能**: 显示补丁包含的文件列表
**语法**: `quilt files [patch-name]`
**说明**: 如果未指定补丁名，显示当前补丁的文件

```bash
# 显示当前补丁的文件
quilt files

# 显示指定补丁的文件
quilt files fix-memory-leak.patch
```

### `quilt edit`
**功能**: 编辑文件并自动添加到当前补丁
**语法**: `quilt edit file`
**说明**: 如果文件不在补丁中，自动添加后再编辑

```bash
# 编辑文件
quilt edit drivers/network.c
```

---

## 补丁编辑

### `quilt refresh`
**功能**: 更新当前补丁内容
**语法**: `quilt refresh [-p ab-level] [--no-timestamps] [--backup]`
**选项**:
- `-p N`: 设置补丁的路径层级
- `--no-timestamps`: 不在补丁中包含时间戳
- `--backup`: 创建备份文件

```bash
# 刷新当前补丁
quilt refresh

# 刷新补丁并设置路径层级
quilt refresh -p1

# 刷新补丁不包含时间戳
quilt refresh --no-timestamps
```

### `quilt fold`
**功能**: 将另一个补丁的内容合并到当前补丁
**语法**: `quilt fold patch-file`
**说明**: 将指定补丁文件的内容合并到当前顶层补丁

```bash
# 合并补丁内容
quilt fold external-patch.patch
```

---

## 补丁信息

### `quilt diff`
**功能**: 显示补丁的差异内容
**语法**: `quilt diff [-p ab-level] [patch-name] [file ...]`
**选项**:
- `-P patch`: 指定补丁
- `-p N`: 设置diff的路径层级

```bash
# 显示当前补丁的diff
quilt diff

# 显示指定补丁的diff
quilt diff -P fix-memory-leak.patch

# 显示特定文件的diff
quilt diff drivers/network.c
```

### `quilt header`
**功能**: 显示或编辑补丁的头部信息
**语法**: `quilt header [-a|-r|-e] [patch-name]`
**选项**:
- `-a, --append`: 追加内容到头部
- `-r, --replace`: 替换头部内容
- `-e, --edit`: 编辑头部内容

```bash
# 显示当前补丁头部
quilt header

# 编辑补丁头部
quilt header -e

# 替换头部内容
quilt header -r < new-header.txt
```

### `quilt annotate`
**功能**: 显示文件的注释信息
**语法**: `quilt annotate file`
**说明**: 显示文件中每行是由哪个补丁引入的

```bash
# 显示文件注释
quilt annotate drivers/network.c
```

---

## 补丁导入导出

### `quilt import`
**功能**: 导入补丁到系列中
**语法**: `quilt import [-p n] [-R] patch-file`
**选项**:
- `-p n`: 设置补丁的strip层级
- `-R`: 反向应用补丁

```bash
# 导入补丁
quilt import external-fix.patch

# 导入并设置strip层级
quilt import -p1 kernel-patch.patch
```

### `quilt mail`
**功能**: 通过邮件发送补丁系列
**语法**: `quilt mail [options] [first_patch [last_patch]]`
**说明**: 将补丁系列格式化为邮件格式发送

```bash
# 发送所有补丁
quilt mail --to maintainer@example.com
```

---

## 高级功能

### `quilt graph`
**功能**: 生成补丁依赖关系图
**语法**: `quilt graph [patch-name]`
**说明**: 输出DOT格式的依赖关系图，可用graphviz可视化

```bash
# 生成所有补丁的依赖图
quilt graph > patches.dot

# 生成特定补丁的依赖图
quilt graph fix-memory-leak.patch > memory-fix.dot

# 使用graphviz生成图片
dot -Tpng patches.dot -o patches.png
```

### `quilt setup`
**功能**: 初始化补丁目录
**语法**: `quilt setup [options] series-file`
**说明**: 根据series文件设置补丁环境

```bash
# 设置补丁环境
quilt setup patches/series
```

### `quilt snapshot`
**功能**: 创建当前状态的快照
**语法**: `quilt snapshot [-d]`
**选项**:
- `-d`: 显示与快照的差异

```bash
# 创建快照
quilt snapshot

# 显示与快照的差异
quilt snapshot -d
```

### `quilt upgrade`
**功能**: 升级补丁格式
**语法**: `quilt upgrade`
**说明**: 将旧格式的补丁升级到新格式

```bash
# 升级补丁格式
quilt upgrade
```

---

## 🔧 配置选项

### 环境变量
- `QUILT_PATCHES`: 指定补丁目录位置
- `QUILT_SERIES`: 指定series文件位置
- `QUILT_PC`: 指定.pc目录位置
- `QUILT_DIFF_ARGS`: diff命令的默认参数
- `QUILT_PATCH_OPTS`: patch命令的默认选项

### 配置文件
Quilt配置文件位置：
- 全局配置: `/etc/quilt.quiltrc`
- 用户配置: `~/.quiltrc`
- 项目配置: `.quiltrc`

### 常用配置示例
```bash
# ~/.quiltrc 示例
QUILT_DIFF_ARGS="--no-timestamps --color=auto"
QUILT_REFRESH_ARGS="--no-timestamps --backup"
QUILT_COLORS="diff_hdr=1;32:diff_add=1;34:diff_rem=1;31"
QUILT_PATCH_OPTS="--reject-format=unified"
```

---

## 📚 最佳实践

### 1. 补丁命名规范
```bash
# 使用描述性名称
001-fix-memory-leak.patch
002-add-network-driver.patch
003-update-documentation.patch
```

### 2. 补丁头部格式
```
Subject: [PATCH] Fix memory leak in network driver

This patch fixes a memory leak that occurs when the network
driver fails to initialize properly.

Signed-off-by: Your Name <your.email@example.com>
```

### 3. 工作流程
```bash
# 1. 创建新补丁
quilt new fix-bug.patch

# 2. 添加要修改的文件
quilt add drivers/network.c

# 3. 编辑文件
vim drivers/network.c

# 4. 刷新补丁
quilt refresh

# 5. 添加补丁描述
quilt header -e
```

### 4. 错误处理
```bash
# 查看应用失败的原因
quilt push -f

# 查看冲突文件
find . -name "*.rej"

# 手动解决冲突后刷新
quilt refresh
```

---

## 🎯 常见使用场景

### 场景1: 创建新补丁
```bash
quilt new my-feature.patch
quilt add file1.c file2.h
# 编辑文件...
quilt refresh
quilt header -e  # 添加描述
```

### 场景2: 修改现有补丁
```bash
quilt goto target-patch.patch
quilt add new-file.c
# 编辑文件...
quilt refresh
```

### 场景3: 测试补丁系列
```bash
quilt push -a   # 应用所有补丁
# 进行测试...
quilt pop -a    # 撤销所有补丁
```

### 场景4: 生成补丁文件
```bash
quilt refresh
cp patches/my-patch.patch /path/to/destination/
```

---

## ⚠️ 注意事项

1. **文件修改前必须先添加**: 使用 `quilt add` 将文件添加到补丁中
2. **及时刷新补丁**: 修改文件后使用 `quilt refresh` 更新补丁内容
3. **避免手动编辑.pc目录**: .pc目录由quilt自动管理
4. **备份重要数据**: 在进行复杂操作前创建备份
5. **理解补丁顺序**: 补丁应用顺序很重要，注意依赖关系

---

**文档版本**: 1.0  
**最后更新**: 2025-01-13  
**适用于**: Quilt 0.60+ 