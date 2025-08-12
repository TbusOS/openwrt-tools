# 硬件 Watchpoint 内存监控驱动

## 概述

硬件 Watchpoint 内存监控驱动使用处理器的硬件调试功能来监控特定内存地址的访问。通过配置硬件断点寄存器，可以在内存被读取或写入时触发中断，从而实现精确的内存访问监控。

## 特性

- ✅ **精确监控**: 字节级精度，支持1、2、4、8字节监控
- ✅ **硬件实现**: 利用处理器调试寄存器，开销极小
- ✅ **多架构支持**: ARM32 Cortex-A5, ARM64, x86, x86_64
- ✅ **实时检测**: 硬件级实时响应，无延迟
- ✅ **读写分离**: 可选择监控读取、写入或两者
- ✅ **详细上下文**: 提供寄存器状态和调用栈信息

## 工作原理

1. **硬件配置**: 配置处理器的调试寄存器设置断点
2. **地址匹配**: 硬件自动比较访问地址与监控地址
3. **中断触发**: 匹配时触发调试异常或断点中断
4. **信息收集**: 在中断处理函数中收集上下文信息
5. **继续执行**: 记录信息后继续正常程序执行

## 🏗️ 架构设计图

```
┌─────────────────────────────────────────────────────────────┐
│                      用户空间应用                            │
├─────────────────────────────────────────────────────────────┤
│                  /proc/hw_watchpoint                        │
│            (配置接口 + 状态查看接口)                         │
├─────────────────────────────────────────────────────────────┤
│                memory_monitor.ko 驱动模块                   │
│  ┌─────────────────┬────────────────┬─────────────────────┐  │
│  │   配置管理       │   事件处理      │    架构适配层        │  │
│  │ - 监控点管理     │ - 中断处理      │ - ARM32/ARM64      │  │
│  │ - proc 接口     │ - 上下文收集    │ - x86/x86_64       │  │
│  │ - 参数验证      │ - 调用栈解析    │ - 寄存器抽象        │  │
│  └─────────────────┴────────────────┴─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                     Linux 内核层                            │
│  ┌─────────────────┬────────────────┬─────────────────────┐  │
│  │   perf 子系统    │   异常处理      │    符号解析          │  │
│  │ - perf_event    │ - 调试异常      │ - kallsyms         │  │
│  │ - hw_breakpoint │ - 中断路由      │ - stack_trace      │  │
│  │ - 事件调度      │ - 上下文切换    │ - 符号查找          │  │
│  └─────────────────┴────────────────┴─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                       硬件层                                │
│           处理器调试寄存器 / 硬件断点单元                     │
│  ┌─────────────────┬────────────────┬─────────────────────┐  │
│  │      ARM        │      x86       │      共同特性        │  │
│  │ - DBG 寄存器     │ - DR0~DR7      │ - 地址匹配          │  │
│  │ - DBGBVR/DBGBCR │ - 断点控制      │ - 大小检测          │  │
│  │ - Watchpoint    │ - 状态寄存器    │ - 读写类型          │  │
│  │ - 调试异常      │ - #DB 异常      │ - 实时触发          │  │
│  └─────────────────┴────────────────┴─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## 📊 工作流程图

```
[用户配置监控点] 
        │
        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   参数验证       │───▶│   地址对齐检查   │───▶│   硬件资源分配   │
│ - 地址有效性     │    │ - 按大小对齐     │    │ - 断点寄存器     │
│ - 大小范围      │    │ - 边界检查      │    │ - perf 事件      │
│ - 类型有效性     │    │ - 权限验证      │    │ - 资源管理      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │                       │                       │
        ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   配置硬件断点   │    │   注册 perf 事件 │    │   激活监控      │
