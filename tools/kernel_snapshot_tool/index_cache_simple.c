/**
 * Git风格索引缓存实现 - 简化版本
 * 专注于核心功能，避免复杂依赖
 */

#include "snapshot_core.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
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

// 哈希表桶大小（选择质数以减少冲突）
#define HASH_TABLE_SIZE 65537

// 哈希表条目
typedef struct hash_entry {
    const char *key;  // 相对路径
    simple_index_entry_t *value;  // 指向索引条目
    struct hash_entry *next;
} hash_entry_t;

// 简化的索引结构（增加哈希表加速查找）
typedef struct {
    uint64_t file_count;
    simple_index_entry_t *entries;
    hash_entry_t *hash_table[HASH_TABLE_SIZE];  // 哈希表加速查找
    char base_dir[MAX_PATH_LEN];  // 存储base_dir用于路径计算
    int dirty;
} simple_index_t;

// 文件变更列表类型已在 snapshot_core.h 中定义

// ========== 哈希表辅助函数 ==========

// 简单的字符串哈希函数（djb2算法）
static uint32_t hash_string(const char *str) {
    uint32_t hash = 5381;
    int c;
    while ((c = *str++)) {
        hash = ((hash << 5) + hash) + c; // hash * 33 + c
    }
    return hash % HASH_TABLE_SIZE;
}

// 向哈希表中插入条目
static void hash_table_insert(simple_index_t *index, const char *rel_path, simple_index_entry_t *entry) {
    uint32_t hash = hash_string(rel_path);
    
    hash_entry_t *hash_entry = malloc(sizeof(hash_entry_t));
    if (!hash_entry) return;
    
    // 为键分配独立内存
    char *key_copy = malloc(strlen(rel_path) + 1);
    if (!key_copy) {
        free(hash_entry);
        return;
    }
    strcpy(key_copy, rel_path);
    
    hash_entry->key = key_copy;
    hash_entry->value = entry;
    hash_entry->next = index->hash_table[hash];
    index->hash_table[hash] = hash_entry;
}

// 从哈希表中查找条目
static simple_index_entry_t* hash_table_lookup(simple_index_t *index, const char *rel_path) {
    uint32_t hash = hash_string(rel_path);
    
    hash_entry_t *hash_entry = index->hash_table[hash];
    while (hash_entry) {
        if (strcmp(hash_entry->key, rel_path) == 0) {
            return hash_entry->value;
        }
        hash_entry = hash_entry->next;
    }
    return NULL;
}

// 清理哈希表
static void hash_table_clear(simple_index_t *index) {
    for (int i = 0; i < HASH_TABLE_SIZE; i++) {
        hash_entry_t *hash_entry = index->hash_table[i];
        while (hash_entry) {
            hash_entry_t *next = hash_entry->next;
            free((void*)hash_entry->key);  // 释放键内存
            free(hash_entry);
            hash_entry = next;
        }
        index->hash_table[i] = NULL;
    }
}

// 提取相对路径的辅助函数
__attribute__((unused)) static const char* extract_relative_path(const char *full_path, const char *base_path) {
    if (!base_path || strlen(base_path) == 0) {
        return full_path;
    }
    
    size_t base_len = strlen(base_path);
    if (strncmp(full_path, base_path, base_len) == 0) {
        const char *rel_path = full_path + base_len;
        // 跳过前导斜杠
        while (*rel_path == '/') {
            rel_path++;
        }
        return rel_path;
    }
    
    // 如果不匹配，返回文件名部分
    const char *last_slash = strrchr(full_path, '/');
    return last_slash ? last_slash + 1 : full_path;
}



