# 页面保护内存监控驱动

## 概述

页面保护内存监控驱动使用 Linux 页面保护机制来监控大块内存区域的访问。当被监控的内存页面被访问时，会触发页面错误，从而捕获到内存访问行为。

## 特性

- ✅ **多架构支持**: ARM32, ARM64, x86, x86_64
- ✅ **页面级监控**: 以页面为单位监控内存访问
- ✅ **读写检测**: 支持读取、写入、读写监控
- ✅ **大块内存**: 适合监控缓冲区、数组等大块内存
- ✅ **低开销**: 利用硬件页面保护机制，开销相对较小
- ✅ **上下文信息**: 提供详细的访问上下文和调用栈

## 工作原理

1. **页面保护设置**: 修改目标页面的保护属性（只读/不可访问）
2. **访问触发**: 当程序访问被保护的页面时触发页面错误
3. **异常处理**: 在页面错误处理函数中记录访问信息
4. **权限恢复**: 临时恢复页面权限允许正常访问
5. **重新保护**: 重新设置页面保护以继续监控

## 🏗️ 架构设计图

```
┌─────────────────────────────────────────────────────────────┐
│                      用户空间应用                            │
├─────────────────────────────────────────────────────────────┤
│                  /proc/page_monitor                         │
│             (配置接口 + 状态查看接口)                        │
├─────────────────────────────────────────────────────────────┤
│                 page_monitor.ko 驱动模块                    │
│  ┌─────────────────┬────────────────┬─────────────────────┐  │
│  │   页面管理       │   异常处理      │    架构适配层        │  │
│  │ - 监控点管理     │ - 页面错误处理  │ - ARM32/ARM64      │  │
│  │ - proc 接口     │ - 权限管理      │ - x86/x86_64       │  │
│  │ - 页面对齐      │ - 上下文收集    │ - MMU 抽象         │  │
│  │ - 大小检查      │ - 调用栈解析    │ - 页表操作          │  │
│  └─────────────────┴────────────────┴─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                     Linux 内核层                            │
│  ┌─────────────────┬────────────────┬─────────────────────┐  │
│  │   内存管理       │   异常处理      │    符号解析          │  │
│  │ - 页面分配器     │ - 页面错误      │ - kallsyms         │  │
│  │ - VMA 管理      │ - 异常向量      │ - stack_trace      │  │
│  │ - 页表操作      │ - 信号处理      │ - 符号查找          │  │
│  │ - 权限控制      │ - 上下文切换    │ - 地址解析          │  │
│  └─────────────────┴────────────────┴─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                       硬件层                                │
│             MMU (内存管理单元) / 页表硬件                     │
│  ┌─────────────────┬────────────────┬─────────────────────┐  │
│  │      ARM        │      x86       │      共同特性        │  │
│  │ - TTBR 寄存器    │ - CR3 寄存器    │ - 页表遍历          │  │
│  │ - TCR 配置      │ - PDE/PTE      │ - 权限检查          │  │
│  │ - 页表格式      │ - 页目录结构    │ - 地址转换          │  │
│  │ - 域权限       │ - 段页面模式    │ - 异常生成          │  │
│  └─────────────────┴────────────────┴─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## 📊 工作流程图

```
[用户配置监控区域]
        │
        ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   参数验证       │───▶│   页面对齐检查   │───▶│   虚拟内存检查   │
│ - 地址有效性     │    │ - 4KB 对齐      │    │ - VMA 存在      │
│ - 大小范围      │    │ - 边界计算      │    │ - 权限验证      │
│ - 类型有效性     │    │ - 页面数量      │    │ - 地址空间      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │                       │                       │
        ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   保存原始权限   │    │   修改页面权限   │    │   激活监控      │
