/**
 * Git风格快照系统 - 完整的差异分析功能
 */

#include "snapshot_core.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include <unistd.h>

// 跨平台获取CPU核心数函数 - 避免复杂的系统头文件包含
static int get_cpu_count(void) {
#ifdef __APPLE__
    // macOS: 使用更简单的方法，避免头文件冲突
    // 简化版本，使用固定的合理默认值
    // 在实际使用中，大多数macOS系统都是多核的
    return 4; // 合理的默认值，用户可通过-t参数覆盖
#else
    // Linux 和其他 POSIX 系统
    long cpu_count = sysconf(_SC_NPROCESSORS_ONLN);
    return (cpu_count > 0) ? (int)cpu_count : 2; // 默认值
#endif
}

// 实时状态检查功能 - 基于快照的实时目录对比
int git_snapshot_status(const char *snapshot_path, const char *dir_path,
                       const snapshot_config_t *config, snapshot_result_t *result) {
    FILE *snapshot_file = NULL;
    git_index_t *baseline_index = NULL, *current_index = NULL;
    int ret = -1;
    
    memset(result, 0, sizeof(snapshot_result_t));
    
    // 1. 载入基线快照
    snapshot_file = fopen(snapshot_path, "r");
    if (!snapshot_file) {
        snprintf(result->error_message, sizeof(result->error_message), 
                "无法打开快照文件: %s", snapshot_path);
        goto cleanup;
    }
    
    baseline_index = git_index_create(50000);
    if (!baseline_index) {
        strcpy(result->error_message, "内存分配失败");
        goto cleanup;
    }
    
    if (load_snapshot_file(snapshot_file, baseline_index) < 0) {
        strcpy(result->error_message, "读取基线快照失败");
        goto cleanup;
    }
    
    if (config->verbose) {
        printf("📖 已载入基线快照：%"PRIu64" 个文件\n", baseline_index->count);
    }
    
    // 2. 实时扫描当前目录
    current_index = git_index_create(50000);
    if (!current_index) {
        strcpy(result->error_message, "内存分配失败");
        goto cleanup;
    }
    
    if (config->verbose) {
        printf("🔍 正在扫描当前目录：%s\n", dir_path);
    }
    
    // 创建临时的结果收集器进行实时扫描
    result_collector_t *collector = result_collector_create();
    if (!collector) {
        strcpy(result->error_message, "无法创建结果收集器");
        goto cleanup;
    }
    
    // 使用简化的工作线程池进行实时扫描（不写文件）
    int thread_count = config->thread_count > 0 ? config->thread_count : get_cpu_count();
    worker_pool_t *pool = worker_pool_create(thread_count, collector, config, NULL, NULL);  // 不创建快照文件
    if (!pool) {
        result_collector_destroy(collector);
        strcpy(result->error_message, "无法创建工作线程池");
        goto cleanup;
    }
    
    // 执行实时目录扫描
    uint64_t total_files = 0;
    if (scan_directory_recursive(dir_path, pool, config, &total_files) < 0) {
        worker_pool_destroy(pool);
        result_collector_destroy(collector);
        strcpy(result->error_message, "目录扫描失败");
        goto cleanup;
    }
    
    // 3. 收集结果（先从结果队列获取，再等待线程完成）
    int queue_items = 0;
    
    // 等待一小段时间让工作线程完成
    usleep(10000);  // 10ms
    
    // 从结果队列中获取所有结果
    if (pool->result_queue) {
        while (pool->result_queue->size > 0) {
            result_entry_t *result_item = bounded_result_queue_pop(pool->result_queue);
            if (result_item) {
                if (result_item->error_code == 0) {
                    if (git_index_add(current_index, &result_item->entry) < 0) {
                        free(result_item);
                        worker_pool_destroy(pool);
                        result_collector_destroy(collector);
                        strcpy(result->error_message, "索引构建失败");
                        goto cleanup;
                    }
                    queue_items++;
                }
                free(result_item);
            } else {
                break;  // 队列为空
            }
        }
    }
    
    // 等待所有工作线程完成（但不销毁队列）
    pool->shutdown = 1;
    
    // 关闭工作队列
    if (pool->work_queue) {
        pthread_mutex_lock(&pool->work_queue->lock);
        pool->work_queue->shutdown = 1;
        pthread_cond_broadcast(&pool->work_queue->not_empty);
        pthread_mutex_unlock(&pool->work_queue->lock);
    }
    
    // 等待工作线程完成
    for (int i = 0; i < pool->thread_count; i++) {
        pthread_join(pool->threads[i], NULL);
    }
    
    // 再次检查结果队列中的剩余结果
    if (pool->result_queue) {
        while (pool->result_queue->size > 0) {
            result_entry_t *result_item = bounded_result_queue_pop(pool->result_queue);
            if (result_item) {
                if (result_item->error_code == 0) {
                    if (git_index_add(current_index, &result_item->entry) < 0) {
                        free(result_item);
                        worker_pool_destroy(pool);
                        result_collector_destroy(collector);
                        strcpy(result->error_message, "索引构建失败");
                        goto cleanup;
                    }
                    queue_items++;
                }
                free(result_item);
            } else {
                break;
            }
        }
    }
    
    if (config->verbose) {
        printf("📊 扫描完成：发现 %"PRIu64" 个文件\n", total_files);
        printf("🔍 成功添加到索引：%d 个文件\n", queue_items);
        printf("🔍 当前索引文件数：%"PRIu64"\n", current_index->count);
    }
    
    worker_pool_destroy(pool);
    result_collector_destroy(collector);
    
    // 4. 执行差异分析
    git_index_sort(baseline_index);
    git_index_sort(current_index);
    
    if (perform_diff_analysis(baseline_index, current_index, config, result) < 0) {
        strcpy(result->error_message, "差异分析失败");
        goto cleanup;
    }
    
    ret = 0;
    
cleanup:
    if (snapshot_file) fclose(snapshot_file);
    if (baseline_index) git_index_destroy(baseline_index);
    if (current_index) git_index_destroy(current_index);
    
    return ret;
}

