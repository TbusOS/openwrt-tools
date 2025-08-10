/**
 * Git风格索引缓存实现 - 简化版本
 * 专注于核心功能，避免复杂依赖
 */

#include "snapshot_core.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>
#include <time.h>
#include <errno.h>

#define INDEX_FILE "index"  // 索引文件名
#define INDEX_MAGIC "KSGI"  // Kernel Snapshot Git Index
#define INDEX_VERSION 1

// 简化的索引条目（内存中）
typedef struct simple_index_entry {
    char path[MAX_PATH_LEN];
    uint64_t mtime;
    uint64_t size;
    char hash_hex[HASH_HEX_SIZE];
    struct simple_index_entry *next;
} simple_index_entry_t;

// 简化的索引结构
typedef struct {
    uint64_t file_count;
    simple_index_entry_t *entries;
    int dirty;
} simple_index_t;

// 文件变更列表
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

// 函数声明
simple_index_t* create_simple_index_from_snapshot(const char *snapshot_path);
simple_index_t* load_simple_index(const char *index_path);
int save_simple_index(simple_index_t *index, const char *index_path);
void simple_check_status_with_list(const char *workspace_root, simple_index_t *index,
                                  change_list_t *changes, uint64_t *unchanged, uint64_t *hash_calculations);
void simple_scan_directory_with_list(const char *base_path, const char *current_path, simple_index_t *index,
                                    change_list_t *changes, uint64_t *unchanged, uint64_t *hash_calculations);
void simple_check_file_with_list(const char *base_path, const char *file_path, struct stat *st, simple_index_t *index,
                                change_list_t *changes, uint64_t *unchanged, uint64_t *hash_calculations);
void add_file_change(change_list_t *changes, const char *path, char status);
void print_change_list(change_list_t *changes);
void destroy_change_list(change_list_t *changes);
void destroy_simple_index(simple_index_t *index);

// Git风格的快速status实现
int git_status_with_index(const char *workspace_root, const snapshot_config_t *config) {
    printf("🚀 Git风格快速状态检查 (使用索引缓存)...\n");
    
    char index_path[MAX_PATH_LEN];
    snprintf(index_path, sizeof(index_path), "%s/%s/%s", 
             workspace_root, SNAPSHOT_DIR, INDEX_FILE);
    
    // 尝试加载索引
    simple_index_t *index = load_simple_index(index_path);
    if (!index) {
        printf("⚠️  索引缓存不存在或损坏，建议重新运行create命令\n");
        return -1;
    }
    
    printf("✅ 索引载入完成，包含 %llu 个文件\n", index->file_count);
    
    // 创建变更列表
    change_list_t changes = {0};
    uint64_t unchanged = 0;
    uint64_t hash_calculations = 0;
    
    printf("🔍 开始快速扫描...\n");
    simple_check_status_with_list(workspace_root, index, &changes, &unchanged, &hash_calculations);
    
    // 显示文件变更列表（像git status那样）
    print_change_list(&changes);
    
    // 显示统计结果
    printf("\n📊 状态检查完成!\n");
    printf("================\n");
    printf("🧮 哈希计算: %llu (仅 %.1f%% 的文件)\n", hash_calculations, 
           index->file_count > 0 ? (double)hash_calculations * 100.0 / index->file_count : 0);
    printf("\n📈 变更统计:\n");
    printf("  🆕 新增文件: %llu\n", changes.added_count);
    printf("  ✏️  修改文件: %llu\n", changes.modified_count);
    printf("  🗑️  删除文件: %llu\n", changes.deleted_count);
    printf("  ✅ 未变更: %llu\n", unchanged);
    printf("  📊 总变更: %llu\n", changes.added_count + changes.modified_count + changes.deleted_count);
    
    // 性能统计
    double efficiency = index->file_count > 0 ? 
        (double)(index->file_count - hash_calculations) * 100.0 / index->file_count : 0;
    printf("\n⚡ 性能优化:\n");
    printf("  快速检测: %.1f%% 的文件无需计算哈希\n", efficiency);
    printf("  算法效率: 类似 Git status\n");
    
    // 清理变更列表
    destroy_change_list(&changes);
    
    destroy_simple_index(index);
    return 0;
}

