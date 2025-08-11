/**
 * Git风格快照系统 - 零文件丢失设计
 * 
 * 设计原则：
 * 1. 文件遍历单线程 - 绝对不丢失文件
 * 2. 内容处理并行 - 安全的多线程优化
 * 3. 简单数据流 - 避免复杂队列
 * 4. 内存效率 - 流式处理大型项目
 */

#ifndef SNAPSHOT_CORE_H
#define SNAPSHOT_CORE_H

#include <stdint.h>
#include <pthread.h>
#include <sys/stat.h>
#include <stdio.h>

// 进度条显示函数
void show_progress_bar(uint64_t current, uint64_t total, const char *current_file);
void show_create_summary(uint64_t total_files, uint64_t processed_files, 
                        uint64_t failed_files, time_t elapsed_time);
void show_scan_progress(uint64_t scanned_dirs, const char *current_dir);

#define MAX_PATH_LEN 4096
#define HASH_SIZE_SHA1 20      // SHA1大小（Git兼容）
#define HASH_SIZE_SHA256 32    // SHA256大小（默认使用）
#define HASH_SIZE 32           // 默认使用SHA256
#define HASH_HEX_SIZE 65       // SHA256十六进制字符串
#define WORKERS_MAX 32         // 最大工作线程数

// 文件条目（类似Git的cache_entry）
typedef struct file_entry {
    char path[MAX_PATH_LEN];
    uint64_t size;
    uint64_t mtime;
    mode_t mode;               // 文件权限和类型（新增元数据）
    unsigned char hash[HASH_SIZE];
    char hash_hex[HASH_HEX_SIZE];
    uint32_t flags;            // 状态标志
} file_entry_t;

// 快照状态
typedef enum {
    FILE_UNMODIFIED = 0,
    FILE_ADDED = 1,
    FILE_MODIFIED = 2,
    FILE_DELETED = 3
} file_status_t;

// 工作单元（只包含需要处理的文件路径）
typedef struct work_unit {
    char path[MAX_PATH_LEN];
    struct work_unit *next;
} work_unit_t;

// 结果条目
typedef struct result_entry {
    file_entry_t entry;
    file_status_t status;
    int error_code;
    struct result_entry *next;
} result_entry_t;

// 线程安全的结果收集器（替代复杂队列）
typedef struct result_collector {
    result_entry_t *head;
    result_entry_t *tail;
    pthread_mutex_t lock;
    uint64_t count;
    uint64_t errors;
} result_collector_t;

// 有界队列配置
// 队列容量配置 - 针对大型项目（如Linux内核）优化
#define WORK_QUEUE_MAX_SIZE 100000     // 工作队列最大大小 (支持10万+ 文件)
#define RESULT_QUEUE_MAX_SIZE 50000    // 结果队列最大大小 (支持5万+ 文件)

// 内存友好的小项目队列大小
#define WORK_QUEUE_MIN_SIZE 1000       // 小项目工作队列大小
#define RESULT_QUEUE_MIN_SIZE 500      // 小项目结果队列大小

// 工作区配置
#define SNAPSHOT_DIR ".snapshot"       // 隐藏快照目录
#define BASELINE_FILE "baseline.snapshot"  // 基线快照文件
#define CONFIG_FILE "workspace.conf"   // 工作区配置文件

// 有界工作队列
typedef struct bounded_work_queue {
    work_unit_t **items;               // 队列数组
    int capacity;                      // 队列容量
    int size;                          // 当前大小
    int head;                          // 队列头
    int tail;                          // 队列尾
    pthread_mutex_t lock;
    pthread_cond_t not_full;           // 队列不满条件
    pthread_cond_t not_empty;          // 队列不空条件
    int shutdown;
} bounded_work_queue_t;

// 有界结果队列
typedef struct bounded_result_queue {
    result_entry_t **items;            // 队列数组
    int capacity;                      // 队列容量
    int size;                          // 当前大小
    int head;                          // 队列头
    int tail;                          // 队列尾
    pthread_mutex_t lock;
    pthread_cond_t not_full;           // 队列不满条件
    pthread_cond_t not_empty;          // 队列不空条件
    int shutdown;
} bounded_result_queue_t;

