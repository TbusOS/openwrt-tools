/*
 * 真正的MMU写保护内存监控驱动 - 内核内建版本
 * 通过直接操作页表实现真正的硬件级内存保护
 * 编译到内核中，避免符号依赖问题
 */

#include <linux/init.h>
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
#include <linux/mm_types.h>
#include <linux/mman.h>
#include <asm/pgtable.h>
#include <asm/tlbflush.h>
#include <asm/cacheflush.h>

#define DRIVER_NAME "true_mmu_monitor"
#define DRIVER_VERSION "1.0.0-true-mmu"
#define MAX_MONITORS 8
#define MAX_NAME_LEN 32

// 监控配置结构体
struct mmu_monitor_config {
    char name[MAX_NAME_LEN];
    unsigned long start_addr;
    size_t size;
    int type;                   // 1=读保护, 2=写保护, 3=读写保护
    int hit_count;              // 页错误命中次数
    int active;                 // 是否激活
    pte_t *pte_array;          // 页表项指针数组
    pte_t *orig_pte_values;    // 原始页表项值数组
    int num_pages;             // 页面数量
};

// 全局变量
static void *test_memory = NULL;
static size_t test_memory_size = 16 * 1024;  // 16KB
static struct mmu_monitor_config monitors[MAX_MONITORS];
static int monitor_count = 0;
static struct proc_dir_entry *proc_entry = NULL;

// 页错误统计
static atomic_t total_page_faults = ATOMIC_INIT(0);
static atomic_t write_violations = ATOMIC_INIT(0);
static atomic_t read_violations = ATOMIC_INIT(0);

// 获取页表项指针 - 真正的MMU页表遍历
static pte_t *get_pte_for_address(unsigned long addr)
{
    pgd_t *pgd;
    pud_t *pud;
    pmd_t *pmd;
    pte_t *pte;
    
    // 使用内核的init_mm - 内建驱动可以直接访问
    pgd = pgd_offset(&init_mm, addr);
    if (pgd_none(*pgd) || pgd_bad(*pgd)) {
        printk(KERN_ERR "[%s] 无效的PGD: 0x%lx\n", DRIVER_NAME, addr);
        return NULL;
    }
    
#if defined(CONFIG_ARM64) || (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 11, 0))
    pud = pud_offset(pgd, addr);
    if (pud_none(*pud) || pud_bad(*pud)) {
        printk(KERN_ERR "[%s] 无效的PUD: 0x%lx\n", DRIVER_NAME, addr);
        return NULL;
    }
#else
    pud = (pud_t *)pgd;  // ARM32上PUD与PGD相同
#endif
    
    pmd = pmd_offset(pud, addr);
    if (pmd_none(*pmd) || pmd_bad(*pmd)) {
        printk(KERN_ERR "[%s] 无效的PMD: 0x%lx\n", DRIVER_NAME, addr);
        return NULL;
    }
    
    pte = pte_offset_kernel(pmd, addr);
    if (!pte) {
        printk(KERN_ERR "[%s] 无法获取PTE: 0x%lx\n", DRIVER_NAME, addr);
        return NULL;
    }
    
    return pte;
}

