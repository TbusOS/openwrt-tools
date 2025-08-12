/*
 * Kprobe 内存监控驱动
 * 支持 ARM32, ARM64, 和 x86/x64 架构
 * 使用内核探针技术监控内存访问相关的系统调用和内核函数
 * 
 * 作者: OpenWrt Tools Project
 * 版本: 1.2.0
 * 日期: 2024
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/kprobes.h>
#include <linux/version.h>
#include <linux/mm.h>
#include <linux/mman.h>
#include <linux/sched.h>
#include <linux/pid.h>
#include <linux/kallsyms.h>
#include <linux/stacktrace.h>
#include <asm/stacktrace.h>
#include <linux/string.h>
#include <linux/time.h>

#define DRIVER_NAME "kprobe_monitor"
#define DRIVER_VERSION "1.2.0"
#define MAX_MONITORS 16
#define MAX_STACK_TRACE 16
#define MAX_SYMBOL_LEN 128

// 监控目标类型
enum monitor_target_type {
    MONITOR_SYSCALL,        // 系统调用
    MONITOR_KERNEL_FUNC,    // 内核函数
    MONITOR_USER_FUNC,      // 用户函数（模块）
    MONITOR_ADDRESS         // 特定地址
};

// 监控配置结构
struct kprobe_monitor_config {
    char name[32];                      // 监控点名称
    char symbol[MAX_SYMBOL_LEN];        // 函数符号名
    unsigned long address;              // 监控地址
    enum monitor_target_type type;      // 监控类型
    int active;                         // 是否激活
    unsigned long hit_count;            // 命中次数
    struct kprobe kp;                   // kprobe 结构
    struct kretprobe krp;               // kretprobe 结构
    int use_kretprobe;                  // 是否使用返回探针
    
    // 过滤条件
    pid_t target_pid;                   // 目标进程PID (0=所有)
    char target_comm[TASK_COMM_LEN];    // 目标进程名
    unsigned long min_addr;             // 最小地址过滤
    unsigned long max_addr;             // 最大地址过滤
};

// 调用栈信息
struct stack_info {
    unsigned long addresses[MAX_STACK_TRACE];
    char symbols[MAX_STACK_TRACE][MAX_SYMBOL_LEN];
    int depth;
};

// 全局变量
static struct kprobe_monitor_config monitors[MAX_MONITORS];
static int monitor_count = 0;
static struct proc_dir_entry *proc_entry = NULL;
static unsigned long total_hits = 0;

// 模块参数
static char monitor_symbol[MAX_SYMBOL_LEN] = "sys_mmap";
static char monitor_name[32] = "mmap_monitor";
static int monitor_type = MONITOR_SYSCALL;
static int use_kretprobe = 0;
static pid_t target_pid = 0;
static char target_comm[TASK_COMM_LEN] = "";

module_param_string(monitor_symbol, monitor_symbol, sizeof(monitor_symbol), 0644);
MODULE_PARM_DESC(monitor_symbol, "要监控的函数符号 (默认: sys_mmap)");

module_param_string(monitor_name, monitor_name, sizeof(monitor_name), 0644);
MODULE_PARM_DESC(monitor_name, "监控点名称");

module_param(monitor_type, int, 0644);
MODULE_PARM_DESC(monitor_type, "监控类型: 0=系统调用, 1=内核函数, 2=用户函数, 3=地址");

module_param(use_kretprobe, int, 0644);
MODULE_PARM_DESC(use_kretprobe, "是否使用返回探针: 0=入口探针, 1=返回探针");

module_param(target_pid, int, 0644);
MODULE_PARM_DESC(target_pid, "目标进程PID (0=所有进程)");

module_param_string(target_comm, target_comm, sizeof(target_comm), 0644);
MODULE_PARM_DESC(target_comm, "目标进程名 (空=所有进程)");

// 架构检测和配置
#if defined(CONFIG_ARM) || defined(__arm__)
    #define ARCH_NAME "ARM32"
    #define SUPPORTS_KPROBES
    #define ARCH_ARM32
#elif defined(CONFIG_ARM64) || defined(__aarch64__)
    #define ARCH_NAME "ARM64"
    #define SUPPORTS_KPROBES
    #define ARCH_ARM64
#elif defined(CONFIG_X86) || defined(__i386__)
    #define ARCH_NAME "x86"
    #define SUPPORTS_KPROBES
    #define ARCH_X86_32
#elif defined(CONFIG_X86_64) || defined(__x86_64__)
    #define ARCH_NAME "x86_64"
    #define SUPPORTS_KPROBES
    #define ARCH_X86_64
#else
    #define ARCH_NAME "Unknown"
#endif

// 获取架构信息
static void get_arch_info(char *buf, size_t size)
{
    snprintf(buf, size, "架构: %s\n", ARCH_NAME);
    
#ifdef CONFIG_KPROBES
    snprintf(buf + strlen(buf), size - strlen(buf),
             "Kprobe 支持: 已启用\n");
#else
    snprintf(buf + strlen(buf), size - strlen(buf),
             "Kprobe 支持: 未启用\n");
#endif

#ifdef CONFIG_KRETPROBES
    snprintf(buf + strlen(buf), size - strlen(buf),
             "Kretprobe 支持: 已启用\n");
#else
    snprintf(buf + strlen(buf), size - strlen(buf),
             "Kretprobe 支持: 未启用\n");
#endif

#ifdef CONFIG_STACKTRACE
    snprintf(buf + strlen(buf), size - strlen(buf),
             "调用栈追踪: 已启用\n");
#else
    snprintf(buf + strlen(buf), size - strlen(buf),
             "调用栈追踪: 未启用\n");
#endif

    snprintf(buf + strlen(buf), size - strlen(buf),
             "最大探针数: %d\n", MAX_MONITORS);
    snprintf(buf + strlen(buf), size - strlen(buf),
             "调用栈深度: %d\n", MAX_STACK_TRACE);
}

// 获取调用栈信息
static void get_stack_trace(struct stack_info *stack)
{
#ifdef CONFIG_STACKTRACE
    unsigned long *entries = stack->addresses;
    int i;
    
    memset(stack, 0, sizeof(*stack));
    
    // 获取调用栈地址
    stack->depth = stack_trace_save(entries, MAX_STACK_TRACE, 0);
    
    // 解析符号名
    for (i = 0; i < stack->depth && i < MAX_STACK_TRACE; i++) {
        char *symbol_name = stack->symbols[i];
        unsigned long offset, size;
        char *modname;
        
        // 获取符号信息
        symbol_name = kallsyms_lookup(entries[i], &size, &offset, &modname, symbol_name);
        
        if (!symbol_name) {
            snprintf(stack->symbols[i], MAX_SYMBOL_LEN, "0x%lx", entries[i]);
        }
    }
#else
    memset(stack, 0, sizeof(*stack));
    stack->depth = 0;
#endif
}

// 检查进程过滤条件
static int check_process_filter(struct kprobe_monitor_config *monitor)
{
    struct task_struct *current_task = current;
    
    // 检查PID过滤
    if (monitor->target_pid != 0 && current_task->pid != monitor->target_pid) {
        return 0;
    }
    
    // 检查进程名过滤
    if (strlen(monitor->target_comm) > 0) {
        if (strncmp(current_task->comm, monitor->target_comm, TASK_COMM_LEN) != 0) {
            return 0;
        }
    }
    
    return 1;
}

// 显示内存相关参数
static void print_memory_info(struct pt_regs *regs, struct kprobe_monitor_config *monitor)
{
    // 根据不同的系统调用/函数显示相关参数
    if (strcmp(monitor->symbol, "sys_mmap") == 0 || 
        strcmp(monitor->symbol, "__vm_mmap_pgoff") == 0) {
        
#if defined(ARCH_X86_64)
        unsigned long addr = regs->di;
        unsigned long len = regs->si;
        unsigned long prot = regs->dx;
        unsigned long flags = regs->cx;
        
        printk(KERN_INFO "mmap参数: addr=0x%lx, len=%lu, prot=0x%lx, flags=0x%lx\n",
               addr, len, prot, flags);
               
#elif defined(ARCH_ARM64)
        unsigned long addr = regs->regs[0];
        unsigned long len = regs->regs[1];
        unsigned long prot = regs->regs[2];
        unsigned long flags = regs->regs[3];
        
        printk(KERN_INFO "mmap参数: addr=0x%lx, len=%lu, prot=0x%lx, flags=0x%lx\n",
               addr, len, prot, flags);
               
#elif defined(ARCH_ARM32)
        unsigned long addr = regs->ARM_r0;
        unsigned long len = regs->ARM_r1;
        unsigned long prot = regs->ARM_r2;
        unsigned long flags = regs->ARM_r3;
        
        printk(KERN_INFO "mmap参数: addr=0x%lx, len=%lu, prot=0x%lx, flags=0x%lx\n",
               addr, len, prot, flags);
#endif
    }
    
    else if (strcmp(monitor->symbol, "sys_munmap") == 0) {
#if defined(ARCH_X86_64)
        unsigned long addr = regs->di;
        unsigned long len = regs->si;
        printk(KERN_INFO "munmap参数: addr=0x%lx, len=%lu\n", addr, len);
        
#elif defined(ARCH_ARM64)
        unsigned long addr = regs->regs[0];
        unsigned long len = regs->regs[1];
        printk(KERN_INFO "munmap参数: addr=0x%lx, len=%lu\n", addr, len);
        
#elif defined(ARCH_ARM32)
        unsigned long addr = regs->ARM_r0;
        unsigned long len = regs->ARM_r1;
        printk(KERN_INFO "munmap参数: addr=0x%lx, len=%lu\n", addr, len);
#endif
    }
    
    else if (strcmp(monitor->symbol, "sys_brk") == 0) {
#if defined(ARCH_X86_64)
        unsigned long addr = regs->di;
        printk(KERN_INFO "brk参数: addr=0x%lx\n", addr);
        
#elif defined(ARCH_ARM64)
        unsigned long addr = regs->regs[0];
        printk(KERN_INFO "brk参数: addr=0x%lx\n", addr);
        
#elif defined(ARCH_ARM32)
        unsigned long addr = regs->ARM_r0;
        printk(KERN_INFO "brk参数: addr=0x%lx\n", addr);
#endif
    }
}

// kprobe 入口处理函数
static int kprobe_pre_handler(struct kprobe *kp, struct pt_regs *regs)
{
    struct kprobe_monitor_config *monitor = container_of(kp, struct kprobe_monitor_config, kp);
    struct stack_info stack;
    struct task_struct *task = current;
    struct timespec64 ts;
    int i;
    
    // 检查过滤条件
    if (!check_process_filter(monitor)) {
        return 0;
    }
    
    monitor->hit_count++;
    total_hits++;
    
    ktime_get_real_ts64(&ts);
    
    printk(KERN_INFO "🔍 [%s] Kprobe 探针触发!\n", DRIVER_NAME);
    printk(KERN_INFO "时间: %ld.%06ld\n", ts.tv_sec, ts.tv_nsec / 1000);
    printk(KERN_INFO "监控点: %s\n", monitor->name);
    printk(KERN_INFO "函数: %s @ 0x%px\n", monitor->symbol, (void *)kp->addr);
    printk(KERN_INFO "命中次数: %lu (总计: %lu)\n", monitor->hit_count, total_hits);
    
    // 进程信息
    printk(KERN_INFO "进程信息:\n");
    printk(KERN_INFO "  PID: %d, TGID: %d\n", task->pid, task->tgid);
    printk(KERN_INFO "  进程名: %s\n", task->comm);
    printk(KERN_INFO "  UID: %u, GID: %u\n", 
           from_kuid(&init_user_ns, task_uid(task)),
           from_kgid(&init_user_ns, task_gid(task)));
    
    // 内存信息
    if (task->mm) {
        printk(KERN_INFO "  虚拟内存: %lu KB\n", 
               (task->mm->total_vm * PAGE_SIZE) >> 10);
        printk(KERN_INFO "  RSS: %lu KB\n",
               get_mm_rss(task->mm) << (PAGE_SHIFT - 10));
    }
    
    // 寄存器信息
    printk(KERN_INFO "寄存器状态:\n");
#if defined(ARCH_X86_64)
    printk(KERN_INFO "  RIP: 0x%016lx, RSP: 0x%016lx\n", 
           regs->ip, regs->sp);
    printk(KERN_INFO "  RAX: 0x%016lx, RBX: 0x%016lx\n", 
           regs->ax, regs->bx);
    printk(KERN_INFO "  RCX: 0x%016lx, RDX: 0x%016lx\n", 
           regs->cx, regs->dx);
    printk(KERN_INFO "  RSI: 0x%016lx, RDI: 0x%016lx\n", 
           regs->si, regs->di);
           
#elif defined(ARCH_ARM64)
    printk(KERN_INFO "  PC: 0x%016lx, SP: 0x%016lx\n", 
           regs->pc, regs->sp);
    printk(KERN_INFO "  LR: 0x%016lx, FP: 0x%016lx\n",
           regs->regs[30], regs->regs[29]);
    printk(KERN_INFO "  X0: 0x%016lx, X1: 0x%016lx\n",
           regs->regs[0], regs->regs[1]);
    printk(KERN_INFO "  X2: 0x%016lx, X3: 0x%016lx\n",
           regs->regs[2], regs->regs[3]);
           
#elif defined(ARCH_ARM32)
    printk(KERN_INFO "  PC: 0x%08lx, SP: 0x%08lx\n", 
           regs->ARM_pc, regs->ARM_sp);
    printk(KERN_INFO "  LR: 0x%08lx, FP: 0x%08lx\n",
           regs->ARM_lr, regs->ARM_fp);
    printk(KERN_INFO "  R0: 0x%08lx, R1: 0x%08lx\n",
           regs->ARM_r0, regs->ARM_r1);
    printk(KERN_INFO "  R2: 0x%08lx, R3: 0x%08lx\n",
           regs->ARM_r2, regs->ARM_r3);
           
#elif defined(ARCH_X86_32)
    printk(KERN_INFO "  EIP: 0x%08lx, ESP: 0x%08lx\n", 
           regs->ip, regs->sp);
    printk(KERN_INFO "  EAX: 0x%08lx, EBX: 0x%08lx\n", 
           regs->ax, regs->bx);
    printk(KERN_INFO "  ECX: 0x%08lx, EDX: 0x%08lx\n", 
           regs->cx, regs->dx);
#endif
    
    // 内存相关参数
    print_memory_info(regs, monitor);
    
    // 调用栈信息
    get_stack_trace(&stack);
    if (stack.depth > 0) {
        printk(KERN_INFO "调用栈 (%d 层):\n", stack.depth);
        for (i = 0; i < stack.depth && i < 8; i++) {  // 限制显示层数
            printk(KERN_INFO "  [%d] %s (0x%lx)\n", 
                   i, stack.symbols[i], stack.addresses[i]);
        }
    }
    
    return 0;
}

// kprobe 错误处理函数
static void kprobe_fault_handler(struct kprobe *kp, struct pt_regs *regs, int trapnr)
{
    struct kprobe_monitor_config *monitor = container_of(kp, struct kprobe_monitor_config, kp);
    
    printk(KERN_ERR "[%s] Kprobe 错误: %s, trapnr=%d\n", 
           DRIVER_NAME, monitor->symbol, trapnr);
}

// kretprobe 返回处理函数
static int kretprobe_ret_handler(struct kretprobe_instance *ri, struct pt_regs *regs)
{
    struct kprobe_monitor_config *monitor = container_of(ri->rp, struct kprobe_monitor_config, krp);
    struct task_struct *task = current;
    
    // 检查过滤条件
    if (!check_process_filter(monitor)) {
        return 0;
    }
    
    monitor->hit_count++;
    total_hits++;
    
    printk(KERN_INFO "↩️ [%s] Kretprobe 返回探针触发!\n", DRIVER_NAME);
    printk(KERN_INFO "监控点: %s\n", monitor->name);
    printk(KERN_INFO "函数: %s\n", monitor->symbol);
    printk(KERN_INFO "进程: %s[%d]\n", task->comm, task->pid);
    
    // 显示返回值
#if defined(ARCH_X86_64)
    printk(KERN_INFO "返回值: 0x%lx\n", regs->ax);
#elif defined(ARCH_ARM64)
    printk(KERN_INFO "返回值: 0x%lx\n", regs->regs[0]);
#elif defined(ARCH_ARM32)
    printk(KERN_INFO "返回值: 0x%lx\n", regs->ARM_r0);
#elif defined(ARCH_X86_32)
    printk(KERN_INFO "返回值: 0x%lx\n", regs->ax);
#endif
    
    return 0;
}

// 设置 kprobe 监控
static int setup_kprobe_monitor(struct kprobe_monitor_config *monitor)
{
    int ret;
    
    if (!monitor || monitor->active) {
        return -EINVAL;
    }
    
    // 查找符号地址
    if (monitor->type != MONITOR_ADDRESS) {
        monitor->address = kallsyms_lookup_name(monitor->symbol);
        if (!monitor->address) {
            printk(KERN_ERR "[%s] 找不到符号: %s\n", DRIVER_NAME, monitor->symbol);
            return -ENOENT;
        }
    }
    
    if (monitor->use_kretprobe) {
        // 设置 kretprobe
        memset(&monitor->krp, 0, sizeof(monitor->krp));
        monitor->krp.handler = kretprobe_ret_handler;
        monitor->krp.maxactive = 20;  // 最大并发实例
        
        if (monitor->type == MONITOR_ADDRESS) {
            monitor->krp.kp.addr = (kprobe_opcode_t *)monitor->address;
        } else {
            monitor->krp.kp.symbol_name = monitor->symbol;
        }
        
        ret = register_kretprobe(&monitor->krp);
        if (ret < 0) {
            printk(KERN_ERR "[%s] 注册kretprobe失败: %s, ret=%d\n", 
                   DRIVER_NAME, monitor->symbol, ret);
            return ret;
        }
        
        printk(KERN_INFO "[%s] ✅ Kretprobe已设置: %s @ 0x%lx\n",
               DRIVER_NAME, monitor->symbol, monitor->address);
    } else {
        // 设置 kprobe
        memset(&monitor->kp, 0, sizeof(monitor->kp));
        monitor->kp.pre_handler = kprobe_pre_handler;
        monitor->kp.fault_handler = kprobe_fault_handler;
        
        if (monitor->type == MONITOR_ADDRESS) {
            monitor->kp.addr = (kprobe_opcode_t *)monitor->address;
        } else {
            monitor->kp.symbol_name = monitor->symbol;
        }
        
        ret = register_kprobe(&monitor->kp);
        if (ret < 0) {
            printk(KERN_ERR "[%s] 注册kprobe失败: %s, ret=%d\n", 
                   DRIVER_NAME, monitor->symbol, ret);
            return ret;
        }
        
        printk(KERN_INFO "[%s] ✅ Kprobe已设置: %s @ 0x%lx\n",
               DRIVER_NAME, monitor->symbol, monitor->address);
    }
    
    monitor->active = 1;
    monitor->hit_count = 0;
    
    return 0;
}

// 移除 kprobe 监控
static void remove_kprobe_monitor(struct kprobe_monitor_config *monitor)
{
    if (!monitor || !monitor->active) {
        return;
    }
    
    if (monitor->use_kretprobe) {
        unregister_kretprobe(&monitor->krp);
        printk(KERN_INFO "[%s] 🛑 Kretprobe已移除: %s\n", 
               DRIVER_NAME, monitor->name);
    } else {
        unregister_kprobe(&monitor->kp);
        printk(KERN_INFO "[%s] 🛑 Kprobe已移除: %s\n", 
               DRIVER_NAME, monitor->name);
    }
    
    monitor->active = 0;
}

// 常用的监控目标
static const char *common_targets[] = {
    "sys_mmap",           // mmap系统调用
    "sys_munmap",         // munmap系统调用  
    "sys_brk",            // brk系统调用
    "sys_mprotect",       // mprotect系统调用
    "do_mmap",            // 内核mmap实现
    "do_munmap",          // 内核munmap实现
    "__vm_mmap_pgoff",    // 虚拟内存映射
    "vm_mmap_pgoff",      // 页面映射
    "mmap_region",        // 内存区域映射
    "vma_merge",          // VMA合并
    "split_vma",          // VMA分割
    "copy_page_range",    // 页面范围复制
    "handle_mm_fault",    // 内存管理错误处理
    "do_page_fault",      // 页面错误处理
    "__alloc_pages",      // 页面分配
    "__free_pages",       // 页面释放
    "kmalloc",            // 内核内存分配
    "kfree",              // 内核内存释放
    "vmalloc",            // 虚拟内存分配
    "vfree"               // 虚拟内存释放
};

// proc 文件读取函数
static int kprobe_monitor_proc_show(struct seq_file *m, void *v)
{
    char arch_info[1024];
    int i;
    
    seq_printf(m, "=== Kprobe 内存监控驱动 ===\n");
    seq_printf(m, "版本: %s\n", DRIVER_VERSION);
    seq_printf(m, "监控方案: 内核探针 (Kprobe/Kretprobe)\n");
    
    get_arch_info(arch_info, sizeof(arch_info));
    seq_printf(m, "%s", arch_info);
    
    seq_printf(m, "\n=== 监控状态 ===\n");
    seq_printf(m, "活跃监控数: %d / %d\n", monitor_count, MAX_MONITORS);
    seq_printf(m, "总命中次数: %lu\n", total_hits);
    
    for (i = 0; i < MAX_MONITORS; i++) {
        if (monitors[i].active) {
            const char *type_str = "";
            switch (monitors[i].type) {
                case MONITOR_SYSCALL: type_str = "系统调用"; break;
                case MONITOR_KERNEL_FUNC: type_str = "内核函数"; break;
                case MONITOR_USER_FUNC: type_str = "用户函数"; break;
                case MONITOR_ADDRESS: type_str = "地址"; break;
            }
            
            seq_printf(m, "[%d] %s: %s @ 0x%lx (%s%s, 命中:%lu)\n",
                      i, monitors[i].name, monitors[i].symbol, monitors[i].address,
                      type_str, monitors[i].use_kretprobe ? ", 返回探针" : "",
                      monitors[i].hit_count);
                      
            if (monitors[i].target_pid != 0) {
                seq_printf(m, "    过滤PID: %d\n", monitors[i].target_pid);
            }
            if (strlen(monitors[i].target_comm) > 0) {
                seq_printf(m, "    过滤进程: %s\n", monitors[i].target_comm);
            }
        }
    }
    
    seq_printf(m, "\n=== 使用方法 ===\n");
    seq_printf(m, "1. 设置监控: echo 'add <name> <symbol> <type> [kret] [pid] [comm]' > /proc/%s\n", DRIVER_NAME);
    seq_printf(m, "2. 删除监控: echo 'del <name>' > /proc/%s\n", DRIVER_NAME);
    seq_printf(m, "3. 列出符号: echo 'list_symbols' > /proc/%s\n", DRIVER_NAME);
    seq_printf(m, "4. 清除统计: echo 'clear_stats' > /proc/%s\n", DRIVER_NAME);
    seq_printf(m, "类型: 0=系统调用, 1=内核函数, 2=用户函数, 3=地址\n");
    seq_printf(m, "kret: 1=使用返回探针, 0=使用入口探针\n");
    
    seq_printf(m, "\n=== 常用监控目标 ===\n");
    for (i = 0; i < ARRAY_SIZE(common_targets); i++) {
        unsigned long addr = kallsyms_lookup_name(common_targets[i]);
        seq_printf(m, "  %s: %s\n", common_targets[i], 
                  addr ? "可用" : "不可用");
    }
    
    seq_printf(m, "\n=== Kprobe 特性 ===\n");
    seq_printf(m, "优势: 精确的函数级监控, 丰富的上下文信息\n");
    seq_printf(m, "适用: 系统调用追踪, 内核函数调试, 行为分析\n");
    seq_printf(m, "注意: 可能影响系统性能, 仅用于调试\n");
    
    return 0;
}

// proc 文件写入函数
static ssize_t kprobe_monitor_proc_write(struct file *file, const char __user *buffer,
                                         size_t count, loff_t *pos)
{
    char cmd[256];
    char name[32];
    char symbol[MAX_SYMBOL_LEN];
    char comm[TASK_COMM_LEN];
    int type, use_kret, pid;
    int i;
    
    if (count >= sizeof(cmd))
        return -EINVAL;
    
    if (copy_from_user(cmd, buffer, count))
        return -EFAULT;
    
    cmd[count] = '\0';
    
    // 处理命令
    if (strncmp(cmd, "add ", 4) == 0) {
        // 解析参数: add name symbol type [kret] [pid] [comm]
        int parsed = sscanf(cmd + 4, "%31s %127s %d %d %d %15s", 
                           name, symbol, &type, &use_kret, &pid, comm);
        
        if (parsed < 3) {
            printk(KERN_ERR "[%s] 参数不足: add <name> <symbol> <type> [kret] [pid] [comm]\n", DRIVER_NAME);
            return -EINVAL;
        }
        
        // 设置默认值
        if (parsed < 4) use_kret = 0;
        if (parsed < 5) pid = 0;
        if (parsed < 6) comm[0] = '\0';
        
        // 验证参数
        if (type < 0 || type > 3) {
            printk(KERN_ERR "[%s] 无效的监控类型: %d\n", DRIVER_NAME, type);
            return -EINVAL;
        }
        
        // 查找空闲槽位
        for (i = 0; i < MAX_MONITORS; i++) {
            if (!monitors[i].active) {
                strncpy(monitors[i].name, name, sizeof(monitors[i].name) - 1);
                strncpy(monitors[i].symbol, symbol, sizeof(monitors[i].symbol) - 1);
                monitors[i].type = type;
                monitors[i].use_kretprobe = use_kret;
                monitors[i].target_pid = pid;
                strncpy(monitors[i].target_comm, comm, sizeof(monitors[i].target_comm) - 1);
                
                if (setup_kprobe_monitor(&monitors[i]) == 0) {
                    monitor_count++;
                    printk(KERN_INFO "[%s] 添加Kprobe监控: %s -> %s\n", 
                           DRIVER_NAME, name, symbol);
                }
                break;
            }
        }
        if (i == MAX_MONITORS) {
            printk(KERN_ERR "[%s] 无可用监控槽位\n", DRIVER_NAME);
            return -ENOSPC;
        }
        
    } else if (strncmp(cmd, "del ", 4) == 0) {
        if (sscanf(cmd + 4, "%31s", name) == 1) {
            for (i = 0; i < MAX_MONITORS; i++) {
                if (monitors[i].active && strcmp(monitors[i].name, name) == 0) {
                    remove_kprobe_monitor(&monitors[i]);
                    memset(&monitors[i], 0, sizeof(monitors[i]));
                    monitor_count--;
                    printk(KERN_INFO "[%s] 删除Kprobe监控: %s\n", DRIVER_NAME, name);
                    break;
                }
            }
        }
        
    } else if (strncmp(cmd, "list_symbols", 12) == 0) {
        printk(KERN_INFO "[%s] 常用监控符号:\n", DRIVER_NAME);
        for (i = 0; i < ARRAY_SIZE(common_targets); i++) {
            unsigned long addr = kallsyms_lookup_name(common_targets[i]);
            printk(KERN_INFO "  %s: 0x%lx %s\n", common_targets[i], addr,
                   addr ? "(可用)" : "(不可用)");
        }
        
    } else if (strncmp(cmd, "clear_stats", 11) == 0) {
        for (i = 0; i < MAX_MONITORS; i++) {
            monitors[i].hit_count = 0;
        }
        total_hits = 0;
        printk(KERN_INFO "[%s] 统计信息已清除\n", DRIVER_NAME);
        
    } else {
        printk(KERN_WARNING "[%s] 未知命令: %s\n", DRIVER_NAME, cmd);
        return -EINVAL;
    }
    
    return count;
}

static int kprobe_monitor_proc_open(struct inode *inode, struct file *file)
{
    return single_open(file, kprobe_monitor_proc_show, NULL);
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5,6,0)
static const struct proc_ops kprobe_monitor_proc_ops = {
    .proc_open    = kprobe_monitor_proc_open,
    .proc_read    = seq_read,
    .proc_write   = kprobe_monitor_proc_write,
    .proc_lseek   = seq_lseek,
    .proc_release = single_release,
};
#else
static const struct file_operations kprobe_monitor_proc_ops = {
    .open    = kprobe_monitor_proc_open,
    .read    = seq_read,
    .write   = kprobe_monitor_proc_write,
    .llseek  = seq_lseek,
    .release = single_release,
};
#endif

// 模块初始化
static int __init kprobe_monitor_init(void)
{
    int ret = 0;
    
    printk(KERN_INFO "[%s] Kprobe内存监控驱动加载中...\n", DRIVER_NAME);
    
    // 检查kprobe支持
#ifndef CONFIG_KPROBES
    printk(KERN_ERR "[%s] 内核未启用Kprobe支持\n", DRIVER_NAME);
    return -ENODEV;
#endif
    
    // 初始化监控数组
    memset(monitors, 0, sizeof(monitors));
    
    // 创建 proc 文件
    proc_entry = proc_create(DRIVER_NAME, 0666, NULL, &kprobe_monitor_proc_ops);
    if (!proc_entry) {
        printk(KERN_ERR "[%s] 创建proc文件失败\n", DRIVER_NAME);
        return -ENOMEM;
    }
    
    // 设置初始监控点
    if (strlen(monitor_symbol) > 0) {
        strncpy(monitors[0].name, monitor_name, sizeof(monitors[0].name) - 1);
        strncpy(monitors[0].symbol, monitor_symbol, sizeof(monitors[0].symbol) - 1);
        monitors[0].type = monitor_type;
        monitors[0].use_kretprobe = use_kretprobe;
        monitors[0].target_pid = target_pid;
        strncpy(monitors[0].target_comm, target_comm, sizeof(monitors[0].target_comm) - 1);
        
        ret = setup_kprobe_monitor(&monitors[0]);
        if (ret == 0) {
            monitor_count = 1;
        } else {
            printk(KERN_WARNING "[%s] 初始监控点设置失败: %s\n", 
                   DRIVER_NAME, monitor_symbol);
        }
    }
    
    char arch_info[1024];
    get_arch_info(arch_info, sizeof(arch_info));
    printk(KERN_INFO "[%s] ✅ Kprobe监控驱动加载成功!\n", DRIVER_NAME);
    printk(KERN_INFO "%s", arch_info);
    printk(KERN_INFO "[%s] 使用: cat /proc/%s 查看状态\n", DRIVER_NAME, DRIVER_NAME);
    
    return 0;
}

// 模块卸载
static void __exit kprobe_monitor_exit(void)
{
    int i;
    
    // 移除所有监控点
    for (i = 0; i < MAX_MONITORS; i++) {
        if (monitors[i].active) {
            remove_kprobe_monitor(&monitors[i]);
        }
    }
    
    // 删除 proc 文件
    if (proc_entry) {
        proc_remove(proc_entry);
    }
    
    printk(KERN_INFO "[%s] 🛑 Kprobe监控驱动已卸载\n", DRIVER_NAME);
}

module_init(kprobe_monitor_init);
module_exit(kprobe_monitor_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("OpenWrt Tools Project");
MODULE_DESCRIPTION("Kprobe内存监控驱动 - 支持ARM32/ARM64/x86/x64");
MODULE_VERSION(DRIVER_VERSION);
MODULE_ALIAS("kprobe-monitor"); 