// 快照对比功能 - 100%准确的差异检测
int git_snapshot_diff(const char *old_snapshot, const char *new_snapshot,
                     const snapshot_config_t *config, snapshot_result_t *result) {
    FILE *old_file = NULL, *new_file = NULL;
    git_index_t *old_index = NULL, *new_index = NULL;
    int ret = -1;
    
    memset(result, 0, sizeof(snapshot_result_t));
    
    // 打开快照文件
    old_file = fopen(old_snapshot, "r");
    if (!old_file) {
        snprintf(result->error_message, sizeof(result->error_message), 
                "无法打开旧快照文件: %s", old_snapshot);
        goto cleanup;
    }
    
    new_file = fopen(new_snapshot, "r");
    if (!new_file) {
        snprintf(result->error_message, sizeof(result->error_message),
                "无法打开新快照文件: %s", new_snapshot);
        goto cleanup;
    }
    
    // 创建索引
    old_index = git_index_create(50000);
    new_index = git_index_create(50000);
    if (!old_index || !new_index) {
        strcpy(result->error_message, "内存分配失败");
        goto cleanup;
    }
    
    // 读取旧快照
    if (load_snapshot_file(old_file, old_index) < 0) {
        strcpy(result->error_message, "读取旧快照失败");
        goto cleanup;
    }
    
    // 读取新快照
    if (load_snapshot_file(new_file, new_index) < 0) {
        strcpy(result->error_message, "读取新快照失败");
        goto cleanup;
    }
    
    // 排序索引以便高效比较
    git_index_sort(old_index);
    git_index_sort(new_index);
    
    // 执行差异分析
    if (perform_diff_analysis(old_index, new_index, config, result) < 0) {
        strcpy(result->error_message, "差异分析失败");
        goto cleanup;
    }
    
    ret = 0;
    
cleanup:
    if (old_file) fclose(old_file);
    if (new_file) fclose(new_file);
    if (old_index) git_index_destroy(old_index);
    if (new_index) git_index_destroy(new_index);
    
    return ret;
}

