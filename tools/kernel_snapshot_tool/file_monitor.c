#include "file_monitor.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <signal.h>
#include <fnmatch.h>
#include <sys/stat.h>

// 全局状态
static volatile int g_monitor_running = 0;
static watch_stats_t *g_stats = NULL;

// 信号处理
static void signal_handler(int sig) {
    (void)sig;
    g_monitor_running = 0;
    printf("\n🛑 监控已停止\n");
}

// 检查文件是否应该被忽略
static int should_ignore_file(const char *path, const char *patterns) {
    if (!patterns || !path) return 0;
    
    char patterns_copy[1024];
    strncpy(patterns_copy, patterns, sizeof(patterns_copy) - 1);
    patterns_copy[sizeof(patterns_copy) - 1] = '\0';
    
    char *pattern = strtok(patterns_copy, ",");
    while (pattern) {
        // 去除空格
        while (*pattern == ' ') pattern++;
        char *end = pattern + strlen(pattern) - 1;
        while (end > pattern && *end == ' ') *end-- = '\0';
        
        if (fnmatch(pattern, path, FNM_PATHNAME | FNM_PERIOD) == 0) {
            return 1;
        }
        pattern = strtok(NULL, ",");
    }
    return 0;
}

// 获取当前时间戳（毫秒）
uint64_t get_current_timestamp_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

// 格式化时间字符串
static void format_time_string(char *buffer, size_t size) {
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    strftime(buffer, size, "%H:%M:%S", tm_info);
}

// 更新统计信息
static void update_stats(file_event_type_t type) {
    if (!g_stats) return;
    
    switch (type) {
        case FILE_EVENT_CREATED:
            g_stats->created_count++;
            break;
        case FILE_EVENT_MODIFIED:
            g_stats->modified_count++;
            break;
        case FILE_EVENT_DELETED:
            g_stats->deleted_count++;
            break;
        case FILE_EVENT_MOVED:
            g_stats->moved_count++;
            break;
    }
    g_stats->last_event_time = get_current_timestamp_ms();
}

// 默认事件处理回调
static void default_event_callback(const file_event_t *event, void *user_data) {
    watch_config_t *config = (watch_config_t *)user_data;
    
    // 计算相对路径显示
    const char *display_path = event->path;
    
    // 尝试获取监控目录的绝对路径进行比较
    char abs_monitor_dir[MAX_PATH_LEN];
    if (realpath(config->monitor_dir, abs_monitor_dir) != NULL) {
        size_t abs_dir_len = strlen(abs_monitor_dir);
        if (strncmp(event->path, abs_monitor_dir, abs_dir_len) == 0) {
            // 如果事件路径以监控目录开头，显示相对路径
            display_path = event->path + abs_dir_len;
            if (display_path[0] == '/') display_path++; // 跳过开头的斜杠
            if (display_path[0] == '\0') display_path = "."; // 如果是根目录本身
        }
    }
    
    // 检查忽略规则
    if (should_ignore_file(event->path, config->ignore_patterns)) {
        return;
    }
    
    char time_str[32];
    format_time_string(time_str, sizeof(time_str));
    
    const char *emoji, *action;
    switch (event->type) {
        case FILE_EVENT_CREATED:
            emoji = "🆕"; action = "ADDED   ";
            break;
        case FILE_EVENT_MODIFIED:
            emoji = "📝"; action = "MODIFIED";
            break;
        case FILE_EVENT_DELETED:
            emoji = "🗑️ "; action = "DELETED ";
            break;
        case FILE_EVENT_MOVED:
            emoji = "📦"; action = "MOVED   ";
            break;
        default:
            emoji = "❓"; action = "UNKNOWN ";
            break;
    }
    
    if (config->verbose && event->file_size > 0) {
        printf("[%s] %s %s %s (%zu bytes)\n", 
               time_str, emoji, action, display_path, event->file_size);
    } else {
        printf("[%s] %s %s %s\n", 
               time_str, emoji, action, display_path);
    }
    
    update_stats(event->type);
}

#ifdef __APPLE__
// ==================== macOS 实现 (FSEvents) ====================
#include <CoreServices/CoreServices.h>

static FSEventStreamRef g_stream = NULL;
static CFRunLoopRef g_run_loop = NULL;