│ - 设置断点地址   │    │ - 创建事件结构   │    │ - 启用断点      │
│ - 配置断点类型   │    │ - 绑定处理函数   │    │ - 状态记录      │
│ - 设置断点大小   │    │ - 设置事件属性   │    │ - 监控激活      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│                    内存访问监控循环                          │
│                                                             │
│  [程序执行] ──┬─→ [访问被监控地址] ──┬─→ [硬件断点触发]      │
│              │                      │                      │
│              │                      ▼                      │
│              │            ┌─────────────────┐              │
│              │            │   调试异常产生   │              │
│              │            │ - ARM: DBG异常  │              │
│              │            │ - x86: #DB异常  │              │
│              │            └─────────────────┘              │
│              │                      │                      │
│              │                      ▼                      │
│              │            ┌─────────────────┐              │
│              │            │   异常处理函数   │              │
│              │            │ - 保存寄存器状态 │              │
│              │            │ - 获取访问地址   │              │
│              │            │ - 读取当前值     │              │
│              │            └─────────────────┘              │
│              │                      │                      │
│              │                      ▼                      │
│              │            ┌─────────────────┐              │
│              │            │   上下文收集     │              │
│              │            │ - 进程信息      │              │
│              │            │ - 寄存器状态     │              │
│              │            │ - 调用栈追踪     │              │
│              │            │ - 时间戳       │              │
│              │            └─────────────────┘              │
│              │                      │                      │
│              │                      ▼                      │
│              │            ┌─────────────────┐              │
│              │            │   信息输出       │              │
│              │            │ - 内核日志      │              │
│              │            │ - 统计更新      │              │
│              │            │ - 格式化输出     │              │
│              │            └─────────────────┘              │
│              │                      │                      │
│              │                      ▼                      │
│              └──────────────── [恢复执行] ◀─────────────────┘
│
└─────────────────────────────────────────────────────────────┘
```

## 🎯 架构特定实现

### ARM32/ARM64 架构
```
┌─────────────────────────────────────────────────────────┐
│                    ARM 调试架构                          │
│                                                         │
│  ┌─────────────────┐         ┌─────────────────────────┐ │
│  │    用户代码      │         │       内核驱动           │ │
│  │                │         │                         │ │
│  │ load/store ────┼────────▶│ memory_access_handler   │ │
│  │ 指令执行       │         │                         │ │
│  └─────────────────┘         └─────────────────────────┘ │
│          │                             ▲                │
│          ▼                             │                │
│  ┌─────────────────┐         ┌─────────────────────────┐ │
│  │  内存访问检查    │         │      DBG 异常处理        │ │
│  │                │         │                         │ │
│  │ 地址比较 ◀──────┼─────────┤ 异常向量表              │ │
│  │ 类型匹配       │         │ 上下文保存               │ │
│  └─────────────────┘         └─────────────────────────┘ │
│          │                                              │
│          ▼                                              │
│  ┌─────────────────────────────────────────────────────┐ │
│  │               ARM 调试寄存器                         │ │
│  │                                                     │ │
│  │  DBGBVR[n]  ← 断点地址寄存器                        │ │
│  │  DBGBCR[n]  ← 断点控制寄存器                        │ │
│  │  DBGWVR[n]  ← Watchpoint 地址寄存器                 │ │
│  │  DBGWCR[n]  ← Watchpoint 控制寄存器                 │ │
│  │  DBGDSCR    ← 调试状态控制寄存器                     │ │
│  │                                                     │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### x86/x86_64 架构
```
┌─────────────────────────────────────────────────────────┐
│                   x86 调试架构                           │
│                                                         │
│  ┌─────────────────┐         ┌─────────────────────────┐ │
│  │    用户代码      │         │       内核驱动           │ │
│  │                │         │                         │ │
│  │ mov/add 等 ────┼────────▶│ memory_access_handler   │ │
│  │ 内存指令       │         │                         │ │
│  └─────────────────┘         └─────────────────────────┘ │
│          │                             ▲                │
│          ▼                             │                │
│  ┌─────────────────┐         ┌─────────────────────────┐ │
│  │  内存访问检查    │         │       #DB 异常           │ │
│  │                │         │                         │ │
│  │ 地址比较 ◀──────┼─────────┤ INT 1 处理程序          │ │
│  │ 大小匹配       │         │ 寄存器保存               │ │
│  └─────────────────┘         └─────────────────────────┘ │
│          │                                              │
│          ▼                                              │
│  ┌─────────────────────────────────────────────────────┐ │
│  │               x86 调试寄存器                         │ │
│  │                                                     │ │
│  │  DR0-DR3  ← 断点地址寄存器 (4个)                     │ │
│  │  DR6      ← 调试状态寄存器                          │ │
│  │  DR7      ← 调试控制寄存器                          │ │
│  │            - L0-L3: 本地断点使能                    │ │
│  │            - G0-G3: 全局断点使能                    │ │
│  │            - R/W0-R/W3: 读写控制                    │ │
│  │            - LEN0-LEN3: 长度控制                    │ │
│  │                                                     │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## 🔧 内核配置要求

### 必需的内核配置选项

使用硬件 Watchpoint 监控驱动**必须**启用以下内核配置选项：

```bash
# 硬件断点基础支持
CONFIG_HAVE_HW_BREAKPOINT=y          # 架构支持硬件断点
CONFIG_HW_BREAKPOINT=y               # 硬件断点核心支持
CONFIG_PERF_EVENTS=y                 # 性能事件框架 (必需)