// Git索引相关功能 - 完整实现
git_index_t* git_index_create(uint64_t initial_capacity) {
    git_index_t *index = malloc(sizeof(git_index_t));
    if (!index) return NULL;
    
    index->entries = malloc(sizeof(file_entry_t) * initial_capacity);
    if (!index->entries) {
        free(index);
        return NULL;
    }
    
    index->count = 0;
    index->capacity = initial_capacity;
    index->sorted = 0;
    
    return index;
}

void git_index_destroy(git_index_t *index) {
    if (index) {
        if (index->entries) free(index->entries);
        free(index);
    }
}

int git_index_add(git_index_t *index, const file_entry_t *entry) {
    if (!index || !entry) return -1;
    
    // 扩容检查
    if (index->count >= index->capacity) {
        uint64_t new_capacity = index->capacity * 2;
        file_entry_t *new_entries = realloc(index->entries, 
                                           sizeof(file_entry_t) * new_capacity);
        if (!new_entries) return -1;
        
        index->entries = new_entries;
        index->capacity = new_capacity;
    }
    
    // 添加条目
    memcpy(&index->entries[index->count], entry, sizeof(file_entry_t));
    index->count++;
    index->sorted = 0;  // 标记为未排序
    
    return 0;
}

file_entry_t* git_index_find(git_index_t *index, const char *path) {
    if (!index || !path) return NULL;
    
    // 如果未排序，先排序
    if (!index->sorted) {
        git_index_sort(index);
    }
    
    // 二分搜索
    int left = 0, right = index->count - 1;
    while (left <= right) {
        int mid = (left + right) / 2;
        int cmp = strcmp(index->entries[mid].path, path);
        
        if (cmp == 0) {
            return &index->entries[mid];
        } else if (cmp < 0) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }
    
    return NULL;
}

void git_index_sort(git_index_t *index) {
    if (!index || index->sorted) return;
    
    qsort(index->entries, index->count, sizeof(file_entry_t), compare_file_entries);
    index->sorted = 1;
}

int compare_file_entries(const void *a, const void *b) {
    const file_entry_t *ea = (const file_entry_t*)a;
    const file_entry_t *eb = (const file_entry_t*)b;
    return strcmp(ea->path, eb->path);
}

// 读取快照文件到索引
int load_snapshot_file(FILE *file, git_index_t *index) {
    char line[8192];
    file_entry_t entry;
    
    // 跳过文件头部注释
    while (fgets(line, sizeof(line), file)) {
        if (line[0] != '#') {
            // 解析第一行数据
            if (parse_snapshot_line(line, &entry) == 0) {
                if (git_index_add(index, &entry) < 0) {
                    return -1;
                }
            }
            break;
        }
    }
    
    // 继续读取剩余行
    while (fgets(line, sizeof(line), file)) {
        if (parse_snapshot_line(line, &entry) == 0) {
            if (git_index_add(index, &entry) < 0) {
                return -1;
            }
        }
    }
    
    return 0;
}

// 解析快照文件中的一行
int parse_snapshot_line(const char *line, file_entry_t *entry) {
    char *line_copy = strdup(line);
    char *token;
    int field = 0;
    
    if (!line_copy) return -1;
    
    // 去除换行符
    char *newline = strchr(line_copy, '\n');
    if (newline) *newline = '\0';
    
    token = strtok(line_copy, ";");
    while (token && field < 5) {
        switch (field) {
            case 0: // 路径
                strncpy(entry->path, token, MAX_PATH_LEN - 1);
                entry->path[MAX_PATH_LEN - 1] = '\0';
                break;
            case 1: // 大小
                entry->size = strtoull(token, NULL, 10);
                break;
            case 2: // 修改时间
                entry->mtime = strtoull(token, NULL, 10);
                break;
            case 3: // 文件权限
                entry->mode = (mode_t)strtoul(token, NULL, 8);  // 八进制
                break;
            case 4: // 哈希
                strncpy(entry->hash_hex, token, HASH_HEX_SIZE - 1);
                entry->hash_hex[HASH_HEX_SIZE - 1] = '\0';
                // 将十六进制字符串转换为二进制
                hex_to_binary(token, entry->hash);
                break;
        }
        token = strtok(NULL, ";");
        field++;
    }
    
    free(line_copy);
    return (field >= 4) ? 0 : -1;  // 至少解析4个字段（兼容旧格式）
}

