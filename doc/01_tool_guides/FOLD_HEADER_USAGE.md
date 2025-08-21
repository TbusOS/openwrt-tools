# Quilt Fold 和 Header 命令使用指南

本文档介绍 `quilt_patch_manager_final.sh` 脚本中新增的 `fold` 和 `header` 命令的使用方法。

## 1. Quilt Header 命令

`header` 命令用于查看和编辑补丁的头部信息（元数据）。

### 基本用法

```bash
# 查看当前补丁的头部信息
./quilt_patch_manager_final.sh header

# 查看指定补丁的头部信息
./quilt_patch_manager_final.sh header platform/CVE-2016-3138.patch

# 查看顶部补丁的头部信息（明确指定）
./quilt_patch_manager_final.sh header top
```

### 编辑选项

```bash
# 使用编辑器编辑头部信息
./quilt_patch_manager_final.sh header -e

# 添加头部信息（追加模式）
./quilt_patch_manager_final.sh header -a

# 替换头部信息
./quilt_patch_manager_final.sh header -r

# 为指定补丁编辑头部
./quilt_patch_manager_final.sh header -e platform/my-patch.patch

# 从文件追加头部信息
./quilt_patch_manager_final.sh header -a < description.txt
./quilt_patch_manager_final.sh header -a platform/my-patch.patch < description.txt

# 从管道追加头部信息
echo "新的描述信息" | ./quilt_patch_manager_final.sh header -a
echo "Signed-off-by: Your Name <email@example.com>" | ./quilt_patch_manager_final.sh header -a platform/my-patch.patch
```

### 实际应用场景

1. **查看补丁信息**：在应用或修改补丁前了解其内容和作者信息
2. **添加元数据**：为自己创建的补丁添加详细的描述、作者信息等
3. **修正信息**：更正补丁中的错误信息或更新描述

## 2. Quilt Fold 命令

`fold` 命令用于将一个补丁文件的内容合并到当前的补丁中。

### 基本用法

```bash
# 将补丁文件内容合并到当前补丁
./quilt_patch_manager_final.sh fold /path/to/additional.patch

# 合并多个补丁文件
./quilt_patch_manager_final.sh fold patch1.patch patch2.patch

# 从标准输入折叠补丁内容
cat additional.patch | ./quilt_patch_manager_final.sh fold -
```

### 实际应用场景

1. **合并相关修改**：将多个小的修改合并到一个补丁中
2. **整合修复**：将针对同一问题的多个修复合并
3. **补丁重构**：重新组织补丁结构，将相关修改归类

## 3. 典型工作流程示例

### 场景1：编辑补丁头部信息

```bash
# 1. 查看当前状态
./quilt_patch_manager_final.sh status

# 2. 查看当前补丁的头部信息
./quilt_patch_manager_final.sh header

# 3. 编辑头部信息
./quilt_patch_manager_final.sh header -e

# 4. 确认修改
./quilt_patch_manager_final.sh header
```

### 场景2：合并补丁

```bash
# 1. 创建一个新补丁
./quilt_patch_manager_final.sh create-patch 999-combined-fix.patch

# 2. 将现有补丁内容合并进来
./quilt_patch_manager_final.sh fold patch_manager_work/outputs/fix1.patch
./quilt_patch_manager_final.sh fold patch_manager_work/outputs/fix2.patch

# 3. 添加头部信息
./quilt_patch_manager_final.sh header -a

# 4. 刷新补丁
./quilt_patch_manager_final.sh refresh
```

### 场景3：修复补丁描述

```bash
# 1. 查看补丁列表
./quilt_patch_manager_final.sh series

# 2. 查看特定补丁的当前头部
./quilt_patch_manager_final.sh header platform/problematic-patch.patch

# 3. 切换到该补丁（如果不是当前补丁）
./quilt_patch_manager_final.sh push platform/problematic-patch.patch

# 4. 编辑头部信息
./quilt_patch_manager_final.sh header -e

# 5. 刷新补丁
./quilt_patch_manager_final.sh refresh
```

### 场景4：从文件批量添加头部信息

```bash
# 1. 准备头部信息文件
cat > patch_header.txt << 'EOF'

This patch addresses a critical security vulnerability.
It has been tested on multiple kernel versions.

Reported-by: Security Team <security@example.com>
Tested-by: QA Team <qa@example.com>
Signed-off-by: Developer Name <dev@example.com>
EOF

# 2. 为当前补丁追加头部信息
./quilt_patch_manager_final.sh header -a < patch_header.txt

# 3. 为指定补丁追加头部信息
./quilt_patch_manager_final.sh header -a platform/security-fix.patch < patch_header.txt

# 4. 使用管道方式添加签名
echo "Reviewed-by: Maintainer <maintainer@example.com>" | \
  ./quilt_patch_manager_final.sh header -a

# 5. 验证头部信息
./quilt_patch_manager_final.sh header

# 6. 刷新补丁
./quilt_patch_manager_final.sh refresh
```

## 4. Tab 自动补全支持

启用自动补全后，可以使用以下快捷方式：

```bash
# 加载补全脚本
source quilt_patch_manager_completion.bash

# 使用 Tab 键补全命令
./quilt_patch_manager_final.sh hea<Tab>  # 补全为 header
./quilt_patch_manager_final.sh fol<Tab>  # 补全为 fold

# 对于 header 命令，可以补全选项
./quilt_patch_manager_final.sh header -<Tab>  # 显示 -a -r -e 选项

# 对于需要补丁文件的命令，可以补全文件路径
./quilt_patch_manager_final.sh fold <Tab>  # 补全 .patch 文件
```

## 5. 注意事项

1. **备份重要补丁**：在使用 fold 命令合并补丁前，建议备份原始补丁文件
2. **头部格式**：编辑头部信息时注意保持正确的补丁格式
3. **当前补丁状态**：某些操作需要有当前活动的补丁，确保使用 `push` 命令应用到正确的补丁
4. **权限检查**：确保对补丁文件和内核源码目录有适当的读写权限
5. **文件编码**：从文件追加头部信息时，确保文件使用 UTF-8 编码
6. **行尾格式**：注意文件的行尾格式（LF vs CRLF），建议使用 Unix 格式（LF）
7. **空行处理**：追加头部信息时，系统会自动处理空行，但建议在文件开头留一个空行用于分隔

## 6. 错误处理

如果命令执行失败，请检查：

1. 是否在正确的工作目录中
2. 是否有当前活动的补丁（对于某些操作）
3. 补丁文件路径是否正确
4. 是否有足够的文件权限

## 7. 更多信息

- 使用 `./quilt_patch_manager_final.sh help` 查看完整命令列表
- 参考 quilt 官方文档了解更多高级用法
- 查看 `quilt header --help` 和 `quilt fold --help` 获取原始命令的详细选项 