// 构建哈希表（在索引加载后调用）
static void build_hash_table_with_base_dir(simple_index_t *index, const char *base_dir) {
    // 首先清理现有哈希表
    hash_table_clear(index);
    
    if (!base_dir) {
        printf("⚠️  警告: 无法获取base_dir，使用文件名模式\n");
        return;
    }
    
    size_t base_len = strlen(base_dir);
    
    simple_index_entry_t *entry = index->entries;
    while (entry) {
        const char *rel_path = entry->path;
        
        // 如果路径以base_dir开头，提取相对路径部分
        if (strncmp(entry->path, base_dir, base_len) == 0) {
            rel_path = entry->path + base_len;
            // 跳过前导斜杠
            while (*rel_path == '/') {
                rel_path++;
            }
        } else {
            // 如果不匹配，使用文件名
            const char *last_slash = strrchr(entry->path, '/');
            rel_path = last_slash ? last_slash + 1 : entry->path;
        }
        
        if (rel_path && strlen(rel_path) > 0) {
            hash_table_insert(index, rel_path, entry);
        }
        entry = entry->next;
    }
}

// 构建哈希表（在索引加载后调用）
static void build_hash_table(simple_index_t *index) {
    // 使用索引中存储的base_dir
    if (strlen(index->base_dir) > 0) {
        build_hash_table_with_base_dir(index, index->base_dir);
    } else {
        printf("⚠️  警告: 索引中没有base_dir信息\n");
        // 降级处理：使用文件名模式
        build_hash_table_with_base_dir(index, NULL);
    }
}

// 函数声明
simple_index_t* create_simple_index_from_snapshot(const char *snapshot_path);
void* load_simple_index(const char *index_path);
int save_simple_index(simple_index_t *index, const char *index_path);
int simple_check_status_with_list(const char *workspace_root, void *index,
                                  change_list_t *changes, uint64_t *unchanged, uint64_t *hash_calculations, const char *ignore_patterns);
void simple_scan_directory_with_list(const char *base_path, const char *current_path, simple_index_t *index,
                                    change_list_t *changes, uint64_t *unchanged, uint64_t *hash_calculations, const char *ignore_patterns);
void simple_check_file_with_list(const char *base_path, const char *file_path, struct stat *st, simple_index_t *index,
                                change_list_t *changes, uint64_t *unchanged, uint64_t *hash_calculations);
void add_file_change(change_list_t *changes, const char *path, char status);
void print_change_list(change_list_t *changes);
void destroy_change_list(change_list_t *changes);

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
    
    printf("✅ 索引载入完成，包含 %"PRIu64" 个文件\n", index->file_count);
    
    // 构建完整的忽略模式（与create命令保持一致）
    char combined_patterns[MAX_PATH_LEN * 2];
    if (config && config->exclude_patterns && strlen(config->exclude_patterns) > 0) {
        snprintf(combined_patterns, sizeof(combined_patterns), ".snapshot,%s", config->exclude_patterns);
    } else {
        strncpy(combined_patterns, ".snapshot", sizeof(combined_patterns) - 1);
        combined_patterns[sizeof(combined_patterns) - 1] = '\0';
    }
    
    // 创建变更列表
    change_list_t changes = {0};
    uint64_t unchanged = 0;
    uint64_t hash_calculations = 0;
    
    printf("🔍 开始快速扫描...\n");
    simple_check_status_with_list(workspace_root, index, &changes, &unchanged, &hash_calculations, combined_patterns);
    
    // 显示文件变更列表（像git status那样）
    print_change_list(&changes);
    
    // 显示统计结果
    printf("\n📊 状态检查完成!\n");
    printf("================\n");
    printf("🧮 哈希计算: %"PRIu64" (仅 %.1f%% 的文件)\n", hash_calculations, 
           index->file_count > 0 ? (double)hash_calculations * 100.0 / index->file_count : 0);
    printf("\n📈 变更统计:\n");
    printf("  🆕 新增文件: %"PRIu64"\n", changes.added_count);
    printf("  ✏️  修改文件: %"PRIu64"\n", changes.modified_count);
    printf("  🗑️  删除文件: %"PRIu64"\n", changes.deleted_count);
    printf("  ✅ 未变更: %"PRIu64"\n", unchanged);
    printf("  📊 总变更: %"PRIu64"\n", changes.added_count + changes.modified_count + changes.deleted_count);
    
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
    (void)config;  // 参数保留用于未来扩展
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
    
    printf("✅ 索引缓存已创建: %"PRIu64" 个文件\n", index->file_count);
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
    
    // 读取快照文件头部和数据
    while (fgets(line, sizeof(line), fp)) {
        // 处理注释行，寻找Base Dir
        if (line[0] == '#') {
            if (strncmp(line, "# Base Dir: ", 12) == 0) {
                char *dir_start = line + 12;
                char *dir_end = strchr(dir_start, '\n');
                if (dir_end) {
                    *dir_end = '\0';
                    strncpy(index->base_dir, dir_start, MAX_PATH_LEN - 1);
                    index->base_dir[MAX_PATH_LEN - 1] = '\0';
                }
            }
            continue;
        }
        
        // 跳过空行
        if (line[0] == '\n') {
            continue;
        }
        
        // 解析文件条目：path;size;mtime;mode;hash (5字段格式)
        char *path = strtok(line, ";");
        char *size_str = strtok(NULL, ";");
        char *mtime_str = strtok(NULL, ";");
        char *mode_str = strtok(NULL, ";");  // 添加mode字段
        char *hash_hex = strtok(NULL, ";\n");
        
        if (!path || !size_str || !mtime_str || !mode_str || !hash_hex) {
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
        
        // 调试：显示前几个解析的条目
        static int debug_parse = 0;
        if (debug_parse < 3) {
            printf("🔧 解析条目[%d]: path='%s', size_str='%s' -> size=%"PRIu64"\n", 
                   debug_parse, path, size_str, entry->size);
            debug_parse++;
        }
        
        // 添加到索引
        entry->next = index->entries;
        index->entries = entry;
        index->file_count++;
    }
    
    fclose(fp);
    index->dirty = 1;
    
    // 构建哈希表加速查找
    build_hash_table(index);
    
    return index;
}