void fsevents_callback(ConstFSEventStreamRef streamRef,
                      void *clientCallBackInfo,
                      size_t numEvents,
                      void *eventPaths,
                      const FSEventStreamEventFlags eventFlags[],
                      const FSEventStreamEventId eventIds[]) {
    (void)streamRef;
    (void)eventIds;
    
    char **paths = (char **)eventPaths;
    watch_config_t *config = (watch_config_t *)clientCallBackInfo;
    
    for (size_t i = 0; i < numEvents; i++) {
        file_event_t event = {0};
        strncpy(event.path, paths[i], sizeof(event.path) - 1);
        event.timestamp = get_current_timestamp_ms();
        
        // 简化的事件类型判断
        if (eventFlags[i] & kFSEventStreamEventFlagItemCreated) {
            event.type = FILE_EVENT_CREATED;
        } else if (eventFlags[i] & kFSEventStreamEventFlagItemModified) {
            event.type = FILE_EVENT_MODIFIED;
        } else if (eventFlags[i] & kFSEventStreamEventFlagItemRemoved) {
            event.type = FILE_EVENT_DELETED;
        } else if (eventFlags[i] & kFSEventStreamEventFlagItemRenamed) {
            event.type = FILE_EVENT_MOVED;
        } else {
            event.type = FILE_EVENT_MODIFIED; // 默认为修改
        }
        
        // 获取文件大小
        struct stat st;
        if (stat(event.path, &st) == 0) {
            event.file_size = st.st_size;
        }
        
        if (config->callback) {
            config->callback(&event, config->user_data);
        }
    }
}

int file_monitor_start(const watch_config_t *config, watch_stats_t *stats) {
    if (!config || !config->monitor_dir[0]) {
        fprintf(stderr, "错误: 无效的监控配置\n");
        return -1;
    }
    
    g_stats = stats;
    if (g_stats) {
        memset(g_stats, 0, sizeof(watch_stats_t));
        g_stats->start_time = get_current_timestamp_ms();
    }
    
    printf("👀 [macOS] 开始监控目录: %s\n", config->monitor_dir);
    printf("    架构: %s\n", 
#ifdef __x86_64__
           "Intel x86_64"
#elif defined(__arm64__)
           "Apple Silicon ARM64"
#else
           "Unknown"
#endif
    );
    printf("    (按 Ctrl+C 停止监控)\n\n");
    
    // 设置信号处理
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    CFStringRef path = CFStringCreateWithCString(NULL, config->monitor_dir, kCFStringEncodingUTF8);
    CFArrayRef pathsToWatch = CFArrayCreate(NULL, (const void **)&path, 1, NULL);
    
    FSEventStreamContext context = {0, (void*)config, NULL, NULL, NULL};
    
    g_stream = FSEventStreamCreate(
        NULL,
        &fsevents_callback,
        &context,
        pathsToWatch,
        kFSEventStreamEventIdSinceNow,
        1.0, // 延迟
        kFSEventStreamCreateFlagFileEvents  // 移除 UseCFTypes 标志
    );
    
    if (!g_stream) {
        fprintf(stderr, "错误: 无法创建 FSEvent 流\n");
        CFRelease(path);
        CFRelease(pathsToWatch);
        return -1;
    }
    
    g_run_loop = CFRunLoopGetCurrent();
    FSEventStreamScheduleWithRunLoop(g_stream, g_run_loop, kCFRunLoopDefaultMode);
    FSEventStreamStart(g_stream);
    
    g_monitor_running = 1;
    
    // 运行事件循环
    while (g_monitor_running) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
        
        // 定期显示统计信息
        if (config->show_stats && config->stats_interval > 0) {
            static time_t last_stats_time = 0;
            time_t now = time(NULL);
            if (now - last_stats_time >= config->stats_interval) {
                if (g_stats) {
                    printf("\r📊 创建:%llu 修改:%llu 删除:%llu 移动:%llu",
                           g_stats->created_count, g_stats->modified_count,
                           g_stats->deleted_count, g_stats->moved_count);
                    fflush(stdout);
                }
                last_stats_time = now;
            }
        }
    }
    
    // 清理
    FSEventStreamStop(g_stream);
    FSEventStreamInvalidate(g_stream);
    FSEventStreamRelease(g_stream);
    CFRelease(path);
    CFRelease(pathsToWatch);
    
    g_stream = NULL;
    g_run_loop = NULL;
    
    return 0;
}

void file_monitor_stop(void) {
    g_monitor_running = 0;
    if (g_run_loop) {
        CFRunLoopStop(g_run_loop);
    }
}

int file_monitor_is_supported(void) {
    return 1; // macOS 总是支持 FSEvents
}

const char* file_monitor_get_platform_name(void) {
#ifdef __x86_64__
    return "macOS Intel x86_64";
#elif defined(__arm64__)
    return "macOS Apple Silicon ARM64";
#else
    return "macOS Unknown Architecture";
#endif
}

