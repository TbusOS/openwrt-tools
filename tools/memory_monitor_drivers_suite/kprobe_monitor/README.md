# Kprobe 内存监控驱动

## 概述

Kprobe 内存监控驱动使用 Linux 内核探针技术来监控内存访问相关的系统调用和内核函数。通过在函数入口或返回处插入探针，可以捕获详细的函数调用信息、参数、返回值和执行上下文。

## 特性

- ✅ **多架构支持**: ARM32, ARM64, x86, x86_64
- ✅ **函数级监控**: 监控系统调用和内核函数
- ✅ **进程过滤**: 支持按 PID 和进程名过滤
- ✅ **返回值监控**: 支持函数返回值捕获
- ✅ **丰富上下文**: 提供最详细的调用信息
- ✅ **符号解析**: 自动解析函数符号和调用栈

## 工作原理

1. **探针注册**: 在目标函数入口或返回处注册 kprobe/kretprobe
2. **函数拦截**: 当目标函数被调用时触发探针处理函数
3. **信息收集**: 收集寄存器、参数、进程信息等上下文
4. **过滤判断**: 根据设置的过滤条件决定是否记录
5. **详细输出**: 输出完整的函数调用信息和调用栈

## 🏗️ 架构设计图

```
┌─────────────────────────────────────────────────────────────┐
│                      用户空间应用                            │
├─────────────────────────────────────────────────────────────┤
│                 /proc/kprobe_monitor                        │
│             (配置接口 + 状态查看接口)                        │
├─────────────────────────────────────────────────────────────┤
│                kprobe_monitor.ko 驱动模块                   │
│  ┌─────────────────┬────────────────┬─────────────────────┐  │
│  │   探针管理       │   事件处理      │    架构适配层        │  │
│  │ - kprobe 注册   │ - 函数拦截      │ - ARM32/ARM64      │  │
│  │ - kretprobe 注册│ - 参数解析      │ - x86/x86_64       │  │
│  │ - proc 接口     │ - 上下文收集    │ - 寄存器抽象        │  │
│  │ - 过滤规则      │ - 调用栈解析    │ - 符号解析          │  │
│  │ - 符号查找      │ - 返回值处理    │ - 指令集适配        │  │
│  └─────────────────┴────────────────┴─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                     Linux 内核层                            │
│  ┌─────────────────┬────────────────┬─────────────────────┐  │
│  │   kprobe 框架    │   符号管理      │    进程管理          │  │
│  │ - kprobe 核心   │ - kallsyms     │ - task_struct      │  │
│  │ - kretprobe     │ - 符号查找      │ - 进程上下文        │  │
│  │ - 探针调度      │ - 模块符号      │ - 内存管理          │  │
│  │ - 异常处理      │ - 动态符号      │ - 调度器           │  │
│  └─────────────────┴────────────────┴─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                       硬件层                                │
│           处理器指令集 / 异常处理单元                         │
│  ┌─────────────────┬────────────────┬─────────────────────┐  │
│  │      ARM        │      x86       │      共同特性        │  │
│  │ - ARM/Thumb 指令│ - x86/x64 指令  │ - 断点指令          │  │
│  │ - 异常向量表     │ - 中断向量表    │ - 单步执行          │  │
│  │ - 指令模拟      │ - 指令模拟      │ - 上下文保存        │  │
│  │ - 分支预测      │ - 分支预测      │ - 异常恢复          │  │
│  └─────────────────┴────────────────┴─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## 📊 工作流程图

```
[用户配置监控函数]
        │
        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   符号查找       │───▶│   地址解析       │───▶│   探针类型选择   │
│ - kallsyms 查询 │    │ - 函数地址获取   │    │ - kprobe       │
│ - 模块符号      │    │ - 偏移计算      │    │ - kretprobe    │
│ - 符号验证      │    │ - 权限检查      │    │ - 过滤条件      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │                       │                       │
        ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   探针注册       │    │   异常处理设置   │    │   激活监控      │