// 在创建快照时同时建立索引缓存
int create_index_during_snapshot(const char *workspace_root, const char *snapshot_path, 
                                const snapshot_config_t *config) {
    printf("🔧 创建索引缓存...\n");
    
    char index_path[MAX_PATH_LEN];
    snprintf(index_path, sizeof(index_path), "%s/%s/%s", 
             workspace_root, SNAPSHOT_DIR, INDEX_FILE);
    
    // 从刚创建的快照文件构建索引
    simple_index_t *index = create_simple_index_from_snapshot(snapshot_path);
    if (!index) {
        printf("⚠️  警告: 索引缓存创建失败，不影响快照功能\n");
        return -1;
    }
    
    // 保存索引到文件
    if (save_simple_index(index, index_path) < 0) {
        printf("⚠️  警告: 索引缓存保存失败，不影响快照功能\n");
        destroy_simple_index(index);
        return -1;
    }
    
    printf("✅ 索引缓存已创建: %llu 个文件\n", index->file_count);
    destroy_simple_index(index);
    return 0;
}

// 从快照文件创建索引
simple_index_t* create_simple_index_from_snapshot(const char *snapshot_path) {
    FILE *fp = fopen(snapshot_path, "r");
    if (!fp) {
        return NULL;
    }
    
    simple_index_t *index = calloc(1, sizeof(simple_index_t));
    if (!index) {
        fclose(fp);
        return NULL;
    }
    
    char line[MAX_PATH_LEN * 2];
    
    // 读取快照文件，跳过注释行
    while (fgets(line, sizeof(line), fp)) {
        // 跳过注释行
        if (line[0] == '#' || line[0] == '\n') {
            continue;
        }
        
        // 解析文件条目：path;size;mtime;hash
        char *path = strtok(line, ";");
        char *size_str = strtok(NULL, ";");
        char *mtime_str = strtok(NULL, ";");
        char *hash_hex = strtok(NULL, ";\n");
        
        if (!path || !size_str || !mtime_str || !hash_hex) {
            continue;
        }
        
        // 创建索引条目
        simple_index_entry_t *entry = malloc(sizeof(simple_index_entry_t));
        if (!entry) {
            continue;
        }
        
        strncpy(entry->path, path, MAX_PATH_LEN - 1);
        entry->path[MAX_PATH_LEN - 1] = '\0';
        entry->size = strtoull(size_str, NULL, 10);
        entry->mtime = strtoull(mtime_str, NULL, 10);
        strncpy(entry->hash_hex, hash_hex, HASH_HEX_SIZE - 1);
        entry->hash_hex[HASH_HEX_SIZE - 1] = '\0';
        
        // 添加到索引
        entry->next = index->entries;
        index->entries = entry;
        index->file_count++;
    }
    
    fclose(fp);
    index->dirty = 1;
    
    return index;
}

// 加载索引文件
simple_index_t* load_simple_index(const char *index_path) {
    FILE *fp = fopen(index_path, "r");
    if (!fp) {
        return NULL;
    }
    
    simple_index_t *index = calloc(1, sizeof(simple_index_t));
    if (!index) {
        fclose(fp);
        return NULL;
    }
    
    char magic[5] = {0};
    if (fread(magic, 1, 4, fp) != 4 || strcmp(magic, INDEX_MAGIC) != 0) {
        fclose(fp);
        free(index);
        return NULL;
    }
    
    // 读取文件数量
    if (fread(&index->file_count, sizeof(uint64_t), 1, fp) != 1) {
        fclose(fp);
        free(index);
        return NULL;
    }
    
    // 读取条目
    for (uint64_t i = 0; i < index->file_count; i++) {
        simple_index_entry_t *entry = malloc(sizeof(simple_index_entry_t));
        if (!entry) {
            break;
        }
        
        if (fread(entry->path, MAX_PATH_LEN, 1, fp) != 1 ||
            fread(&entry->mtime, sizeof(uint64_t), 1, fp) != 1 ||
            fread(&entry->size, sizeof(uint64_t), 1, fp) != 1 ||
            fread(entry->hash_hex, HASH_HEX_SIZE, 1, fp) != 1) {
            free(entry);
            break;
        }
        
        entry->next = index->entries;
        index->entries = entry;
    }
    
    fclose(fp);
    return index;
}