│ - 记录 PTE 状态  │    │ - 清除可写位     │    │ - 监控点注册    │
│ - 备份页表项     │    │ - 清除可读位     │    │ - 状态记录      │
│ - 权限备份      │    │ - 刷新 TLB      │    │ - 计数初始化     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│                    页面访问监控循环                          │
│                                                             │
│  [程序执行] ──┬─→ [访问被监控页面] ──┬─→ [页面错误触发]      │
│              │                      │                      │
│              │                      ▼                      │
│              │            ┌─────────────────┐              │
│              │            │   页面错误异常   │              │
│              │            │ - ARM: 数据异常 │              │
│              │            │ - x86: #PF异常  │              │
│              │            │ - 错误代码分析   │              │
│              │            └─────────────────┘              │
│              │                      │                      │
│              │                      ▼                      │
│              │            ┌─────────────────┐              │
│              │            │   异常处理函数   │              │
│              │            │ - 获取错误地址   │              │
│              │            │ - 分析访问类型   │              │
│              │            │ - 查找监控点     │              │
│              │            └─────────────────┘              │
│              │                      │                      │
│              │                      ▼                      │
│              │            ┌─────────────────┐              │
│              │            │   权限临时恢复   │              │
│              │            │ - 恢复页面权限   │              │
│              │            │ - 刷新 TLB      │              │
│              │            │ - 允许访问      │              │
│              │            └─────────────────┘              │
│              │                      │                      │
│              │                      ▼                      │
│              │            ┌─────────────────┐              │
│              │            │   上下文收集     │              │
│              │            │ - 进程信息      │              │
│              │            │ - 故障地址      │              │
│              │            │ - 访问类型      │              │
│              │            │ - 调用栈追踪     │              │
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
│              │            │   重新保护页面   │              │
│              │            │ - 恢复保护权限   │              │
│              │            │ - 刷新 TLB      │              │
│              │            │ - 继续监控      │              │
│              │            └─────────────────┘              │
│              │                      │                      │
│              │                      ▼                      │
│              └──────────────── [恢复执行] ◀─────────────────┘
│
└─────────────────────────────────────────────────────────────┘
```

## 🎯 页面保护机制详解

### 页面权限控制
```
┌─────────────────────────────────────────────────────────┐
│                    页面权限位图                          │
│                                                         │
│  原始页面权限:     ┌─────┬─────┬─────┬─────┬─────┬─────┐  │
│  (监控前)         │  P  │  R  │  W  │  X  │  U  │  G  │  │
│                   │  1  │  1  │  1  │  1  │  1  │  0  │  │
│                   └─────┴─────┴─────┴─────┴─────┴─────┘  │
│                                                         │
│  监控配置:                                               │
│  ┌─────────────────┐  ┌─────────────────┐              │
│  │  只读监控        │  │  写入监控        │              │
│  │  (清除写位)      │  │  (清除读写位)    │              │
│  │                │  │                │              │
│  │ ┌─────┬─────────┐ │  │ ┌─────┬─────────┐ │              │
│  │ │  W  │    0    │ │  │ │ R/W │   00    │ │              │
│  │ └─────┴─────────┘ │  │ └─────┴─────────┘ │              │
│  └─────────────────┘  └─────────────────┘              │
│                                                         │
│  监控后页面权限:   ┌─────┬─────┬─────┬─────┬─────┬─────┐  │
│  (读监控)         │  P  │  R  │  W  │  X  │  U  │  G  │  │
│                   │  1  │  1  │  0  │  1  │  1  │  0  │  │
│                   └─────┴─────┴─────┴─────┴─────┴─────┘  │
│                                                         │
│  监控后页面权限:   ┌─────┬─────┬─────┬─────┬─────┬─────┐  │
│  (写监控)         │  P  │  R  │  W  │  X  │  U  │  G  │  │
│                   │  1  │  0  │  0  │  1  │  1  │  0  │  │
│                   └─────┴─────┴─────┴─────┴─────┴─────┘  │
│                                                         │
│  P=Present, R=Read, W=Write, X=Execute, U=User, G=Global│
└─────────────────────────────────────────────────────────┘
```

### 架构特定页表结构

#### ARM64 页表结构
```
┌─────────────────────────────────────────────────────────┐
│                   ARM64 页表层次                         │
│                                                         │
│  虚拟地址 [47:0]                                         │
│  ┌─────────┬─────────┬─────────┬─────────┬─────────────┐ │
│  │ [47:39] │ [38:30] │ [29:21] │ [20:12] │   [11:0]   │ │
│  │  PGD    │  PUD    │  PMD    │  PTE    │   OFFSET   │ │
│  └─────────┴─────────┴─────────┴─────────┴─────────────┘ │
│       │         │         │         │                  │
│       ▼         ▼         ▼         ▼                  │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐        │
│  │   PGD   │ │   PUD   │ │   PMD   │ │   PTE   │        │
│  │  Table  │ │  Table  │ │  Table  │ │  Entry  │        │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘        │
│                                            │            │
│                                            ▼            │
│  ┌─────────────────────────────────────────────────────┐ │
│  │                 页表项 (PTE)                         │ │
│  │                                                     │ │
│  │ [63:59] [58:55] [54:47] [46:12] [11:10] [9:8] [7:0] │ │
│  │ ignore  sw-use  ignore  PFN     access  ap   attr  │ │
│  │                                                     │ │
│  │ 关键位:                                             │ │
│  │ bit 0  : Valid (页面有效)                           │ │
│  │ bit 6  : AP[0] (访问权限)                          │ │
│  │ bit 7  : AP[1] (访问权限)                          │ │
│  │ bit 10 : AF (访问标志)                             │ │
│  │ bit 51 : DBM (脏位管理)                            │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

