# 内存监控驱动套件

一个完整的内存监控解决方案，提供三种不同的监控方式，支持多种架构的嵌入式和服务器系统。

## 概述

本套件包含三种不同实现方式的内存监控驱动，每种方式都有其独特的优势和适用场景：

1. **硬件 Watchpoint 监控** - 使用处理器硬件断点进行精确监控
2. **页面保护监控** - 利用 MMU 页面保护机制监控大块内存
3. **Kprobe 监控** - 通过内核探针技术监控系统调用和内核函数

## 支持的架构

- ✅ **ARM32** (Cortex-A5/A7/A8/A9/A15)
- ✅ **ARM64** (ARMv8-A)  
- ✅ **x86** (32位)
- ✅ **x86_64** (64位)

## 目录结构

```
memory_monitor_drivers_suite/
├── README.md                           # 本文件
├── hardware_watchpoint/                # 硬件断点监控
│   ├── memory_monitor.c                # 驱动源码
│   ├── Makefile                        # 编译配置
│   ├── README.md                       # 详细文档
│   ├── test_driver.sh                  # 测试脚本
│   └── test_results.log               # 测试日志
├── page_protection/                    # 页面保护监控
│   ├── page_monitor.c                  # 驱动源码
│   ├── Makefile                        # 编译配置
│   ├── README.md                       # 详细文档
│   └── test_driver.sh                  # 测试脚本
└── kprobe_monitor/                     # Kprobe 监控
    ├── kprobe_monitor.c                # 驱动源码
    ├── Makefile                        # 编译配置
    ├── README.md                       # 详细文档
    └── test_driver.sh                  # 测试脚本
```

## 三种监控方式对比

| 特性 | 硬件 Watchpoint | 页面保护 | Kprobe |
|------|----------------|----------|--------|
| **监控粒度** | 字节级 (1-8字节) | 页面级 (4KB) | 函数级 |
| **监控数量** | 有限 (2-16个) | 多个 | 大量 |
| **性能开销** | 极低 | 中等 | 较高 |
| **精确度** | 最高 | 中等 | 中等 |
| **上下文信息** | 丰富 | 中等 | 最丰富 |
| **适用场景** | 精确变量监控 | 缓冲区监控 | 系统调用追踪 |
| **架构依赖** | 高 | 中等 | 低 |

## 快速开始

### 1. 环境准备

确保系统已安装内核开发包：

```bash
# Ubuntu/Debian
sudo apt-get install linux-headers-$(uname -r) build-essential

# CentOS/RHEL
sudo yum install kernel-devel-$(uname -r) gcc make

# Arch Linux
sudo pacman -S linux-headers base-devel
```

### 2. 编译所有驱动

```bash
# 进入套件目录
cd tools/memory_monitor_drivers_suite

# 编译所有驱动
for dir in hardware_watchpoint page_protection kprobe_monitor; do
    echo "编译 $dir..."
    cd $dir
    make
    cd ..
done
```

### 3. 选择合适的监控方式

根据您的需求选择监控方式：

#### 精确变量监控 - 硬件 Watchpoint
```bash
cd hardware_watchpoint
sudo make install

# 监控特定变量
echo "add my_var 0x12345678 4 3" > /proc/hw_watchpoint
```

#### 缓冲区监控 - 页面保护
```bash
cd page_protection  
sudo make install

# 监控 4KB 内存区域
echo "add buffer_guard 0x10000000 4096 3" > /proc/page_monitor
```

#### 系统调用追踪 - Kprobe
```bash
cd kprobe_monitor
sudo make install

# 监控 mmap 系统调用
echo "add mmap_trace sys_mmap 0" > /proc/kprobe_monitor
```

## 使用场景

### 1. 调试内存越界访问

**场景**: 程序中某个数组可能存在越界访问问题

**推荐方案**: 硬件 Watchpoint
```bash
# 监控数组边界
echo "add array_guard 0xarray_end_addr 4 3" > /proc/hw_watchpoint
```

### 2. 检测缓冲区溢出

**场景**: 大型缓冲区可能被恶意溢出

**推荐方案**: 页面保护  
```bash
# 保护缓冲区末尾页面
echo "add buffer_overflow_guard 0xbuffer_end_page 4096 2" > /proc/page_monitor
```

### 3. 分析内存分配行为

**场景**: 分析程序的内存分配模式

**推荐方案**: Kprobe
```bash
# 监控内存分配相关系统调用
echo "add malloc_trace sys_mmap 0" > /proc/kprobe_monitor
echo "add free_trace sys_munmap 0" > /proc/kprobe_monitor
```