# 性能监控和事件
CONFIG_PERF_EVENTS_INTEL_UNCORE=y    # Intel uncore 事件 (x86)
CONFIG_PERF_EVENTS_INTEL_RAPL=y      # Intel RAPL 事件 (x86, 可选)
CONFIG_PERF_EVENTS_INTEL_CSTATE=y    # Intel C-state 事件 (x86, 可选)

# 调试支持
CONFIG_DEBUG_KERNEL=y                # 内核调试支持
CONFIG_DEBUG_INFO=y                  # 调试信息
CONFIG_FRAME_POINTER=y               # 帧指针 (推荐)

# 调用栈追踪
CONFIG_STACKTRACE=y                  # 调用栈追踪支持
CONFIG_STACKTRACE_SUPPORT=y          # 架构支持调用栈追踪
CONFIG_RELIABLE_STACKTRACE=y         # 可靠的调用栈追踪 (可选)

# 符号表支持 (用于调用栈解析)
CONFIG_KALLSYMS=y                    # 内核符号表
CONFIG_KALLSYMS_ALL=y                # 所有符号 (推荐)
CONFIG_KALLSYMS_EXTRA_PASS=y         # 额外符号处理

# 处理器特性
CONFIG_X86_DEBUGCTLMSR=y             # x86 调试控制 MSR (x86)
CONFIG_X86_DS=y                      # x86 调试存储 (x86, 可选)
```

### 架构特定配置

#### ARM32 (Cortex-A5/A7/A8/A9/A15)
```bash
CONFIG_ARM=y
CONFIG_HAVE_HW_BREAKPOINT=y
CONFIG_ARM_UNWIND=y                  # ARM 堆栈展开
CONFIG_UNWINDER_ARM=y                # ARM unwinder
CONFIG_DEBUG_USER=y                  # 用户空间调试 (可选)

# ARM 调试架构支持
CONFIG_ARM_AMBA=y                    # AMBA 总线支持
CONFIG_ARM_ERRATA_643719=y           # ARM Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_720789=y           # ARM Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_742230=y           # ARM Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_742231=y           # ARM Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_743622=y           # ARM Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_751472=y           # ARM Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_754322=y           # ARM Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_754327=y           # ARM Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_764369=y           # ARM Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_775420=y           # ARM Cortex-A9 errata (如适用)

# 特定于 Cortex-A5 的配置
CONFIG_ARM_ERRATA_430973=y           # ARM Cortex-A8 errata (如适用)
CONFIG_ARM_ERRATA_458693=y           # ARM Cortex-A8 errata (如适用)
CONFIG_ARM_ERRATA_460075=y           # ARM Cortex-A8 errata (如适用)
CONFIG_ARM_ERRATA_798181=y           # ARM Cortex-A15 errata (如适用)
```

#### ARM64 (ARMv8-A)
```bash
CONFIG_ARM64=y
CONFIG_HAVE_HW_BREAKPOINT=y
CONFIG_ARM64_HW_AFDBM=y              # 硬件访问/脏位管理 (可选)
CONFIG_ARM64_PAN=y                   # 特权访问保护 (可选)
CONFIG_ARM64_LSE_ATOMICS=y           # LSE 原子操作 (可选)
CONFIG_ARM64_VHE=y                   # 虚拟化主机扩展 (可选)
CONFIG_UNWIND_TABLES=y               # 展开表
CONFIG_ARM64_MODULE_PLTS=y           # 模块 PLT 支持

