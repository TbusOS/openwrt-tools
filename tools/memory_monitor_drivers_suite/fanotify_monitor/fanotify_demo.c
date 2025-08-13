/*
 * fanotify 示例实现 - 演示高级文件监控功能
 * 注意：需要CAP_SYS_ADMIN权限或root用户运行
 * 
 * 编译：gcc -o fanotify_demo fanotify_demo.c
 * 运行：sudo ./fanotify_demo /path/to/monitor
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/fanotify.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <signal.h>
#include <time.h>
#include <limits.h>
#include <linux/limits.h>

#define EVENT_SIZE (sizeof(struct fanotify_event_metadata))
#define BUF_LEN (1024 * EVENT_SIZE)

static volatile int running = 1;

void signal_handler(int sig) {
    (void)sig;
    running = 0;
    printf("\n🛑 fanotify 监控已停止\n");
}

const char* get_event_type_name(uint64_t mask) {
    if (mask & FAN_OPEN) return "OPEN";
    if (mask & FAN_CLOSE_WRITE) return "CLOSE_WRITE";
    if (mask & FAN_CLOSE_NOWRITE) return "CLOSE_NOWRITE";
    if (mask & FAN_ACCESS) return "ACCESS";
    if (mask & FAN_MODIFY) return "MODIFY";
    if (mask & FAN_OPEN_PERM) return "OPEN_PERM";
    if (mask & FAN_ACCESS_PERM) return "ACCESS_PERM";
    return "UNKNOWN";
}

void format_time_string(char *buffer, size_t size) {
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    strftime(buffer, size, "%H:%M:%S", tm_info);
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("使用方法: %s <监控路径>\n", argv[0]);
        printf("注意: 需要root权限运行\n");
        return 1;
    }

    const char *monitor_path = argv[1];

    // 检查权限
    if (geteuid() != 0) {
        fprintf(stderr, "错误: fanotify 需要root权限\n");
        fprintf(stderr, "请使用: sudo %s %s\n", argv[0], monitor_path);
        return 1;
    }

    // 检查路径是否存在
    struct stat st;
    if (stat(monitor_path, &st) != 0) {
        perror("stat");
        return 1;
    }

    printf("🚀 fanotify 文件监控启动\n");
    printf("=========================\n");
    printf("监控路径: %s\n", monitor_path);
    printf("权限: root (CAP_SYS_ADMIN)\n");
    printf("监控事件: OPEN, CLOSE, ACCESS, MODIFY\n");
    printf("(按 Ctrl+C 停止监控)\n\n");

    // 设置信号处理
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    // 初始化 fanotify
    int fanotify_fd = fanotify_init(
        FAN_CLOEXEC | FAN_CLASS_CONTENT,  // 标志
        O_RDONLY                          // 事件文件描述符标志
    );

    if (fanotify_fd == -1) {
        perror("fanotify_init");
        fprintf(stderr, "提示: 确保内核支持fanotify且拥有root权限\n");
        return 1;
    }

    // 标记要监控的路径
    uint64_t mask = FAN_OPEN | FAN_CLOSE | FAN_ACCESS | FAN_MODIFY;
    
    if (fanotify_mark(fanotify_fd, FAN_MARK_ADD | FAN_MARK_MOUNT,
                      mask, AT_FDCWD, monitor_path) == -1) {
        perror("fanotify_mark");
        close(fanotify_fd);
        return 1;
    }

    printf("✅ fanotify 监控已启动\n\n");

    char buffer[BUF_LEN];
    ssize_t length;
    unsigned long event_count = 0;

    while (running) {
        length = read(fanotify_fd, buffer, sizeof(buffer));
        if (length == -1) {
            if (errno == EINTR) continue;
            perror("read");
            break;
        }

        struct fanotify_event_metadata *metadata;
        metadata = (struct fanotify_event_metadata*)buffer;

        while (FAN_EVENT_OK(metadata, length)) {
            if (metadata->vers != FANOTIFY_METADATA_VERSION) {
                fprintf(stderr, "错误: fanotify 元数据版本不匹配\n");
                break;
            }

            // 获取文件路径
            char path[PATH_MAX];
            char proc_fd_path[64];
            snprintf(proc_fd_path, sizeof(proc_fd_path), "/proc/self/fd/%d", metadata->fd);
            
            ssize_t path_len = readlink(proc_fd_path, path, sizeof(path) - 1);
            if (path_len > 0) {
                path[path_len] = '\0';
                
                // 过滤一些系统文件
                if (strstr(path, "/proc/") || strstr(path, "/sys/") || 
                    strstr(path, "/dev/")) {
                    goto next_event;
                }

                char time_str[32];
                format_time_string(time_str, sizeof(time_str));

                event_count++;
                printf("[%s] 📁 %s %s (PID: %d)\n", 
                       time_str,
                       get_event_type_name(metadata->mask),
                       path,
                       metadata->pid);
            }

        next_event:
            // 关闭事件文件描述符
            close(metadata->fd);
            
            // 移动到下一个事件
            metadata = FAN_EVENT_NEXT(metadata, length);
        }
    }

    printf("\n📊 监控统计\n");
    printf("===========\n");
    printf("总事件数: %lu\n", event_count);

    close(fanotify_fd);
    return 0;
}
