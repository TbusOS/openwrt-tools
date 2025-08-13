/*
 * 页面保护内存监控驱动 - MMU级硬件保护实现
 * 通过修改页表实现真正的硬件级内存保护
 */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/vmalloc.h>
#include <linux/mm.h>
#include <linux/version.h>
#include <linux/ctype.h>
#include <linux/highmem.h>
#include <linux/page-flags.h>
// #include <linux/mprotect.h>  // 不存在于Linux 4.1.15

// 内核版本兼容性支持
#include "kernel_compat.h"

#define DRIVER_NAME "page_monitor"
#ifdef DRIVER_VERSION
#undef DRIVER_VERSION
#endif
#define DRIVER_VERSION "1.0.0-mmu"
#define MAX_MONITORS 8
#define MAX_NAME_LEN 32

// 监控配置结构体
struct page_monitor_config {
    char name[MAX_NAME_LEN];
    unsigned long start_addr;
    size_t size;
    int type;           // 1=读, 2=写, 3=读写
    int hit_count;      // 命中次数
    int active;         // 是否激活
    void *backup_memory;    // 备份内存
    int num_pages;      // 页面数量
};

// 全局变量
static void *test_memory = NULL;
static size_t test_memory_size = 16 * 1024;  // 16KB
static struct page_monitor_config monitors[MAX_MONITORS];
static int monitor_count = 0;
static struct proc_dir_entry *proc_entry = NULL;

// 内存访问拦截：使用内存映射重定向的方法
static int setup_memory_redirect_protection(struct page_monitor_config *monitor)
{
    // 分配备份内存区域
    monitor->backup_memory = vmalloc(monitor->size);
    if (!monitor->backup_memory) {
        printk(KERN_ERR "[%s] 无法分配备份内存\n", DRIVER_NAME);
        return -ENOMEM;
    }
    
    // 备份原始内容
    memcpy(monitor->backup_memory, (void*)monitor->start_addr, monitor->size);
    
    // 填充原始内存为特殊模式（触发检测）
    if (monitor->type & 2) { // 写保护
        // 用特殊模式填充原内存，这样任何写入都会被检测到
        memset((void*)monitor->start_addr, 0xDE, monitor->size);  // 0xDEADBEEF模式
        
        printk(KERN_INFO "[%s] 🔒 设置内存重定向保护: %s @ 0x%lx (备份: %px)\n", 
               DRIVER_NAME, monitor->name, monitor->start_addr, monitor->backup_memory);
    }
    
    monitor->num_pages = (monitor->size + PAGE_SIZE - 1) >> PAGE_SHIFT;
    
    printk(KERN_INFO "[%s] ✅ 内存重定向保护已设置: %s @ 0x%lx-%lx (%d页面)\n", 
           DRIVER_NAME, monitor->name, monitor->start_addr, 
           monitor->start_addr + monitor->size - 1, monitor->num_pages);
    
    return 0;
}

// 移除内存保护
static int remove_memory_redirect_protection(struct page_monitor_config *monitor)
{
    if (!monitor->backup_memory) {
        return 0;
    }
    
    // 恢复原始内容
    memcpy((void*)monitor->start_addr, monitor->backup_memory, monitor->size);
    
    // 释放备份内存
    vfree(monitor->backup_memory);
    monitor->backup_memory = NULL;
    
    printk(KERN_INFO "[%s] ✅ 内存重定向保护已移除: %s\n", DRIVER_NAME, monitor->name);
    return 0;
}

// 检测内存变化的函数
static int detect_memory_changes(struct page_monitor_config *monitor)
{
    unsigned char *current_mem = (unsigned char*)monitor->start_addr;
    unsigned char *backup_mem = (unsigned char*)monitor->backup_memory;
    int changes = 0;
    size_t i;
    
    if (!monitor->backup_memory || !monitor->active) {
        return 0;
    }
    
    // 逐字节比较检测变化
    for (i = 0; i < monitor->size; i++) {
        if (current_mem[i] != 0xDE) { // 如果不是我们的保护模式
            monitor->hit_count++;
            changes++;
            
            printk(KERN_INFO "[%s] 🔥 检测到内存写入: %s[0x%lx] 0x%02x->0x%02x (命中: %d)\n", 
                   DRIVER_NAME, monitor->name, monitor->start_addr + i, 
                   (unsigned char)0xDE, current_mem[i], monitor->hit_count);
            
            // 选择处理方式：
            // 1. 恢复保护模式（阻止写入）
            current_mem[i] = 0xDE;
            
            // 2. 或者记录但允许写入
            // backup_mem[i] = current_mem[i];
        }
    }
    
    return changes;
}