│ - 断点指令插入   │    │ - 处理函数绑定   │    │ - 探针启用      │
│ - 原指令保存     │    │ - 异常向量注册   │    │ - 状态记录      │
│ - 探针结构初始化 │    │ - 上下文准备     │    │ - 监控激活      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│                    函数调用监控循环                           │
│                                                            │
│  [程序执行] ──┬─→ [调用被监控函数] ──┬─→ [探针触发]             │
│              │                      │                      │
│              │                      ▼                      │
│              │            ┌─────────────────┐              │
│              │            │   断点指令命中    │              │
│              │            │ - ARM: bkpt/brk │              │
│              │            │ - x86: int3     │              │
│              │            │ - 异常触发       │              │
│              │            └─────────────────┘              │
│              │                      │                      │
│              │                      ▼                      │
│              │            ┌─────────────────┐              │
│              │            │   异常处理函数   │              │
│              │            │ - 上下文保存     │              │
│              │            │ - 探针识别      │              │
│              │            │ - 处理器分发     │              │
│              │            └─────────────────┘              │
│              │                      │                      │
│              │                      ▼                      │
│              │            ┌─────────────────┐              │
│              │            │   过滤检查       │              │
│              │            │ - PID 匹配      │              │
│              │            │ - 进程名匹配     │              │
│              │            │ - 地址范围      │              │
│              │            └─────────────────┘              │
│              │                      │                      │
│              │                      ▼                      │
│              │            ┌─────────────────┐              │
│              │            │   信息收集       │              │
│              │            │ - 寄存器状态     │              │
│              │            │ - 函数参数      │              │
│              │            │ - 进程信息      │              │
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
│              │            ┌─────────────────┐              │
│              │            │   函数执行       │              │
│              │            │ - 单步执行原指令 │              │
│              │            │ - 或跳转到函数   │              │
│              │            │ - 返回值捕获     │              │
│              │            └─────────────────┘              │
│              │                      │                      │
│              │                      ▼                      │
│              └──────────────── [继续执行] ◀─────────────────┘
│
└─────────────────────────────────────────────────────────────┘
```

## 🎯 Kprobe 机制详解

### 探针插入原理
```
┌─────────────────────────────────────────────────────────┐
│                  函数探针插入过程                        │
│                                                         │
│  原始函数代码:                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ sys_mmap:                                           │ │
│  │   0x81234560: push   %rbp          ← 目标插入点     │ │
│  │   0x81234561: mov    %rsp,%rbp                     │ │
│  │   0x81234564: sub    $0x20,%rsp                    │ │
│  │   0x81234568: mov    %rdi,-0x8(%rbp)               │ │
│  │   ...                                               │ │
│  └─────────────────────────────────────────────────────┘ │
│                           │                             │
│                           ▼                             │
│  探针插入后:                                             │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ sys_mmap:                                           │ │
│  │   0x81234560: int3              ← 断点指令 (x86)   │ │
│  │   0x81234561: mov    %rsp,%rbp                     │ │
│  │   0x81234564: sub    $0x20,%rsp                    │ │
│  │   0x81234568: mov    %rdi,-0x8(%rbp)               │ │
│  │   ...                                               │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                         │
│  保存的原始指令:                                         │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ kprobe->opcode = 0x55  (push %rbp)                 │ │
│  │ kprobe->addr = 0x81234560                          │ │
│  │ kprobe->pre_handler = memory_access_handler        │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 架构特定实现

#### ARM32/ARM64 指令处理
```
┌─────────────────────────────────────────────────────────┐
│                   ARM Kprobe 实现                       │
│                                                         │
│  ARM32 指令模式:                                         │
│  ┌─────────────────┐         ┌─────────────────────────┐ │
│  │   ARM 指令      │         │       Thumb 指令         │ │
│  │ (32位固定长度)   │         │    (16/32位变长)        │ │
│  │                │         │                         │ │
│  │ 原指令:         │         │ 原指令:                  │ │
│  │ e1a00000 nop    │         │ 46c0     nop            │ │
│  │               │         │                         │ │
│  │ 断点指令:       │         │ 断点指令:                │ │
│  │ e1200070 bkpt   │         │ be00     bkpt           │ │
│  └─────────────────┘         └─────────────────────────┘ │
│                                                         │
│  ARM64 指令处理:                                         │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ 原指令: d503201f   nop                              │ │
│  │ 断点:   d4200000   brk  #0                         │ │
│  │                                                     │ │
│  │ 异常处理:                                           │ │
│  │ - ESR_EL1: 异常状态寄存器                           │ │
│  │ - FAR_EL1: 故障地址寄存器                           │ │
│  │ - ELR_EL1: 异常链接寄存器                           │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

#### x86/x86_64 指令处理
```
┌─────────────────────────────────────────────────────────┐
│                   x86 Kprobe 实现                       │
│                                                         │
│  指令替换过程:                                           │
│  ┌─────────────────┐         ┌─────────────────────────┐ │
│  │   原始指令      │         │       断点指令           │ │
│  │                │         │                         │ │
│  │ 55    push %rbp │   ───▶  │ cc    int3              │ │
│  │ 48 89 e5        │         │ 89 e5 (保存)            │ │
│  │   mov %rsp,%rbp │         │                         │ │
│  └─────────────────┘         └─────────────────────────┘ │
│                                                         │
│  异常处理流程:                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ INT3 异常触发 → do_int3() → kprobe_handler()        │ │
│  │                ↓                                   │ │
│  │ 1. 保存寄存器状态                                   │ │
│  │ 2. 查找对应的 kprobe                               │ │
│  │ 3. 调用 pre_handler                                │ │
│  │ 4. 单步执行原指令                                   │ │
│  │ 5. 恢复正常执行                                     │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                         │
│  Kretprobe 处理:                                        │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ 函数入口: 替换返回地址为 kretprobe_trampoline      │ │
│  │ 函数返回: 跳转到 trampoline                        │ │
│  │ Trampoline: 调用 ret_handler → 恢复原返回地址      │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## 🔬 探针类型对比

