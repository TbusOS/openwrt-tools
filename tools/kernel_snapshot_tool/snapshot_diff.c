/**
 * Git风格快照系统 - 完整的差异分析功能
 */

#include "snapshot_core.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

// 暂时未实现的状态检查功能
int git_snapshot_status(const char *snapshot_path, const char *dir_path,
                       const snapshot_config_t *config, snapshot_result_t *result) {
    strcpy(result->error_message, "status功能尚未实现");
    return -1;
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
    while (token && field < 4) {
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
            case 3: // 哈希
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
    return (field == 4) ? 0 : -1;
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
    
    printf("🔄 正在分析 %llu 个旧文件和 %llu 个新文件...\n", 
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
    printf("新增文件: %llu\n", added);
    printf("修改文件: %llu\n", modified);
    printf("删除文件: %llu\n", deleted);
    printf("总变更: %llu\n", added + modified + deleted);
    
    return 0;
}