// 加载索引文件
void* load_simple_index(const char *index_path) {
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
    
    // 读取版本号
    uint32_t version = 0;
    if (fread(&version, sizeof(uint32_t), 1, fp) != 1) {
        // 兼容旧版本：回退到文件开始，按旧格式读取
        fseek(fp, 4, SEEK_SET);  // 跳过魔数
        version = 1;
    }
    
    if (version >= 2) {
        // 版本2：读取base_dir
        if (fread(index->base_dir, MAX_PATH_LEN, 1, fp) != 1) {
            fclose(fp);
            free(index);
            return NULL;
        }
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
        
        // 调试信息已移除，避免干扰 quilt 文件列表格式
        
        entry->next = index->entries;
        index->entries = entry;
    }
    
    fclose(fp);
    
    // 构建哈希表加速查找
    build_hash_table(index);
    
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
    
    // 写入版本号（用于兼容性）
    uint32_t version = 2;  // 版本2支持base_dir
    fwrite(&version, sizeof(uint32_t), 1, fp);
    
    // 写入base_dir
    fwrite(index->base_dir, MAX_PATH_LEN, 1, fp);
    
    // 写入文件数量
    fwrite(&index->file_count, sizeof(uint64_t), 1, fp);
    
    // 写入条目
    simple_index_entry_t *entry = index->entries;
    int debug_save = 0;
    while (entry) {
        if (debug_save < 3) {
            printf("🔧 保存条目[%d]: path='%s', size=%"PRIu64"\n", 
                   debug_save, entry->path, entry->size);
            debug_save++;
        }
        
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
int simple_check_status_with_list(const char *workspace_root, void *index_ptr,
                                  change_list_t *changes, uint64_t *unchanged, uint64_t *hash_calculations, const char *ignore_patterns) {
    simple_index_t *index = (simple_index_t *)index_ptr;
    *unchanged = *hash_calculations = 0;
    
    // 标记索引中的文件 - 不要破坏原始size字段
    // 我们将在simple_check_file_with_list中处理标记
    
    // 扫描当前目录
    simple_scan_directory_with_list(workspace_root, workspace_root, index, changes, unchanged, hash_calculations, ignore_patterns);
    
    // 检查删除的文件
    simple_index_entry_t *entry = index->entries;
    while (entry) {
        if (!(entry->mtime & (1ULL << 63))) { // 未被标记，说明已删除
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
        
        // 恢复原始mtime值（清除访问标记）
        entry->mtime &= ~(1ULL << 63);
        
        entry = entry->next;
    }
    
    return 0; // 成功
}

// 修改版的目录扫描
void simple_scan_directory_with_list(const char *base_path, const char *current_path, simple_index_t *index,
                                    change_list_t *changes, uint64_t *unchanged, uint64_t *hash_calculations, const char *ignore_patterns) {
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
        
        // 使用完整的忽略模式检查
        if (is_file_ignored(rel_entry_path, ignore_patterns)) {
            continue;
        }
        
        char full_path[MAX_PATH_LEN];
        snprintf(full_path, sizeof(full_path), "%s/%s", current_path, entry->d_name);
        
        struct stat st;
        if (lstat(full_path, &st) != 0) {
            continue;
        }
        
        // 处理符号链接：像git一样只检查符号链接本身，不递归处理目标
        if (S_ISLNK(st.st_mode)) {
            // 只检查符号链接本身
            simple_check_file_with_list(base_path, full_path, &st, index, changes, unchanged, hash_calculations);
            
            // Git策略：只检查符号链接本身，不通过符号链接路径处理目标内容
            // 目标文件/目录会在真实路径遍历时被检查，避免重复计算
            continue; // 符号链接已处理完毕，继续下一个
        }
        
        if (S_ISDIR(st.st_mode)) {
            simple_scan_directory_with_list(base_path, full_path, index, changes, unchanged, hash_calculations, ignore_patterns);
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
    
    // 使用哈希表快速查找索引条目（O(1)复杂度）
    simple_index_entry_t *entry = hash_table_lookup(index, rel_path);
    
    if (!entry) {
        // 新文件
        add_file_change(changes, rel_path, 'A');
        return;
    }
    
    // 标记为已找到（使用mtime字段的最高位作为标记）
    uint64_t original_mtime = entry->mtime;
    entry->mtime |= (1ULL << 63);  // 设置最高位作为访问标记
    
    // 快速检查：比较mtime和size（去掉标记位）
    uint64_t clean_mtime = original_mtime & ~(1ULL << 63);
    if (clean_mtime == (uint64_t)st->st_mtime && entry->size == (uint64_t)st->st_size) {
        (*unchanged)++;
        return;
    }
    
    // 时间戳或大小不匹配，需要进一步验证内容是否真正变化
    // 这里采用git的策略：计算内容哈希进行精确比较
    (*hash_calculations)++;
    
    // 计算当前文件的哈希
    unsigned char current_hash[HASH_SIZE];
    char current_hash_hex[HASH_HEX_SIZE];
    
    // 计算SHA256哈希
    if (calculate_sha256_hash(file_path, current_hash) < 0) {
        // 哈希计算失败，保守起见认为文件被修改
        add_file_change(changes, rel_path, 'M');
        return;
    }
    
    // 转换为十六进制字符串
    hash_to_hex(current_hash, current_hash_hex);
    
    // 比较哈希值，只有内容真正变化才报告修改（git行为）
    if (strcmp(current_hash_hex, entry->hash_hex) == 0) {
        // 内容未变化，虽然时间戳变了但不算修改（符合git行为）
        (*unchanged)++;
        return;
    }
    
    // 内容确实发生了变化
    add_file_change(changes, rel_path, 'M');
}

// 销毁索引
void destroy_simple_index(void *index_ptr) {
    simple_index_t *index = (simple_index_t *)index_ptr;
    if (!index) return;
    
    simple_index_entry_t *entry = index->entries;
    while (entry) {
        simple_index_entry_t *next = entry->next;
        free(entry);
        entry = next;
    }
    
    // 清理哈希表
    hash_table_clear(index);
    
    free(index);
}