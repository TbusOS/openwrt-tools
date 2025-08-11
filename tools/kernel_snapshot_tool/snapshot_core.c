/**
 * Git风格快照系统实现 - 零文件丢失的高性能设计
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
#include <fcntl.h>
#include <sys/mman.h>
#include <stdint.h>
#include <inttypes.h>
#include <time.h>
#include <sys/stat.h>

// Git风格的文件遍历（单线程，确保不丢失）
int scan_directory_recursive(const char *dir_path, worker_pool_t *pool, 
                                   const snapshot_config_t *config, uint64_t *total_files) {
    DIR *dir = opendir(dir_path);
    if (!dir) {
        if (config->verbose) {
            fprintf(stderr, "警告: 无法打开目录 %s: %s\n", dir_path, strerror(errno));
        }
        return -1;
    }
    
    struct dirent *entry;
    char full_path[MAX_PATH_LEN];
    
    while ((entry = readdir(dir)) != NULL) {
        // 跳过 . 和 ..
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        
        // 构建完整路径
        int ret = snprintf(full_path, sizeof(full_path), "%s/%s", dir_path, entry->d_name);
        if (ret >= (int)sizeof(full_path)) {
            if (config->verbose) {
                fprintf(stderr, "警告: 路径过长被截断: %s/%s\n", dir_path, entry->d_name);
            }
            continue;
        }
        
        struct stat st;
        if (lstat(full_path, &st) < 0) {
            if (config->verbose) {
                fprintf(stderr, "警告: 无法获取文件状态 %s: %s\n", full_path, strerror(errno));
            }
            continue;
        }
        
        // 处理符号链接：像git一样只记录符号链接本身，不递归处理目标
        if (S_ISLNK(st.st_mode)) {
            // 记录符号链接本身（作为常规文件处理）
            (*total_files)++;
            // 添加符号链接到工作队列（阻塞添加确保不丢失）
            while (worker_pool_add_work(pool, full_path) != 0) {
                usleep(1000);  // 1ms
            }
            
            // Git策略：只记录符号链接本身，不通过符号链接路径处理目标内容
            // 目标文件/目录会在真实路径遍历时被发现和处理，避免重复计算
            if (config->verbose) {
                char link_target[MAX_PATH_LEN];
                ssize_t link_len = readlink(full_path, link_target, sizeof(link_target) - 1);
                if (link_len > 0) {
                    link_target[link_len] = '\0';
                    fprintf(stderr, "记录符号链接: %s -> %s\n", full_path, link_target);
                }
            }
            continue; // 符号链接已处理完毕，继续下一个
        }
        
        if (S_ISDIR(st.st_mode)) {
            // 检查目录是否应该被忽略（使用配置模式和内置默认）
            char combined_patterns[MAX_PATH_LEN * 2];
            if (config->exclude_patterns && strlen(config->exclude_patterns) > 0) {
                snprintf(combined_patterns, sizeof(combined_patterns), ".snapshot,%s", config->exclude_patterns);
            } else {
                strncpy(combined_patterns, ".snapshot", sizeof(combined_patterns) - 1);
                combined_patterns[sizeof(combined_patterns) - 1] = '\0';
            }
            
            if (is_file_ignored(full_path, combined_patterns)) {
                continue;
            }
            
            // 递归处理子目录（单线程遍历，确保完整性）
            scan_directory_recursive(full_path, pool, config, total_files);
        } else if (S_ISREG(st.st_mode)) {
            // 检查是否需要忽略（使用配置模式和内置默认）
            char combined_patterns[MAX_PATH_LEN * 2];
            if (config->exclude_patterns && strlen(config->exclude_patterns) > 0) {
                snprintf(combined_patterns, sizeof(combined_patterns), ".snapshot,%s", config->exclude_patterns);
            } else {
                strncpy(combined_patterns, ".snapshot", sizeof(combined_patterns) - 1);
                combined_patterns[sizeof(combined_patterns) - 1] = '\0';
            }
            
            if (is_file_ignored(full_path, combined_patterns)) {
                continue;
            }
            
            // 记录找到的文件
            (*total_files)++;
            
            // 添加到工作队列（这里不会丢失，因为是阻塞添加）
            while (worker_pool_add_work(pool, full_path) != 0) {
                // 如果队列满了，等待一小段时间再试
                usleep(1000);  // 1ms
            }
            
                    if ((*total_files % 1000) == 0) { // 每1000个文件显示一次进度
            printf("\r🔍 已扫描: %"PRIu64" 个文件", *total_files);
                fflush(stdout);
            }
        }
        // 忽略符号链接和其他特殊文件类型
    }
    
    closedir(dir);
    return 0;
}

// 工作线程函数（处理文件内容）
static void* worker_thread(void *arg) {
    worker_pool_t *pool = (worker_pool_t*)arg;
    
    while (1) {
        pthread_mutex_lock(&pool->work_lock);
        
            pthread_mutex_unlock(&pool->work_lock);
        
        // 从有界队列获取工作单元
        work_unit_t *work = bounded_work_queue_pop(pool->work_queue);
        if (!work) {
            break;  // 队列关闭且空
        }
        
        pthread_mutex_lock(&pool->work_lock);
        pool->active_workers++;
        pthread_mutex_unlock(&pool->work_lock);
        
        if (work) {
            // 处理文件
            result_entry_t *result = malloc(sizeof(result_entry_t));
            if (result) {
                memset(result, 0, sizeof(result_entry_t));
                
                result->error_code = process_file_content(work->path, &result->entry, 
                                                       pool->use_git_hash);  // 修复参数传递错误
                
                if (result->error_code == 0) {
                    result->status = FILE_ADDED;  // 新创建快照时都是新增
                    
                    // 推送到结果队列进行流式写出
                    if (bounded_result_queue_push(pool->result_queue, result) == 0) {
                        __sync_fetch_and_add(&pool->processed_files, 1);
            } else {
                        free(result);
                        __sync_fetch_and_add(&pool->failed_files, 1);
                    }
                } else {
                    free(result);
                    __sync_fetch_and_add(&pool->failed_files, 1);
                }
            } else {
                __sync_fetch_and_add(&pool->failed_files, 1);
            }
            
            free(work);
        }
        
        // 标记工作完成
        pthread_mutex_lock(&pool->work_lock);
        pool->active_workers--;
        pthread_mutex_unlock(&pool->work_lock);
    }
    
    return NULL;
}

// ========== 有界队列实现 ==========

// 创建有界工作队列
bounded_work_queue_t* bounded_work_queue_create(int capacity) {
    bounded_work_queue_t *queue = calloc(1, sizeof(bounded_work_queue_t));
    if (!queue) return NULL;
    
    queue->items = calloc(capacity, sizeof(work_unit_t*));
    if (!queue->items) {
        free(queue);
        return NULL;
    }
    
    queue->capacity = capacity;
    queue->size = 0;
    queue->head = 0;
    queue->tail = 0;
    queue->shutdown = 0;
    
    pthread_mutex_init(&queue->lock, NULL);
    pthread_cond_init(&queue->not_full, NULL);
    pthread_cond_init(&queue->not_empty, NULL);
    
    return queue;
}

// 销毁有界工作队列
void bounded_work_queue_destroy(bounded_work_queue_t *queue) {
    if (!queue) return;
    
    pthread_mutex_lock(&queue->lock);
    queue->shutdown = 1;
    pthread_cond_broadcast(&queue->not_full);
    pthread_cond_broadcast(&queue->not_empty);
    pthread_mutex_unlock(&queue->lock);
    
    // 清理剩余的工作单元
    for (int i = 0; i < queue->size; i++) {
        free(queue->items[(queue->head + i) % queue->capacity]);
    }
    
    pthread_mutex_destroy(&queue->lock);
    pthread_cond_destroy(&queue->not_full);
    pthread_cond_destroy(&queue->not_empty);
    free(queue->items);
    free(queue);
}

// 向有界工作队列推送（带回压）
int bounded_work_queue_push(bounded_work_queue_t *queue, work_unit_t *item) {
    pthread_mutex_lock(&queue->lock);
    
    // 等待队列不满或关闭
    while (queue->size >= queue->capacity && !queue->shutdown) {
        pthread_cond_wait(&queue->not_full, &queue->lock);
    }
    
    if (queue->shutdown) {
        pthread_mutex_unlock(&queue->lock);
        return -1;  // 队列已关闭
    }
    
    queue->items[queue->tail] = item;
    queue->tail = (queue->tail + 1) % queue->capacity;
    queue->size++;
    
    pthread_cond_signal(&queue->not_empty);
    pthread_mutex_unlock(&queue->lock);
    
    return 0;
}

// 从有界工作队列弹出
work_unit_t* bounded_work_queue_pop(bounded_work_queue_t *queue) {
    pthread_mutex_lock(&queue->lock);
    
    // 等待队列不空或关闭
    while (queue->size == 0 && !queue->shutdown) {
        pthread_cond_wait(&queue->not_empty, &queue->lock);
    }
    
    if (queue->shutdown && queue->size == 0) {
        pthread_mutex_unlock(&queue->lock);
        return NULL;
    }
    
    work_unit_t *item = queue->items[queue->head];
    queue->head = (queue->head + 1) % queue->capacity;
    queue->size--;
    
    pthread_cond_signal(&queue->not_full);
    pthread_mutex_unlock(&queue->lock);
    
    return item;
}

// 创建有界结果队列
bounded_result_queue_t* bounded_result_queue_create(int capacity) {
    bounded_result_queue_t *queue = calloc(1, sizeof(bounded_result_queue_t));
    if (!queue) return NULL;
    
    queue->items = calloc(capacity, sizeof(result_entry_t*));
    if (!queue->items) {
        free(queue);
        return NULL;
    }
    
    queue->capacity = capacity;
    queue->size = 0;
    queue->head = 0;
    queue->tail = 0;
    queue->shutdown = 0;
    
    pthread_mutex_init(&queue->lock, NULL);
    pthread_cond_init(&queue->not_full, NULL);
    pthread_cond_init(&queue->not_empty, NULL);
    
    return queue;
}

// 销毁有界结果队列
void bounded_result_queue_destroy(bounded_result_queue_t *queue) {
    if (!queue) return;
    
    pthread_mutex_lock(&queue->lock);
    queue->shutdown = 1;
    pthread_cond_broadcast(&queue->not_full);
    pthread_cond_broadcast(&queue->not_empty);
    pthread_mutex_unlock(&queue->lock);
    
    // 清理剩余的结果条目
    for (int i = 0; i < queue->size; i++) {
        free(queue->items[(queue->head + i) % queue->capacity]);
    }
    
    pthread_mutex_destroy(&queue->lock);
    pthread_cond_destroy(&queue->not_full);
    pthread_cond_destroy(&queue->not_empty);
    free(queue->items);
    free(queue);
}

// 向有界结果队列推送（带回压）
int bounded_result_queue_push(bounded_result_queue_t *queue, result_entry_t *item) {
    pthread_mutex_lock(&queue->lock);
    
    // 等待队列不满或关闭
    while (queue->size >= queue->capacity && !queue->shutdown) {
        pthread_cond_wait(&queue->not_full, &queue->lock);
    }
    
    if (queue->shutdown) {
        pthread_mutex_unlock(&queue->lock);
        return -1;  // 队列已关闭
    }
    
    queue->items[queue->tail] = item;
    queue->tail = (queue->tail + 1) % queue->capacity;
    queue->size++;
    
    pthread_cond_signal(&queue->not_empty);
    pthread_mutex_unlock(&queue->lock);
    
    return 0;
}

// 从有界结果队列弹出
result_entry_t* bounded_result_queue_pop(bounded_result_queue_t *queue) {
    pthread_mutex_lock(&queue->lock);
    
    // 等待队列不空或关闭
    while (queue->size == 0 && !queue->shutdown) {
        pthread_cond_wait(&queue->not_empty, &queue->lock);
    }
    
    if (queue->shutdown && queue->size == 0) {
        pthread_mutex_unlock(&queue->lock);
        return NULL;
    }
    
    result_entry_t *item = queue->items[queue->head];
    queue->head = (queue->head + 1) % queue->capacity;
    queue->size--;
    
    pthread_cond_signal(&queue->not_full);
    pthread_mutex_unlock(&queue->lock);
    
    return item;
}

// ========== 流式写入线程 ==========

// 专用写入线程函数（流式写出快照）
static void* writer_thread(void *arg) {
    worker_pool_t *pool = (worker_pool_t*)arg;
    
    if (pool->verbose) {
        printf("🔄 写入线程启动，开始流式处理结果...\n");
    }
    
    uint64_t written_count = 0;
    
    while (1) {
        result_entry_t *result = bounded_result_queue_pop(pool->result_queue);
        if (!result) {
            break;  // 队列关闭且空
        }
        
        // 写入快照条目到文件（流式写出）
        if (pool->snapshot_file && result->error_code == 0) {
            fprintf(pool->snapshot_file, "%s;%"PRIu64";%"PRIu64";%o;%s\n",
                    result->entry.path,
                    result->entry.size,
                    result->entry.mtime,
                    result->entry.mode,  // 新增文件权限
                    result->entry.hash_hex);
            
            written_count++;
            
            if (pool->verbose && (written_count % 10000) == 0) {
                printf("📝 已写入 %"PRIu64" 个文件条目...\r", written_count);
                fflush(stdout);
            }
        }
        
        free(result);
    }
    
    if (pool->verbose) {
        printf("\n✅ 写入线程完成，共写入 %"PRIu64" 个条目\n", written_count);
    }
    
    return NULL;
}

// 创建工作线程池（有界队列版本）
worker_pool_t* worker_pool_create(int thread_count, result_collector_t *collector, const snapshot_config_t *config, const char *snapshot_path, const char *base_dir) {
    worker_pool_t *pool = calloc(1, sizeof(worker_pool_t));
    if (!pool) return NULL;
    
    pool->thread_count = thread_count;
    pool->collector = collector;
    pool->threads = malloc(thread_count * sizeof(pthread_t));
    
    // 正确传递配置参数到工作线程池
    if (config) {
        pool->use_git_hash = config->use_git_hash;
        pool->verbose = config->verbose;
    }
    
    if (!pool->threads) {
        free(pool);
        return NULL;
    }
    
    // 创建有界队列（防止内存爆炸）
    // 创建有界队列 - 动态选择队列大小
    // 对于大型项目使用大队列，小项目使用小队列节约内存
    int work_queue_size = WORK_QUEUE_MAX_SIZE;
    int result_queue_size = RESULT_QUEUE_MAX_SIZE;
    
    pool->work_queue = bounded_work_queue_create(work_queue_size);
    pool->result_queue = bounded_result_queue_create(result_queue_size);
    
    if (!pool->work_queue || !pool->result_queue) {
        worker_pool_destroy(pool);
        return NULL;
    }
    
    // 初始化同步原语
    pthread_mutex_init(&pool->work_lock, NULL);
    
    // 打开快照文件进行流式写出
    if (snapshot_path) {
        pool->snapshot_file = fopen(snapshot_path, "w");
        if (!pool->snapshot_file) {
            worker_pool_destroy(pool);
            return NULL;
        }
        
        // 写入快照文件头部
        time_t now = time(NULL);
        fprintf(pool->snapshot_file, "# Git-Style Snapshot v1.1\n");
        fprintf(pool->snapshot_file, "# Created: %ld\n", now);
        fprintf(pool->snapshot_file, "# Hash Algorithm: %s\n", 
                config && config->use_git_hash ? "SHA1" : "SHA256");
        fprintf(pool->snapshot_file, "# Base Dir: %s\n", base_dir ? base_dir : ".");
        fflush(pool->snapshot_file);
    }
    
    // 创建工作线程
    for (int i = 0; i < thread_count; i++) {
        if (pthread_create(&pool->threads[i], NULL, worker_thread, pool) != 0) {
            // 清理已创建的线程
            pool->shutdown = 1;
            for (int j = 0; j < i; j++) {
                pthread_join(pool->threads[j], NULL);
            }
            worker_pool_destroy(pool);
            return NULL;
        }
    }
    
    // 创建写入线程（如果配置了快照文件）
    if (pool->snapshot_file) {
        if (pthread_create(&pool->writer_thread, NULL, writer_thread, pool) != 0) {
            pool->shutdown = 1;
            for (int i = 0; i < thread_count; i++) {
                pthread_join(pool->threads[i], NULL);
            }
            worker_pool_destroy(pool);
            return NULL;
        }
        pool->writer_active = 1;
    }
    
    return pool;
}

// 添加工作到线程池（有界队列，带回压）
int worker_pool_add_work(worker_pool_t *pool, const char *file_path) {
    work_unit_t *work = malloc(sizeof(work_unit_t));
    if (!work) return -1;
    
    strncpy(work->path, file_path, MAX_PATH_LEN - 1);
    work->path[MAX_PATH_LEN - 1] = '\0';
    work->next = NULL;
    
    // 使用有界队列，自带回压机制
    return bounded_work_queue_push(pool->work_queue, work);
}

// 等待所有工作完成（有界队列版本）
void worker_pool_wait_completion(worker_pool_t *pool) {
    // 设置关闭标志，停止接受新任务
    pool->shutdown = 1;
    
    // 通知工作队列关闭（但不销毁）
    if (pool->work_queue) {
        pthread_mutex_lock(&pool->work_queue->lock);
        pool->work_queue->shutdown = 1;
        pthread_cond_broadcast(&pool->work_queue->not_empty);
        pthread_mutex_unlock(&pool->work_queue->lock);
    }
    
    // 等待所有工作线程完成
    for (int i = 0; i < pool->thread_count; i++) {
        pthread_join(pool->threads[i], NULL);
    }
    
    // 通知结果队列关闭
    if (pool->result_queue) {
        pthread_mutex_lock(&pool->result_queue->lock);
        pool->result_queue->shutdown = 1;
        pthread_cond_broadcast(&pool->result_queue->not_empty);
        pthread_mutex_unlock(&pool->result_queue->lock);
    }
    
    // 等待写入线程完成
    if (pool->writer_active) {
        pthread_join(pool->writer_thread, NULL);
        pool->writer_active = 0;
    }
    
    // 现在可以安全地销毁队列
    if (pool->work_queue) {
        bounded_work_queue_destroy(pool->work_queue);
        pool->work_queue = NULL;
    }
    
    if (pool->result_queue) {
        bounded_result_queue_destroy(pool->result_queue);
        pool->result_queue = NULL;
    }
}

// 等待所有工作完成并显示进度条
void worker_pool_wait_completion_with_progress(worker_pool_t *pool, uint64_t total_files) {
    // 设置关闭标志，停止接受新任务
    pool->shutdown = 1;
    
    // 通知工作队列关闭
    if (pool->work_queue) {
        pthread_mutex_lock(&pool->work_queue->lock);
        pool->work_queue->shutdown = 1;
        pthread_cond_broadcast(&pool->work_queue->not_empty);
        pthread_mutex_unlock(&pool->work_queue->lock);
    }
    
    printf("🔄 处理文件...\n");
    
    // 循环检查进度直到所有线程完成
    int all_done = 0;
    while (!all_done) {
        // 显示当前进度
        uint64_t processed = pool->processed_files;
        if (total_files > 0) {
            show_progress_bar(processed, total_files, "处理中...");
        }
        
        // 短暂休眠
        usleep(100000); // 100毫秒
        
        // 检查是否所有工作都完成了
        all_done = (processed >= total_files) || 
                   (pool->work_queue && pool->work_queue->size == 0 && pool->processed_files > 0);
    }
    
    // 等待所有工作线程完成
    for (int i = 0; i < pool->thread_count; i++) {
        pthread_join(pool->threads[i], NULL);
    }
    
    // 通知结果队列关闭
    if (pool->result_queue) {
        pthread_mutex_lock(&pool->result_queue->lock);
        pool->result_queue->shutdown = 1;
        pthread_cond_broadcast(&pool->result_queue->not_empty);
        pthread_mutex_unlock(&pool->result_queue->lock);
    }
    
    // 等待写入线程完成
    if (pool->writer_active) {
        pthread_join(pool->writer_thread, NULL);
        pool->writer_active = 0;
    }
    
    // 显示最终进度
    show_progress_bar(pool->processed_files, total_files, "完成");
    printf("\n");
    
    // 现在可以安全地销毁队列
    if (pool->work_queue) {
        bounded_work_queue_destroy(pool->work_queue);
        pool->work_queue = NULL;
    }
    
    if (pool->result_queue) {
        bounded_result_queue_destroy(pool->result_queue);
        pool->result_queue = NULL;
    }
}

// 销毁工作线程池（有界队列版本）
void worker_pool_destroy(worker_pool_t *pool) {
    if (!pool) return;
    
    // 确保完成清理
    if (!pool->shutdown) {
        worker_pool_wait_completion(pool);
    }
    
    // 清理剩余资源
    if (pool->work_queue) {
        bounded_work_queue_destroy(pool->work_queue);
    }
    
    if (pool->result_queue) {
        bounded_result_queue_destroy(pool->result_queue);
    }
    
    // 关闭快照文件
    if (pool->snapshot_file) {
        fclose(pool->snapshot_file);
    }
    
    // 释放线程数组
    if (pool->threads) {
    free(pool->threads);
    }
    
    // 销毁同步原语
    pthread_mutex_destroy(&pool->work_lock);
    
    free(pool);
}

// 创建结果收集器
result_collector_t* result_collector_create(void) {
    result_collector_t *collector = calloc(1, sizeof(result_collector_t));
    if (!collector) return NULL;
    
    pthread_mutex_init(&collector->lock, NULL);
    return collector;
}

// 添加结果到收集器
void result_collector_add(result_collector_t *collector, const result_entry_t *entry) {
    result_entry_t *new_entry = malloc(sizeof(result_entry_t));
    if (!new_entry) return;
    
    *new_entry = *entry;
    new_entry->next = NULL;
    
    pthread_mutex_lock(&collector->lock);
    
    if (collector->tail) {
        collector->tail->next = new_entry;
    } else {
        collector->head = new_entry;
    }
    collector->tail = new_entry;
    collector->count++;
    
    pthread_mutex_unlock(&collector->lock);
}

// 销毁结果收集器
void result_collector_destroy(result_collector_t *collector) {
    if (!collector) return;
    
    result_entry_t *current = collector->head;
    while (current) {
        result_entry_t *next = current->next;
        free(current);
        current = next;
    }
    
    pthread_mutex_destroy(&collector->lock);
    free(collector);
}

// 处理单个文件内容
int process_file_content(const char *file_path, file_entry_t *entry, int use_git_hash) {
    struct stat st;
    
    if (lstat(file_path, &st) < 0) {
        return -1;
    }
    
    if (!S_ISREG(st.st_mode) && !S_ISLNK(st.st_mode)) {
        return -2;  // 不是普通文件或符号链接
    }
    
    // 填充基本信息（路径规范化）
    char *normalized_path = normalize_path(".", file_path);
    if (normalized_path) {
        strncpy(entry->path, normalized_path, MAX_PATH_LEN - 1);
        entry->path[MAX_PATH_LEN - 1] = '\0';
        free(normalized_path);
    } else {
    strncpy(entry->path, file_path, MAX_PATH_LEN - 1);
    entry->path[MAX_PATH_LEN - 1] = '\0';
    }
    
    entry->size = st.st_size;
    entry->mtime = st.st_mtime;
    entry->flags = 0;
    
    // 填充新增的元数据
    entry->mode = st.st_mode;
    
    // 计算哈希（符号链接和普通文件分别处理）
    int hash_result;
    if (S_ISLNK(st.st_mode)) {
        // 对于符号链接，使用目标路径的简单哈希
        char link_target[MAX_PATH_LEN];
        ssize_t link_len = readlink(file_path, link_target, sizeof(link_target) - 1);
        if (link_len > 0) {
            link_target[link_len] = '\0';
            // 基于目标路径生成简单哈希（使用CRC32或简单字符串哈希）
            uint32_t simple_hash = 0;
            for (int i = 0; i < link_len; i++) {
                simple_hash = simple_hash * 31 + (unsigned char)link_target[i];
            }
            // 将simple_hash转换为256位哈希格式
            memset(entry->hash, 0, 32);
            memcpy(entry->hash, &simple_hash, sizeof(simple_hash));
            hash_result = 0;
        } else {
            return -3;  // 无法读取符号链接目标
        }
    } else {
        // 普通文件，按原来的方式计算
    if (use_git_hash) {
        hash_result = calculate_git_hash(file_path, entry->hash);
    } else {
            hash_result = calculate_sha256_hash(file_path, entry->hash);
        }
    }
    
    if (hash_result < 0) {
        return -3;  // 哈希计算失败
    }
    
    // 转换为十六进制
    hash_to_hex(entry->hash, entry->hash_hex);
    
    return 0;
}

// 快速文件状态检查（仅检查mtime和size，不计算哈希）
int process_file_quick_check(const char *file_path, file_entry_t *entry) {
    struct stat st;
    
    if (lstat(file_path, &st) < 0) {
        return -1;
    }
    
    if (!S_ISREG(st.st_mode) && !S_ISLNK(st.st_mode)) {
        return -2;  // 不是普通文件或符号链接
    }
    
    // 填充基本信息（路径规范化）
    char *normalized_path = normalize_path(".", file_path);
    if (normalized_path) {
        strncpy(entry->path, normalized_path, MAX_PATH_LEN - 1);
        entry->path[MAX_PATH_LEN - 1] = '\0';
        free(normalized_path);
    } else {
        strncpy(entry->path, file_path, MAX_PATH_LEN - 1);
        entry->path[MAX_PATH_LEN - 1] = '\0';
    }
    
    entry->size = st.st_size;
    entry->mtime = st.st_mtime;
    entry->mode = st.st_mode;
    entry->flags = 0;
    
    // 不计算哈希，留空
    memset(entry->hash, 0, HASH_SIZE);
    entry->hash_hex[0] = '\0';
    
    return 0;
}

// SHA256算法常量
static const uint32_t sha256_k[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

// SHA256辅助函数
#define ROTLEFT(a,b) (((a) << (b)) | ((a) >> (32-(b))))
#define ROTRIGHT(a,b) (((a) >> (b)) | ((a) << (32-(b))))
#define CH(x,y,z) (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x) (ROTRIGHT(x,2) ^ ROTRIGHT(x,13) ^ ROTRIGHT(x,22))
#define EP1(x) (ROTRIGHT(x,6) ^ ROTRIGHT(x,11) ^ ROTRIGHT(x,25))
#define SIG0(x) (ROTRIGHT(x,7) ^ ROTRIGHT(x,18) ^ ((x) >> 3))
#define SIG1(x) (ROTRIGHT(x,17) ^ ROTRIGHT(x,19) ^ ((x) >> 10))

void sha256_init(sha256_ctx_t *ctx) {
    ctx->count = 0;
    ctx->state[0] = 0x6a09e667;
    ctx->state[1] = 0xbb67ae85;
    ctx->state[2] = 0x3c6ef372;
    ctx->state[3] = 0xa54ff53a;
    ctx->state[4] = 0x510e527f;
    ctx->state[5] = 0x9b05688c;
    ctx->state[6] = 0x1f83d9ab;
    ctx->state[7] = 0x5be0cd19;
}

static void sha256_transform(sha256_ctx_t *ctx, const uint8_t data[]) {
    uint32_t a, b, c, d, e, f, g, h, i, j, t1, t2, m[64];

    for (i = 0, j = 0; i < 16; ++i, j += 4)
        m[i] = (data[j] << 24) | (data[j + 1] << 16) | (data[j + 2] << 8) | (data[j + 3]);
    for (; i < 64; ++i)
        m[i] = SIG1(m[i - 2]) + m[i - 7] + SIG0(m[i - 15]) + m[i - 16];

    a = ctx->state[0];
    b = ctx->state[1];
    c = ctx->state[2];
    d = ctx->state[3];
    e = ctx->state[4];
    f = ctx->state[5];
    g = ctx->state[6];
    h = ctx->state[7];

    for (i = 0; i < 64; ++i) {
        t1 = h + EP1(e) + CH(e, f, g) + sha256_k[i] + m[i];
        t2 = EP0(a) + MAJ(a, b, c);
        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }

    ctx->state[0] += a;
    ctx->state[1] += b;
    ctx->state[2] += c;
    ctx->state[3] += d;
    ctx->state[4] += e;
    ctx->state[5] += f;
    ctx->state[6] += g;
    ctx->state[7] += h;
}

void sha256_update(sha256_ctx_t *ctx, const uint8_t *data, size_t len) {
    uint32_t i;

    for (i = 0; i < len; ++i) {
        ctx->buffer[ctx->count] = data[i];
        ctx->count++;
        if (ctx->count == 64) {
            sha256_transform(ctx, ctx->buffer);
            ctx->count = 0;
        }
    }
}

void sha256_final(sha256_ctx_t *ctx, uint8_t *hash) {
    uint32_t i;

    i = ctx->count;

    // Pad whatever data is left in the buffer.
    if (ctx->count < 56) {
        ctx->buffer[i++] = 0x80;
        while (i < 56)
            ctx->buffer[i++] = 0x00;
    } else {
        ctx->buffer[i++] = 0x80;
        while (i < 64)
            ctx->buffer[i++] = 0x00;
        sha256_transform(ctx, ctx->buffer);
        memset(ctx->buffer, 0, 56);
    }

    // Append to the padding the total message's length in bits and transform.
    uint64_t bitlen = (ctx->count * 8);
    ctx->buffer[63] = bitlen;
    ctx->buffer[62] = bitlen >> 8;
    ctx->buffer[61] = bitlen >> 16;
    ctx->buffer[60] = bitlen >> 24;
    ctx->buffer[59] = bitlen >> 32;
    ctx->buffer[58] = bitlen >> 40;
    ctx->buffer[57] = bitlen >> 48;
    ctx->buffer[56] = bitlen >> 56;
    sha256_transform(ctx, ctx->buffer);

    // Since this implementation uses little endian byte ordering and SHA uses big endian,
    // reverse all the bytes when copying the final state to the output hash.
    for (i = 0; i < 4; ++i) {
        hash[i]      = (ctx->state[0] >> (24 - i * 8)) & 0x000000ff;
        hash[i + 4]  = (ctx->state[1] >> (24 - i * 8)) & 0x000000ff;
        hash[i + 8]  = (ctx->state[2] >> (24 - i * 8)) & 0x000000ff;
        hash[i + 12] = (ctx->state[3] >> (24 - i * 8)) & 0x000000ff;
        hash[i + 16] = (ctx->state[4] >> (24 - i * 8)) & 0x000000ff;
        hash[i + 20] = (ctx->state[5] >> (24 - i * 8)) & 0x000000ff;
        hash[i + 24] = (ctx->state[6] >> (24 - i * 8)) & 0x000000ff;
        hash[i + 28] = (ctx->state[7] >> (24 - i * 8)) & 0x000000ff;
    }
}

// SHA256全量文件哈希计算（新的默认方法）
int calculate_sha256_hash(const char *file_path, unsigned char *hash) {
    int fd = open(file_path, O_RDONLY);
    if (fd < 0) return -1;
    
    sha256_ctx_t ctx;
    sha256_init(&ctx);
    
    uint8_t buffer[4096];  // 4KB缓冲区，平衡内存和I/O效率
    ssize_t bytes_read;
    // uint64_t total_bytes = 0;  // 暂不使用，避免警告
    
    // 流式读取整个文件内容进行哈希计算
    while ((bytes_read = read(fd, buffer, sizeof(buffer))) > 0) {
        sha256_update(&ctx, buffer, bytes_read);
        // total_bytes += bytes_read;
    }
    
    close(fd);
    
    if (bytes_read < 0) {
        return -1;  // 读取错误
    }
    
    sha256_final(&ctx, hash);
    return 0;
}

// Git兼容的SHA1哈希计算（简化实现，使用系统工具）
int calculate_git_hash(const char *file_path, unsigned char *hash) {
    // 为了Git兼容性，使用系统的sha1sum命令
    char command[MAX_PATH_LEN + 64];
    snprintf(command, sizeof(command), "sha1sum \"%s\" 2>/dev/null", file_path);
    
    FILE *fp = popen(command, "r");
    if (!fp) {
        // 如果sha1sum不可用，回退到SHA256
        return calculate_sha256_hash(file_path, hash);
    }
    
    char hex_output[HASH_SIZE_SHA1 * 2 + 1];
    if (fgets(hex_output, sizeof(hex_output), fp) == NULL) {
        pclose(fp);
        return calculate_sha256_hash(file_path, hash);
    }
    
    pclose(fp);
    
    // 转换十六进制字符串为二进制
    for (int i = 0; i < HASH_SIZE_SHA1 && (size_t)(i * 2 + 1) < strlen(hex_output); i++) {
        sscanf(hex_output + i * 2, "%2hhx", &hash[i]);
    }
    
    // 如果是SHA256模式但用了SHA1，需要填充或转换
    if (HASH_SIZE > HASH_SIZE_SHA1) {
        memset(hash + HASH_SIZE_SHA1, 0, HASH_SIZE - HASH_SIZE_SHA1);
    }
    
    return 0;
}

// 快速哈希计算（针对文件变化检测优化）
int calculate_fast_hash(const char *file_path, unsigned char *hash) {
    int fd = open(file_path, O_RDONLY);
    if (fd < 0) return -1;
    
    struct stat st;
    if (fstat(fd, &st) < 0) {
        close(fd);
        return -1;
    }
    
    // 使用文件大小和修改时间作为哈希基础
    uint64_t base_hash = (uint64_t)st.st_size ^ ((uint64_t)st.st_mtime << 32);
    
    if (st.st_size > 0) {
        // 读取文件的开头、中间、结尾进行采样
        char buffer[512];
        ssize_t bytes;
        
        // 开头
        if ((bytes = read(fd, buffer, sizeof(buffer))) > 0) {
            for (ssize_t i = 0; i < bytes; i++) {
                base_hash = base_hash * 31 + (unsigned char)buffer[i];
            }
        }
        
        // 中间
        if (st.st_size > 1024) {
            lseek(fd, st.st_size / 2, SEEK_SET);
            if ((bytes = read(fd, buffer, sizeof(buffer))) > 0) {
                for (ssize_t i = 0; i < bytes; i++) {
                    base_hash = base_hash * 37 + (unsigned char)buffer[i];
                }
            }
        }
        
        // 结尾
        if (st.st_size > 2048) {
            lseek(fd, st.st_size - sizeof(buffer), SEEK_SET);
            if ((bytes = read(fd, buffer, sizeof(buffer))) > 0) {
                for (ssize_t i = 0; i < bytes; i++) {
                    base_hash = base_hash * 41 + (unsigned char)buffer[i];
                }
            }
        }
    }
    
    close(fd);
    
    // 将64位哈希扩展为160位（20字节）
    for (int i = 0; i < HASH_SIZE; i++) {
        hash[i] = (base_hash >> (i * 8)) & 0xFF;
    }
    
    return 0;
}

// 将哈希转换为十六进制字符串
void hash_to_hex(const unsigned char *hash, char *hex_output) {
    for (int i = 0; i < HASH_SIZE; i++) {
        sprintf(hex_output + i * 2, "%02x", hash[i]);
    }
    hex_output[HASH_HEX_SIZE - 1] = '\0';
}

// 检查文件是否应该被排除
int is_excluded_file(const char *path, const char *exclude_patterns) {
    // 简单实现：检查路径是否包含排除模式
    if (!exclude_patterns) return 0;
    
    return strstr(path, exclude_patterns) != NULL;
}

// ========== 路径规范化功能 ==========

// 规范化路径：转换为相对于base_dir的相对路径
char* normalize_path(const char *base_dir, const char *file_path) {
    if (!file_path || !base_dir) return NULL;
    
    // 如果file_path已经是相对路径，检查是否需要去除base_dir前缀
    size_t base_len = strlen(base_dir);
    
    // 处理 "./" 前缀
    if (strncmp(base_dir, "./", 2) == 0) {
        base_dir += 2;
        base_len -= 2;
    }
    
    const char *relative_start = file_path;
    
    // 如果文件路径以base_dir开头，则去除该前缀
    if (strncmp(file_path, base_dir, base_len) == 0) {
        relative_start = file_path + base_len;
        
        // 跳过分隔符
        while (*relative_start == '/') {
            relative_start++;
        }
    }
    
    // 分配内存并复制规范化的路径
    char *normalized = malloc(strlen(relative_start) + 1);
    if (!normalized) return NULL;
    
    strcpy(normalized, relative_start);
    
    // 去除路径中的"./"和规范化分隔符
    sanitize_path(normalized);
    
    return normalized;
}

// 清理路径：去除"./"、重复分隔符等
void sanitize_path(char *path) {
    if (!path) return;
    
    char *src = path;
    char *dst = path;
    
    while (*src) {
        // 跳过"./"
        if (src[0] == '.' && src[1] == '/') {
            src += 2;
            continue;
        }
        
        // 跳过重复的分隔符
        if (*src == '/' && dst > path && *(dst-1) == '/') {
            src++;
            continue;
        }
        
        *dst++ = *src++;
    }
    
    *dst = '\0';
    
    // 去除末尾的分隔符（除非是根目录）
    if (dst > path + 1 && *(dst-1) == '/') {
        *(dst-1) = '\0';
    }
}

// 创建快照的主函数
int git_snapshot_create(const char *dir_path, const char *snapshot_path, 
                       const snapshot_config_t *config, snapshot_result_t *result) {
    
    memset(result, 0, sizeof(snapshot_result_t));
    
    struct timespec start_time;
    clock_gettime(CLOCK_MONOTONIC, &start_time);
    
    // 创建结果收集器
    result_collector_t *collector = result_collector_create();
    if (!collector) {
        strcpy(result->error_message, "无法创建结果收集器");
        return -1;
    }
    
    // 创建工作线程池（支持流式写出）
    int thread_count = config->thread_count > 0 ? config->thread_count : sysconf(_SC_NPROCESSORS_ONLN);
    worker_pool_t *pool = worker_pool_create(thread_count, collector, config, snapshot_path, dir_path);
    if (!pool) {
        result_collector_destroy(collector);
        strcpy(result->error_message, "无法创建工作线程池");
        return -1;
    }
    
    if (config->verbose) {
        printf("开始扫描目录: %s (使用 %d 个线程)\n", dir_path, thread_count);
    }
    
    // 单线程遍历文件系统（确保不丢失文件）
    uint64_t total_files = 0;
    if (scan_directory_recursive(dir_path, pool, config, &total_files) < 0) {
        worker_pool_destroy(pool);
        result_collector_destroy(collector);
        strcpy(result->error_message, "目录扫描失败");
        return -1;
    }
    
    if (config->verbose) {
        printf("\n文件扫描完成，共发现 %"PRIu64" 个文件，等待处理完成...\n", total_files);
    }
    
    // 等待所有文件处理完成，同时显示进度条
    if (config->show_progress) {
        worker_pool_wait_completion_with_progress(pool, total_files);
    } else {
    worker_pool_wait_completion(pool);
    }
    
    // 快照文件已通过流式写入完成
    // 流式写入已经正确处理了所有文件，无需重复写入
    
    // 计算耗时
    struct timespec end_time;
    clock_gettime(CLOCK_MONOTONIC, &end_time);
    result->elapsed_ms = (end_time.tv_sec - start_time.tv_sec) * 1000 + 
                        (end_time.tv_nsec - start_time.tv_nsec) / 1000000;
    
    // 填充结果
    result->total_files = total_files;
    result->processed_files = pool->processed_files;
    result->failed_files = pool->failed_files;
    result->added_files = collector->count;
    
    if (config->verbose) {
        printf("快照创建完成!\n");
        printf("  扫描文件: %"PRIu64"\n", result->total_files);
        printf("  成功处理: %"PRIu64"\n", result->processed_files);
        printf("  失败文件: %"PRIu64"\n", result->failed_files);
        printf("  耗时: %"PRIu64" 毫秒\n", result->elapsed_ms);
        printf("  速度: %.1f 文件/秒\n", 
               result->elapsed_ms > 0 ? (double)result->processed_files * 1000.0 / result->elapsed_ms : 0);
    }
    
    // 显示进度条（简单版本）
    if (config->show_progress && collector->count > 0) {
        printf("\r🔄 处理完成: %"PRIu64" 个文件", collector->count);
        fflush(stdout);
        printf("\n");
    }
    
    worker_pool_destroy(pool);
    result_collector_destroy(collector);
    
    return 0;
}

// ================================
// 工作区管理功能
// ================================

// 初始化工作区（在当前目录）
int init_workspace(const char *project_name) {
    char snapshot_dir[MAX_PATH_LEN];
    char config_path[MAX_PATH_LEN];
    
    // 创建 .snapshot 目录
    snprintf(snapshot_dir, sizeof(snapshot_dir), "%s", SNAPSHOT_DIR);
    if (mkdir(snapshot_dir, 0755) != 0 && errno != EEXIST) {
        return -1;
    }
    
    // 创建配置文件
    snprintf(config_path, sizeof(config_path), "%s/%s", SNAPSHOT_DIR, CONFIG_FILE);
    FILE *config_file = fopen(config_path, "w");
    if (!config_file) {
        return -1;
    }
    
    // 写入工作区配置
    char *cwd = getcwd(NULL, 0);
    fprintf(config_file, "project_name=%s\n", project_name ? project_name : "unnamed");
    fprintf(config_file, "created_time=%ld\n", time(NULL));
    fprintf(config_file, "workspace_root=%s\n", cwd ? cwd : ".");
    fclose(config_file);
    
    if (cwd) free(cwd);
    return 0;
}

// 在指定目录初始化工作区
int init_workspace_in_dir(const char *target_dir, const char *project_name) {
    char snapshot_dir[MAX_PATH_LEN];
    char config_path[MAX_PATH_LEN];
    char abs_target_dir[MAX_PATH_LEN];
    
    // 获取目标目录的绝对路径
    if (!realpath(target_dir, abs_target_dir)) {
        return -1;
    }
    
    // 创建目标目录下的 .snapshot 目录
    snprintf(snapshot_dir, sizeof(snapshot_dir), "%s/%s", abs_target_dir, SNAPSHOT_DIR);
    if (mkdir(snapshot_dir, 0755) != 0 && errno != EEXIST) {
        return -1;
    }
    
    // 创建配置文件
    snprintf(config_path, sizeof(config_path), "%s/%s", snapshot_dir, CONFIG_FILE);
    FILE *config_file = fopen(config_path, "w");
    if (!config_file) {
        return -1;
    }
    
    // 写入工作区配置
    fprintf(config_file, "project_name=%s\n", project_name ? project_name : "unnamed");
    fprintf(config_file, "created_time=%ld\n", time(NULL));
    fprintf(config_file, "workspace_root=%s\n", abs_target_dir);
    fclose(config_file);
    
    return 0;
}

// 查找工作区根目录（向上递归查找）
char* find_workspace_root(const char *start_path) {
    static char workspace_root[MAX_PATH_LEN];
    char current_path[MAX_PATH_LEN];
    char snapshot_dir[MAX_PATH_LEN];
    
    // 从给定路径开始查找
    if (start_path && strcmp(start_path, ".") != 0) {
        strncpy(current_path, start_path, MAX_PATH_LEN - 1);
    } else {
        if (!getcwd(current_path, sizeof(current_path))) {
            return NULL;
        }
    }
    current_path[MAX_PATH_LEN - 1] = '\0';
    
    // 向上递归查找 .snapshot 目录
    while (strlen(current_path) > 1) {
        snprintf(snapshot_dir, sizeof(snapshot_dir), "%s/%s", current_path, SNAPSHOT_DIR);
        
        if (workspace_exists(snapshot_dir)) {
            strncpy(workspace_root, current_path, MAX_PATH_LEN - 1);
            workspace_root[MAX_PATH_LEN - 1] = '\0';
            return workspace_root;
        }
        
        // 移动到父目录
        char *last_slash = strrchr(current_path, '/');
        if (last_slash && last_slash != current_path) {
            *last_slash = '\0';
        } else {
            break;
        }
    }
    
    return NULL;  // 未找到工作区
}

// 获取基线快照路径
char* get_baseline_snapshot_path(const char *workspace_root) {
    static char baseline_path[MAX_PATH_LEN];
    
    if (!workspace_root) {
        return NULL;
    }
    
    snprintf(baseline_path, sizeof(baseline_path), "%s/%s/%s", 
             workspace_root, SNAPSHOT_DIR, BASELINE_FILE);
    
    return baseline_path;
}

// 检查工作区是否存在
int workspace_exists(const char *path) {
    struct stat st;
    return (stat(path, &st) == 0 && S_ISDIR(st.st_mode));
}

// ================================
// 工作区配置管理功能
// ================================

// 创建默认工作区配置
int create_default_workspace_config(workspace_config_t *config, const char *project_name, const char *workspace_dir) {
    if (!config || !project_name) {
        return -1;
    }
    
    memset(config, 0, sizeof(workspace_config_t));
    
    // 设置项目名称
    strncpy(config->project_name, project_name, MAX_PATH_LEN - 1);
    config->project_name[MAX_PATH_LEN - 1] = '\0';
    
    // 设置工作目录
    if (workspace_dir) {
        strncpy(config->workspace_dir, workspace_dir, MAX_PATH_LEN - 1);
        config->workspace_dir[MAX_PATH_LEN - 1] = '\0';
    }
    
    // 设置默认忽略模式
    strncpy(config->ignore_patterns, ".snapshot", MAX_PATH_LEN - 1);
    config->ignore_patterns[MAX_PATH_LEN - 1] = '\0';
    
    // 设置时间戳
    config->created_time = time(NULL);
    config->updated_time = config->created_time;
    
    return 0;
}

// 加载工作区配置
int load_workspace_config(const char *workspace_root, workspace_config_t *config) {
    if (!workspace_root || !config) {
        return -1;
    }
    
    char config_path[MAX_PATH_LEN];
    snprintf(config_path, sizeof(config_path), "%s/%s/%s", 
             workspace_root, SNAPSHOT_DIR, CONFIG_FILE);
    
    FILE *fp = fopen(config_path, "r");
    if (!fp) {
        return -1;
    }
    
    // 初始化配置为默认值
    memset(config, 0, sizeof(workspace_config_t));
    strncpy(config->ignore_patterns, ".snapshot", MAX_PATH_LEN - 1);
    
    char line[MAX_PATH_LEN * 2];
    while (fgets(line, sizeof(line), fp)) {
        // 移除换行符
        line[strcspn(line, "\r\n")] = '\0';
        
        // 跳过空行和注释
        if (line[0] == '\0' || line[0] == '#') {
            continue;
        }
        
        // 解析键值对
        char *key = strtok(line, "=");
        char *value = strtok(NULL, "");
        
        if (!key || !value) {
            continue;
        }
        
        if (strcmp(key, "project_name") == 0) {
            strncpy(config->project_name, value, MAX_PATH_LEN - 1);
        } else if (strcmp(key, "workspace_dir") == 0) {
            strncpy(config->workspace_dir, value, MAX_PATH_LEN - 1);
        } else if (strcmp(key, "ignore_patterns") == 0) {
            strncpy(config->ignore_patterns, value, MAX_PATH_LEN - 1);
        } else if (strcmp(key, "created_time") == 0) {
            config->created_time = strtoull(value, NULL, 10);
        } else if (strcmp(key, "updated_time") == 0) {
            config->updated_time = strtoull(value, NULL, 10);
        }
        // 兼容旧格式的workspace_root字段
        else if (strcmp(key, "workspace_root") == 0) {
            strncpy(config->workspace_dir, value, MAX_PATH_LEN - 1);
        }
    }
    
    fclose(fp);
    return 0;
}

// 保存工作区配置
int save_workspace_config(const char *workspace_root, const workspace_config_t *config) {
    if (!workspace_root || !config) {
        return -1;
    }
    
    char config_path[MAX_PATH_LEN];
    snprintf(config_path, sizeof(config_path), "%s/%s/%s", 
             workspace_root, SNAPSHOT_DIR, CONFIG_FILE);
    
    FILE *fp = fopen(config_path, "w");
    if (!fp) {
        return -1;
    }
    
    // 写入配置文件头
    fprintf(fp, "# 工作区配置文件\n");
    fprintf(fp, "# 由 kernel_snapshot 工具自动生成\n\n");
    
    // 写入配置项
    fprintf(fp, "project_name=%s\n", config->project_name);
    fprintf(fp, "workspace_dir=%s\n", config->workspace_dir);
    fprintf(fp, "ignore_patterns=%s\n", config->ignore_patterns);
    fprintf(fp, "created_time=%"PRIu64"\n", config->created_time);
    fprintf(fp, "updated_time=%"PRIu64"\n", config->updated_time);
    
    // 保持与旧格式的兼容性
    fprintf(fp, "\n# 兼容性字段\n");
    fprintf(fp, "workspace_root=%s\n", config->workspace_dir);
    
    fclose(fp);
    return 0;
}

// 检查文件是否应该被忽略
int is_file_ignored(const char *file_path, const char *ignore_patterns) {
    if (!file_path || !ignore_patterns) {
        return 0;
    }
    
    // 复制忽略模式字符串，因为strtok会修改它
    char patterns[MAX_PATH_LEN];
    strncpy(patterns, ignore_patterns, MAX_PATH_LEN - 1);
    patterns[MAX_PATH_LEN - 1] = '\0';
    
    // 获取文件名（去掉路径）
    const char *filename = strrchr(file_path, '/');
    if (filename) {
        filename++; // 跳过'/'
    } else {
        filename = file_path;
    }
    
    // 分割忽略模式并逐一检查
    char *pattern = strtok(patterns, ",");
    while (pattern) {
        // 去掉模式前后的空格
        while (*pattern == ' ') pattern++;
        char *end = pattern + strlen(pattern) - 1;
        while (end > pattern && *end == ' ') *end-- = '\0';
        
        // 检查是否匹配
        if (strlen(pattern) > 0) {
            // 简单的通配符匹配
            if (pattern[0] == '*') {
                // 匹配后缀，如*.tmp
                const char *suffix = pattern + 1;
                size_t suffix_len = strlen(suffix);
                size_t filename_len = strlen(filename);
                if (filename_len >= suffix_len && 
                    strcmp(filename + filename_len - suffix_len, suffix) == 0) {
                    return 1;
                }
            } else if (pattern[strlen(pattern) - 1] == '*') {
                // 匹配前缀，如temp*
                size_t pattern_len = strlen(pattern) - 1;
                if (strncmp(filename, pattern, pattern_len) == 0) {
                    return 1;
                }
            } else {
                // 精确匹配或路径匹配
                if (strcmp(filename, pattern) == 0 || strstr(file_path, pattern) != NULL) {
                    return 1;
                }
            }
        }
        
        pattern = strtok(NULL, ",");
    }
    
    return 0;
}

// ================================
// 全局配置管理功能
// ================================

// 加载全局配置文件
int load_global_config(FILE *fp, workspace_config_t *config) {
    if (!fp || !config) {
        return -1;
    }
    
    // 初始化配置为默认值
    memset(config, 0, sizeof(workspace_config_t));
    strncpy(config->ignore_patterns, ".snapshot", MAX_PATH_LEN - 1);
    
    char line[MAX_PATH_LEN * 2];
    while (fgets(line, sizeof(line), fp)) {
        // 移除换行符
        line[strcspn(line, "\r\n")] = '\0';
        
        // 跳过空行和注释
        if (line[0] == '\0' || line[0] == '#') {
            continue;
        }
        
        // 解析键值对
        char *key = strtok(line, "=");
        char *value = strtok(NULL, "");
        
        if (!key || !value) {
            continue;
        }
        
        if (strcmp(key, "default_workspace_dir") == 0) {
            strncpy(config->workspace_dir, value, MAX_PATH_LEN - 1);
        } else if (strcmp(key, "ignore_patterns") == 0) {
            strncpy(config->ignore_patterns, value, MAX_PATH_LEN - 1);
        } else if (strcmp(key, "default_project_name") == 0) {
            strncpy(config->project_name, value, MAX_PATH_LEN - 1);
        }
    }
    
    return 0;
}

// 保存全局配置文件
int save_global_config(const char *config_path, const workspace_config_t *config) {
    if (!config_path || !config) {
        return -1;
    }
    
    FILE *fp = fopen(config_path, "w");
    if (!fp) {
        return -1;
    }
    
    // 写入配置文件头
    fprintf(fp, "# kernel_snapshot 全局配置文件\n");
    fprintf(fp, "# 此文件用于设置默认的工作目录和忽略模式\n\n");
    
    // 写入配置项
    if (strlen(config->workspace_dir) > 0) {
        fprintf(fp, "# 默认工作目录（绝对路径）\n");
        fprintf(fp, "default_workspace_dir=%s\n\n", config->workspace_dir);
    }
    
    if (strlen(config->project_name) > 0) {
        fprintf(fp, "# 默认项目名称\n");
        fprintf(fp, "default_project_name=%s\n\n", config->project_name);
    }
    
    fprintf(fp, "# 忽略文件模式（用逗号分隔）\n");
    fprintf(fp, "ignore_patterns=%s\n\n", config->ignore_patterns);
    
    fprintf(fp, "# 配置说明:\n");
    fprintf(fp, "# - default_workspace_dir: 如果设置，create命令将默认在此目录创建快照\n");
    fprintf(fp, "# - ignore_patterns: 扫描时忽略的文件/目录模式\n");
    fprintf(fp, "#   支持通配符: *.tmp, temp*, .git 等\n");
    
    fclose(fp);
    return 0;
}

// ================================
// 系统信息显示功能
// ================================

#ifdef __APPLE__
#include <sys/sysctl.h>
#endif

// 获取可用内存（MB）
static long get_available_memory_mb() {
#ifdef __APPLE__
    // macOS 系统
    int mib[2] = {CTL_HW, HW_MEMSIZE};
    uint64_t physical_memory;
    size_t length = sizeof(physical_memory);
    
    if (sysctl(mib, 2, &physical_memory, &length, NULL, 0) == 0) {
        return physical_memory / (1024 * 1024);  // 转换为MB
    }
#elif __linux__
    // Linux 系统
    FILE *fp = fopen("/proc/meminfo", "r");
    if (fp) {
        char line[256];
        long mem_available = 0;
        long mem_free = 0;
        long buffers = 0;
        long cached = 0;
        
        while (fgets(line, sizeof(line), fp)) {
            if (strncmp(line, "MemAvailable:", 13) == 0) {
                sscanf(line, "MemAvailable: %ld kB", &mem_available);
                break;
            } else if (strncmp(line, "MemFree:", 8) == 0) {
                sscanf(line, "MemFree: %ld kB", &mem_free);
            } else if (strncmp(line, "Buffers:", 8) == 0) {
                sscanf(line, "Buffers: %ld kB", &buffers);
            } else if (strncmp(line, "Cached:", 7) == 0) {
                sscanf(line, "Cached: %ld kB", &cached);
            }
        }
        fclose(fp);
        
        if (mem_available > 0) {
            return mem_available / 1024;  // 转换为MB
        } else if (mem_free > 0) {
            return (mem_free + buffers + cached) / 1024;  // 估算可用内存
        }
    }
#endif
    return -1;  // 无法获取
}

// 获取CPU信息
static void get_cpu_info(char *cpu_info, size_t size) {
#ifdef __APPLE__
    // macOS 系统
    size_t cpu_size = size;
    if (sysctlbyname("machdep.cpu.brand_string", cpu_info, &cpu_size, NULL, 0) != 0) {
        strncpy(cpu_info, "Unknown CPU", size - 1);
        cpu_info[size - 1] = '\0';
    }
#elif __linux__
    // Linux 系统
    FILE *fp = fopen("/proc/cpuinfo", "r");
    if (fp) {
        char line[256];
        int found = 0;
        
        while (fgets(line, sizeof(line), fp) && !found) {
            if (strncmp(line, "model name", 10) == 0) {
                char *colon = strchr(line, ':');
                if (colon) {
                    colon += 2;  // 跳过 ": "
                    // 移除换行符
                    char *newline = strchr(colon, '\n');
                    if (newline) *newline = '\0';
                    
                    strncpy(cpu_info, colon, size - 1);
                    cpu_info[size - 1] = '\0';
                    found = 1;
                }
            }
        }
        fclose(fp);
        
        if (!found) {
            strncpy(cpu_info, "Unknown CPU", size - 1);
            cpu_info[size - 1] = '\0';
        }
    } else {
        strncpy(cpu_info, "Unknown CPU", size - 1);
        cpu_info[size - 1] = '\0';
    }
#else
    strncpy(cpu_info, "Unknown CPU", size - 1);
    cpu_info[size - 1] = '\0';
#endif
}

// 显示系统信息
void show_system_info(int thread_count) {
    printf("💻 系统信息\n");
    printf("==========\n");
    
    // CPU 信息
    char cpu_info[256];
    get_cpu_info(cpu_info, sizeof(cpu_info));
    printf("🔧 CPU: %s\n", cpu_info);
    
    // 内存信息
    long available_memory = get_available_memory_mb();
    if (available_memory > 0) {
        if (available_memory >= 1024) {
            printf("💾 可用内存: %.1f GB\n", available_memory / 1024.0);
        } else {
            printf("💾 可用内存: %ld MB\n", available_memory);
        }
    } else {
        printf("💾 可用内存: 无法获取\n");
    }
    
    // 线程信息
    printf("⚡ 使用线程数: %d\n", thread_count);
    
    printf("\n");
}