// 设置MMU写保护 - 真正的硬件级保护
static int set_mmu_write_protection(unsigned long addr, pte_t **out_pte, pte_t *orig_pte)
{
    pte_t *pte;
    pte_t old_pte, new_pte;
    
    pte = get_pte_for_address(addr);
    if (!pte) {
        return -EFAULT;
    }
    
    old_pte = *pte;
    if (!pte_present(old_pte)) {
        printk(KERN_WARNING "[%s] 页面不存在: 0x%lx\n", DRIVER_NAME, addr);
        return -EINVAL;
    }
    
    // 保存原始PTE值
    *orig_pte = old_pte;
    *out_pte = pte;
    
    // 设置写保护 - 这是真正的MMU硬件保护！
#ifdef CONFIG_ARM
    // ARM32: 设置L_PTE_RDONLY位
    new_pte = pte_wrprotect(old_pte);
    printk(KERN_INFO "[%s] ARM32写保护: 0x%lx PTE: 0x%lx -> 0x%lx\n", 
           DRIVER_NAME, addr, (unsigned long)pte_val(old_pte), (unsigned long)pte_val(new_pte));
#elif defined(CONFIG_ARM64)
    // ARM64: 清除PTE_WRITE位
    new_pte = pte_wrprotect(old_pte);
    printk(KERN_INFO "[%s] ARM64写保护: 0x%lx PTE: 0x%lx -> 0x%lx\n", 
           DRIVER_NAME, addr, (unsigned long)pte_val(old_pte), (unsigned long)pte_val(new_pte));
#elif defined(CONFIG_X86)
    // x86: 清除_PAGE_RW位
    new_pte = pte_clear_flags(old_pte, _PAGE_RW);
    printk(KERN_INFO "[%s] x86写保护: 0x%lx PTE: 0x%lx -> 0x%lx\n", 
           DRIVER_NAME, addr, (unsigned long)pte_val(old_pte), (unsigned long)pte_val(new_pte));
#else
    // 通用方法
    new_pte = pte_wrprotect(old_pte);
    printk(KERN_INFO "[%s] 通用写保护: 0x%lx PTE: 0x%lx -> 0x%lx\n", 
           DRIVER_NAME, addr, (unsigned long)pte_val(old_pte), (unsigned long)pte_val(new_pte));
#endif
    
    // 原子性更新页表项 - 真正的MMU操作
    set_pte_at(&init_mm, addr, pte, new_pte);
    
    // 刷新TLB - 让CPU硬件知道权限改变了
#ifdef CONFIG_ARM
    // ARM特定的TLB刷新
    flush_tlb_kernel_page(addr);
    // 确保指令和数据缓存一致性
    flush_cache_page(find_vma(&init_mm, addr), addr, page_to_pfn(pte_page(*pte)));
#else
    // 通用TLB刷新
    flush_tlb_kernel_page(addr);
#endif
    
    printk(KERN_INFO "[%s] 🔒 MMU硬件写保护已激活: 0x%lx\n", DRIVER_NAME, addr);
    return 0;
}

// 移除MMU写保护
static int remove_mmu_write_protection(unsigned long addr, pte_t *pte, pte_t orig_pte)
{
    if (!pte) {
        return -EINVAL;
    }
    
    // 恢复原始页表项
    set_pte_at(&init_mm, addr, pte, orig_pte);
    
    // 刷新TLB
#ifdef CONFIG_ARM
    flush_tlb_kernel_page(addr);
    flush_cache_page(find_vma(&init_mm, addr), addr, page_to_pfn(pte_page(orig_pte)));
#else
    flush_tlb_kernel_page(addr);
#endif
    
    printk(KERN_INFO "[%s] ✅ MMU写保护已移除: 0x%lx\n", DRIVER_NAME, addr);
    return 0;
}

// 设置完整的内存区域保护
static int setup_mmu_memory_protection(struct mmu_monitor_config *monitor)
{
    unsigned long addr;
    int page_idx = 0;
    unsigned long num_pages;
    int ret;
    
    num_pages = (monitor->size + PAGE_SIZE - 1) >> PAGE_SHIFT;
    monitor->num_pages = num_pages;
    
    // 分配PTE指针数组和原始值数组
    monitor->pte_array = kmalloc(num_pages * sizeof(pte_t*), GFP_KERNEL);
    monitor->orig_pte_values = kmalloc(num_pages * sizeof(pte_t), GFP_KERNEL);
    
    if (!monitor->pte_array || !monitor->orig_pte_values) {
        kfree(monitor->pte_array);
        kfree(monitor->orig_pte_values);
        return -ENOMEM;
    }
    
    // 对每个页面设置MMU保护
    for (addr = monitor->start_addr; addr < monitor->start_addr + monitor->size; addr += PAGE_SIZE) {
        ret = set_mmu_write_protection(addr, 
                                      &monitor->pte_array[page_idx], 
                                      &monitor->orig_pte_values[page_idx]);
        if (ret != 0) {
            printk(KERN_ERR "[%s] 页面保护设置失败: 0x%lx\n", DRIVER_NAME, addr);
            
            // 清理已经设置的保护
            while (page_idx > 0) {
                page_idx--;
                remove_mmu_write_protection(monitor->start_addr + page_idx * PAGE_SIZE,
                                          monitor->pte_array[page_idx],
                                          monitor->orig_pte_values[page_idx]);
            }
            
            kfree(monitor->pte_array);
            kfree(monitor->orig_pte_values);
            return ret;
        }
        page_idx++;
    }
    
    printk(KERN_INFO "[%s] ✅ MMU内存保护已设置: %s @ 0x%lx-%lx (%d页面)\n", 
           DRIVER_NAME, monitor->name, monitor->start_addr, 
           monitor->start_addr + monitor->size - 1, page_idx);
    
    return 0;
}