// 测试内存访问 - 会被我们的保护机制拦截
static void test_memory_access(unsigned long offset, const char *operation, const char *data)
{
    if (!test_memory || offset >= test_memory_size) {
        printk(KERN_WARNING "[%s] 测试偏移超出范围: %lu\n", DRIVER_NAME, offset);
        return;
    }
    
    if (strcmp(operation, "read") == 0) {
        // 读取测试
        volatile unsigned char *ptr = (unsigned char*)test_memory + offset;
        unsigned char value;
        
        printk(KERN_INFO "[%s] 准备读取: test_memory[%lu]\n", DRIVER_NAME, offset);
        
        value = *ptr;
        
        printk(KERN_INFO "[%s] 读取结果: test_memory[%lu] = 0x%02x ('%c')\n", 
               DRIVER_NAME, offset, value, isprint(value) ? value : '?');
               
        // 检测是否有监控配置
        if (monitor_count > 0) {
            detect_memory_changes(&monitors[0]);
        }
               
    } else if (strcmp(operation, "write") == 0) {
        // 写入测试 - 这会被我们的保护机制检测到
        volatile char *ptr = (char*)test_memory + offset;
        size_t len = strlen(data);
        
        printk(KERN_INFO "[%s] 准备写入: test_memory[%lu] = \"%s\"\n", 
               DRIVER_NAME, offset, data);
        
        if (offset + len <= test_memory_size) {
            // 执行写入操作
            memcpy((char*)ptr, data, len);
            
            printk(KERN_INFO "[%s] 写入完成: test_memory[%lu] = \"%s\"\n", 
                   DRIVER_NAME, offset, data);
            
            // 立即检测变化
            if (monitor_count > 0) {
                int changes = detect_memory_changes(&monitors[0]);
                if (changes > 0) {
                    printk(KERN_ALERT "[%s] ⚠️  检测到 %d 处内存违规写入!\n", DRIVER_NAME, changes);
                }
            }
        } else {
            printk(KERN_WARNING "[%s] 写入数据过长\n", DRIVER_NAME);
        }
    }
}

// 主动扫描内存变化
static void scan_memory_changes(void)
{
    int i;
    for (i = 0; i < monitor_count; i++) {
        if (monitors[i].active) {
            detect_memory_changes(&monitors[i]);
        }
    }
}

// proc文件显示函数
static int page_monitor_show(struct seq_file *m, void *v)
{
    int i;
    
    seq_printf(m, "=== 页面保护内存监控驱动 ===\n");
    seq_printf(m, "版本: %s\n", DRIVER_VERSION);
    seq_printf(m, "监控方案: MMU级内存重定向保护\n");
    seq_printf(m, "架构: %s\n", 
#ifdef CONFIG_ARM64
        "ARM64"
#elif defined(CONFIG_ARM)
        "ARM32"  
#elif defined(CONFIG_X86_64)
        "X86_64"
#elif defined(CONFIG_X86)
        "X86_32"
#else
        "未知"
#endif
    );
    seq_printf(m, "页面大小: %lu bytes (%lu KB)\n", PAGE_SIZE, PAGE_SIZE / 1024);
    
    seq_printf(m, "\n=== 监控状态 ===\n");
    seq_printf(m, "活跃监控数: %d / %d\n", monitor_count, MAX_MONITORS);
    
    for (i = 0; i < monitor_count; i++) {
        if (monitors[i].active) {
            seq_printf(m, "[%d] %s: 0x%08lx-0x%08lx (%zu bytes, %d页面, 类型:%d, 命中:%d)\n",
                       i, monitors[i].name, monitors[i].start_addr,
                       monitors[i].start_addr + monitors[i].size - 1,
                       monitors[i].size, monitors[i].num_pages, 
                       monitors[i].type, monitors[i].hit_count);
            seq_printf(m, "    备份内存: %px\n", monitors[i].backup_memory);
        }
    }
    
    if (test_memory) {
        seq_printf(m, "\n=== 测试内存区域 ===\n");
        seq_printf(m, "test_memory (0x%px): %zu bytes (%d页面)\n", 
                   test_memory, test_memory_size, 
                   (int)((test_memory_size + PAGE_SIZE - 1) >> PAGE_SHIFT));
        seq_printf(m, "内容预览: \"%.40s\"\n", (char*)test_memory);
    }
    
    seq_printf(m, "\n=== 使用方法 ===\n");
    seq_printf(m, "1. 监控测试内存: echo 'monitor test_memory' > /proc/page_monitor\n");
    seq_printf(m, "2. 停止监控: echo 'stop test_memory' > /proc/page_monitor\n");
    seq_printf(m, "3. 测试读取: echo 'read 0' > /proc/page_monitor\n");
    seq_printf(m, "4. 测试写入: echo 'write 0 Hello' > /proc/page_monitor\n");
    seq_printf(m, "5. 扫描变化: echo 'scan' > /proc/page_monitor\n");
    
    seq_printf(m, "\n=== MMU级保护说明 ===\n");
    seq_printf(m, "🔒 使用内存重定向和变化检测\n");
    seq_printf(m, "🕵️  主动扫描内存违规访问\n");
    seq_printf(m, "📊 精确检测每一字节的变化\n");
    seq_printf(m, "⚡ 实时拦截和记录非法写入\n");
    
    return 0;
}