# ARM64 调试支持
CONFIG_ARM64_BREAK_GDB=y             # GDB 断点支持 (可选)
CONFIG_ARM64_PTDUMP_CORE=y           # 页表转储核心 (可选)
CONFIG_ARM64_PTDUMP_DEBUGFS=y        # 页表转储 debugfs (可选)
```

#### x86/x86_64
```bash
CONFIG_X86=y                         # (或 CONFIG_X86_64=y)
CONFIG_HAVE_HW_BREAKPOINT=y
CONFIG_X86_DEBUGCTLMSR=y             # 调试控制 MSR
CONFIG_X86_DS=y                      # 调试存储区域 (可选)
CONFIG_X86_PTDUMP_CORE=y             # 页表转储核心 (可选)

# x86 特定调试特性
CONFIG_X86_DECODER_SELFTEST=y        # 指令解码器自测 (可选)
CONFIG_X86_INSTRUCTION_DECODER=y     # 指令解码器
CONFIG_OPTIMIZE_INLINING=y           # 内联优化

# 性能监控单元
CONFIG_PERF_EVENTS_INTEL_UNCORE=y    # Intel uncore PMU
CONFIG_PERF_EVENTS_INTEL_RAPL=y      # Intel RAPL PMU (可选)
CONFIG_PERF_EVENTS_INTEL_CSTATE=y    # Intel C-state PMU (可选)
```

### 检查当前内核配置

```bash
# 方法1: 检查 /proc/config.gz (如果可用)
zcat /proc/config.gz | grep -E "CONFIG_HAVE_HW_BREAKPOINT|CONFIG_HW_BREAKPOINT|CONFIG_PERF_EVENTS"

# 方法2: 检查 /boot/config-$(uname -r)
grep -E "CONFIG_HAVE_HW_BREAKPOINT|CONFIG_HW_BREAKPOINT|CONFIG_PERF_EVENTS" /boot/config-$(uname -r)

# 方法3: 使用驱动的检查功能
make check-config

# 方法4: 检查运行时支持
ls /sys/kernel/debug/breakpoint/
cat /proc/sys/kernel/perf_event_paranoid
```

### 检查硬件断点可用性

```bash
# 检查硬件断点数量 (x86/x86_64)
dmesg | grep -i "hw.*breakpoint"

# 检查 perf 事件支持
perf list | grep breakpoint

# 检查调试寄存器 (需要 root)
# 注意: 直接访问调试寄存器可能不安全，仅供参考
```

### 内核模块加载配置

```bash
# 确保可以加载内核模块
CONFIG_MODULES=y                     # 模块支持
CONFIG_MODULE_UNLOAD=y               # 模块卸载
CONFIG_MODVERSIONS=y                 # 模块版本 (推荐)

# proc 文件系统
CONFIG_PROC_FS=y                     # /proc 文件系统
CONFIG_PROC_SYSCTL=y                 # /proc/sys 支持

# sysfs 文件系统
CONFIG_SYSFS=y                       # /sys 文件系统
```

### 性能事件安全配置

```bash
# 设置 perf 事件权限 (运行时配置)
# 0: 允许所有用户使用 perf 事件
# 1: 仅允许 root 使用内核地址符号
# 2: 仅允许 root 使用 perf 事件
# 3: 完全禁用 perf 事件

# 临时设置 (重启后失效)
echo 1 > /proc/sys/kernel/perf_event_paranoid

