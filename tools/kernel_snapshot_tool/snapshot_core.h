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

#define MAX_PATH_LEN 4096
#define HASH_SIZE 20           // SHA1大小（Git兼容）
#define HASH_HEX_SIZE 41       // 十六进制字符串
#define WORKERS_MAX 32         // 最大工作线程数

// 文件条目（类似Git的cache_entry）
typedef struct file_entry {
    char path[MAX_PATH_LEN];
    uint64_t size;
    uint64_t mtime;
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

// 工作线程池（简化设计）
typedef struct worker_pool {
    pthread_t *threads;
    int thread_count;
    
    // 工作分发（生产者消费者模式）
    work_unit_t *work_head;
    work_unit_t *work_tail;
    pthread_mutex_t work_lock;
    pthread_cond_t work_cond;
    pthread_cond_t done_cond;
    
    // 结果收集
    result_collector_t *collector;
    
    // 控制标志
    int shutdown;
    int active_workers;
    
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
} snapshot_config_t;

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

worker_pool_t* worker_pool_create(int thread_count, result_collector_t *collector);
void worker_pool_destroy(worker_pool_t *pool);
int worker_pool_add_work(worker_pool_t *pool, const char *file_path);
void worker_pool_wait_completion(worker_pool_t *pool);

result_collector_t* result_collector_create(void);
void result_collector_destroy(result_collector_t *collector);
void result_collector_add(result_collector_t *collector, const result_entry_t *entry);

// 文件处理
int process_file_content(const char *file_path, file_entry_t *entry, int use_git_hash);
int calculate_git_hash(const char *file_path, unsigned char *hash);
int calculate_fast_hash(const char *file_path, unsigned char *hash);

// 工具函数
void hash_to_hex(const unsigned char *hash, char *hex_output);
int compare_file_entries(const void *a, const void *b);
int is_excluded_file(const char *path, const char *exclude_patterns);

// 快照差异分析函数
int load_snapshot_file(FILE *file, git_index_t *index);
int parse_snapshot_line(const char *line, file_entry_t *entry);
void hex_to_binary(const char *hex, unsigned char *binary);
int perform_diff_analysis(git_index_t *old_index, git_index_t *new_index,
                         const snapshot_config_t *config, snapshot_result_t *result);

#endif // SNAPSHOT_CORE_H