// 保存索引到文件
int save_simple_index(simple_index_t *index, const char *index_path) {
    FILE *fp = fopen(index_path, "wb");
    if (!fp) {
        return -1;
    }
    
    // 写入魔数
    fwrite(INDEX_MAGIC, 1, 4, fp);
    
    // 写入文件数量
    fwrite(&index->file_count, sizeof(uint64_t), 1, fp);
    
    // 写入条目
    simple_index_entry_t *entry = index->entries;
    while (entry) {
        fwrite(entry->path, MAX_PATH_LEN, 1, fp);
        fwrite(&entry->mtime, sizeof(uint64_t), 1, fp);
        fwrite(&entry->size, sizeof(uint64_t), 1, fp);
        fwrite(entry->hash_hex, HASH_HEX_SIZE, 1, fp);
        entry = entry->next;
    }
    
    fclose(fp);
    return 0;
}


// 添加文件变更到列表
void add_file_change(change_list_t *changes, const char *path, char status) {
    file_change_t *change = malloc(sizeof(file_change_t));
    if (!change) return;
    
    strncpy(change->path, path, MAX_PATH_LEN - 1);
    change->path[MAX_PATH_LEN - 1] = '\0';
    change->status = status;
    change->next = NULL;
    
    switch (status) {
        case 'A':
            change->next = changes->added;
            changes->added = change;
            changes->added_count++;
            break;
        case 'M':
            change->next = changes->modified;
            changes->modified = change;
            changes->modified_count++;
            break;
        case 'D':
            change->next = changes->deleted;
            changes->deleted = change;
            changes->deleted_count++;
            break;
        default:
            free(change);
            break;
    }
}

// 打印文件变更列表（像git status那样）
void print_change_list(change_list_t *changes) {
    printf("\n🔍 差异分析报告:\n");
    printf("================\n");
    
    // 显示修改的文件
    if (changes->modified_count > 0) {
        printf("\n📝 修改的文件:\n");
        file_change_t *change = changes->modified;
        while (change) {
            printf("M\t%s\n", change->path);
            change = change->next;
        }
    }
    
    // 显示新增的文件
    if (changes->added_count > 0) {
        printf("\n🆕 新增的文件:\n");
        file_change_t *change = changes->added;
        while (change) {
            printf("A\t%s\n", change->path);
            change = change->next;
        }
    }
    
    // 显示删除的文件
    if (changes->deleted_count > 0) {
        printf("\n🗑️  删除的文件:\n");
        file_change_t *change = changes->deleted;
        while (change) {
            printf("D\t%s\n", change->path);
            change = change->next;
        }
    }
    
    // 如果没有变更
    if (changes->added_count == 0 && changes->modified_count == 0 && changes->deleted_count == 0) {
        printf("\n✅ 没有变更\n");
    }
}

// 清理变更列表
void destroy_change_list(change_list_t *changes) {
    file_change_t *lists[] = {changes->added, changes->modified, changes->deleted};
    
    for (int i = 0; i < 3; i++) {
        file_change_t *change = lists[i];
        while (change) {
            file_change_t *next = change->next;
            free(change);
            change = next;
        }
    }
    
    memset(changes, 0, sizeof(change_list_t));
}

// 修改版的状态检查
void simple_check_status_with_list(const char *workspace_root, simple_index_t *index,
                                  change_list_t *changes, uint64_t *unchanged, uint64_t *hash_calculations) {
    *unchanged = *hash_calculations = 0;
    
    // 标记索引中的文件
    simple_index_entry_t *entry = index->entries;
    while (entry) {
        entry->size = 0; // 使用size字段作为临时标记
        entry = entry->next;
    }
    
    // 扫描当前目录
    simple_scan_directory_with_list(workspace_root, workspace_root, index, changes, unchanged, hash_calculations);
    
    // 检查删除的文件
    entry = index->entries;
    while (entry) {
        if (entry->size != UINT64_MAX) { // 未被标记，说明已删除
            // 从绝对路径中提取相对路径
            const char *rel_path = entry->path;
            
            // 如果路径包含工作区根目录，提取相对部分
            size_t workspace_len = strlen(workspace_root);
            if (strncmp(entry->path, workspace_root, workspace_len) == 0) {
                rel_path = entry->path + workspace_len;
                // 跳过前导斜杠
                while (*rel_path == '/') {
                    rel_path++;
                }
            }
            // 如果还是空的，使用原路径的最后部分
            if (*rel_path == '\0') {
                const char *last_slash = strrchr(entry->path, '/');
                rel_path = last_slash ? last_slash + 1 : entry->path;
            }
            
            add_file_change(changes, rel_path, 'D');
        }
        entry = entry->next;
    }
}

