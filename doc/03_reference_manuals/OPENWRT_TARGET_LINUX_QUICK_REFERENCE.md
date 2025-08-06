# OpenWrt target/linux 命令快速参考卡片

## 🚀 最常用命令

| 命令 | 功能 | 使用场景 |
|------|------|----------|
| `make target/linux/prepare` | 准备内核源码 | 首次设置或重新开始 |
| `make target/linux/clean` | 清理内核构建 | 重新开始或释放空间 |
| `make target/linux/menuconfig` | 配置内核 | 修改内核配置选项 |
| `make target/linux/compile` | 编译内核 | 生成内核镜像 |
| `make target/linux/update` | 更新补丁 | 修改补丁后应用 |

## 📋 完整命令列表

### 源码管理
- `make target/linux/download` - 下载内核源码
- `make target/linux/prepare` - 准备内核源码（推荐）
- `make target/linux/clean` - 清理内核构建

### 配置管理
- `make target/linux/oldconfig` - 使用现有配置
- `make target/linux/menuconfig` - 交互式配置
- `make target/linux/nconfig` - ncurses 配置界面
- `make target/linux/xconfig` - 图形化配置界面

### 编译安装
- `make target/linux/compile` - 编译内核
- `make target/linux/install` - 安装内核
- `make target/linux/dtb` - 编译设备树

### 补丁管理
- `make target/linux/update` - 更新补丁
- `make target/linux/refresh` - 刷新补丁

### 其他
- `make target/linux/prereq` - 检查前置条件

## 🔧 常用参数

| 参数 | 说明 |
|------|------|
| `V=s` | 显示详细输出 |
| `V=99` | 显示调试信息 |
| `-jN` | 并行编译 |
| `FORCE=1` | 强制执行 |

## 📁 重要目录

- **内核源码**: `build_dir/target-*/linux-*/linux-*/`
- **补丁目录**: `target/linux/<board>/patches-<version>/`
- **下载目录**: `dl/`

## ⚡ 快速工作流

```bash
# 1. 准备内核
make target/linux/prepare V=s

# 2. 配置内核
make target/linux/menuconfig V=s

# 3. 编译内核
make target/linux/compile V=s
```
