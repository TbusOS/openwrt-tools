# Linux fanotify 文件访问监控工具

## 概述

这是一个基于Linux `fanotify`（文件访问通知）机制的高级文件监控工具，提供系统级的文件访问监控功能。与传统的`inotify`相比，`fanotify`提供了更强大的监控能力和权限控制功能。

## 特性

- 🔐 **系统级监控**：监控整个挂载点的文件访问
- 👁️ **精确事件**：不会丢失文件访问事件
- 🛡️ **权限控制**：支持阻止或允许文件访问
- 📊 **进程信息**：显示访问文件的进程PID
- ⚡ **高性能**：适合安全审计和系统监控

## 系统要求

- **操作系统**：Linux 2.6.37+ (推荐3.8+)
- **权限**：root用户或CAP_SYS_ADMIN权限
- **内核支持**：CONFIG_FANOTIFY=y

## 编译和安装

### 快速编译
```bash
make
```

### 手动编译
```bash
gcc -o fanotify_demo fanotify_demo.c
```

### 检查系统支持
```bash
# 检查内核是否支持fanotify
grep -q "CONFIG_FANOTIFY=y" /boot/config-$(uname -r) && echo "支持fanotify" || echo "不支持fanotify"

# 检查当前权限
id -u
# 如果输出0，表示有root权限
```

## 使用方法

### 基本用法
```bash
# 监控指定目录（需要root权限）
sudo ./fanotify_demo /path/to/monitor

# 监控当前目录
sudo ./fanotify_demo .

# 监控整个根文件系统（谨慎使用）
sudo ./fanotify_demo /
```

### 实际使用示例

#### 1. 监控开发目录
```bash
# 监控内核源码目录的文件访问
sudo ./fanotify_demo /usr/src/linux
```

#### 2. 安全审计
```bash
# 监控重要系统目录
sudo ./fanotify_demo /etc
sudo ./fanotify_demo /usr/bin
```

#### 3. 调试文件访问
```bash
# 监控应用程序的文件访问模式
sudo ./fanotify_demo /home/user/app_data
```

## 输出示例

```
🚀 fanotify 文件监控启动
=========================
监控路径: /home/user/test
权限: root (CAP_SYS_ADMIN)
监控事件: OPEN, CLOSE, ACCESS, MODIFY
(按 Ctrl+C 停止监控)

✅ fanotify 监控已启动

[14:30:15] 📁 OPEN /home/user/test/file.txt (PID: 1234)
[14:30:15] 📁 ACCESS /home/user/test/file.txt (PID: 1234)
[14:30:15] 📁 CLOSE_NOWRITE /home/user/test/file.txt (PID: 1234)
[14:30:20] 📁 OPEN /home/user/test/config.cfg (PID: 5678)
[14:30:20] 📁 MODIFY /home/user/test/config.cfg (PID: 5678)
[14:30:20] 📁 CLOSE_WRITE /home/user/test/config.cfg (PID: 5678)

🛑 fanotify 监控已停止

📊 监控统计
===========
总事件数: 6
```

## 事件类型说明

| 事件类型 | 描述 |
|----------|------|
| **OPEN** | 文件被打开 |
| **ACCESS** | 文件被读取 |
| **MODIFY** | 文件内容被修改 |
| **CLOSE_WRITE** | 以写入模式打开的文件被关闭 |
| **CLOSE_NOWRITE** | 以只读模式打开的文件被关闭 |
| **OPEN_PERM** | 文件打开权限检查 |
| **ACCESS_PERM** | 文件访问权限检查 |

## 与inotify的对比

详细的技术对比请参考：[MONITORING_COMPARISON.md](./MONITORING_COMPARISON.md)

| 特性 | fanotify | inotify |
|------|----------|---------|
| **权限要求** | root/CAP_SYS_ADMIN | 普通用户 |
| **监控范围** | 整个挂载点 | 指定目录 |
| **事件精度** | 不丢失 | 可能丢失 |
| **权限控制** | 支持 | 不支持 |
| **资源占用** | 中高 | 低 |
| **适用场景** | 安全审计、系统监控 | 开发工具、用户应用 |

## 安全注意事项

⚠️ **重要提醒**：
1. **权限敏感**：fanotify需要root权限，使用时要谨慎
2. **性能影响**：监控大范围目录可能影响系统性能
3. **事件洪流**：监控活跃目录会产生大量事件
4. **权限控制**：在生产环境中可能影响系统稳定性

## 故障排除

### 常见错误

#### 1. 权限错误
```
错误: fanotify 需要root权限
请使用: sudo ./fanotify_demo /path
```
**解决方案**：使用sudo运行或切换到root用户

#### 2. 内核不支持
```
fanotify_init: Function not implemented
提示: 确保内核支持fanotify且拥有root权限
```
**解决方案**：
- 检查内核版本：`uname -r`
- 检查内核配置：`grep FANOTIFY /boot/config-$(uname -r)`
- 升级到支持fanotify的内核版本

#### 3. 资源不足
```
fanotify_mark: No space left on device
```
**解决方案**：
- 检查inotify限制：`cat /proc/sys/fs/inotify/max_user_watches`
- 增加限制：`echo 524288 | sudo tee /proc/sys/fs/inotify/max_user_watches`

## 高级用法

### 1. 集成到监控系统
```bash
# 将输出重定向到日志文件
sudo ./fanotify_demo /var/log 2>&1 | tee fanotify.log

# 与其他工具结合
sudo ./fanotify_demo /etc | grep -E "(ssh|passwd|shadow)"
```

### 2. 性能调优
```bash
# 监控特定文件类型（在代码中添加过滤）
# 避免监控临时文件和系统文件
```

## 开发参考

### API文档
- `man 7 fanotify`：fanotify概述
- `man 2 fanotify_init`：初始化fanotify
- `man 2 fanotify_mark`：标记监控对象

### 相关项目
- [inotify-tools](https://github.com/inotify-tools/inotify-tools)：基于inotify的工具集
- [sysdig](https://github.com/draios/sysdig)：系统监控工具
- [osquery](https://github.com/osquery/osquery)：系统查询框架

## 许可证

本项目遵循与OpenWrt工具套件相同的许可证。

## 贡献

欢迎提交Issue和Pull Request来改进这个工具。

---

**注意**：这是一个演示工具，生产环境使用前请充分测试。