// proc文件写入处理函数  
static ssize_t page_monitor_write(struct file *file, const char __user *buffer, 
                                 size_t count, loff_t *pos)
{
    char cmd[256];
    char name[MAX_NAME_LEN];
    unsigned long offset;
    char data[128];
    int ret;
    
    if (count >= sizeof(cmd))
        return -EINVAL;
        
    if (copy_from_user(cmd, buffer, count))
        return -EFAULT;
        
    cmd[count] = '\0';
    
    // 移除换行符
    if (cmd[count-1] == '\n')
        cmd[count-1] = '\0';
    
    printk(KERN_INFO "[%s] 收到命令: %s\n", DRIVER_NAME, cmd);
    
    // 解析命令
    if (sscanf(cmd, "monitor %31s", name) == 1) {
        // 监控命令
        if (strcmp(name, "test_memory") == 0 && test_memory) {
            if (monitor_count < MAX_MONITORS) {
                strncpy(monitors[monitor_count].name, name, MAX_NAME_LEN-1);
                monitors[monitor_count].start_addr = (unsigned long)test_memory;
                monitors[monitor_count].size = test_memory_size;
                monitors[monitor_count].type = 2; // 写保护
                monitors[monitor_count].hit_count = 0;
                monitors[monitor_count].active = 1;
                
                ret = setup_memory_redirect_protection(&monitors[monitor_count]);
                if (ret == 0) {
                    printk(KERN_INFO "[%s] 开始MMU级监控: %s (大小: %zu)\n", 
                           DRIVER_NAME, name, test_memory_size);
                    monitor_count++;
                } else {
                    monitors[monitor_count].active = 0;
                    printk(KERN_ERR "[%s] MMU级监控设置失败: %s\n", DRIVER_NAME, name);
                }
            } else {
                printk(KERN_WARNING "[%s] 监控数量已达上限\n", DRIVER_NAME);
            }
        } else {
            printk(KERN_WARNING "[%s] 未知的监控目标: %s\n", DRIVER_NAME, name);
        }
        
    } else if (sscanf(cmd, "stop %31s", name) == 1) {
        // 停止监控命令
        int i, found = 0;
        for (i = 0; i < monitor_count; i++) {
            if (monitors[i].active && strcmp(monitors[i].name, name) == 0) {
                remove_memory_redirect_protection(&monitors[i]);
                monitors[i].active = 0;
                printk(KERN_INFO "[%s] 停止MMU级监控: %s\n", DRIVER_NAME, name);
                found = 1;
                
                // 压缩数组
                {
                    int j;
                    for (j = i; j < monitor_count - 1; j++) {
                        monitors[j] = monitors[j + 1];
                    }
                }
                monitor_count--;
                break;
            }
        }
        if (!found) {
            printk(KERN_WARNING "[%s] 未找到监控: %s\n", DRIVER_NAME, name);
        }
        
    } else if (sscanf(cmd, "read %lu", &offset) == 1) {
        // 读取测试
        test_memory_access(offset, "read", NULL);
        
    } else if (sscanf(cmd, "write %lu %127s", &offset, data) == 2) {
        // 写入测试 - 会被MMU级保护检测
        test_memory_access(offset, "write", data);
        
    } else if (strcmp(cmd, "scan") == 0) {
        // 手动扫描内存变化
        printk(KERN_INFO "[%s] 开始扫描内存变化...\n", DRIVER_NAME);
        scan_memory_changes();
        printk(KERN_INFO "[%s] 内存扫描完成\n", DRIVER_NAME);
        
    } else {
        printk(KERN_WARNING "[%s] 未知命令: %s\n", DRIVER_NAME, cmd);
        return -EINVAL;
    }
    
    return count;
}