// 十六进制字符串转二进制
void hex_to_binary(const char *hex, unsigned char *binary) {
    for (int i = 0; i < HASH_SIZE && hex[i*2] && hex[i*2+1]; i++) {
        sscanf(&hex[i*2], "%2hhx", &binary[i]);
    }
}

// 执行差异分析 - 高效O(n)算法
int perform_diff_analysis(git_index_t *old_index, git_index_t *new_index,
                         const snapshot_config_t *config, snapshot_result_t *result) {
    (void)config;  // 参数保留用于未来扩展
    
    printf("\n🔍 差异分析报告:\n");
    printf("================\n");
    
    uint64_t added = 0, modified = 0, deleted = 0;
    
    // 确保两个索引都已排序
    git_index_sort(old_index);
    git_index_sort(new_index);
    
    // 初始化所有旧文件的标记为0（未处理）
    for (uint64_t i = 0; i < old_index->count; i++) {
        old_index->entries[i].flags = 0;
    }
    
    printf("🔄 正在分析 %"PRIu64" 个旧文件和 %"PRIu64" 个新文件...\n", 
           old_index->count, new_index->count);
    
    // 使用双指针技术进行高效比较 O(n+m)
    uint64_t old_idx = 0, new_idx = 0;
    
    while (new_idx < new_index->count && old_idx < old_index->count) {
        file_entry_t *new_entry = &new_index->entries[new_idx];
        file_entry_t *old_entry = &old_index->entries[old_idx];
        
        int cmp = strcmp(new_entry->path, old_entry->path);
        
        if (cmp == 0) {
            // 文件路径相同，检查是否修改
            if (strcmp(new_entry->hash_hex, old_entry->hash_hex) != 0) {
                printf("M\t%s\n", new_entry->path);
                modified++;
            }
            // 标记旧文件已处理
            old_entry->flags = 1;
            new_idx++;
            old_idx++;
        } else if (cmp < 0) {
            // 新文件路径更小，说明是新增的
            printf("A\t%s\n", new_entry->path);
            added++;
            new_idx++;
        } else {
            // 旧文件路径更小，说明该文件被删除了
            // 但这里不输出，稍后统一处理
            old_idx++;
        }
        
        // 进度显示（每处理1000个文件显示一次）
        if ((new_idx + old_idx) % 1000 == 0) {
            printf(".");
            fflush(stdout);
        }
    }
    
    // 处理剩余的新文件（都是新增的）
    while (new_idx < new_index->count) {
        printf("A\t%s\n", new_index->entries[new_idx].path);
        added++;
        new_idx++;
    }
    
    printf("\n");
    
    // 检查删除的文件（未标记的旧文件）
    for (uint64_t i = 0; i < old_index->count; i++) {
        file_entry_t *old_entry = &old_index->entries[i];
        if (old_entry->flags == 0) {
            printf("D\t%s\n", old_entry->path);
            deleted++;
        }
    }
    
    // 统计结果
    result->added_files = added;
    result->modified_files = modified;
    result->deleted_files = deleted;
    result->total_files = old_index->count;
    result->processed_files = new_index->count;
    
    printf("\n📊 统计信息:\n");
    printf("新增文件: %"PRIu64"\n", added);
    printf("修改文件: %"PRIu64"\n", modified);
    printf("删除文件: %"PRIu64"\n", deleted);
    printf("总变更: %"PRIu64"\n", added + modified + deleted);
    
    return 0;
}