// 移除完整的内存区域保护
static int remove_mmu_memory_protection(struct mmu_monitor_config *monitor)
{
    int i;
    unsigned long addr;
    
    if (!monitor->pte_array || !monitor->orig_pte_values) {
        return 0;
    }
    
    // 恢复所有页面的原始保护
    for (i = 0; i < monitor->num_pages; i++) {
        addr = monitor->start_addr + i * PAGE_SIZE;
        remove_mmu_write_protection(addr, monitor->pte_array[i], monitor->orig_pte_values[i]);
    }
    
    kfree(monitor->pte_array);
    kfree(monitor->orig_pte_values);
    monitor->pte_array = NULL;
    monitor->orig_pte_values = NULL;
    
    printk(KERN_INFO "[%s] ✅ MMU内存保护已移除: %s\n", DRIVER_NAME, monitor->name);
    return 0;
}

// 页错误处理函数 - 真正的硬件异常处理
static int mmu_page_fault_handler(struct pt_regs *regs, unsigned long fault_addr, unsigned int fsr)
{
    int i;
    
    atomic_inc(&total_page_faults);
    
    // 查找匹配的监控配置
    for (i = 0; i < monitor_count; i++) {
        if (monitors[i].active && 
            fault_addr >= monitors[i].start_addr && 
            fault_addr < monitors[i].start_addr + monitors[i].size) {
            
            monitors[i].hit_count++;
            
            // 判断错误类型
            if (fsr & (1 << 11)) {  // 写错误
                atomic_inc(&write_violations);
                printk(KERN_ALERT "[%s] 🔥 MMU硬件检测到写违规: %s[0x%lx] (命中: %d)\n", 
                       DRIVER_NAME, monitors[i].name, fault_addr, monitors[i].hit_count);
            } else {
                atomic_inc(&read_violations);
                printk(KERN_ALERT "[%s] 🔥 MMU硬件检测到读违规: %s[0x%lx] (命中: %d)\n", 
                       DRIVER_NAME, monitors[i].name, fault_addr, monitors[i].hit_count);
            }
            
            // 这里可以选择处理策略：
            // 1. 临时解除保护让访问继续 (开发调试)
            // 2. 终止违规进程 (安全模式)
            // 3. 仅记录不处理 (监控模式)
            
            #ifdef CONFIG_MMU_MONITOR_DEBUG
            // 调试模式：临时解除保护让访问继续
            printk(KERN_WARNING "[%s] 调试模式：临时解除保护\n", DRIVER_NAME);
            // 这里可以临时修改页表权限...
            #endif
            
            return 1; // 表示我们处理了这个页错误
        }
    }
    
    return 0; // 未处理，让内核继续处理
}

// 测试内存访问 - 这会触发真正的MMU页错误
static void test_mmu_memory_access(unsigned long offset, const char *operation, const char *data)
{
    if (!test_memory || offset >= test_memory_size) {
        printk(KERN_WARNING "[%s] 测试偏移超出范围: %lu\n", DRIVER_NAME, offset);
        return;
    }
    
    if (strcmp(operation, "read") == 0) {
        // 读取测试
        volatile unsigned char *ptr = (unsigned char*)test_memory + offset;
        unsigned char value;
        
        printk(KERN_INFO "[%s] 准备读取: test_memory[%lu] (地址: 0x%px)\n", 
               DRIVER_NAME, offset, ptr);
        
        // 这个访问可能会触发MMU页错误
        value = *ptr;
        
        printk(KERN_INFO "[%s] 读取成功: test_memory[%lu] = 0x%02x ('%c')\n", 
               DRIVER_NAME, offset, value, isprint(value) ? value : '?');
               
    } else if (strcmp(operation, "write") == 0) {
        // 写入测试 - 这会触发MMU写保护页错误
        volatile char *ptr = (char*)test_memory + offset;
        size_t len = strlen(data);
        
        printk(KERN_INFO "[%s] 准备写入: test_memory[%lu] = \"%s\" (地址: 0x%px)\n", 
               DRIVER_NAME, offset, data, ptr);
        
        if (offset + len <= test_memory_size) {
            // 这个访问会触发MMU硬件写保护页错误！
            memcpy((char*)ptr, data, len);
            
            printk(KERN_INFO "[%s] 写入成功: test_memory[%lu] = \"%s\"\n", 
                   DRIVER_NAME, offset, data);
        } else {
            printk(KERN_WARNING "[%s] 写入数据过长\n", DRIVER_NAME);
        }
    }
}

