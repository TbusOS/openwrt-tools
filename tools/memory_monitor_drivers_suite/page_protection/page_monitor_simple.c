/*
 * 页面保护内存监控驱动 - 简化版本
 * 避免init_mm依赖，专注于基本功能测试
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

// 内核版本兼容性支持
#include "kernel_compat.h"

#define DRIVER_NAME "page_monitor"
#ifdef DRIVER_VERSION
#undef DRIVER_VERSION
#endif
#define DRIVER_VERSION "1.0.0-simple"
#define MAX_MONITORS 8
#define MAX_NAME_LEN 32

// 监控配置结构体
struct page_monitor_config {
    char name[MAX_NAME_LEN];
    unsigned long start_addr;
    size_t size;
    int type;           // 1=读, 2=写, 3=读写
    int hit_count;      // 命中次数（模拟）
    int active;         // 是否激活
};

// 全局变量
static void *test_memory = NULL;
static size_t test_memory_size = 16 * 1024;  // 16KB
static struct page_monitor_config monitors[MAX_MONITORS];
static int monitor_count = 0;
static struct proc_dir_entry *proc_entry = NULL;

// 页错误处理函数（模拟）
static int page_fault_handler(unsigned long addr, const char *operation)
{
    int i;
    
    // 查找匹配的监控配置
    for (i = 0; i < monitor_count; i++) {
        if (monitors[i].active && 
            addr >= monitors[i].start_addr && 
            addr < monitors[i].start_addr + monitors[i].size) {
            
            monitors[i].hit_count++;
            
            printk(KERN_INFO "[%s] 🔥 内存访问检测: %s[0x%lx] %s操作 (命中: %d)\n", 
                   DRIVER_NAME, monitors[i].name, addr, operation, monitors[i].hit_count);
            
            return 1; // 模拟处理成功
        }
    }
    
    return 0; // 未找到监控配置
}

// 设置页面保护（简化版本）
static int setup_page_protection(struct page_monitor_config *monitor)
{
    printk(KERN_INFO "[%s] ✅ 模拟页面保护已设置: %s @ 0x%lx-%lx (%zu bytes)\n", 
           DRIVER_NAME, monitor->name, monitor->start_addr, 
           monitor->start_addr + monitor->size - 1, monitor->size);
    return 0;
}

// 移除页面保护（简化版本）
static int remove_page_protection(struct page_monitor_config *monitor)
{
    printk(KERN_INFO "[%s] ✅ 模拟页面保护已移除: %s\n", DRIVER_NAME, monitor->name);
    return 0;
}

// proc文件显示函数
static int page_monitor_show(struct seq_file *m, void *v)
{
    int i;
    
    seq_printf(m, "=== 页面保护内存监控驱动 ===\n");
    seq_printf(m, "版本: %s\n", DRIVER_VERSION);
    seq_printf(m, "监控方案: 简化模拟版本\n");
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
            seq_printf(m, "[%d] %s: 0x%08lx-0x%08lx (%zu bytes, 类型:%d, 命中:%d)\n",
                       i, monitors[i].name, monitors[i].start_addr,
                       monitors[i].start_addr + monitors[i].size - 1,
                       monitors[i].size, monitors[i].type, monitors[i].hit_count);
        }
    }
    
    if (test_memory) {
        seq_printf(m, "\n=== 测试内存区域 ===\n");
        seq_printf(m, "test_memory (0x%px): %zu bytes\n", test_memory, test_memory_size);
        seq_printf(m, "内容预览: \"%.40s\"\n", (char*)test_memory);
    }
    
    seq_printf(m, "\n=== 使用方法 ===\n");
    seq_printf(m, "1. 监控测试内存: echo 'monitor test_memory' > /proc/page_monitor\n");
    seq_printf(m, "2. 停止监控: echo 'stop test_memory' > /proc/page_monitor\n");
    seq_printf(m, "3. 测试读取: echo 'read 0' > /proc/page_monitor\n");
    seq_printf(m, "4. 测试写入: echo 'write 0 Hello' > /proc/page_monitor\n");
    
    seq_printf(m, "\n=== 简化版本说明 ===\n");
    seq_printf(m, "此版本避免了复杂的页表操作和符号依赖\n");
    seq_printf(m, "通过模拟的方式演示内存监控的基本概念\n");
    seq_printf(m, "适用于兼容性测试和功能验证\n");
    
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
                
                ret = setup_page_protection(&monitors[monitor_count]);
                if (ret == 0) {
                    printk(KERN_INFO "[%s] 开始监控测试内存: %s (大小: %zu)\n", 
                           DRIVER_NAME, name, test_memory_size);
                    monitor_count++;
                } else {
                    monitors[monitor_count].active = 0;
                    printk(KERN_ERR "[%s] 监控设置失败: %s\n", DRIVER_NAME, name);
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
                remove_page_protection(&monitors[i]);
                monitors[i].active = 0;
                printk(KERN_INFO "[%s] 停止监控: %s\n", DRIVER_NAME, name);
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
        if (test_memory && offset < test_memory_size) {
            unsigned char value = *((unsigned char*)test_memory + offset);
            printk(KERN_INFO "[%s] 读取: test_memory[%lu] = 0x%02x ('%c')\n", 
                   DRIVER_NAME, offset, value, isprint(value) ? value : '?');
            
            // 模拟触发监控
            page_fault_handler((unsigned long)test_memory + offset, "读");
        } else {
            printk(KERN_WARNING "[%s] 读取偏移超出范围: %lu\n", DRIVER_NAME, offset);
        }
        
    } else if (sscanf(cmd, "write %lu %127s", &offset, data) == 2) {
        // 写入测试
        if (test_memory && offset < test_memory_size) {
            size_t len = strlen(data);
            if (offset + len <= test_memory_size) {
                memcpy((char*)test_memory + offset, data, len);
                printk(KERN_INFO "[%s] 写入: test_memory[%lu] = \"%s\"\n", 
                       DRIVER_NAME, offset, data);
                       
                // 模拟触发监控
                page_fault_handler((unsigned long)test_memory + offset, "写");
            } else {
                printk(KERN_WARNING "[%s] 写入数据过长\n", DRIVER_NAME);
            }
        } else {
            printk(KERN_WARNING "[%s] 写入偏移超出范围: %lu\n", DRIVER_NAME, offset);
        }
        
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
    printk(KERN_INFO "[%s] 页面保护内存监控驱动加载中...\n", DRIVER_NAME);
    
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
    snprintf((char*)test_memory, test_memory_size, "Protected Test Memory - Initial Data");
    
    printk(KERN_INFO "[%s] 使用默认监控地址: test_memory @ %px\n", DRIVER_NAME, test_memory);
    
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
    
    printk(KERN_INFO "[%s] ✅ 页面保护监控驱动加载成功!\n", DRIVER_NAME);
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
    
    return 0;
}

// 模块退出函数
static void __exit page_monitor_exit(void)
{
    int i;
    
    // 清理所有监控
    for (i = 0; i < monitor_count; i++) {
        if (monitors[i].active) {
            remove_page_protection(&monitors[i]);
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
    
    printk(KERN_INFO "[%s] 页面保护监控驱动已卸载\n", DRIVER_NAME);
}

module_init(page_monitor_init);
module_exit(page_monitor_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("页面保护监控驱动");
MODULE_DESCRIPTION("页面保护内存监控驱动 - 简化版本");
MODULE_VERSION(DRIVER_VERSION);
MODULE_ALIAS("page-monitor-simple");