#elif defined(__linux__)
// ==================== Linux 实现 (inotify) ====================
#include <sys/inotify.h>
#include <limits.h>
#include <dirent.h>

#define MAX_WATCH_DIRS 1024
#define EVENT_SIZE (sizeof(struct inotify_event))
#define BUF_LEN (1024 * (EVENT_SIZE + 16))
#define EVENT_DEDUP_WINDOW_MS 500  // 事件去重时间窗口：500毫秒（更长的窗口处理CREATE+CLOSE_WRITE组合）

static int g_inotify_fd = -1;
static int g_watch_descriptors[MAX_WATCH_DIRS];
static char g_watch_paths[MAX_WATCH_DIRS][MAX_PATH_LEN];
static int g_watch_count = 0;

// 事件去重结构
typedef struct recent_event {
    char path[MAX_PATH_LEN];
    file_event_type_t type;
    uint64_t timestamp;
    struct recent_event *next;
} recent_event_t;

static recent_event_t *g_recent_events = NULL;

// 清理过期的事件记录
static void cleanup_expired_events(uint64_t current_time) {
    recent_event_t **current = &g_recent_events;
    while (*current) {
        if (current_time - (*current)->timestamp > EVENT_DEDUP_WINDOW_MS) {
            recent_event_t *to_delete = *current;
            *current = (*current)->next;
            free(to_delete);
        } else {
            current = &((*current)->next);
        }
    }
}

// 检查是否为重复事件
static int is_duplicate_event(const char *path, file_event_type_t type, uint64_t timestamp) {
    cleanup_expired_events(timestamp);
    
    recent_event_t *current = g_recent_events;
    while (current) {
        if (current->type == type && 
            strcmp(current->path, path) == 0 &&
            (timestamp - current->timestamp) <= EVENT_DEDUP_WINDOW_MS) {
            return 1; // 是重复事件
        }
        current = current->next;
    }
    return 0; // 不是重复事件
}

// 记录新事件
static void record_event(const char *path, file_event_type_t type, uint64_t timestamp) {
    recent_event_t *new_event = malloc(sizeof(recent_event_t));
    if (!new_event) return;
    
    strncpy(new_event->path, path, sizeof(new_event->path) - 1);
    new_event->path[sizeof(new_event->path) - 1] = '\0';
    new_event->type = type;
    new_event->timestamp = timestamp;
    new_event->next = g_recent_events;
    g_recent_events = new_event;
}

// 清理所有事件记录
static void cleanup_all_events(void) {
    while (g_recent_events) {
        recent_event_t *to_delete = g_recent_events;
        g_recent_events = g_recent_events->next;
        free(to_delete);
    }
}

// 递归添加目录监控
static int add_watch_recursive(int fd, const char *path, const watch_config_t *config) {
    if (g_watch_count >= MAX_WATCH_DIRS) {
        fprintf(stderr, "警告: 已达到最大监控目录数量 %d\n", MAX_WATCH_DIRS);
        return -1;
    }
    
    int wd = inotify_add_watch(fd, path, 
                               IN_CREATE | IN_MODIFY | IN_DELETE | 
                               IN_MOVED_FROM | IN_MOVED_TO | IN_CLOSE_WRITE);
    if (wd == -1) {
        perror("inotify_add_watch");
        return -1;
    }
    
    g_watch_descriptors[g_watch_count] = wd;
    strncpy(g_watch_paths[g_watch_count], path, MAX_PATH_LEN - 1);
    g_watch_paths[g_watch_count][MAX_PATH_LEN - 1] = '\0';
    g_watch_count++;
    
    // 递归处理子目录
    if (config->recursive) {
        DIR *dir = opendir(path);
        if (dir) {
            struct dirent *entry;
            while ((entry = readdir(dir)) != NULL) {
                if (entry->d_type == DT_DIR && 
                    strcmp(entry->d_name, ".") != 0 && 
                    strcmp(entry->d_name, "..") != 0) {
                    
                    char subdir[MAX_PATH_LEN];
                    snprintf(subdir, sizeof(subdir), "%s/%s", path, entry->d_name);
                    
                    // 检查是否应该忽略
                    if (!should_ignore_file(subdir, config->ignore_patterns)) {
                        add_watch_recursive(fd, subdir, config);
                    }
                }
            }
            closedir(dir);
        }
    }
    
    return 0;
}

// 根据监控描述符查找路径
static const char* find_watch_path(int wd) {
    for (int i = 0; i < g_watch_count; i++) {
        if (g_watch_descriptors[i] == wd) {
            return g_watch_paths[i];
        }
    }
    return NULL;
}