#### x86_64 页表结构  
```
┌─────────────────────────────────────────────────────────┐
│                   x86_64 页表层次                        │
│                                                         │
│  虚拟地址 [47:0]                                         │
│  ┌─────────┬─────────┬─────────┬─────────┬─────────────┐ │
│  │ [47:39] │ [38:30] │ [29:21] │ [20:12] │   [11:0]   │ │
│  │  PML4   │  PDPT   │   PD    │   PT    │   OFFSET   │ │
│  └─────────┴─────────┴─────────┴─────────┴─────────────┘ │
│       │         │         │         │                  │
│       ▼         ▼         ▼         ▼                  │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐        │
│  │  PML4   │ │  PDPT   │ │   PD    │ │   PT    │        │
│  │  Table  │ │  Table  │ │  Table  │ │  Entry  │        │
│  └─────────┘ └─────────┘ └─────────┘ └─────────┘        │
│                                            │            │
│                                            ▼            │
│  ┌─────────────────────────────────────────────────────┐ │
│  │                 页表项 (PTE)                         │ │
│  │                                                     │ │
│  │ [63] [62:52] [51:12] [11:9] [8] [7] [6] [5] [4:0]   │ │
│  │ XD   avail   PFN     avail  G   PAT PS  A   flags  │ │
│  │                                                     │ │
│  │ 关键位:                                             │ │
│  │ bit 0  : P (Present - 页面存在)                     │ │
│  │ bit 1  : R/W (读/写权限)                           │ │
│  │ bit 2  : U/S (用户/系统权限)                       │ │
│  │ bit 5  : A (Accessed - 访问位)                     │ │
│  │ bit 6  : D (Dirty - 脏位)                          │ │
│  │ bit 63 : XD (Execute Disable)                      │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## 🔧 内核配置要求

### 必需的内核配置选项

使用页面保护内存监控驱动**必须**启用以下内核配置选项：

```bash
# 内存管理基础支持
CONFIG_MMU=y                         # 内存管理单元 (必需)
CONFIG_HIGHMEM=y                     # 高端内存支持 (32位系统)
CONFIG_PAGE_TABLE_ISOLATION=y       # 页表隔离 (x86, 可选)

# 虚拟内存支持
CONFIG_VIRTUAL_MEM=y                 # 虚拟内存支持
CONFIG_VMALLOC=y                     # vmalloc 支持
CONFIG_PROC_VMCORE=y                 # /proc/vmcore 支持 (可选)