### Kprobe vs Kretprobe
```
┌─────────────────────────────────────────────────────────┐
│                    探针类型对比                          │
│                                                         │
│  ┌─────────────────┐              ┌─────────────────────┐│
│  │     Kprobe      │              │     Kretprobe      ││
│  │   (入口探针)     │              │    (返回探针)       ││
│  │                │              │                    ││
│  │ 触发时机:       │              │ 触发时机:           ││
│  │ - 函数入口      │              │ - 函数返回          ││
│  │                │              │                    ││
│  │ 获取信息:       │              │ 获取信息:           ││
│  │ - 输入参数      │              │ - 返回值            ││
│  │ - 调用上下文    │              │ - 执行时间          ││
│  │ - 寄存器状态    │              │ - 修改的状态        ││
│  │                │              │                    ││
│  │ 性能开销:       │              │ 性能开销:           ││
│  │ - 较低          │              │ - 较高 (需要栈操作) ││
│  │                │              │                    ││
│  │ 实现复杂度:     │              │ 实现复杂度:         ││
│  │ - 简单          │              │ - 复杂 (栈管理)     ││
│  └─────────────────┘              └─────────────────────┘│
│                                                         │
│  组合使用示例:                                           │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ [函数入口] → kprobe_handler                         │ │
│  │     │          - 记录参数                           │ │
│  │     │          - 记录时间戳                         │ │
│  │     ▼                                               │ │
│  │ [函数执行] → 原函数逻辑                             │ │
│  │     │                                               │ │
│  │     ▼                                               │ │
│  │ [函数返回] → kretprobe_handler                      │ │
│  │              - 记录返回值                           │ │
│  │              - 计算执行时间                         │ │
│  │              - 分析结果                            │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## 🔧 内核配置要求

### 必需的内核配置选项

使用 Kprobe 监控驱动**必须**启用以下内核配置选项：

```bash
# 基础 Kprobe 支持
CONFIG_KPROBES=y                    # 内核探针基础支持
CONFIG_HAVE_KPROBES=y               # 架构支持 Kprobes
CONFIG_KPROBES_ON_FTRACE=y          # 基于 ftrace 的 Kprobes (推荐)

# Kretprobe 支持 (用于返回值监控)
CONFIG_KRETPROBES=y                 # 返回探针支持
CONFIG_HAVE_KRETPROBES=y            # 架构支持 Kretprobes

# 符号表支持
CONFIG_KALLSYMS=y                   # 内核符号表
CONFIG_KALLSYMS_ALL=y               # 所有符号 (推荐)
CONFIG_KALLSYMS_EXTRA_PASS=y        # 额外符号处理

# 调用栈追踪
CONFIG_STACKTRACE=y                 # 调用栈追踪支持
CONFIG_STACKTRACE_SUPPORT=y         # 架构支持调用栈追踪
CONFIG_USER_STACKTRACE_SUPPORT=y    # 用户空间调用栈 (可选)

# 调试信息
CONFIG_DEBUG_KERNEL=y               # 内核调试支持
CONFIG_DEBUG_INFO=y                 # 调试信息
CONFIG_FRAME_POINTER=y              # 帧指针 (推荐用于调用栈)