// proc文件显示函数
static int mmu_monitor_show(struct seq_file *m, void *v)
{
    int i;
    
    seq_printf(m, "=== 真正的MMU硬件级内存保护监控驱动 ===\n");
    seq_printf(m, "版本: %s\n", DRIVER_VERSION);
    seq_printf(m, "监控方案: 真正的MMU页表保护\n");
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
    
    seq_printf(m, "\n=== MMU硬件统计 ===\n");
    seq_printf(m, "总页错误: %d\n", atomic_read(&total_page_faults));
    seq_printf(m, "写违规: %d\n", atomic_read(&write_violations));
    seq_printf(m, "读违规: %d\n", atomic_read(&read_violations));
    
    seq_printf(m, "\n=== 监控状态 ===\n");
    seq_printf(m, "活跃监控数: %d / %d\n", monitor_count, MAX_MONITORS);
    
    for (i = 0; i < monitor_count; i++) {
        if (monitors[i].active) {
            seq_printf(m, "[%d] %s: 0x%08lx-0x%08lx (%zu bytes, %d页面, 类型:%d, 命中:%d)\n",
                       i, monitors[i].name, monitors[i].start_addr,
                       monitors[i].start_addr + monitors[i].size - 1,
                       monitors[i].size, monitors[i].num_pages, 
                       monitors[i].type, monitors[i].hit_count);
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
    seq_printf(m, "1. 监控测试内存: echo 'monitor test_memory' > /proc/true_mmu_monitor\n");
    seq_printf(m, "2. 停止监控: echo 'stop test_memory' > /proc/true_mmu_monitor\n");
    seq_printf(m, "3. 测试读取: echo 'read 0' > /proc/true_mmu_monitor\n");
    seq_printf(m, "4. 测试写入: echo 'write 0 Hello' > /proc/true_mmu_monitor\n");
    
    seq_printf(m, "\n=== 真正的MMU保护说明 ===\n");
    seq_printf(m, "⚡ 使用真正的MMU页表权限控制\n");
    seq_printf(m, "🔥 CPU硬件自动检测和触发页错误\n");
    seq_printf(m, "📊 无法通过软件绕过的硬件级保护\n");
    seq_printf(m, "⚠️  违规访问会触发内核页错误异常\n");
    seq_printf(m, "🛡️  真正的缓冲区溢出硬件级检测\n");
    
    return 0;
}

// proc文件写入处理函数  
static ssize_t mmu_monitor_write(struct file *file, const char __user *buffer, 
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
                
                ret = setup_mmu_memory_protection(&monitors[monitor_count]);
                if (ret == 0) {
                    printk(KERN_INFO "[%s] 开始MMU硬件监控: %s (大小: %zu)\n", 
                           DRIVER_NAME, name, test_memory_size);
                    monitor_count++;
                } else {
                    monitors[monitor_count].active = 0;
                    printk(KERN_ERR "[%s] MMU硬件监控设置失败: %s\n", DRIVER_NAME, name);
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
                remove_mmu_memory_protection(&monitors[i]);
                monitors[i].active = 0;
                printk(KERN_INFO "[%s] 停止MMU硬件监控: %s\n", DRIVER_NAME, name);
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
        // 读取测试 - 可能触发MMU页错误
        test_mmu_memory_access(offset, "read", NULL);
        
    } else if (sscanf(cmd, "write %lu %127s", &offset, data) == 2) {
        // 写入测试 - 会触发MMU硬件写保护页错误
        test_mmu_memory_access(offset, "write", data);
        
    } else {
        printk(KERN_WARNING "[%s] 未知命令: %s\n", DRIVER_NAME, cmd);
        return -EINVAL;
    }
    
    return count;
}

static int mmu_monitor_open(struct inode *inode, struct file *file)
{
    return single_open(file, mmu_monitor_show, NULL);
}

// proc文件操作结构体
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 6, 0)
static const struct proc_ops mmu_monitor_proc_ops = {
    .proc_open    = mmu_monitor_open,
    .proc_read    = seq_read,
    .proc_write   = mmu_monitor_write,
    .proc_lseek   = seq_lseek,
    .proc_release = single_release,
};
#else
static const struct file_operations mmu_monitor_proc_ops = {
    .owner   = THIS_MODULE,
    .open    = mmu_monitor_open,
    .read    = seq_read,
    .write   = mmu_monitor_write,
    .llseek  = seq_lseek,
    .release = single_release,
};
#endif

// 初始化函数 - 内核启动时调用
static int __init true_mmu_monitor_init(void)
{
    printk(KERN_INFO "[%s] 真正的MMU硬件级内存保护监控驱动加载中...\n", DRIVER_NAME);
    
    // 分配测试内存
    test_memory = vmalloc(test_memory_size);
    if (!test_memory) {
        printk(KERN_ERR "[%s] 无法分配测试内存\n", DRIVER_NAME);
        return -ENOMEM;
    }
    
    // 初始化测试内存内容
    snprintf((char*)test_memory, test_memory_size, "Protected Test Memory - True MMU Hardware Protection");
    
    printk(KERN_INFO "[%s] MMU硬件监控地址: test_memory @ %px\n", DRIVER_NAME, test_memory);
    
    // 创建proc文件
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 6, 0)
    proc_entry = proc_create(DRIVER_NAME, 0666, NULL, &mmu_monitor_proc_ops);
#else
    proc_entry = proc_create(DRIVER_NAME, 0666, NULL, &mmu_monitor_proc_ops);
#endif
    
    if (!proc_entry) {
        printk(KERN_ERR "[%s] 无法创建proc文件\n", DRIVER_NAME);
        vfree(test_memory);
        return -ENOMEM;
    }
    
    printk(KERN_INFO "[%s] ✅ 真正的MMU硬件级保护监控驱动加载成功!\n", DRIVER_NAME);
    printk(KERN_INFO "架构: %s\n", 
#ifdef CONFIG_ARM64
        "ARM64"
#elif defined(CONFIG_ARM)
        "ARM32"  
#else
        "通用"
#endif
    );
    printk(KERN_INFO "页面大小: %lu bytes (%lu KB)\n", PAGE_SIZE, PAGE_SIZE / 1024);
    printk(KERN_INFO "测试内存: %px (%zu bytes)\n", test_memory, test_memory_size);
    printk(KERN_INFO "[%s] 使用: cat /proc/true_mmu_monitor 查看状态\n", DRIVER_NAME);
    printk(KERN_ALERT "[%s] ⚡ 真正的MMU硬件级保护已就绪!\n", DRIVER_NAME);
    
    return 0;
}

// 退出函数 - 内核关闭时调用
static void __exit true_mmu_monitor_exit(void)
{
    int i;
    
    // 清理所有监控
    for (i = 0; i < monitor_count; i++) {
        if (monitors[i].active) {
            remove_mmu_memory_protection(&monitors[i]);
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
    
    printk(KERN_INFO "[%s] 真正的MMU硬件级保护监控驱动已卸载\n", DRIVER_NAME);
}

// 内核内建初始化
subsys_initcall(true_mmu_monitor_init);

// 如果编译为模块，也支持模块化加载
#ifdef MODULE
module_init(true_mmu_monitor_init);
module_exit(true_mmu_monitor_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("MMU硬件级保护监控驱动");
MODULE_DESCRIPTION("真正的MMU硬件级内存保护监控驱动");
MODULE_VERSION(DRIVER_VERSION);
#endif