# 页面错误处理
CONFIG_FAULT_INJECTION=y             # 错误注入框架 (可选)
CONFIG_FAULT_INJECTION_DEBUG_FS=y    # 错误注入 debugfs (可选)
CONFIG_PAGE_POISONING=y              # 页面中毒 (调试用, 可选)
CONFIG_PAGE_GUARD=y                  # 页面保护 (调试用, 可选)

# 调试支持
CONFIG_DEBUG_KERNEL=y                # 内核调试支持
CONFIG_DEBUG_INFO=y                  # 调试信息
CONFIG_DEBUG_VM=y                    # 虚拟内存调试 (推荐)
CONFIG_DEBUG_PAGEALLOC=y             # 页面分配调试 (可选)
CONFIG_DEBUG_PAGEALLOC_ENABLE_DEFAULT=y  # 默认启用页面分配调试 (可选)

# 页面管理
CONFIG_COMPACTION=y                  # 内存压缩
CONFIG_MIGRATION=y                   # 页面迁移
CONFIG_PAGE_OWNER=y                  # 页面所有者跟踪 (调试用, 可选)
CONFIG_PAGE_EXTENSION=y              # 页面扩展 (可选)

# proc 文件系统
CONFIG_PROC_FS=y                     # /proc 文件系统
CONFIG_PROC_SYSCTL=y                 # /proc/sys 支持
CONFIG_PROC_PAGE_MONITOR=y           # 页面监控 proc 接口 (可选)

# 符号表支持 (用于调用栈解析)
CONFIG_KALLSYMS=y                    # 内核符号表
CONFIG_KALLSYMS_ALL=y                # 所有符号 (推荐)
CONFIG_KALLSYMS_EXTRA_PASS=y         # 额外符号处理

# 调用栈追踪
CONFIG_STACKTRACE=y                  # 调用栈追踪支持
CONFIG_STACKTRACE_SUPPORT=y          # 架构支持调用栈追踪
CONFIG_FRAME_POINTER=y               # 帧指针 (推荐)
```

### 架构特定配置

#### ARM32 (Cortex-A5/A7/A8/A9/A15)
```bash
CONFIG_ARM=y
CONFIG_MMU=y
CONFIG_ARM_LPAE=y                    # 大物理地址扩展 (可选)
CONFIG_HIGHMEM=y                     # 高端内存支持
CONFIG_ARM_UNWIND=y                  # ARM 堆栈展开
CONFIG_UNWINDER_ARM=y                # ARM unwinder

# ARM 内存管理
CONFIG_ARM_DMA_USE_IOMMU=y           # DMA IOMMU 支持 (可选)
CONFIG_ARM_ERRATA_430973=y           # Cortex-A8 errata (如适用)
CONFIG_ARM_ERRATA_458693=y           # Cortex-A8 errata (如适用)
CONFIG_ARM_ERRATA_460075=y           # Cortex-A8 errata (如适用)
CONFIG_ARM_ERRATA_742230=y           # Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_742231=y           # Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_743622=y           # Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_751472=y           # Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_754322=y           # Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_754327=y           # Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_764369=y           # Cortex-A9 errata (如适用)
CONFIG_ARM_ERRATA_775420=y           # Cortex-A9 errata (如适用)

# ARM 页面大小
CONFIG_ARM_4K_PAGES=y                # 4K 页面
# CONFIG_ARM_64K_PAGES=y             # 64K 页面 (替代选项)
```

#### ARM64 (ARMv8-A)
```bash
CONFIG_ARM64=y
CONFIG_MMU=y
CONFIG_ARM64_4K_PAGES=y              # 4K 页面 (推荐)
# CONFIG_ARM64_16K_PAGES=y           # 16K 页面 (替代选项)
# CONFIG_ARM64_64K_PAGES=y           # 64K 页面 (替代选项)

