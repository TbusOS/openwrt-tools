/*
 * 页面保护内存监控驱动
 * 支持 ARM32, ARM64, 和 x86/x64 架构
 * 使用页面保护机制监控大块内存区域的访问
 * 
 * 作者: OpenWrt Tools Project
 * 版本: 1.0.0
 * 日期: 2024
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/mm.h>
#include <linux/mman.h>
#include <linux/vmalloc.h>
#include <linux/version.h>
#include <linux/highmem.h>
#include <linux/page-flags.h>

#define DRIVER_NAME "page_monitor"
#define DRIVER_VERSION "1.0.0"
#define MAX_MONITORS 8
#define DEFAULT_MONITOR_SIZE (PAGE_SIZE * 4)  // 默认监控4个页面

// 页面监控配置结构
struct page_monitor_config {
    unsigned long start_addr;       // 监控起始地址
    size_t size;                   // 监控大小（字节）
    unsigned long start_pfn;       // 起始页面号
    unsigned long end_pfn;         // 结束页面号
    int type;                      // 监控类型 (读/写/读写)
    int active;                    // 是否激活
    unsigned long hit_count;       // 命中次数
    char name[32];                 // 监控点名称
    struct page **pages;           // 页面指针数组
    int page_count;                // 页面数量
    unsigned long *orig_prot;      // 原始页面保护属性
};

// 全局变量
static struct page_monitor_config monitors[MAX_MONITORS];
static int monitor_count = 0;
static struct proc_dir_entry *proc_entry = NULL;

// 测试内存区域
static char *test_memory = NULL;
static size_t test_memory_size = DEFAULT_MONITOR_SIZE;

// 模块参数
static unsigned long monitor_addr = 0;
static int monitor_size = DEFAULT_MONITOR_SIZE;
static int monitor_type = 3;  // 默认读写都监控
static char monitor_name[32] = "test_page_monitor";

module_param(monitor_addr, ulong, 0644);
MODULE_PARM_DESC(monitor_addr, "要监控的内存地址 (默认: 0 - 监控test_memory)");

module_param(monitor_size, int, 0644);
MODULE_PARM_DESC(monitor_size, "监控的字节数 (必须是PAGE_SIZE的倍数)");

module_param(monitor_type, int, 0644);
MODULE_PARM_DESC(monitor_type, "监控类型: 1=读, 2=写, 3=读写");

module_param_string(monitor_name, monitor_name, sizeof(monitor_name), 0644);
MODULE_PARM_DESC(monitor_name, "监控点名称");

// 架构检测
#if defined(CONFIG_ARM) || defined(__arm__)
    #define ARCH_NAME "ARM32"
    #define SUPPORTS_PAGE_PROTECTION
#elif defined(CONFIG_ARM64) || defined(__aarch64__)
    #define ARCH_NAME "ARM64"
    #define SUPPORTS_PAGE_PROTECTION
#elif defined(CONFIG_X86) || defined(__i386__)
    #define ARCH_NAME "x86"
    #define SUPPORTS_PAGE_PROTECTION
#elif defined(CONFIG_X86_64) || defined(__x86_64__)
    #define ARCH_NAME "x86_64"
    #define SUPPORTS_PAGE_PROTECTION
#else
    #define ARCH_NAME "Unknown"
#endif

// 获取架构信息
static void get_arch_info(char *buf, size_t size)
{
    snprintf(buf, size, "架构: %s\n", ARCH_NAME);
    snprintf(buf + strlen(buf), size - strlen(buf),
             "页面大小: %lu bytes (%lu KB)\n", PAGE_SIZE, PAGE_SIZE / 1024);
    snprintf(buf + strlen(buf), size - strlen(buf),
             "页面移位: %d bits\n", PAGE_SHIFT);
    
#ifdef CONFIG_HIGHMEM
    snprintf(buf + strlen(buf), size - strlen(buf),
             "高端内存: 支持\n");
#else
    snprintf(buf + strlen(buf), size - strlen(buf),
             "高端内存: 不支持\n");
#endif

    snprintf(buf + strlen(buf), size - strlen(buf),
             "虚拟内存: 支持\n");
    snprintf(buf + strlen(buf), size - strlen(buf),
             "页面保护: 读/写/执行控制\n");
}

// 页面错误处理函数
static vm_fault_t page_fault_handler(struct vm_fault *vmf)
{
    struct page_monitor_config *monitor = NULL;
    unsigned long fault_addr = vmf->address;
    unsigned long fault_pfn = fault_addr >> PAGE_SHIFT;
    int i, j;
    
    // 查找对应的监控配置
    for (i = 0; i < MAX_MONITORS; i++) {
        if (monitors[i].active) {
            if (fault_pfn >= monitors[i].start_pfn && fault_pfn <= monitors[i].end_pfn) {
                monitor = &monitors[i];
                break;
            }
        }
    }
    
    if (!monitor) {
        return VM_FAULT_SIGBUS;  // 未找到监控配置
    }
    
    monitor->hit_count++;
    
    printk(KERN_INFO "📄 [%s] 页面访问检测!\n", DRIVER_NAME);
    printk(KERN_INFO "监控点: %s\n", monitor->name);
    printk(KERN_INFO "故障地址: 0x%016lx\n", fault_addr);
    printk(KERN_INFO "页面号: %lu\n", fault_pfn);
    printk(KERN_INFO "命中次数: %lu\n", monitor->hit_count);
    
    // 判断访问类型
    if (vmf->flags & FAULT_FLAG_WRITE) {
        printk(KERN_INFO "访问类型: 写入\n");
    } else {
        printk(KERN_INFO "访问类型: 读取\n");
    }
    
    // 显示故障页面信息
    struct page *fault_page = vmf->page;
    if (fault_page) {
        printk(KERN_INFO "页面标志: 0x%lx\n", fault_page->flags);
        printk(KERN_INFO "页面引用: %d\n", page_ref_count(fault_page));
    }
    
    // 临时恢复页面权限，允许访问
    // 然后重新设置保护 (这样可以捕获每次访问)
    for (j = 0; j < monitor->page_count; j++) {
        if (page_to_pfn(monitor->pages[j]) == fault_pfn) {
            // 临时允许访问
            set_page_dirty(monitor->pages[j]);
            break;
        }
    }
    
    return VM_FAULT_NOPAGE;
}

// 设置页面保护
static int setup_page_protection(struct page_monitor_config *monitor)
{
    unsigned long addr, pfn;
    struct page *page;
    int i;
    
    if (!monitor || monitor->active) {
        return -EINVAL;
    }
    
    // 确保地址和大小是页面对齐的
    monitor->start_addr = PAGE_ALIGN(monitor->start_addr);
    monitor->size = PAGE_ALIGN(monitor->size);
    
    monitor->start_pfn = monitor->start_addr >> PAGE_SHIFT;
    monitor->end_pfn = (monitor->start_addr + monitor->size - 1) >> PAGE_SHIFT;
    monitor->page_count = monitor->end_pfn - monitor->start_pfn + 1;
    
    // 分配页面指针数组
    monitor->pages = kzalloc(monitor->page_count * sizeof(struct page *), GFP_KERNEL);
    if (!monitor->pages) {
        return -ENOMEM;
    }
    
    monitor->orig_prot = kzalloc(monitor->page_count * sizeof(unsigned long), GFP_KERNEL);
    if (!monitor->orig_prot) {
        kfree(monitor->pages);
        return -ENOMEM;
    }
    
    // 获取并设置页面保护
    for (i = 0, addr = monitor->start_addr; i < monitor->page_count; i++, addr += PAGE_SIZE) {
        pfn = addr >> PAGE_SHIFT;
        
        if (pfn_valid(pfn)) {
            page = pfn_to_page(pfn);
            monitor->pages[i] = page;
            
            // 保存原始保护属性
            monitor->orig_prot[i] = page->flags;
            
            // 根据监控类型设置保护
            switch (monitor->type) {
            case 1:  // 只读监控
                // 设置为不可读
                ClearPageReserved(page);
                break;
            case 2:  // 只写监控
                // 设置为只读
                SetPageReserved(page);
                break;
            case 3:  // 读写监控
                // 设置为不可访问
                SetPageReserved(page);
                ClearPageDirty(page);
                break;
            default:
                kfree(monitor->pages);
                kfree(monitor->orig_prot);
                return -EINVAL;
            }
        } else {
            printk(KERN_WARNING "[%s] 无效页面: PFN %lu\n", DRIVER_NAME, pfn);
        }
    }
    
    monitor->active = 1;
    monitor->hit_count = 0;
    
    printk(KERN_INFO "[%s] ✅ 页面保护已设置: %s @ 0x%lx-%lx (%d页面)\n",
           DRIVER_NAME, monitor->name, monitor->start_addr, 
           monitor->start_addr + monitor->size - 1, monitor->page_count);
    
    return 0;
}

// 移除页面保护
static void remove_page_protection(struct page_monitor_config *monitor)
{
    int i;
    
    if (!monitor || !monitor->active) {
        return;
    }
    
    // 恢复原始页面保护属性
    for (i = 0; i < monitor->page_count; i++) {
        if (monitor->pages[i]) {
            monitor->pages[i]->flags = monitor->orig_prot[i];
        }
    }
    
    // 释放内存
    kfree(monitor->pages);
    kfree(monitor->orig_prot);
    monitor->pages = NULL;
    monitor->orig_prot = NULL;
    monitor->active = 0;
    
    printk(KERN_INFO "[%s] 🛑 页面保护已移除: %s\n", 
           DRIVER_NAME, monitor->name);
}

// proc 文件读取函数
static int page_monitor_proc_show(struct seq_file *m, void *v)
{
    char arch_info[1024];
    int i;
    
    seq_printf(m, "=== 页面保护内存监控驱动 ===\n");
    seq_printf(m, "版本: %s\n", DRIVER_VERSION);
    seq_printf(m, "监控方案: 页面保护机制\n");
    
    get_arch_info(arch_info, sizeof(arch_info));
    seq_printf(m, "%s", arch_info);
    
    seq_printf(m, "\n=== 监控状态 ===\n");
    seq_printf(m, "活跃监控数: %d / %d\n", monitor_count, MAX_MONITORS);
    
    for (i = 0; i < MAX_MONITORS; i++) {
        if (monitors[i].active) {
            seq_printf(m, "[%d] %s: 0x%016lx-%016lx (%zu bytes, %d页面, 类型:%d, 命中:%lu)\n",
                      i, monitors[i].name, monitors[i].start_addr,
                      monitors[i].start_addr + monitors[i].size - 1,
                      monitors[i].size, monitors[i].page_count,
                      monitors[i].type, monitors[i].hit_count);
        }
    }
    
    seq_printf(m, "\n=== 测试内存区域 ===\n");
    if (test_memory) {
        seq_printf(m, "test_memory (0x%px): %zu bytes (%lu页面)\n", 
                  test_memory, test_memory_size, test_memory_size / PAGE_SIZE);
        seq_printf(m, "内容预览: \"%.50s\"\n", test_memory);
    } else {
        seq_printf(m, "test_memory: 未分配\n");
    }
    
    seq_printf(m, "\n=== 使用方法 ===\n");
    seq_printf(m, "1. 设置监控: echo 'add <name> <addr> <size> <type>' > /proc/%s\n", DRIVER_NAME);
    seq_printf(m, "2. 删除监控: echo 'del <name>' > /proc/%s\n", DRIVER_NAME);
    seq_printf(m, "3. 测试读取: echo 'test_read <offset>' > /proc/%s\n", DRIVER_NAME);
    seq_printf(m, "4. 测试写入: echo 'test_write <offset> <data>' > /proc/%s\n", DRIVER_NAME);
    seq_printf(m, "类型: 1=读, 2=写, 3=读写\n");
    seq_printf(m, "大小: 必须是PAGE_SIZE(%lu)的倍数\n", PAGE_SIZE);
    
    seq_printf(m, "\n=== 页面保护特性 ===\n");
    seq_printf(m, "优势: 适合大块内存监控, 开销小\n");
    seq_printf(m, "限制: 页面粒度(%lu字节), 可能影响正常访问\n", PAGE_SIZE);
    seq_printf(m, "适用: 缓冲区溢出检测, 内存泄漏监控\n");
    
    return 0;
}

// proc 文件写入函数
static ssize_t page_monitor_proc_write(struct file *file, const char __user *buffer,
                                      size_t count, loff_t *pos)
{
    char cmd[256];
    char name[32];
    char data[128];
    unsigned long addr;
    int size, type, offset, i;
    
    if (count >= sizeof(cmd))
        return -EINVAL;
    
    if (copy_from_user(cmd, buffer, count))
        return -EFAULT;
    
    cmd[count] = '\0';
    
    // 处理命令
    if (strncmp(cmd, "add ", 4) == 0) {
        if (sscanf(cmd + 4, "%31s %lx %d %d", name, &addr, &size, &type) == 4) {
            // 验证参数
            if (size <= 0 || (size % PAGE_SIZE) != 0) {
                printk(KERN_ERR "[%s] 大小必须是PAGE_SIZE(%lu)的倍数: %d\n", 
                       DRIVER_NAME, PAGE_SIZE, size);
                return -EINVAL;
            }
            if (type < 1 || type > 3) {
                printk(KERN_ERR "[%s] 无效的监控类型: %d\n", DRIVER_NAME, type);
                return -EINVAL;
            }
            if (addr & (PAGE_SIZE - 1)) {
                printk(KERN_ERR "[%s] 地址必须页面对齐: 0x%lx\n", DRIVER_NAME, addr);
                return -EINVAL;
            }
            
            // 查找空闲槽位
            for (i = 0; i < MAX_MONITORS; i++) {
                if (!monitors[i].active) {
                    strncpy(monitors[i].name, name, sizeof(monitors[i].name) - 1);
                    monitors[i].start_addr = addr;
                    monitors[i].size = size;
                    monitors[i].type = type;
                    
                    if (setup_page_protection(&monitors[i]) == 0) {
                        monitor_count++;
                        printk(KERN_INFO "[%s] 添加页面保护监控: %s\n", DRIVER_NAME, name);
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
                    remove_page_protection(&monitors[i]);
                    memset(&monitors[i], 0, sizeof(monitors[i]));
                    monitor_count--;
                    printk(KERN_INFO "[%s] 删除页面保护监控: %s\n", DRIVER_NAME, name);
                    break;
                }
            }
        }
    } else if (strncmp(cmd, "test_read ", 10) == 0) {
        if (sscanf(cmd + 10, "%d", &offset) == 1 && test_memory) {
            if (offset >= 0 && offset < test_memory_size) {
                volatile char val = test_memory[offset];
                printk(KERN_INFO "[%s] 测试读取: test_memory[%d] = 0x%02x ('%c')\n", 
                       DRIVER_NAME, offset, val, val);
            } else {
                printk(KERN_ERR "[%s] 偏移超出范围: %d (max: %zu)\n", 
                       DRIVER_NAME, offset, test_memory_size - 1);
                return -EINVAL;
            }
        }
    } else if (strncmp(cmd, "test_write ", 11) == 0) {
        if (sscanf(cmd + 11, "%d %127s", &offset, data) == 2 && test_memory) {
            if (offset >= 0 && offset < test_memory_size - strlen(data)) {
                strncpy(test_memory + offset, data, strlen(data));
                printk(KERN_INFO "[%s] 测试写入: test_memory[%d] = \"%s\"\n", 
                       DRIVER_NAME, offset, data);
            } else {
                printk(KERN_ERR "[%s] 偏移或数据长度超出范围\n", DRIVER_NAME);
                return -EINVAL;
            }
        }
    } else {
        printk(KERN_WARNING "[%s] 未知命令: %s\n", DRIVER_NAME, cmd);
        return -EINVAL;
    }
    
    return count;
}

static int page_monitor_proc_open(struct inode *inode, struct file *file)
{
    return single_open(file, page_monitor_proc_show, NULL);
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5,6,0)
static const struct proc_ops page_monitor_proc_ops = {
    .proc_open    = page_monitor_proc_open,
    .proc_read    = seq_read,
    .proc_write   = page_monitor_proc_write,
    .proc_lseek   = seq_lseek,
    .proc_release = single_release,
};
#else
static const struct file_operations page_monitor_proc_ops = {
    .open    = page_monitor_proc_open,
    .read    = seq_read,
    .write   = page_monitor_proc_write,
    .llseek  = seq_lseek,
    .release = single_release,
};
#endif

// 模块初始化
static int __init page_monitor_init(void)
{
    int ret = 0;
    
    printk(KERN_INFO "[%s] 页面保护内存监控驱动加载中...\n", DRIVER_NAME);
    
    // 检查平台支持
#ifndef SUPPORTS_PAGE_PROTECTION
    printk(KERN_ERR "[%s] 当前架构不支持页面保护监控\n", DRIVER_NAME);
    return -ENODEV;
#endif
    
    // 初始化监控数组
    memset(monitors, 0, sizeof(monitors));
    
    // 分配测试内存
    test_memory = vmalloc(test_memory_size);
    if (!test_memory) {
        printk(KERN_ERR "[%s] 分配测试内存失败\n", DRIVER_NAME);
        return -ENOMEM;
    }
    memset(test_memory, 0, test_memory_size);
    strcpy(test_memory, "Page Protection Test Memory - Initial Data");
    
    // 创建 proc 文件
    proc_entry = proc_create(DRIVER_NAME, 0666, NULL, &page_monitor_proc_ops);
    if (!proc_entry) {
        printk(KERN_ERR "[%s] 创建proc文件失败\n", DRIVER_NAME);
        vfree(test_memory);
        return -ENOMEM;
    }
    
    // 如果指定了监控地址，设置默认监控
    if (monitor_addr == 0) {
        monitor_addr = (unsigned long)test_memory;
        strncpy(monitor_name, "test_memory", sizeof(monitor_name));
        printk(KERN_INFO "[%s] 使用默认监控地址: test_memory @ 0x%lx\n", 
               DRIVER_NAME, monitor_addr);
    }
    
    // 设置初始监控点
    strncpy(monitors[0].name, monitor_name, sizeof(monitors[0].name) - 1);
    monitors[0].start_addr = monitor_addr;
    monitors[0].size = monitor_size;
    monitors[0].type = monitor_type;
    
    ret = setup_page_protection(&monitors[0]);
    if (ret == 0) {
        monitor_count = 1;
    }
    
    char arch_info[1024];
    get_arch_info(arch_info, sizeof(arch_info));
    printk(KERN_INFO "[%s] ✅ 页面保护监控驱动加载成功!\n", DRIVER_NAME);
    printk(KERN_INFO "%s", arch_info);
    printk(KERN_INFO "[%s] 使用: cat /proc/%s 查看状态\n", DRIVER_NAME, DRIVER_NAME);
    
    return 0;
}

// 模块卸载
static void __exit page_monitor_exit(void)
{
    int i;
    
    // 移除所有监控点
    for (i = 0; i < MAX_MONITORS; i++) {
        if (monitors[i].active) {
            remove_page_protection(&monitors[i]);
        }
    }
    
    // 释放测试内存
    if (test_memory) {
        vfree(test_memory);
    }
    
    // 删除 proc 文件
    if (proc_entry) {
        proc_remove(proc_entry);
    }
    
    printk(KERN_INFO "[%s] 🛑 页面保护监控驱动已卸载\n", DRIVER_NAME);
}

module_init(page_monitor_init);
module_exit(page_monitor_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("OpenWrt Tools Project");
MODULE_DESCRIPTION("页面保护内存监控驱动 - 支持ARM32/ARM64/x86/x64");
MODULE_VERSION(DRIVER_VERSION);
MODULE_ALIAS("page-monitor"); 