# 动态调试 (可选但推荐)
CONFIG_DYNAMIC_DEBUG=y              # 动态调试
CONFIG_FTRACE=y                     # ftrace 跟踪框架
CONFIG_FUNCTION_TRACER=y            # 函数跟踪器
```

### 架构特定配置

#### ARM32 (Cortex-A5/A7/A8/A9/A15)
```bash
CONFIG_ARM=y
CONFIG_HAVE_KPROBES=y
CONFIG_HAVE_KRETPROBES=y
CONFIG_ARM_UNWIND=y                 # ARM 堆栈展开
CONFIG_UNWINDER_ARM=y               # ARM unwinder
```

#### ARM64 (ARMv8-A)
```bash
CONFIG_ARM64=y
CONFIG_HAVE_KPROBES=y
CONFIG_HAVE_KRETPROBES=y
CONFIG_ARM64_MODULE_PLTS=y          # 模块支持
CONFIG_UNWIND_TABLES=y              # 展开表
```

#### x86/x86_64
```bash
CONFIG_X86=y                        # (或 CONFIG_X86_64=y)
CONFIG_HAVE_KPROBES=y
CONFIG_HAVE_KRETPROBES=y
CONFIG_X86_DECODER_SELFTEST=y       # 指令解码器测试
CONFIG_OPTIMIZE_INLINING=y          # 内联优化
```

### 检查当前内核配置

```bash
# 方法1: 检查 /proc/config.gz (如果可用)
zcat /proc/config.gz | grep -E "CONFIG_KPROBES|CONFIG_KRETPROBES|CONFIG_KALLSYMS|CONFIG_STACKTRACE"

# 方法2: 检查 /boot/config-$(uname -r)
grep -E "CONFIG_KPROBES|CONFIG_KRETPROBES|CONFIG_KALLSYMS|CONFIG_STACKTRACE" /boot/config-$(uname -r)

# 方法3: 使用驱动的检查功能
make check-config

# 方法4: 检查运行时支持
ls /sys/kernel/debug/kprobes/
cat /proc/kallsyms | head -5
```

### 内核模块加载配置

```bash
# 确保可以加载内核模块
CONFIG_MODULES=y                    # 模块支持
CONFIG_MODULE_UNLOAD=y              # 模块卸载
CONFIG_MODVERSIONS=y                # 模块版本 (推荐)

# proc 文件系统
CONFIG_PROC_FS=y                    # /proc 文件系统
CONFIG_PROC_SYSCTL=y                # /proc/sys 支持
```

## 支持的架构

### ARM32 (Cortex-A5/A7/A8/A9/A15)
- 使用 ARM kprobes 框架
- 支持 Thumb 和 ARM 指令集
- 需要 CONFIG_ARM_UNWIND=y

### ARM64 (ARMv8-A)
- 使用 AArch64 kprobes 框架  
- 支持异常级别切换
- 优秀的调用栈追踪能力

### x86/x86_64
- 成熟的 kprobes 支持
- 丰富的调试特性
- 完整的符号信息

## 编译和安装

### 基本编译
```bash
cd tools/memory_monitor_drivers_suite/kprobe_monitor
make
```

### 检查内核支持
```bash
# 编译前先检查内核配置
make check-config

# 查找可用符号
make find-symbols
```

### 架构特定编译
```bash
# ARM32
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
cat /proc/kprobe_monitor
```

输出示例:
```
=== Kprobe 内存监控驱动 ===
版本: 1.2.0
监控方案: 内核探针 (Kprobe/Kretprobe)
架构: ARM64
Kprobe 支持: 已启用
Kretprobe 支持: 已启用
调用栈追踪: 已启用
最大探针数: 16
调用栈深度: 16

=== 监控状态 ===
活跃监控数: 1 / 16
总命中次数: 0
[0] mmap_monitor: sys_mmap @ 0x81234567 (系统调用, 命中:0)

=== 常用监控目标 ===
  sys_mmap: 可用
  sys_munmap: 可用
  sys_brk: 可用
  ...
```

### 2. 添加监控点
```bash
echo "add name symbol type [kret] [pid] [comm]" > /proc/kprobe_monitor
```

参数说明:
- `name`: 监控点名称（最大31字符）
- `symbol`: 函数符号名
- `type`: 监控类型
  - `0`: 系统调用
  - `1`: 内核函数
  - `2`: 用户函数（模块）
  - `3`: 特定地址
- `kret`: 是否使用返回探针 (0=入口, 1=返回, 可选)
- `pid`: 目标进程PID (0=所有进程, 可选)
- `comm`: 目标进程名 (可选)

示例:
```bash
# 监控所有进程的 mmap 系统调用
echo "add mmap_trace sys_mmap 0" > /proc/kprobe_monitor