CONFIG_ARM64_VA_BITS_39=y            # 39位虚拟地址 (或其他选项)
# CONFIG_ARM64_VA_BITS_42=y          # 42位虚拟地址
# CONFIG_ARM64_VA_BITS_47=y          # 47位虚拟地址
# CONFIG_ARM64_VA_BITS_48=y          # 48位虚拟地址

CONFIG_ARM64_PAN=y                   # 特权访问保护 (推荐)
CONFIG_ARM64_HW_AFDBM=y              # 硬件访问/脏位管理 (可选)
CONFIG_ARM64_LSE_ATOMICS=y           # LSE 原子操作 (可选)
CONFIG_ARM64_VHE=y                   # 虚拟化主机扩展 (可选)
CONFIG_UNWIND_TABLES=y               # 展开表
CONFIG_ARM64_MODULE_PLTS=y           # 模块 PLT 支持

# ARM64 内存管理
CONFIG_ZONE_DMA=y                    # DMA 区域 (可选)
CONFIG_ZONE_DMA32=y                  # DMA32 区域 (可选)
CONFIG_ARM64_DMA_USE_IOMMU=y         # DMA IOMMU 支持 (可选)
```

#### x86/x86_64
```bash
CONFIG_X86=y                         # (或 CONFIG_X86_64=y)
CONFIG_MMU=y
CONFIG_X86_PAE=y                     # 物理地址扩展 (x86)
CONFIG_HIGHMEM4G=y                   # 4GB 高端内存 (x86)
# CONFIG_HIGHMEM64G=y                # 64GB 高端内存 (x86, 替代选项)

# x86 页面大小
CONFIG_X86_4K_PAGES=y                # 4K 页面
# CONFIG_X86_2M_PAGES=y              # 2M 大页面 (替代选项)
# CONFIG_X86_1G_PAGES=y              # 1G 大页面 (替代选项)

# x86 内存管理特性
CONFIG_X86_PAT=y                     # 页面属性表
CONFIG_X86_INTEL_MEMORY_PROTECTION_KEYS=y  # Intel MPK (可选)
CONFIG_X86_5LEVEL=y                  # 5级页表 (x86_64, 可选)
CONFIG_X86_DIRECT_GBPAGES=y          # 直接 GB 页面映射 (可选)

# x86 特定调试
CONFIG_X86_PTDUMP_CORE=y             # 页表转储核心 (可选)
CONFIG_X86_PTDUMP_DEBUGFS=y          # 页表转储 debugfs (可选)
```

### 检查当前内核配置

```bash
# 方法1: 检查 /proc/config.gz (如果可用)
zcat /proc/config.gz | grep -E "CONFIG_MMU|CONFIG_PROC_FS|CONFIG_DEBUG_VM|CONFIG_STACKTRACE"

# 方法2: 检查 /boot/config-$(uname -r)
grep -E "CONFIG_MMU|CONFIG_PROC_FS|CONFIG_DEBUG_VM|CONFIG_STACKTRACE" /boot/config-$(uname -r)

# 方法3: 使用驱动的检查功能
make check-config

# 方法4: 检查运行时支持
cat /proc/meminfo | grep -E "MemTotal|VmallocTotal"
ls -la /proc/self/maps
```

### 检查页面管理功能

```bash
# 检查页面大小
getconf PAGESIZE
getconf PAGE_SIZE

# 检查虚拟内存统计
cat /proc/vmstat | grep -E "nr_pages|pgalloc|pgfault"

# 检查内存映射
cat /proc/self/maps | head -5

# 检查页面标志 (需要 root)
# 注意: 某些操作可能需要特殊权限
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

# debugfs 文件系统 (可选)
CONFIG_DEBUG_FS=y                    # debugfs 支持
```

### 虚拟内存管理配置

```bash
# 虚拟内存调优参数 (运行时配置)
# 可通过 /proc/sys/vm/ 或 sysctl 设置

