/*
 * 内核版本兼容性头文件
 * 支持 Linux 4.1, 5.x, 6.x 版本
 * 作者: OpenWrt Tools Project
 */

#ifndef _KERNEL_COMPAT_H
#define _KERNEL_COMPAT_H

#include <linux/version.h>
#include <linux/kernel.h>

/* 内核版本宏定义 */
#define KERNEL_VERSION_4_1    KERNEL_VERSION(4, 1, 0)
#define KERNEL_VERSION_5_0    KERNEL_VERSION(5, 0, 0)
#define KERNEL_VERSION_6_0    KERNEL_VERSION(6, 0, 0)

/* 调试信息 */
#if defined(DEBUG) || defined(CONFIG_DEBUG_KERNEL)
#define COMPAT_DEBUG(fmt, ...) \
    printk(KERN_DEBUG "[COMPAT] " fmt, ##__VA_ARGS__)
#else
#define COMPAT_DEBUG(fmt, ...)
#endif

/*
 * =============================================================================
 * VM_FAULT 相关兼容性定义
 * =============================================================================
 */

/* Linux 4.17+ 引入了 vm_fault_t 类型 */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 17, 0)
    /* 新版本已经有 vm_fault_t */
    #define COMPAT_VM_FAULT_T vm_fault_t
#else
    /* 老版本使用 int */
    #define COMPAT_VM_FAULT_T int
    typedef int vm_fault_t;
#endif

/* struct vm_fault 成员变量兼容性 */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 10, 0)
    /* Linux 4.10+ 使用 address */
    #define COMPAT_VMF_ADDRESS(vmf) ((vmf)->address)
#else
    /* Linux 4.1-4.9 使用 virtual_address */
    #define COMPAT_VMF_ADDRESS(vmf) ((vmf)->virtual_address)
#endif

/*
 * =============================================================================
 * 页面引用计数相关兼容性定义
 * =============================================================================
 */

/* Linux 4.6+ 引入了 page_ref_count() */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 6, 0)
    #include <linux/page_ref.h>
    #define COMPAT_PAGE_REF_COUNT(page) page_ref_count(page)
#else
    /* 老版本直接访问 _count */
    #define COMPAT_PAGE_REF_COUNT(page) atomic_read(&(page)->_count)
#endif

/*
 * =============================================================================
 * 进程文件系统相关兼容性定义
 * =============================================================================
 */

/* Linux 5.6+ proc_ops 替代了 file_operations */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 6, 0)
    #define COMPAT_PROC_OPS_AVAILABLE 1
    #define COMPAT_PROC_CREATE(name, mode, parent, ops) \
        proc_create(name, mode, parent, ops)
#else
    #define COMPAT_PROC_OPS_AVAILABLE 0
    #define COMPAT_PROC_CREATE(name, mode, parent, ops) \
        proc_create(name, mode, parent, ops)
#endif

/*
 * =============================================================================
 * 内存管理相关兼容性定义
 * =============================================================================
 */

/* Linux 5.1+ get_user_pages 参数变化 */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 1, 0)
    #define COMPAT_GET_USER_PAGES(start, nr_pages, gup_flags, pages, vmas) \
        get_user_pages(start, nr_pages, gup_flags, pages, vmas)
#elif LINUX_VERSION_CODE >= KERNEL_VERSION(4, 6, 0)
    #define COMPAT_GET_USER_PAGES(start, nr_pages, gup_flags, pages, vmas) \
        get_user_pages(start, nr_pages, gup_flags, pages, vmas)
#else
    #define COMPAT_GET_USER_PAGES(start, nr_pages, gup_flags, pages, vmas) \
        get_user_pages(current, current->mm, start, nr_pages, \
                      (gup_flags & FOLL_WRITE), 0, pages, vmas)
#endif

/*
 * =============================================================================
 * 访问权限标志兼容性定义
 * =============================================================================
 */

/* FOLL_* 标志兼容性 */
#ifndef FOLL_WRITE
    #define FOLL_WRITE 0x01
#endif

#ifndef FOLL_FORCE
    #define FOLL_FORCE 0x10
#endif

/*
 * =============================================================================
 * VM_FAULT 返回值兼容性定义
 * =============================================================================
 */