# 监控特定进程的 munmap (只监控 PID 1234)
echo "add munmap_1234 sys_munmap 0 0 1234" > /proc/kprobe_monitor

# 监控特定程序的 brk (只监控进程名为 "myapp")
echo "add myapp_brk sys_brk 0 0 0 myapp" > /proc/kprobe_monitor

# 使用返回探针监控 mmap 的返回值
echo "add mmap_ret sys_mmap 0 1" > /proc/kprobe_monitor

# 监控内核函数
echo "add alloc_trace __alloc_pages 1" > /proc/kprobe_monitor
```

### 3. 删除监控点
```bash
echo "del name" > /proc/kprobe_monitor
```

示例:
```bash
echo "del mmap_trace" > /proc/kprobe_monitor
```

### 4. 管理命令

#### 列出可用符号
```bash
echo "list_symbols" > /proc/kprobe_monitor
```

#### 清除统计信息
```bash
echo "clear_stats" > /proc/kprobe_monitor
```

## 监控输出示例

### 入口探针输出
```
🔍 [kprobe_monitor] Kprobe 探针触发!
时间: 1640995200.123456
监控点: mmap_trace
函数: sys_mmap @ 0x81234567
命中次数: 1 (总计: 1)
进程信息:
  PID: 1234, TGID: 1234
  进程名: myapp
  UID: 1000, GID: 1000
  虚拟内存: 12345 KB
  RSS: 6789 KB
寄存器状态:
  RIP: 0x0000567890123456, RSP: 0x0000789012345678
  RAX: 0x0000000000000000, RBX: 0x0000789012345000
  RCX: 0x0000000000000022, RDX: 0x0000000000000003
  RSI: 0x0000000000001000, RDI: 0x0000000000000000
mmap参数: addr=0x0, len=4096, prot=0x3, flags=0x22
调用栈 (8 层):
  [0] sys_mmap (0x81234567)
  [1] do_syscall_64 (0x81234568)
  [2] entry_SYSCALL_64 (0x81234569)
  [3] __libc_mmap (0x7f1234567890)
  [4] mmap (0x7f1234567891)
  [5] main (0x401234)
  [6] __libc_start_main (0x7f1234567892)
  [7] _start (0x401000)
```

### 返回探针输出
```
↩️ [kprobe_monitor] Kretprobe 返回探针触发!
监控点: mmap_ret
函数: sys_mmap
进程: myapp[1234]
返回值: 0x7f1234567000
```

## 常用监控目标

### 内存管理系统调用
```bash
# 内存映射
echo "add mmap_monitor sys_mmap 0" > /proc/kprobe_monitor
echo "add munmap_monitor sys_munmap 0" > /proc/kprobe_monitor
echo "add mprotect_monitor sys_mprotect 0" > /proc/kprobe_monitor
echo "add brk_monitor sys_brk 0" > /proc/kprobe_monitor

# 内存分配 (用户空间)
echo "add mmap2_monitor sys_mmap2 0" > /proc/kprobe_monitor  # ARM32
```

### 内核内存管理函数
```bash
# 页面分配
echo "add alloc_pages __alloc_pages 1" > /proc/kprobe_monitor
echo "add free_pages __free_pages 1" > /proc/kprobe_monitor

# 虚拟内存管理
echo "add vm_mmap vm_mmap_pgoff 1" > /proc/kprobe_monitor
echo "add vm_munmap do_munmap 1" > /proc/kprobe_monitor

# 内核内存分配
echo "add kmalloc_trace kmalloc 1" > /proc/kprobe_monitor
echo "add kfree_trace kfree 1" > /proc/kprobe_monitor
echo "add vmalloc_trace vmalloc 1" > /proc/kprobe_monitor
echo "add vfree_trace vfree 1" > /proc/kprobe_monitor
```

### 内存错误处理
```bash
# 页面错误处理
echo "add page_fault do_page_fault 1" > /proc/kprobe_monitor
echo "add mm_fault handle_mm_fault 1" > /proc/kprobe_monitor

# OOM 处理
echo "add oom_kill oom_kill_process 1" > /proc/kprobe_monitor
```

## 应用场景

### 1. 系统调用追踪
监控程序的所有内存相关系统调用:
```bash
echo "add mmap_trace sys_mmap 0" > /proc/kprobe_monitor
echo "add munmap_trace sys_munmap 0" > /proc/kprobe_monitor
echo "add brk_trace sys_brk 0" > /proc/kprobe_monitor
```

### 2. 进程特定监控
只监控特定进程的内存操作:
```bash
# 监控 PID 1234 的内存操作
echo "add app_mmap sys_mmap 0 0 1234" > /proc/kprobe_monitor

