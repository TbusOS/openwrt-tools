/*
 * 硬件 Watchpoint 内存监控驱动
 * 支持 ARM32 Cortex-A5, ARM64, 和 x86/x64 架构
 * 使用硬件断点寄存器进行精确的内存访问监控
 * 
 * 作者: OpenWrt Tools Project
 * 版本: 1.1.0
 * 日期: 2024
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/hw_breakpoint.h>
#include <linux/perf_event.h>
#include <linux/debugfs.h>
#include <linux/version.h>

#define DRIVER_NAME "hw_watchpoint"
#define DRIVER_VERSION "1.1.0"
#define MAX_MONITORS 8

// 监控配置结构
struct monitor_config {
    unsigned long address;          // 监控地址
    size_t size;                   // 监控大小
    int type;                      // 监控类型 (读/写/读写)
    struct perf_event *event;      // perf事件
    int active;                    // 是否激活
    unsigned long hit_count;       // 命中次数
    char name[32];                 // 监控点名称
};

// 全局变量
static struct monitor_config monitors[MAX_MONITORS];
static int monitor_count = 0;
static struct dentry *debug_dir = NULL;
static struct proc_dir_entry *proc_entry = NULL;

// 测试变量 - 用于验证监控功能
static int test_variable = 0;
static char test_buffer[256] = "Initial test data";

// 模块参数
static unsigned long monitor_addr = 0;
static int monitor_size = 4;
static int monitor_type = 3;  // 默认读写都监控
static char monitor_name[32] = "test_monitor";

module_param(monitor_addr, ulong, 0644);
MODULE_PARM_DESC(monitor_addr, "要监控的内存地址 (默认: 0 - 监控test_variable)");

module_param(monitor_size, int, 0644);
MODULE_PARM_DESC(monitor_size, "监控的字节数 (1, 2, 4, 8)");

module_param(monitor_type, int, 0644);
MODULE_PARM_DESC(monitor_type, "监控类型: 1=读, 2=写, 3=读写");

module_param_string(monitor_name, monitor_name, sizeof(monitor_name), 0644);
MODULE_PARM_DESC(monitor_name, "监控点名称");

// 架构检测和配置
#if defined(CONFIG_ARM) || defined(__arm__)
    #define ARCH_NAME "ARM32"
    #define SUPPORTS_HW_BREAKPOINT
    #define ARCH_ARM32
#elif defined(CONFIG_ARM64) || defined(__aarch64__)
    #define ARCH_NAME "ARM64"
    #define SUPPORTS_HW_BREAKPOINT
    #define ARCH_ARM64
#elif defined(CONFIG_X86) || defined(__i386__)
    #define ARCH_NAME "x86"
    #define SUPPORTS_HW_BREAKPOINT
    #define ARCH_X86_32
#elif defined(CONFIG_X86_64) || defined(__x86_64__)
    #define ARCH_NAME "x86_64"
    #define SUPPORTS_HW_BREAKPOINT
    #define ARCH_X86_64
#else
    #define ARCH_NAME "Unknown"
#endif

// 获取架构特定信息
static void get_arch_info(char *buf, size_t size)
{
    snprintf(buf, size, "架构: %s\n", ARCH_NAME);
    
#ifdef ARCH_ARM32
    u32 midr, debug_arch = 0;
    
    // 读取主处理器ID寄存器
    asm volatile("mrc p15, 0, %0, c0, c0, 0" : "=r" (midr));
    
    // 尝试读取调试ID寄存器
#ifdef CONFIG_HAVE_HW_BREAKPOINT
    u32 dbgdidr;
    asm volatile("mrc p14, 0, %0, c0, c0, 0" : "=r" (dbgdidr));
    debug_arch = (dbgdidr >> 16) & 0xf;
    int num_wp = ((dbgdidr >> 28) & 0xf) + 1;
    
    snprintf(buf + strlen(buf), size - strlen(buf),
             "处理器ID: 0x%08x\n调试架构: ARMv%d\n可用watchpoint: %d\n",
             midr, debug_arch, num_wp);
#endif

#elif defined(ARCH_ARM64)
    u64 midr_el1, id_aa64dfr0_el1;
    
    // 读取ARM64寄存器
    asm volatile("mrs %0, midr_el1" : "=r" (midr_el1));
    asm volatile("mrs %0, id_aa64dfr0_el1" : "=r" (id_aa64dfr0_el1));
    
    // 解析调试特性
    int debug_ver = (id_aa64dfr0_el1 >> 0) & 0xf;
    int num_wp = ((id_aa64dfr0_el1 >> 20) & 0xf) + 1;
    int num_bp = ((id_aa64dfr0_el1 >> 12) & 0xf) + 1;
    
    snprintf(buf + strlen(buf), size - strlen(buf),
             "处理器ID: 0x%016llx\n调试版本: ARMv8.%d\n"
             "可用watchpoint: %d\n可用breakpoint: %d\n",
             midr_el1, debug_ver, num_wp, num_bp);
    
#elif defined(ARCH_X86_32) || defined(ARCH_X86_64)
    snprintf(buf + strlen(buf), size - strlen(buf),
             "调试寄存器: DR0-DR7 可用\n最大watchpoint: 4\n"
             "支持类型: 执行断点, 数据读写断点\n");
#endif

    // 显示内核配置状态
#ifdef CONFIG_HAVE_HW_BREAKPOINT
    snprintf(buf + strlen(buf), size - strlen(buf),
             "内核支持: 硬件断点已启用\n");
#else
    snprintf(buf + strlen(buf), size - strlen(buf),
             "内核支持: 硬件断点未启用\n");
#endif
}

// watchpoint 触发回调函数
static void memory_access_handler(struct perf_event *bp,
                                 struct perf_sample_data *data,
                                 struct pt_regs *regs)
{
    struct monitor_config *monitor = NULL;
    int i;
    
    // 查找对应的监控配置
    for (i = 0; i < MAX_MONITORS; i++) {
        if (monitors[i].event == bp) {
            monitor = &monitors[i];
            break;
        }
    }
    
    if (!monitor) {
        printk(KERN_WARNING "[%s] 找不到对应的监控配置\n", DRIVER_NAME);
        return;
    }
    
    monitor->hit_count++;
    
    printk(KERN_INFO "🔍 [%s] 硬件断点触发!\n", DRIVER_NAME);
    printk(KERN_INFO "监控点: %s\n", monitor->name);
    printk(KERN_INFO "地址: 0x%016lx\n", monitor->address);
    printk(KERN_INFO "命中次数: %lu\n", monitor->hit_count);
    
    // 显示架构特定的寄存器信息
#ifdef ARCH_ARM32
    printk(KERN_INFO "ARM32 - PC: 0x%08lx, LR: 0x%08lx, CPSR: 0x%08lx\n", 
           instruction_pointer(regs), regs->ARM_lr, regs->ARM_cpsr);
#elif defined(ARCH_ARM64)
    printk(KERN_INFO "ARM64 - PC: 0x%016lx, LR: 0x%016lx, SP: 0x%016lx\n",
           instruction_pointer(regs), regs->regs[30], regs->sp);
#elif defined(ARCH_X86_64)
    printk(KERN_INFO "x86_64 - RIP: 0x%016lx, RSP: 0x%016lx\n", 
           instruction_pointer(regs), regs->sp);
#elif defined(ARCH_X86_32)
    printk(KERN_INFO "x86 - EIP: 0x%08lx, ESP: 0x%08lx\n", 
           instruction_pointer(regs), regs->sp);
#endif
    
    // 显示当前内存内容
    if (monitor->address && monitor->size <= 8) {
        void *ptr = (void *)monitor->address;
        switch (monitor->size) {
        case 1:
            printk(KERN_INFO "当前值: 0x%02x (%d)\n", 
                   *(u8*)ptr, *(u8*)ptr);
            break;
        case 2:
            printk(KERN_INFO "当前值: 0x%04x (%d)\n", 
                   *(u16*)ptr, *(u16*)ptr);
            break;
        case 4:
            printk(KERN_INFO "当前值: 0x%08x (%d)\n", 
                   *(u32*)ptr, *(u32*)ptr);
            break;
        case 8:
            printk(KERN_INFO "当前值: 0x%016llx (%lld)\n", 
                   *(u64*)ptr, *(u64*)ptr);
            break;
        }
    }
    
    // 显示调用栈信息（简化版）
    printk(KERN_INFO "调用栈信息:\n");
    dump_stack();
}

// 设置硬件 watchpoint
static int setup_watchpoint(struct monitor_config *monitor)
{
    struct perf_event_attr attr;
    
    if (!monitor || monitor->active) {
        return -EINVAL;
    }
    
    memset(&attr, 0, sizeof(attr));
    attr.type = PERF_TYPE_BREAKPOINT;
    attr.size = sizeof(attr);
    attr.bp_addr = monitor->address;
    attr.bp_len = monitor->size;
    
    // 设置监控类型
    switch (monitor->type) {
    case 1:  // 只读
        attr.bp_type = HW_BREAKPOINT_R;
        break;
    case 2:  // 只写
        attr.bp_type = HW_BREAKPOINT_W;
        break;
    case 3:  // 读写
        attr.bp_type = HW_BREAKPOINT_W | HW_BREAKPOINT_R;
        break;
    default:
        return -EINVAL;
    }
    
    // 创建 perf 事件
    monitor->event = perf_event_create_kernel_counter(&attr, -1, NULL,
                                                     memory_access_handler, NULL);
    
    if (IS_ERR(monitor->event)) {
        printk(KERN_ERR "[%s] 创建硬件watchpoint失败: %ld\n", 
               DRIVER_NAME, PTR_ERR(monitor->event));
        monitor->event = NULL;
        return PTR_ERR(monitor->event);
    }
    
    monitor->active = 1;
    monitor->hit_count = 0;
    
    printk(KERN_INFO "[%s] ✅ 硬件watchpoint已设置: %s @ 0x%lx (类型:%d, 大小:%zu)\n",
           DRIVER_NAME, monitor->name, monitor->address, monitor->type, monitor->size);
    
    return 0;
}

// 移除 watchpoint
static void remove_watchpoint(struct monitor_config *monitor)
{
    if (monitor && monitor->active && monitor->event) {
        perf_event_release_kernel(monitor->event);
        monitor->event = NULL;
        monitor->active = 0;
        
        printk(KERN_INFO "[%s] 🛑 硬件watchpoint已移除: %s\n", 
               DRIVER_NAME, monitor->name);
    }
}

// proc 文件读取函数
static int memory_monitor_proc_show(struct seq_file *m, void *v)
{
    char arch_info[1024];
    int i;
    
    seq_printf(m, "=== 硬件 Watchpoint 内存监控驱动 ===\n");
    seq_printf(m, "版本: %s\n", DRIVER_VERSION);
    seq_printf(m, "监控方案: 硬件断点寄存器\n");
    
    get_arch_info(arch_info, sizeof(arch_info));
    seq_printf(m, "%s", arch_info);
    
    seq_printf(m, "\n=== 监控状态 ===\n");
    seq_printf(m, "活跃监控数: %d / %d\n", monitor_count, MAX_MONITORS);
    
    for (i = 0; i < MAX_MONITORS; i++) {
        if (monitors[i].active) {
            seq_printf(m, "[%d] %s: 0x%016lx (大小:%zu, 类型:%d, 命中:%lu)\n",
                      i, monitors[i].name, monitors[i].address,
                      monitors[i].size, monitors[i].type, monitors[i].hit_count);
        }
    }
    
    seq_printf(m, "\n=== 测试变量 ===\n");
    seq_printf(m, "test_variable (0x%px): %d\n", &test_variable, test_variable);
    seq_printf(m, "test_buffer (0x%px): \"%.50s\"\n", test_buffer, test_buffer);
    
    seq_printf(m, "\n=== 使用方法 ===\n");
    seq_printf(m, "1. 设置监控: echo 'add <name> <addr> <size> <type>' > /proc/%s\n", DRIVER_NAME);
    seq_printf(m, "2. 删除监控: echo 'del <name>' > /proc/%s\n", DRIVER_NAME);
    seq_printf(m, "3. 测试读取: echo 'test_read' > /proc/%s\n", DRIVER_NAME);
    seq_printf(m, "4. 测试写入: echo 'test_write <value>' > /proc/%s\n", DRIVER_NAME);
    seq_printf(m, "类型: 1=读, 2=写, 3=读写\n");
    seq_printf(m, "大小: 1,2,4,8 字节 (必须对齐)\n");
    
    seq_printf(m, "\n=== 架构特性 ===\n");
#ifdef ARCH_ARM32
    seq_printf(m, "ARM32: 使用协处理器p14调试寄存器\n");
    seq_printf(m, "限制: 通常2-6个同时watchpoint\n");
#elif defined(ARCH_ARM64)
    seq_printf(m, "ARM64: 使用AArch64调试架构\n");
    seq_printf(m, "限制: 通常2-16个同时watchpoint\n");
#elif defined(ARCH_X86_32) || defined(ARCH_X86_64)
    seq_printf(m, "x86/x64: 使用DR0-DR7调试寄存器\n");
    seq_printf(m, "限制: 最多4个同时watchpoint\n");
#endif
    
    return 0;
}

// proc 文件写入函数
static ssize_t memory_monitor_proc_write(struct file *file, const char __user *buffer,
                                        size_t count, loff_t *pos)
{
    char cmd[256];
    char name[32];
    unsigned long addr;
    int size, type, value;
    int i;
    
    if (count >= sizeof(cmd))
        return -EINVAL;
    
    if (copy_from_user(cmd, buffer, count))
        return -EFAULT;
    
    cmd[count] = '\0';
    
    // 处理命令
    if (strncmp(cmd, "add ", 4) == 0) {
        if (sscanf(cmd + 4, "%31s %lx %d %d", name, &addr, &size, &type) == 4) {
            // 验证参数
            if (size != 1 && size != 2 && size != 4 && size != 8) {
                printk(KERN_ERR "[%s] 无效的监控大小: %d\n", DRIVER_NAME, size);
                return -EINVAL;
            }
            if (type < 1 || type > 3) {
                printk(KERN_ERR "[%s] 无效的监控类型: %d\n", DRIVER_NAME, type);
                return -EINVAL;
            }
            if (addr & (size - 1)) {
                printk(KERN_ERR "[%s] 地址未对齐: 0x%lx (size=%d)\n", DRIVER_NAME, addr, size);
                return -EINVAL;
            }
            
            // 查找空闲槽位
            for (i = 0; i < MAX_MONITORS; i++) {
                if (!monitors[i].active) {
                    strncpy(monitors[i].name, name, sizeof(monitors[i].name) - 1);
                    monitors[i].address = addr;
                    monitors[i].size = size;
                    monitors[i].type = type;
                    
                    if (setup_watchpoint(&monitors[i]) == 0) {
                        monitor_count++;
                        printk(KERN_INFO "[%s] 添加硬件watchpoint: %s\n", DRIVER_NAME, name);
                    }
                    break;
                }
            }
            if (i == MAX_MONITORS) {
                printk(KERN_ERR "[%s] 无可用监控槽位\n", DRIVER_NAME);
                return -ENOSPC;
            }
        }
    } else if (strncmp(cmd, "del ", 4) == 0) {
        if (sscanf(cmd + 4, "%31s", name) == 1) {
            for (i = 0; i < MAX_MONITORS; i++) {
                if (monitors[i].active && strcmp(monitors[i].name, name) == 0) {
                    remove_watchpoint(&monitors[i]);
                    memset(&monitors[i], 0, sizeof(monitors[i]));
                    monitor_count--;
                    printk(KERN_INFO "[%s] 删除硬件watchpoint: %s\n", DRIVER_NAME, name);
                    break;
                }
            }
        }
    } else if (strncmp(cmd, "test_read", 9) == 0) {
        // 测试读取
        volatile int val = test_variable;
        printk(KERN_INFO "[%s] 测试读取: test_variable = %d\n", DRIVER_NAME, val);
        
        volatile char ch = test_buffer[0];
        printk(KERN_INFO "[%s] 测试读取: test_buffer[0] = '%c'\n", DRIVER_NAME, ch);
        
    } else if (strncmp(cmd, "test_write ", 11) == 0) {
        if (sscanf(cmd + 11, "%d", &value) == 1) {
            test_variable = value;
            printk(KERN_INFO "[%s] 测试写入: test_variable = %d\n", DRIVER_NAME, value);
            
            snprintf(test_buffer, sizeof(test_buffer), "Updated with value: %d", value);
            printk(KERN_INFO "[%s] 测试写入: test_buffer更新\n", DRIVER_NAME);
        }
    } else {
        printk(KERN_WARNING "[%s] 未知命令: %s\n", DRIVER_NAME, cmd);
        return -EINVAL;
    }
    
    return count;
}

static int memory_monitor_proc_open(struct inode *inode, struct file *file)
{
    return single_open(file, memory_monitor_proc_show, NULL);
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5,6,0)
static const struct proc_ops memory_monitor_proc_ops = {
    .proc_open    = memory_monitor_proc_open,
    .proc_read    = seq_read,
    .proc_write   = memory_monitor_proc_write,
    .proc_lseek   = seq_lseek,
    .proc_release = single_release,
};
#else
static const struct file_operations memory_monitor_proc_ops = {
    .open    = memory_monitor_proc_open,
    .read    = seq_read,
    .write   = memory_monitor_proc_write,
    .llseek  = seq_lseek,
    .release = single_release,
};
#endif

// 模块初始化
static int __init memory_monitor_init(void)
{
    int ret = 0;
    
    printk(KERN_INFO "[%s] 硬件Watchpoint内存监控驱动加载中...\n", DRIVER_NAME);
    
    // 检查硬件支持
#ifndef SUPPORTS_HW_BREAKPOINT
    printk(KERN_ERR "[%s] 当前架构不支持硬件watchpoint\n", DRIVER_NAME);
    return -ENODEV;
#endif
    
    // 初始化监控数组
    memset(monitors, 0, sizeof(monitors));
    
    // 创建 proc 文件
    proc_entry = proc_create(DRIVER_NAME, 0666, NULL, &memory_monitor_proc_ops);
    if (!proc_entry) {
        printk(KERN_ERR "[%s] 创建proc文件失败\n", DRIVER_NAME);
        return -ENOMEM;
    }
    
    // 如果指定了监控地址，设置默认监控
    if (monitor_addr == 0) {
        monitor_addr = (unsigned long)&test_variable;
        strncpy(monitor_name, "test_variable", sizeof(monitor_name));
        printk(KERN_INFO "[%s] 使用默认监控地址: test_variable @ 0x%lx\n", 
               DRIVER_NAME, monitor_addr);
    }
    
    // 设置初始监控点
    strncpy(monitors[0].name, monitor_name, sizeof(monitors[0].name) - 1);
    monitors[0].address = monitor_addr;
    monitors[0].size = monitor_size;
    monitors[0].type = monitor_type;
    
    ret = setup_watchpoint(&monitors[0]);
    if (ret == 0) {
        monitor_count = 1;
    }
    
    char arch_info[1024];
    get_arch_info(arch_info, sizeof(arch_info));
    printk(KERN_INFO "[%s] ✅ 硬件Watchpoint驱动加载成功!\n", DRIVER_NAME);
    printk(KERN_INFO "%s", arch_info);
    printk(KERN_INFO "[%s] 使用: cat /proc/%s 查看状态\n", DRIVER_NAME, DRIVER_NAME);
    
    return 0;
}

// 模块卸载
static void __exit memory_monitor_exit(void)
{
    int i;
    
    // 移除所有监控点
    for (i = 0; i < MAX_MONITORS; i++) {
        if (monitors[i].active) {
            remove_watchpoint(&monitors[i]);
        }
    }
    
    // 删除 proc 文件
    if (proc_entry) {
        proc_remove(proc_entry);
    }
    
    printk(KERN_INFO "[%s] 🛑 硬件Watchpoint驱动已卸载\n", DRIVER_NAME);
}

module_init(memory_monitor_init);
module_exit(memory_monitor_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("OpenWrt Tools Project");
MODULE_DESCRIPTION("硬件Watchpoint内存监控驱动 - 支持ARM32/ARM64/x86/x64");
MODULE_VERSION(DRIVER_VERSION);
MODULE_ALIAS("hw-watchpoint"); 