# 脏页处理
vm.dirty_background_ratio = 10       # 后台回写阈值
vm.dirty_ratio = 20                  # 强制回写阈值

# 内存回收
vm.swappiness = 60                   # 交换积极性
vm.vfs_cache_pressure = 100          # VFS 缓存压力

# 内存映射
vm.max_map_count = 65530             # 最大内存映射数
vm.mmap_min_addr = 65536             # 最小 mmap 地址

# 页面分配
vm.min_free_kbytes = 67584           # 最小空闲内存
vm.zone_reclaim_mode = 0             # 区域回收模式
```

## 支持的架构

### ARM32 (Cortex-A5/A7/A8/A9/A15)
- 使用 MMU 页面保护机制
- 支持 4KB 页面大小
- 利用页面表权限位控制访问

### ARM64 (ARMv8-A)
- 4KB/16KB/64KB 页面支持
- 2级/3级/4级页面表
- 高级内存保护特性

### x86/x86_64
- 4KB 标准页面
- 2MB/1GB 大页面支持
- NX 位支持

## 编译和安装

### 基本编译
```bash
cd tools/memory_monitor_drivers_suite/page_protection
make
```

### 检查内核支持
```bash
# 编译前先检查内核配置
make check-config

# 检查页面管理支持
make debug
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
cat /proc/page_monitor
```

输出示例:
```
=== 页面保护内存监控驱动 ===
版本: 1.0.0
监控方案: 页面保护机制
架构: ARM64
页面大小: 4096 bytes (4 KB)
页面移位: 12 bits
高端内存: 不支持
虚拟内存: 支持
页面保护: 读/写/执行控制

=== 监控状态 ===
活跃监控数: 1 / 8
[0] test_memory: 0x00007f8b2c000000-0x00007f8b2c003fff (16384 bytes, 4页面, 类型:3, 命中:0)

=== 测试内存区域 ===
test_memory (0x00007f8b2c000000): 16384 bytes (4页面)
内容预览: "Page Protection Test Memory - Initial Data"
```

### 2. 添加监控点
```bash
echo "add monitor_name address size type" > /proc/page_monitor
```

参数说明:
- `monitor_name`: 监控点名称（最大31字符）
- `address`: 监控地址（必须页面对齐）
- `size`: 监控大小（必须是PAGE_SIZE的倍数）
- `type`: 监控类型
  - `1`: 只监控读取
  - `2`: 只监控写入
  - `3`: 监控读写

示例:
```bash
# 监控从地址 0x1000000 开始的 8KB 内存（读写）
echo "add buffer_monitor 0x1000000 8192 3" > /proc/page_monitor