### 4. 监控特定进程

**场景**: 只关注特定程序的内存访问

**推荐方案**: Kprobe (支持进程过滤)
```bash
# 只监控进程名为 "myapp" 的内存操作
echo "add myapp_mmap sys_mmap 0 0 0 myapp" > /proc/kprobe_monitor
```

## 监控输出示例

### 硬件 Watchpoint 输出
```
🔍 [hw_watchpoint] 硬件断点触发!
监控点: test_variable
地址: 0x0000123456789abc
命中次数: 1
ARM64 - PC: 0x0000567890123456, LR: 0x0000567890123400, SP: 0x0000789012345678
当前值: 0x12345678 (305419896)
调用栈信息:
...
```

### 页面保护输出
```
📄 [page_monitor] 页面访问检测!
监控点: test_memory
故障地址: 0x00007f8b2c000000
页面号: 180306
命中次数: 1
访问类型: 写入
页面标志: 0x2fffff
页面引用: 1
```

### Kprobe 输出
```
🔍 [kprobe_monitor] Kprobe 探针触发!
时间: 1640995200.123456
监控点: mmap_monitor
函数: sys_mmap @ 0x81234567
命中次数: 1 (总计: 1)
进程信息:
  PID: 1234, TGID: 1234
  进程名: myapp
  UID: 1000, GID: 1000
  虚拟内存: 12345 KB
  RSS: 6789 KB
mmap参数: addr=0x0, len=4096, prot=0x3, flags=0x22
调用栈 (8 层):
  [0] sys_mmap (0x81234567)
  [1] do_syscall_64 (0x81234568)
  ...
```

## 高级功能

### 1. 交叉编译

针对不同架构进行交叉编译：

```bash
# ARM32
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-

# ARM64  
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-

# OpenWrt
make openwrt
```

### 2. 批量测试

运行完整的测试套件：

```bash
# 在每个目录下运行测试
for dir in hardware_watchpoint page_protection kprobe_monitor; do
    cd $dir
    sudo ./test_driver.sh
    cd ..
done
```

### 3. 性能基准测试

```bash
# 各驱动的性能测试
cd hardware_watchpoint && make benchmark
cd ../page_protection && make benchmark  
cd ../kprobe_monitor && make benchmark
```

## 故障排除

### 1. 编译错误

**问题**: 缺少内核头文件
```bash
# 解决方案
sudo apt-get install linux-headers-$(uname -r)
```

**问题**: 架构不支持某些特性
```bash
# 检查内核配置
make check-config
```

### 2. 运行时错误

**问题**: 驱动加载失败
```bash
# 查看详细错误信息
dmesg | tail -20

# 检查模块依赖
modinfo driver_name.ko
```

**问题**: 权限不足
```bash
# 确保以 root 权限运行
sudo make install
```

### 3. 功能异常

**问题**: 监控不触发
```bash
# 检查监控配置
cat /proc/driver_name

# 验证地址有效性
cat /proc/maps | grep address_range
```

## 安全注意事项

⚠️ **重要提醒**:

1. **仅用于调试**: 这些驱动会显著影响系统性能，仅应在开发和调试环境中使用
2. **Root 权限**: 所有操作都需要 root 权限
3. **系统稳定性**: 不当使用可能导致系统崩溃
4. **生产环境**: 不建议在生产环境中使用

## 开发和贡献

### 扩展新架构

1. 在驱动源码中添加架构检测
2. 实现架构特定的寄存器访问
3. 添加相应的测试用例

### 添加新功能

1. 扩展 proc 接口命令
2. 增加过滤条件
3. 改进输出格式

## 许可证

本项目基于 GPL v2 许可证发布。

## 作者

OpenWrt Tools Project

## 版本历史

- v1.2.0: 完整的三驱动套件，支持多架构
- v1.1.0: 硬件 Watchpoint 驱动
- v1.0.0: 页面保护驱动初始版本

## 相关资源

- [Linux 内核模块编程指南](https://tldp.org/LDP/lkmpg/2.6/html/)
- [Kprobes 文档](https://www.kernel.org/doc/Documentation/kprobes.txt)
- [ARM 调试架构手册](https://developer.arm.com/documentation/)
- [x86 调试寄存器文档](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)

## 技术支持

如有问题或建议，请通过以下方式联系：

1. 提交 Issue 到项目仓库
2. 发送邮件到项目维护者
3. 参考各子目录的 README.md 获取详细信息

---

**Happy Debugging! 🐛🔍** 