int file_monitor_start(const watch_config_t *config, watch_stats_t *stats) {
    if (!config || !config->monitor_dir[0]) {
        fprintf(stderr, "错误: 无效的监控配置\n");
        return -1;
    }
    
    g_stats = stats;
    if (g_stats) {
        memset(g_stats, 0, sizeof(watch_stats_t));
        g_stats->start_time = get_current_timestamp_ms();
    }
    
    printf("👀 [Linux] 开始监控目录: %s\n", config->monitor_dir);
    printf("    架构: %s\n",
#ifdef __x86_64__
           "x86_64"
#elif defined(__i386__)
           "x86 (32-bit)"
#elif defined(__aarch64__)
           "ARM64"
#elif defined(__arm__)
           "ARM32"
#elif defined(__mips__)
           "MIPS"
#elif defined(__riscv)
           "RISC-V"
#else
           "Unknown"
#endif
    );
    printf("    递归监控: %s\n", config->recursive ? "是" : "否");
    printf("    (按 Ctrl+C 停止监控)\n\n");
    
    // 设置信号处理
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    g_inotify_fd = inotify_init();
    if (g_inotify_fd == -1) {
        perror("inotify_init");
        return -1;
    }
    
    g_watch_count = 0;
    if (add_watch_recursive(g_inotify_fd, config->monitor_dir, config) == -1) {
        close(g_inotify_fd);
        return -1;
    }
    
    printf("📁 监控了 %d 个目录\n\n", g_watch_count);
    
    g_monitor_running = 1;
    char buffer[BUF_LEN];
    
    while (g_monitor_running) {
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(g_inotify_fd, &fds);
        
        struct timeval timeout = {1, 0}; // 1秒超时
        int ret = select(g_inotify_fd + 1, &fds, NULL, NULL, &timeout);
        
        if (ret == -1) {
            if (g_monitor_running) {
                perror("select");
            }
            break;
        } else if (ret == 0) {
            // 超时，检查统计显示
            if (config->show_stats && config->stats_interval > 0) {
                static time_t last_stats_time = 0;
                time_t now = time(NULL);
                if (now - last_stats_time >= config->stats_interval) {
                    if (g_stats) {
                        printf("\r📊 创建:%llu 修改:%llu 删除:%llu 移动:%llu",
                               g_stats->created_count, g_stats->modified_count,
                               g_stats->deleted_count, g_stats->moved_count);
                        fflush(stdout);
                    }
                    last_stats_time = now;
                }
            }
            continue;
        }
        
        if (!FD_ISSET(g_inotify_fd, &fds)) {
            continue;
        }
        
        int length = read(g_inotify_fd, buffer, BUF_LEN);
        if (length <= 0) {
            if (g_monitor_running) {
                perror("read");
            }
            break;
        }
        
        int i = 0;
        while (i < length) {
            struct inotify_event *event = (struct inotify_event *)&buffer[i];
            
            if (event->len > 0) {
                const char *watch_path = find_watch_path(event->wd);
                if (watch_path) {
                    file_event_t file_event = {0};
                    snprintf(file_event.path, sizeof(file_event.path), 
                            "%s/%s", watch_path, event->name);
                    file_event.timestamp = get_current_timestamp_ms();
                    
                    // 智能事件判断 - 每次操作只显示最终的、最有意义的事件
                    int should_process = 1;
                    
                    if (event->mask & IN_DELETE || event->mask & IN_MOVED_FROM) {
                        // 文件删除 - 立即处理，优先级最高
                        file_event.type = FILE_EVENT_DELETED;
                    } else if (event->mask & IN_CLOSE_WRITE) {
                        // 文件写入完成 - 这是最可靠的"操作完成"指示
                        struct stat st;
                        if (stat(file_event.path, &st) == 0) {
                            // 检查文件是否为空或很小，以及是否是最近创建的
                            recent_event_t *recent = g_recent_events;
                            int found_recent_create = 0;
                            uint64_t now = get_current_timestamp_ms();
                            
                            // 检查最近500ms内是否有同一文件的CREATE事件
                            while (recent) {
                                if (strcmp(recent->path, file_event.path) == 0 && 
                                    recent->type == FILE_EVENT_CREATED &&
                                    (now - recent->timestamp) <= EVENT_DEDUP_WINDOW_MS) {
                                    found_recent_create = 1;
                                    break;
                                }
                                recent = recent->next;
                            }
                            
                            if (found_recent_create) {
                                // 最近刚创建的文件，CLOSE_WRITE是创建操作的一部分，跳过
                                should_process = 0;
                            } else {
                                // 已存在文件的修改操作
                                file_event.type = FILE_EVENT_MODIFIED;
                            }
                        } else {
                            // 文件不存在了，跳过
                            should_process = 0;
                        }
                    } else if (event->mask & IN_CREATE) {
                        // 文件创建 - 只处理这个事件，忽略后续的CLOSE_WRITE
                        file_event.type = FILE_EVENT_CREATED;
                    } else if (event->mask & IN_MOVED_TO) {
                        // 文件移入 - 视为创建
                        file_event.type = FILE_EVENT_CREATED;
                    } else {
                        // 跳过其他所有事件（包括IN_MODIFY）
                        should_process = 0;
                    }
                    
                    // 只有当should_process为1时才处理事件
                    if (should_process) {
                        // 获取文件大小
                        if (file_event.type != FILE_EVENT_DELETED) {
                            struct stat st;
                            if (stat(file_event.path, &st) == 0) {
                                file_event.file_size = st.st_size;
                            }
                        }
                        
                        // 事件去重检查
                        if (!is_duplicate_event(file_event.path, file_event.type, file_event.timestamp)) {
                            record_event(file_event.path, file_event.type, file_event.timestamp);
                            
                            if (config->callback) {
                                config->callback(&file_event, config->user_data);
                            }
                        } else {
                            // 调试信息：显示被过滤的重复事件
                            if (config->verbose) {
                                char time_str[32];
                                format_time_string(time_str, sizeof(time_str));
                                printf("[%s] 🔄 DUPLICATE %s (已过滤)\n", 
                                       time_str, file_event.path);
                            }
                        }
                    }
                }
            }
            
            i += EVENT_SIZE + event->len;
        }
    }
    
    // 清理
    for (int i = 0; i < g_watch_count; i++) {
        inotify_rm_watch(g_inotify_fd, g_watch_descriptors[i]);
    }
    close(g_inotify_fd);
    g_inotify_fd = -1;
    g_watch_count = 0;
    
    // 清理事件去重记录
    cleanup_all_events();
    
    return 0;
}

