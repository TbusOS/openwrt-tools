#ifndef FILE_MONITOR_H
#define FILE_MONITOR_H

#include "snapshot_core.h"
#include <stdint.h>

// 文件事件类型
typedef enum {
    FILE_EVENT_CREATED = 1,
    FILE_EVENT_MODIFIED = 2,
    FILE_EVENT_DELETED = 4,
    FILE_EVENT_MOVED = 8
} file_event_type_t;

// 文件事件结构
typedef struct file_event {
    char path[MAX_PATH_LEN];
    file_event_type_t type;
    uint64_t timestamp;
    size_t file_size;
} file_event_t;

// 事件回调函数类型
typedef void (*file_event_callback_t)(const file_event_t *event, void *user_data);

// 监控配置
typedef struct watch_config {
    char monitor_dir[MAX_PATH_LEN];     // 监控目录
    char ignore_patterns[1024];         // 忽略模式
    int recursive;                      // 递归监控
    int verbose;                        // 详细输出
    int show_stats;                     // 显示统计
    int stats_interval;                 // 统计间隔（秒）
    file_event_callback_t callback;     // 事件回调
    void *user_data;                    // 用户数据
} watch_config_t;

// 监控统计
typedef struct watch_stats {
    uint64_t created_count;
    uint64_t modified_count;
    uint64_t deleted_count;
    uint64_t moved_count;
    uint64_t start_time;
    uint64_t last_event_time;
} watch_stats_t;

// 跨平台文件监控接口
/**
 * @brief 开始文件监控
 * @param config 监控配置
 * @param stats 统计信息输出（可选）
 * @return 0成功，-1失败
 */
int file_monitor_start(const watch_config_t *config, watch_stats_t *stats);

/**
 * @brief 停止文件监控
 */
void file_monitor_stop(void);

/**
 * @brief 检查平台支持
 * @return 1支持，0不支持
 */
int file_monitor_is_supported(void);

/**
 * @brief 获取平台名称
 */
const char* file_monitor_get_platform_name(void);

/**
 * @brief 创建默认的监控配置
 * @param monitor_dir 监控目录
 * @return 配置指针，使用后需要释放
 */
watch_config_t* create_default_watch_config(const char *monitor_dir);

/**
 * @brief 销毁监控配置
 * @param config 配置指针
 */
void destroy_watch_config(watch_config_t *config);

/**
 * @brief 获取当前时间戳（毫秒）
 * @return 时间戳
 */
uint64_t get_current_timestamp_ms(void);

#endif // FILE_MONITOR_H 