# 监控只写访问
echo "add write_monitor 0x2000000 4096 2" > /proc/page_monitor
```

### 3. 删除监控点
```bash
echo "del monitor_name" > /proc/page_monitor
```

示例:
```bash
echo "del buffer_monitor" > /proc/page_monitor
```

### 4. 测试功能

#### 测试读取
```bash
echo "test_read offset" > /proc/page_monitor
```

示例:
```bash
echo "test_read 0" > /proc/page_monitor     # 读取偏移0处的数据
echo "test_read 100" > /proc/page_monitor   # 读取偏移100处的数据
```

#### 测试写入
```bash
echo "test_write offset data" > /proc/page_monitor
```

示例:
```bash
echo "test_write 0 Hello" > /proc/page_monitor      # 在偏移0写入"Hello"
echo "test_write 100 World" > /proc/page_monitor    # 在偏移100写入"World"
```

## 监控输出示例

当内存访问被检测到时，内核日志会输出详细信息:

```
[12345.678] 📄 [page_monitor] 页面访问检测!
[12345.678] 监控点: test_memory
[12345.678] 故障地址: 0x00007f8b2c000000
[12345.678] 页面号: 180306
[12345.678] 命中次数: 1
[12345.678] 访问类型: 写入
[12345.678] 页面标志: 0x2fffff
[12345.678] 页面引用: 1
```

## 限制和注意事项

### 页面粒度限制
- 监控粒度为页面大小（通常4KB）
- 无法精确监控页面内的特定字节
- 地址必须页面对齐

### 性能影响
- 每次访问会触发页面错误异常
- 适合偶发访问的监控，不适合频繁访问
- 可能影响被监控程序的正常运行

### 架构限制
```bash
# 检查当前架构支持
make debug
```

### 内存类型
- 支持虚拟内存地址
- 支持 vmalloc 分配的内存
- 不支持 DMA 一致性内存
- 不支持保留内存区域

## 应用场景

### 1. 缓冲区溢出检测
监控缓冲区边界，检测越界访问:
```bash
# 分配缓冲区后，监控其边界页面
echo "add buffer_guard 0xbuffer_end 4096 3" > /proc/page_monitor
```

### 2. 内存泄漏监控
监控已释放的内存区域:
```bash
# 在内存释放后继续监控该区域
echo "add freed_memory 0xfreed_addr 8192 3" > /proc/page_monitor
```

### 3. 数据结构监控
监控重要数据结构的访问:
```bash
# 监控关键数据结构
echo "add critical_data 0xstruct_addr 4096 2" > /proc/page_monitor
```

### 4. 调试内存访问
在调试过程中监控特定内存区域:
```bash
# 临时监控问题区域
echo "add debug_region 0xdebug_addr 16384 3" > /proc/page_monitor
```

## 与其他监控方式对比

| 特性 | 页面保护 | 硬件 Watchpoint | Kprobe |
|------|----------|----------------|--------|
| 监控粒度 | 页面级 (4KB) | 字节级 | 函数级 |
| 监控数量 | 多个 | 有限 (2-16) | 大量 |
| 性能开销 | 中等 | 低 | 高 |
| 适用场景 | 大块内存 | 精确监控 | 函数调用 |

## 故障排除

### 1. 驱动加载失败

**问题**: CONFIG_MMU 未启用
```bash
# 检查内核配置
make check-config

# 查看内核版本和配置
uname -r
cat /proc/config.gz | gunzip | grep CONFIG_MMU
```

**问题**: 页面管理不支持
```bash
# 检查页面大小
getconf PAGESIZE

# 检查虚拟内存
cat /proc/meminfo | grep Vmalloc

# 检查架构支持
make debug
```

### 2. 监控不生效

**问题**: 地址未页面对齐
```bash
# 确认地址有效性
cat /proc/page_monitor

# 检查页面对齐
python3 -c "print(f'0x{address:x} % 4096 = {address % 4096}')"
```

**问题**: 内存类型不支持
```bash
# 检查内存映射
cat /proc/self/maps | grep address_range

# 使用 vmalloc 分配的地址进行测试
```

### 3. 系统不稳定

**问题**: 频繁页面错误
```bash
# 立即停止所有监控
echo "del monitor_name" > /proc/page_monitor

# 卸载驱动
make uninstall
```

**问题**: 内存不足
```bash
# 检查内存使用
free -h
cat /proc/meminfo

# 清理缓存
echo 3 > /proc/sys/vm/drop_caches
```

## 开发和扩展

### 添加新的监控类型
修改 `page_monitor.c` 中的类型处理逻辑:
```c
switch (monitor->type) {
case 4:  // 新的监控类型
    // 自定义处理逻辑
    break;
}
```

### 扩展架构支持
在 `page_monitor.c` 中添加新架构的检测:
```c
#elif defined(CONFIG_NEW_ARCH)
    #define ARCH_NAME "new_arch"
    #define SUPPORTS_PAGE_PROTECTION
```

### 优化页面处理
```c
// 添加更高效的页面权限管理
static int optimize_page_protection(struct page *page) {
    // 实现优化逻辑
    return 0;
}
```

## 许可证

本驱动基于 GPL 许可证发布。

## 作者

OpenWrt Tools Project

## 版本历史

- v1.0.0: 初始版本，支持基本页面保护监控功能 