// 工作线程池（增强设计 - 有界队列）
typedef struct worker_pool {
    pthread_t *threads;
    pthread_t writer_thread;           // 专用写入线程
    int thread_count;
    
    // 有界工作队列（替代无限链表）
    bounded_work_queue_t *work_queue;
    
    // 有界结果队列（流式写出）
    bounded_result_queue_t *result_queue;
    
    // 结果收集
    result_collector_t *collector;
    FILE *snapshot_file;               // 流式写出的目标文件
    
    // 配置参数（修复use_git_hash传递问题）
    int use_git_hash;          // 传递给工作线程的哈希选项
    int verbose;               // 传递给工作线程的详细输出选项
    
    // 控制标志和同步（简化版本）
    pthread_mutex_t work_lock;         // 工作线程同步锁
    int shutdown;
    int active_workers;
    int writer_active;                 // 写入线程是否活跃
    
    // 统计信息
    uint64_t processed_files;
    uint64_t failed_files;
} worker_pool_t;

// Git风格索引（用于快速查找）
typedef struct git_index {
    file_entry_t *entries;
    uint64_t count;
    uint64_t capacity;
    int sorted;                // 是否已排序
} git_index_t;

// 快照配置
typedef struct snapshot_config {
    int thread_count;
    int verbose;
    char *exclude_patterns;
    int use_git_hash;          // 使用Git兼容的SHA1
    int streaming_mode;        // 流式处理模式
    int show_progress;         // 显示进度条
} snapshot_config_t;

// 工作区配置（持久化配置文件）
typedef struct workspace_config {
    char project_name[MAX_PATH_LEN];      // 项目名称
    char workspace_dir[MAX_PATH_LEN];     // 默认工作目录绝对路径
    char ignore_patterns[MAX_PATH_LEN];   // 忽略文件模式，用逗号分隔
    uint64_t created_time;                // 创建时间
    uint64_t updated_time;                // 最后更新时间
} workspace_config_t;

// 快照结果
typedef struct snapshot_result {
    uint64_t total_files;      // 扫描的总文件数
    uint64_t processed_files;  // 成功处理的文件数
    uint64_t failed_files;     // 失败的文件数
    uint64_t added_files;      // 新增文件数
    uint64_t modified_files;   // 修改文件数
    uint64_t deleted_files;    // 删除文件数
    uint64_t elapsed_ms;       // 耗时毫秒
    char error_message[256];
} snapshot_result_t;

// 核心API
int git_snapshot_create(const char *dir_path, const char *snapshot_path, 
                       const snapshot_config_t *config, snapshot_result_t *result);

int git_snapshot_diff(const char *old_snapshot, const char *new_snapshot,
                     const snapshot_config_t *config, snapshot_result_t *result);

int git_snapshot_status(const char *snapshot_path, const char *dir_path,
                       const snapshot_config_t *config, snapshot_result_t *result);

// 内部函数
git_index_t* git_index_create(uint64_t initial_capacity);
void git_index_destroy(git_index_t *index);
int git_index_add(git_index_t *index, const file_entry_t *entry);
file_entry_t* git_index_find(git_index_t *index, const char *path);
void git_index_sort(git_index_t *index);

// 有界队列操作
bounded_work_queue_t* bounded_work_queue_create(int capacity);
void bounded_work_queue_destroy(bounded_work_queue_t *queue);
int bounded_work_queue_push(bounded_work_queue_t *queue, work_unit_t *item);
work_unit_t* bounded_work_queue_pop(bounded_work_queue_t *queue);

bounded_result_queue_t* bounded_result_queue_create(int capacity);
void bounded_result_queue_destroy(bounded_result_queue_t *queue);
int bounded_result_queue_push(bounded_result_queue_t *queue, result_entry_t *item);
result_entry_t* bounded_result_queue_pop(bounded_result_queue_t *queue);

worker_pool_t* worker_pool_create(int thread_count, result_collector_t *collector, const snapshot_config_t *config, const char *snapshot_path, const char *base_dir);
void worker_pool_destroy(worker_pool_t *pool);
int worker_pool_add_work(worker_pool_t *pool, const char *file_path);
void worker_pool_wait_completion(worker_pool_t *pool);
void worker_pool_wait_completion_with_progress(worker_pool_t *pool, uint64_t total_files);