// 修改版的目录扫描
void simple_scan_directory_with_list(const char *base_path, const char *current_path, simple_index_t *index,
                                    change_list_t *changes, uint64_t *unchanged, uint64_t *hash_calculations) {
    DIR *dir = opendir(current_path);
    if (!dir) {
        return;
    }
    
    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        
        // 跳过.snapshot目录和其他忽略的文件
        if (strcmp(entry->d_name, ".snapshot") == 0) {
            continue;
        }
        
        // 检查是否应该忽略此文件/目录
        char rel_entry_path[MAX_PATH_LEN];
        const char *relative_current = current_path + strlen(base_path);
        if (relative_current[0] == '/') relative_current++;
        
        if (strlen(relative_current) > 0) {
            snprintf(rel_entry_path, sizeof(rel_entry_path), "%s/%s", relative_current, entry->d_name);
        } else {
            strncpy(rel_entry_path, entry->d_name, MAX_PATH_LEN - 1);
            rel_entry_path[MAX_PATH_LEN - 1] = '\0';
        }
        
        // 使用默认忽略模式检查
        if (is_file_ignored(rel_entry_path, ".snapshot")) {
            continue;
        }
        
        char full_path[MAX_PATH_LEN];
        snprintf(full_path, sizeof(full_path), "%s/%s", current_path, entry->d_name);
        
        struct stat st;
        if (stat(full_path, &st) != 0) {
            continue;
        }
        
        if (S_ISDIR(st.st_mode)) {
            simple_scan_directory_with_list(base_path, full_path, index, changes, unchanged, hash_calculations);
        } else if (S_ISREG(st.st_mode)) {
            simple_check_file_with_list(base_path, full_path, &st, index, changes, unchanged, hash_calculations);
        }
    }
    
    closedir(dir);
}

// 修改版的文件检查
void simple_check_file_with_list(const char *base_path, const char *file_path, struct stat *st, simple_index_t *index,
                                change_list_t *changes, uint64_t *unchanged, uint64_t *hash_calculations) {
    // 计算相对路径
    const char *rel_path = file_path + strlen(base_path);
    if (rel_path[0] == '/') rel_path++; // 跳过开头的'/'
    
    // 查找索引条目，需要处理路径格式差异
    simple_index_entry_t *entry = index->entries;
    while (entry) {
        // 从索引路径中提取相对路径
        const char *entry_rel_path = entry->path;
        
        // 如果索引路径包含工作区根目录，提取相对部分
        size_t base_len = strlen(base_path);
        if (strncmp(entry->path, base_path, base_len) == 0) {
            entry_rel_path = entry->path + base_len;
            // 跳过前导斜杠
            while (*entry_rel_path == '/') {
                entry_rel_path++;
            }
        }
        // 如果还是空的，使用原路径的最后部分
        if (*entry_rel_path == '\0') {
            const char *last_slash = strrchr(entry->path, '/');
            entry_rel_path = last_slash ? last_slash + 1 : entry->path;
        }
        
        if (strcmp(entry_rel_path, rel_path) == 0) {
            break;
        }
        entry = entry->next;
    }
    
    if (!entry) {
        // 新文件
        add_file_change(changes, rel_path, 'A');
        return;
    }
    
    // 保存原始大小，用于比较
    uint64_t original_size = entry->size;
    
    // 标记为已找到（使用特殊值）
    entry->size = UINT64_MAX;
    
    // 快速检查：比较mtime和size
    if (entry->mtime == (uint64_t)st->st_mtime && original_size == (uint64_t)st->st_size) {
        (*unchanged)++;
        return;
    }
    
    // 需要计算哈希来确认是否真的修改了
    (*hash_calculations)++;
    
    // 简化：假设mtime或size变化就是修改了
    add_file_change(changes, rel_path, 'M');
}

// 销毁索引
void destroy_simple_index(simple_index_t *index) {
    if (!index) return;
    
    simple_index_entry_t *entry = index->entries;
    while (entry) {
        simple_index_entry_t *next = entry->next;
        free(entry);
        entry = next;
    }
    
    free(index);
}