# 监控名为 "nginx" 的进程
echo "add nginx_mmap sys_mmap 0 0 0 nginx" > /proc/kprobe_monitor
```

### 3. 内存泄漏检测
监控内存分配和释放的平衡:
```bash
# 监控分配
echo "add alloc_trace __alloc_pages 1" > /proc/kprobe_monitor
echo "add kmalloc_trace kmalloc 1" > /proc/kprobe_monitor

# 监控释放
echo "add free_trace __free_pages 1" > /proc/kprobe_monitor
echo "add kfree_trace kfree 1" > /proc/kprobe_monitor
```

### 4. 性能分析
分析内存分配的性能瓶颈:
```bash
# 使用返回探针测量函数执行时间
echo "add mmap_perf sys_mmap 0 1" > /proc/kprobe_monitor
```

## 与其他监控方式对比

| 特性 | Kprobe | 硬件 Watchpoint | 页面保护 |
|------|--------|----------------|----------|
| 监控粒度 | 函数级 | 字节级 (1-8) | 页面级 (4KB) |
| 监控数量 | 大量 | 有限 (2-16) | 多个 |
| 性能开销 | 较高 | 极低 | 中等 |
| 上下文信息 | 最丰富 | 丰富 | 中等 |
| 进程过滤 | 支持 | 不支持 | 不支持 |
| 适用场景 | 系统调用追踪 | 精确监控 | 大块内存 |

## 限制和注意事项

### 性能影响
- 每个探针触发都有开销
- 大量探针会显著影响系统性能
- 不适合在生产环境长期使用

### 内核版本兼容性
- 不同内核版本的符号名可能不同
- 某些内联函数无法监控
- 需要检查目标符号是否存在

### 安全限制
- 需要 root 权限
- 可能被内核安全模块限制
- 某些关键函数不允许插入探针

## 故障排除

### 1. 驱动加载失败

**问题**: CONFIG_KPROBES 未启用
```bash
# 检查内核配置
make check-config

# 重新编译内核并启用 Kprobes
```

**问题**: 符号表不可用
```bash
# 检查 kallsyms
ls -la /proc/kallsyms
cat /proc/kallsyms | head -5

# 启用 CONFIG_KALLSYMS=y
```

### 2. 监控不生效

**问题**: 符号不存在
```bash
# 查找正确的符号名
make find-symbols
grep "mmap" /proc/kallsyms

# 使用正确的符号名
echo "add test __vm_mmap_pgoff 1" > /proc/kprobe_monitor
```

**问题**: 进程过滤不工作
```bash
# 检查进程名和 PID
ps aux | grep myapp
echo "add test sys_mmap 0 0 $(pidof myapp)" > /proc/kprobe_monitor
```

### 3. 系统不稳定

**问题**: 过多探针导致性能问题
```bash
# 删除不必要的监控点
echo "del monitor_name" > /proc/kprobe_monitor

# 清除所有统计信息
echo "clear_stats" > /proc/kprobe_monitor

# 卸载驱动
make uninstall
```

## 开发和扩展

### 添加新的监控目标
修改 `kprobe_monitor.c` 中的 `common_targets` 数组:
```c
static const char *common_targets[] = {
    "sys_mmap",
    "sys_munmap",
    "your_new_target",  // 添加新目标
    // ...
};
```

### 添加新的参数解析
在 `print_memory_info()` 函数中添加新的系统调用参数解析:
```c
else if (strcmp(monitor->symbol, "your_syscall") == 0) {
    // 解析你的系统调用参数
    unsigned long param1 = regs->di;  // x86_64
    printk(KERN_INFO "参数1: 0x%lx\n", param1);
}
```

### 扩展架构支持
在驱动源码中添加新架构的寄存器访问:
```c
#elif defined(ARCH_NEW_ARCH)
    printk(KERN_INFO "  REG1: 0x%lx, REG2: 0x%lx\n", 
           regs->reg1, regs->reg2);
```

## 许可证

本驱动基于 GPL v2 许可证发布。

## 作者

OpenWrt Tools Project

## 版本历史

- v1.2.0: 完整功能实现，支持多架构和进程过滤
- v1.1.0: 基础 Kprobe 功能
- v1.0.0: 初始版本 