result_collector_t* result_collector_create(void);
void result_collector_destroy(result_collector_t *collector);
void result_collector_add(result_collector_t *collector, const result_entry_t *entry);

// 文件处理（增强哈希支持）
int process_file_content(const char *file_path, file_entry_t *entry, int use_git_hash);
int calculate_git_hash(const char *file_path, unsigned char *hash);
int calculate_sha256_hash(const char *file_path, unsigned char *hash);
int calculate_fast_hash(const char *file_path, unsigned char *hash);

// 目录扫描函数（供status命令使用）
int scan_directory_recursive(const char *dir_path, worker_pool_t *pool, 
                            const snapshot_config_t *config, uint64_t *total_files);

// 工作区管理函数
int init_workspace(const char *project_name);
int init_workspace_in_dir(const char *target_dir, const char *project_name);
char* find_workspace_root(const char *start_path);
char* get_baseline_snapshot_path(const char *workspace_root);
int workspace_exists(const char *path);

// 工作区配置管理函数
int load_workspace_config(const char *workspace_root, workspace_config_t *config);
int save_workspace_config(const char *workspace_root, const workspace_config_t *config);
int create_default_workspace_config(workspace_config_t *config, const char *project_name, const char *workspace_dir);
int is_file_ignored(const char *file_path, const char *ignore_patterns);

// 全局配置管理函数
int load_global_config(FILE *fp, workspace_config_t *config);
int save_global_config(const char *config_path, const workspace_config_t *config);

// 系统信息显示函数
void show_system_info(int thread_count);

// 进度回调函数类型
typedef void (*progress_callback_t)(uint64_t current, uint64_t total, const char *current_file);

// 进度信息结构
typedef struct progress_info {
    uint64_t total_files;
    uint64_t processed_files;
    uint64_t scanned_files;
    char current_file[MAX_PATH_LEN];
    time_t start_time;
    int show_progress;
} progress_info_t;

// SHA256 实现
typedef struct sha256_ctx {
    uint32_t state[8];
    uint64_t count;
    uint8_t buffer[64];
} sha256_ctx_t;

void sha256_init(sha256_ctx_t *ctx);
void sha256_update(sha256_ctx_t *ctx, const uint8_t *data, size_t len);
void sha256_final(sha256_ctx_t *ctx, uint8_t *hash);

// 工具函数
void hash_to_hex(const unsigned char *hash, char *hex_output);
int compare_file_entries(const void *a, const void *b);
int is_excluded_file(const char *path, const char *exclude_patterns);

// 路径规范化函数
char* normalize_path(const char *base_dir, const char *file_path);
void sanitize_path(char *path);

// 快照差异分析函数
int load_snapshot_file(FILE *file, git_index_t *index);
int parse_snapshot_line(const char *line, file_entry_t *entry);
void hex_to_binary(const char *hex, unsigned char *binary);
int perform_diff_analysis(git_index_t *old_index, git_index_t *new_index,
                         const snapshot_config_t *config, snapshot_result_t *result);

// 索引缓存函数 - Git风格快速状态检查
int git_status_with_index(const char *workspace_root, const snapshot_config_t *config);
int create_index_during_snapshot(const char *workspace_root, const char *snapshot_path, 
                                const snapshot_config_t *config);

// 文件变更列表相关类型和函数 (用于list命令)
typedef struct file_change {
    char path[MAX_PATH_LEN];
    char status; // 'A'=added, 'M'=modified, 'D'=deleted
    struct file_change *next;
} file_change_t;

typedef struct change_list {
    file_change_t *added;
    file_change_t *modified;
    file_change_t *deleted;
    uint64_t added_count;
    uint64_t modified_count;
    uint64_t deleted_count;
} change_list_t;

// 文件变更检测函数
int simple_check_status_with_list(const char *workspace_root, void *index, 
                                  change_list_t *changes, uint64_t *unchanged, 
                                  uint64_t *hash_calculations, const char *ignore_patterns);
void destroy_change_list(change_list_t *changes);
void* load_simple_index(const char *index_path);
void destroy_simple_index(void *index);

#endif // SNAPSHOT_CORE_H