/**
 * 进度条显示功能
 * 为create命令提供美观的进度指示
 */

#include "snapshot_core.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <time.h>

// 获取终端宽度
static int get_terminal_width() {
    struct winsize w;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0) {
        return w.ws_col;
    }
    return 80;  // 默认宽度
}

// 格式化文件大小
__attribute__((unused)) static void format_size(uint64_t size, char *buffer, size_t buffer_size) {
    const char *units[] = {"B", "KB", "MB", "GB", "TB"};
    int unit = 0;
    double size_f = (double)size;
    
    while (size_f >= 1024.0 && unit < 4) {
        size_f /= 1024.0;
        unit++;
    }
    
    if (unit == 0) {
        snprintf(buffer, buffer_size, "%"PRIu64" %s", size, units[unit]);
    } else {
        snprintf(buffer, buffer_size, "%.1f %s", size_f, units[unit]);
    }
}

// 格式化时间
static void format_time(time_t seconds, char *buffer, size_t buffer_size) {
    if (seconds < 60) {
        snprintf(buffer, buffer_size, "%lds", seconds);
    } else if (seconds < 3600) {
        snprintf(buffer, buffer_size, "%ldm%lds", seconds / 60, seconds % 60);
    } else {
        snprintf(buffer, buffer_size, "%ldh%ldm", seconds / 3600, (seconds % 3600) / 60);
    }
}

// 显示进度条
void show_progress_bar(uint64_t current, uint64_t total, const char *current_file) {
    if (total == 0) return;
    
    int term_width = get_terminal_width();
    double percentage = (double)current / total * 100.0;
    
    // 计算进度条宽度（为其他信息留出空间）
    int info_space = 50;  // 为百分比、速度等信息预留空间
    int bar_width = term_width - info_space;
    if (bar_width < 20) bar_width = 20;
    
    int filled = (int)(percentage * bar_width / 100.0);
    
    // 清除当前行
    printf("\r\033[K");
    
    // 显示进度条
    printf("📊 [");
    for (int i = 0; i < bar_width; i++) {
        if (i < filled) {
            printf("█");
        } else if (i == filled && percentage > (double)filled * 100.0 / bar_width) {
            printf("▌");
        } else {
            printf("░");
        }
    }
    printf("] %6.1f%% (%"PRIu64"/%"PRIu64")", percentage, current, total);
    
    // 如果有当前文件信息，显示文件名（截断长文件名）
    if (current_file && strlen(current_file) > 0) {
        int remaining = term_width - 60;  // 为进度条和百分比留出空间
        if (remaining > 10) {
            char short_name[256];
            if (strlen(current_file) > (size_t)(remaining - 3)) {
                snprintf(short_name, sizeof(short_name), "...%s", 
                        current_file + strlen(current_file) - (remaining - 6));
            } else {
                strncpy(short_name, current_file, sizeof(short_name) - 1);
                short_name[sizeof(short_name) - 1] = '\0';
            }
            printf(" %s", short_name);
        }
    }
    
    fflush(stdout);
}

// 显示创建完成摘要
void show_create_summary(uint64_t total_files, uint64_t processed_files, 
                        uint64_t failed_files, time_t elapsed_time) {
    printf("\n");
    printf("✅ 快照创建完成!\n");
    printf("📊 统计摘要:\n");
    printf("   📁 扫描文件: %"PRIu64"\n", total_files);
    printf("   ✅ 成功处理: %"PRIu64"\n", processed_files);
    
    if (failed_files > 0) {
        printf("   ❌ 失败文件: %"PRIu64"\n", failed_files);
    }
    
    if (total_files > 0) {
        double success_rate = (double)processed_files * 100.0 / total_files;
        printf("   📈 成功率: %.1f%%\n", success_rate);
    }
    
    if (elapsed_time > 0) {
        char time_str[64];
        format_time(elapsed_time, time_str, sizeof(time_str));
        printf("   ⏱️  总耗时: %s\n", time_str);
        
        if (processed_files > 0) {
            double speed = (double)processed_files / elapsed_time;
            printf("   🚀 处理速度: %.1f 文件/秒\n", speed);
        }
    }
    printf("\n");
}

// 显示扫描阶段进度
void show_scan_progress(uint64_t scanned_dirs, const char *current_dir) {
    printf("\r🔍 扫描目录: %"PRIu64" 个目录", scanned_dirs);
    if (current_dir && strlen(current_dir) > 0) {
        int term_width = get_terminal_width();
        int remaining = term_width - 30;  // 为前缀信息留出空间
        
        if (remaining > 10) {
            char short_dir[256];
            if (strlen(current_dir) > (size_t)(remaining - 3)) {
                snprintf(short_dir, sizeof(short_dir), "...%s", 
                        current_dir + strlen(current_dir) - (remaining - 6));
            } else {
                strncpy(short_dir, current_dir, sizeof(short_dir) - 1);
                short_dir[sizeof(short_dir) - 1] = '\0';
            }
            printf(" - %s", short_dir);
        }
    }
    fflush(stdout);
}