/* 确保所有 VM_FAULT_* 常量都可用 */
#ifndef VM_FAULT_SIGBUS
    #define VM_FAULT_SIGBUS 0x0002
#endif

#ifndef VM_FAULT_MAJOR
    #define VM_FAULT_MAJOR 0x0004
#endif

#ifndef VM_FAULT_NOPAGE
    #define VM_FAULT_NOPAGE 0x0100
#endif

#ifndef VM_FAULT_LOCKED
    #define VM_FAULT_LOCKED 0x0200
#endif

#ifndef VM_FAULT_RETRY
    #define VM_FAULT_RETRY 0x0400
#endif

/*
 * =============================================================================
 * 架构特定兼容性定义
 * =============================================================================
 */

/* ARM 架构兼容性 */
#ifdef CONFIG_ARM
    #ifdef ARCH_ARM32
        #define COMPAT_ARCH_NAME "ARM32"
        #define COMPAT_POINTER_FMT "0x%08lx"
    #endif
#endif

#ifdef CONFIG_ARM64
    #ifdef ARCH_ARM64
        #define COMPAT_ARCH_NAME "ARM64"
        #define COMPAT_POINTER_FMT "0x%016lx"
    #endif
#endif

#ifdef CONFIG_X86
    #ifdef ARCH_X86_32
        #define COMPAT_ARCH_NAME "x86_32"
        #define COMPAT_POINTER_FMT "0x%08lx"
    #endif
    #ifdef ARCH_X86_64
        #define COMPAT_ARCH_NAME "x86_64"
        #define COMPAT_POINTER_FMT "0x%016lx"
    #endif
#endif

/* 默认指针格式 */
#ifndef COMPAT_POINTER_FMT
    #if BITS_PER_LONG == 64
        #define COMPAT_POINTER_FMT "0x%016lx"
    #else
        #define COMPAT_POINTER_FMT "0x%08lx"
    #endif
#endif

#ifndef COMPAT_ARCH_NAME
    #define COMPAT_ARCH_NAME "Unknown"
#endif

/*
 * =============================================================================
 * 辅助宏和内联函数
 * =============================================================================
 */

/* 获取内核版本字符串 */
static inline const char *compat_kernel_version_string(void)
{
    if (LINUX_VERSION_CODE >= KERNEL_VERSION_6_0) {
        return "6.x";
    } else if (LINUX_VERSION_CODE >= KERNEL_VERSION_5_0) {
        return "5.x";
    } else if (LINUX_VERSION_CODE >= KERNEL_VERSION_4_1) {
        return "4.x";
    } else {
        return "Unknown";
    }
}

/* 版本兼容性检查 */
static inline int compat_check_kernel_version(void)
{
    if (LINUX_VERSION_CODE < KERNEL_VERSION_4_1) {
        printk(KERN_ERR "不支持的内核版本: %s (需要 4.1+)\n", 
               compat_kernel_version_string());
        return -ENOTSUPP;
    }
    return 0;
}

/* 打印兼容性信息 */
static inline void compat_print_info(const char *driver_name)
{
    printk(KERN_INFO "[%s] 内核兼容性信息:\n", driver_name);
    printk(KERN_INFO "  内核版本: %s (%d.%d.%d)\n", 
           compat_kernel_version_string(),
           (LINUX_VERSION_CODE >> 16) & 0xFF,
           (LINUX_VERSION_CODE >> 8) & 0xFF,
           LINUX_VERSION_CODE & 0xFF);
    printk(KERN_INFO "  架构: %s\n", COMPAT_ARCH_NAME);
    printk(KERN_INFO "  指针格式: %s\n", COMPAT_POINTER_FMT);
    
#if COMPAT_PROC_OPS_AVAILABLE
    printk(KERN_INFO "  proc_ops: 可用\n");
#else
    printk(KERN_INFO "  proc_ops: 不可用 (使用 file_operations)\n");
#endif

#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 17, 0)
    printk(KERN_INFO "  vm_fault_t: 可用\n");
#else
    printk(KERN_INFO "  vm_fault_t: 不可用 (使用 int)\n");
#endif
}

#endif /* _KERNEL_COMPAT_H */