# 永久设置 (添加到 /etc/sysctl.conf)
kernel.perf_event_paranoid = 1
```

## 支持的架构

### ARM32 (Cortex-A5/A7/A8/A9/A15)
- **调试架构**: ARMv7 调试架构
- **调试寄存器**: 使用协处理器 p14 寄存器
- **断点数量**: 通常 2-6 个硬件断点
- **监控粒度**: 1、2、4 字节
- **特殊要求**: CONFIG_ARM_UNWIND=y

### ARM64 (ARMv8-A)
- **调试架构**: ARMv8 调试架构
- **调试寄存器**: 使用 AArch64 调试寄存器
- **断点数量**: 通常 2-16 个硬件断点
- **监控粒度**: 1、2、4、8 字节
- **高级特性**: 支持异常级别感知

### x86 (32位)
- **调试寄存器**: DR0-DR7
- **断点数量**: 最多 4 个硬件断点
- **监控粒度**: 1、2、4 字节
- **地址空间**: 32位地址空间

### x86_64 (64位)
- **调试寄存器**: DR0-DR7 (64位扩展)
- **断点数量**: 最多 4 个硬件断点
- **监控粒度**: 1、2、4、8 字节
- **地址空间**: 64位地址空间

## 编译和安装

### 基本编译
```bash
cd tools/memory_monitor_drivers_suite/hardware_watchpoint
make
```

### 检查内核支持
```bash
# 编译前先检查内核配置
make check-config

# 检查硬件支持
make debug
```

### 架构特定编译
```bash
# ARM32 (Cortex-A5)
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-

# ARM64
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-

# x86
make ARCH=x86

# x86_64
make ARCH=x86_64
```

### OpenWrt 编译
```bash
make openwrt
```

### 安装驱动
```bash
make install
```

### 卸载驱动
```bash
make uninstall
```

## 使用方法

### 1. 查看驱动状态
```bash
cat /proc/hw_watchpoint
```

输出示例:
```
=== 硬件 Watchpoint 内存监控驱动 ===
版本: 1.1.0
监控方案: 硬件断点寄存器
架构: ARM64
处理器ID: 0x410fd034
调试版本: ARMv8.0
可用watchpoint: 4
可用breakpoint: 6
内核支持: 硬件断点已启用

=== 监控状态 ===
活跃监控数: 1 / 8
[0] test_variable: 0x0000ffff8b2c4000 (大小:4, 类型:3, 命中:0)

=== 测试变量 ===
test_variable (0xffff8b2c4000): 0
test_buffer (0xffff8b2c4010): "Initial test data"
```

### 2. 添加监控点
```bash
echo "add name address size type" > /proc/hw_watchpoint
```

参数说明:
- `name`: 监控点名称（最大31字符）
- `address`: 监控地址（十六进制，必须对齐）
- `size`: 监控大小（1、2、4、8字节）
- `type`: 监控类型
  - `1`: 只监控读取
  - `2`: 只监控写入
  - `3`: 监控读写

示例:
```bash
# 监控一个 4 字节整数变量的读写
echo "add my_var 0x12345678 4 3" > /proc/hw_watchpoint

# 监控一个字节的写入
echo "add flag_byte 0x12345680 1 2" > /proc/hw_watchpoint

# 监控一个 8 字节指针的读取
echo "add ptr_var 0x12345688 8 1" > /proc/hw_watchpoint
```

### 3. 删除监控点
```bash
echo "del name" > /proc/hw_watchpoint
```

示例:
```bash
echo "del my_var" > /proc/hw_watchpoint
```

### 4. 测试功能

#### 测试读取
```bash
echo "test_read" > /proc/hw_watchpoint
```

#### 测试写入
```bash
echo "test_write value" > /proc/hw_watchpoint
```

示例:
```bash
echo "test_write 12345" > /proc/hw_watchpoint
```

## 监控输出示例

当内存访问被检测到时，内核日志会输出详细信息:

```
🔍 [hw_watchpoint] 硬件断点触发!
监控点: test_variable
地址: 0x0000ffff8b2c4000
命中次数: 1
ARM64 - PC: 0x0000ffffab123456, LR: 0x0000ffffab123400, SP: 0x0000ffffcd234567
当前值: 0x12345678 (305419896)
调用栈信息:
Call trace:
[<ffffab123456>] test_function+0x12/0x34
[<ffffab123789>] main_function+0x56/0x78
[<ffffab123abc>] kernel_thread+0x9a/0xbc
```

## 硬件限制

### ARM32 限制
- **断点数量**: 通常 2-6 个，视具体处理器而定
- **地址对齐**: 必须按大小对齐 (4字节必须4字节对齐)
- **调试权限**: 需要适当的安全状态和异常级别

### ARM64 限制
- **断点数量**: 通常 2-16 个，视具体处理器而定
- **地址对齐**: 必须按大小对齐
- **虚拟化**: 在虚拟化环境中可能受限

### x86/x86_64 限制
- **断点数量**: 固定 4 个硬件断点 (DR0-DR3)
- **地址对齐**: 必须按大小对齐
- **段限制**: 在某些模式下可能受段寄存器限制

## 性能考虑

### 优势
- **零开销**: 不使用时完全无性能影响
- **硬件速度**: 硬件级检测，延迟极小
- **精确定位**: 准确捕获访问瞬间的状态

### 限制
- **数量限制**: 硬件断点数量有限
- **资源冲突**: 与调试器共享硬件资源
- **上下文开销**: 触发时的中断处理有开销

## 与其他监控方式对比

| 特性 | 硬件 Watchpoint | 页面保护 | Kprobe |
|------|----------------|----------|--------|
| 监控粒度 | 字节级 (1-8) | 页面级 (4KB) | 函数级 |
| 监控数量 | 有限 (2-16) | 多个 | 大量 |
| 性能开销 | 极低 | 中等 | 较高 |
| 精确度 | 最高 | 中等 | 中等 |
| 硬件依赖 | 高 | 中等 | 低 |
| 适用场景 | 精确变量监控 | 大块内存 | 系统调用追踪 |

## 故障排除

### 1. 驱动加载失败

**问题**: CONFIG_HAVE_HW_BREAKPOINT 未启用
```bash
# 检查内核配置
make check-config