void file_monitor_stop(void) {
    g_monitor_running = 0;
}

int file_monitor_is_supported(void) {
    return 1; // Linux 总是支持 inotify
}

const char* file_monitor_get_platform_name(void) {
    return "Linux ("
#ifdef __x86_64__
           "x86_64"
#elif defined(__i386__)
           "x86"
#elif defined(__aarch64__)
           "ARM64"
#elif defined(__arm__)
           "ARM32"
#elif defined(__mips__)
           "MIPS"
#elif defined(__riscv)
           "RISC-V"
#else
           "Unknown"
#endif
           ")";
}

#else
// ==================== 不支持的平台 ====================

int file_monitor_start(const watch_config_t *config, watch_stats_t *stats) {
    (void)config;
    (void)stats;
    fprintf(stderr, "错误: 当前平台不支持文件监控功能\n");
    fprintf(stderr, "支持的平台: Linux (x86_64/ARM32/ARM64), macOS (Intel/Apple Silicon)\n");
    return -1;
}

void file_monitor_stop(void) {
    // 空实现
}

int file_monitor_is_supported(void) {
    return 0;
}

const char* file_monitor_get_platform_name(void) {
    return "Unsupported Platform";
}

#endif

// ==================== 通用辅助函数 ====================

// 创建默认的 watch 配置
watch_config_t* create_default_watch_config(const char *monitor_dir) {
    watch_config_t *config = malloc(sizeof(watch_config_t));
    if (!config) return NULL;
    
    memset(config, 0, sizeof(watch_config_t));
    
    if (monitor_dir) {
        strncpy(config->monitor_dir, monitor_dir, sizeof(config->monitor_dir) - 1);
    } else {
        strncpy(config->monitor_dir, ".", sizeof(config->monitor_dir) - 1);
    }
    
    // 默认忽略模式
    strncpy(config->ignore_patterns, 
            ".snapshot,*.o,*.so,*.a,*.tmp,*.log,*.bak,.git,node_modules,build,*.pyc",
            sizeof(config->ignore_patterns) - 1);
    
    config->recursive = 1;           // 默认递归监控
    config->verbose = 0;             // 默认简洁输出
    config->show_stats = 0;          // 默认不显示统计
    config->stats_interval = 10;     // 10秒间隔
    config->callback = default_event_callback;
    config->user_data = config;      // 回调中使用配置本身
    
    return config;
}

// 销毁 watch 配置
void destroy_watch_config(watch_config_t *config) {
    if (config) {
        free(config);
    }
} 