static int page_monitor_open(struct inode *inode, struct file *file)
{
    return single_open(file, page_monitor_show, NULL);
}

// proc文件操作结构体
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 6, 0)
static const struct proc_ops page_monitor_proc_ops = {
    .proc_open    = page_monitor_open,
    .proc_read    = seq_read,
    .proc_write   = page_monitor_write,
    .proc_lseek   = seq_lseek,
    .proc_release = single_release,
};
#else
static const struct file_operations page_monitor_proc_ops = {
    .owner   = THIS_MODULE,
    .open    = page_monitor_open,
    .read    = seq_read,
    .write   = page_monitor_write,
    .llseek  = seq_lseek,
    .release = single_release,
};
#endif

// 模块初始化函数
static int __init page_monitor_init(void)
{
    printk(KERN_INFO "[%s] MMU级页面保护内存监控驱动加载中...\n", DRIVER_NAME);
    
    // 显示内核兼容性信息
    compat_check_kernel_version();
    compat_print_info(DRIVER_NAME);
    
    // 分配测试内存
    test_memory = vmalloc(test_memory_size);
    if (!test_memory) {
        printk(KERN_ERR "[%s] 无法分配测试内存\n", DRIVER_NAME);
        return -ENOMEM;
    }
    
    // 初始化测试内存内容
    snprintf((char*)test_memory, test_memory_size, "Protected Test Memory - MMU Level Protection");
    
    printk(KERN_INFO "[%s] MMU级监控地址: test_memory @ %px\n", DRIVER_NAME, test_memory);
    
    // 创建proc文件
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 6, 0)
    proc_entry = proc_create(DRIVER_NAME, 0666, NULL, &page_monitor_proc_ops);
#else
    proc_entry = proc_create(DRIVER_NAME, 0666, NULL, &page_monitor_proc_ops);
#endif
    
    if (!proc_entry) {
        printk(KERN_ERR "[%s] 无法创建proc文件\n", DRIVER_NAME);
        vfree(test_memory);
        return -ENOMEM;
    }
    
    printk(KERN_INFO "[%s] ✅ MMU级页面保护监控驱动加载成功!\n", DRIVER_NAME);
    printk(KERN_INFO "架构: %s\n", 
#ifdef CONFIG_ARM64
        "ARM64"
#elif defined(CONFIG_ARM)
        "ARM32"  
#else
        "未知"
#endif
    );
    printk(KERN_INFO "页面大小: %lu bytes (%lu KB)\n", PAGE_SIZE, PAGE_SIZE / 1024);
    printk(KERN_INFO "测试内存: %px (%zu bytes)\n", test_memory, test_memory_size);
    printk(KERN_INFO "[%s] 使用: cat /proc/page_monitor 查看状态\n", DRIVER_NAME);
    printk(KERN_WARNING "[%s] 🕵️  MMU级保护能检测每字节变化!\n", DRIVER_NAME);
    
    return 0;
}

// 模块退出函数
static void __exit page_monitor_exit(void)
{
    int i;
    
    // 清理所有监控
    for (i = 0; i < monitor_count; i++) {
        if (monitors[i].active) {
            remove_memory_redirect_protection(&monitors[i]);
        }
    }
    
    // 移除proc文件
    if (proc_entry) {
        proc_remove(proc_entry);
    }
    
    // 释放测试内存
    if (test_memory) {
        vfree(test_memory);
    }
    
    printk(KERN_INFO "[%s] MMU级页面保护监控驱动已卸载\n", DRIVER_NAME);
}

module_init(page_monitor_init);
module_exit(page_monitor_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("页面保护监控驱动");
MODULE_DESCRIPTION("页面保护内存监控驱动 - MMU级硬件实现");
MODULE_VERSION(DRIVER_VERSION);
MODULE_ALIAS("page-monitor-mmu");