# 查看编译错误
dmesg | tail -10
```

**问题**: 硬件不支持
```bash
# 检查处理器信息
cat /proc/cpuinfo

# 查看架构特定信息
make debug
```

### 2. 监控不生效

**问题**: 地址未对齐
```bash
# 检查地址对齐
python3 -c "print(f'0x{0x12345678:x} % 4 = {0x12345678 % 4}')"

# 使用对齐的地址
echo "add test 0x12345678 4 3" > /proc/hw_watchpoint
```

**问题**: 硬件断点已用完
```bash
# 查看当前使用情况
cat /proc/hw_watchpoint

# 删除不需要的监控点
echo "del old_monitor" > /proc/hw_watchpoint
```

### 3. 系统不稳定

**问题**: 调试器冲突
```bash
# 停止 GDB 或其他调试器
pkill -f gdb

# 检查是否有其他调试进程
ps aux | grep -E "gdb|strace|ltrace"
```

**问题**: 频繁触发导致性能问题
```bash
# 临时禁用监控
echo "del monitor_name" > /proc/hw_watchpoint

# 卸载驱动
make uninstall
```

## 应用场景

### 1. 变量监控
监控关键变量的改变:
```bash
# 监控一个重要的状态变量
echo "add status_var 0xstatus_addr 4 2" > /proc/hw_watchpoint
```

### 2. 数据结构保护
保护重要数据结构不被意外修改:
```bash
# 监控结构体的关键字段
echo "add struct_field 0xfield_addr 8 2" > /proc/hw_watchpoint
```

### 3. 竞态条件调试
检测多线程访问冲突:
```bash
# 监控共享变量
echo "add shared_var 0xshared_addr 4 3" > /proc/hw_watchpoint
```

### 4. 缓冲区边界检测
监控缓冲区边界访问:
```bash
# 监控缓冲区末尾
echo "add buffer_end 0xbuffer_end 1 3" > /proc/hw_watchpoint
```

## 开发和扩展

### 添加新架构支持
1. 在 `memory_monitor.c` 中添加架构检测
2. 实现架构特定的寄存器访问函数
3. 添加架构特定的调试信息输出

### 扩展监控类型
```c
// 添加新的监控类型
case 4:  // 执行监控
    attr.bp_type = HW_BREAKPOINT_X;
    break;
```

### 优化性能
- 减少中断处理函数的执行时间
- 使用更高效的数据结构
- 优化符号解析过程

## 许可证

本驱动基于 GPL 许可证发布。

## 作者

OpenWrt Tools Project

## 版本历史

- v1.1.0: 完整多架构支持，增强的调试信息
- v1.0.0: 初始版本，基础硬件断点功能 