/**
 * 简单索引缓存系统 - 头文件
 * 提供高性能的文件索引和状态检查功能
 */

#ifndef INDEX_CACHE_SIMPLE_H
#define INDEX_CACHE_SIMPLE_H

#include <stdint.h>
#include <sys/stat.h>

#define INDEX_FILE "index"  // 索引文件名

// 索引条目结构
typedef struct {
    char *rel_path;          // 相对路径
    uint64_t last_modified;  // 最后修改时间 (纳秒)
    uint64_t file_size;      // 文件大小
    char file_hash[41];      // 文件哈希 (40字符 + '\0')
} simple_index_entry_t;

// 简单索引结构
typedef struct {
    simple_index_entry_t *entries;  // 条目数组
    size_t count;                  // 当前条目数
    size_t capacity;               // 数组容量
    
    // 哈希表 (用于快速查找)
    simple_index_entry_t **hash_table;
    size_t hash_table_size;
} simple_index_t;

// 前向声明 - 避免与 snapshot_core.h 冲突
// 移除typedef重复定义，使用前向声明
struct change_list;

// 函数声明
simple_index_t* create_simple_index_from_snapshot(const char *snapshot_path);

#endif // INDEX_CACHE_SIMPLE_H