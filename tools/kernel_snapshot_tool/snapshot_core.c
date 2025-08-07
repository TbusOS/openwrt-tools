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

// Git风格的文件遍历（单线程，确保不丢失）
static int scan_directory_recursive(const char *dir_path, worker_pool_t *pool, 
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
        if (ret >= sizeof(full_path)) {
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
        
        if (S_ISDIR(st.st_mode)) {
            // 递归处理子目录（单线程遍历，确保完整性）
            scan_directory_recursive(full_path, pool, config, total_files);
        } else if (S_ISREG(st.st_mode)) {
            // 检查是否需要排除
            if (config->exclude_patterns && 
                is_excluded_file(full_path, config->exclude_patterns)) {
                continue;
            }
            
            // 记录找到的文件
            (*total_files)++;
            
            // 添加到工作队列（这里不会丢失，因为是阻塞添加）
            while (worker_pool_add_work(pool, full_path) != 0) {
                // 如果队列满了，等待一小段时间再试
                usleep(1000);  // 1ms
            }
            
            if (config->verbose && (*total_files % 10000) == 0) {
                printf("已扫描 %llu 个文件...\r", *total_files);
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
        
        // 等待工作或退出信号
        while (pool->work_head == NULL && !pool->shutdown) {
            pthread_cond_wait(&pool->work_cond, &pool->work_lock);
        }
        
        if (pool->shutdown && pool->work_head == NULL) {
            pthread_mutex_unlock(&pool->work_lock);
            break;
        }
        
        // 获取工作单元
        work_unit_t *work = pool->work_head;
        if (work) {
            pool->work_head = work->next;
            if (pool->work_head == NULL) {
                pool->work_tail = NULL;
            }
        }
        
        pool->active_workers++;
        pthread_mutex_unlock(&pool->work_lock);
        
        if (work) {
            // 处理文件
            result_entry_t result;
            memset(&result, 0, sizeof(result));
            
            result.error_code = process_file_content(work->path, &result.entry, 
                                                   pool->collector != NULL);
            
            if (result.error_code == 0) {
                result.status = FILE_ADDED;  // 新创建快照时都是新增
                result_collector_add(pool->collector, &result);
                
                pthread_mutex_lock(&pool->work_lock);
                pool->processed_files++;
                pthread_mutex_unlock(&pool->work_lock);
            } else {
                pthread_mutex_lock(&pool->work_lock);
                pool->failed_files++;
                pthread_mutex_unlock(&pool->work_lock);
            }
            
            free(work);
        }
        
        // 标记工作完成
        pthread_mutex_lock(&pool->work_lock);
        pool->active_workers--;
        if (pool->active_workers == 0 && pool->work_head == NULL) {
            pthread_cond_signal(&pool->done_cond);
        }
        pthread_mutex_unlock(&pool->work_lock);
    }
    
    return NULL;
}

// 创建工作线程池
worker_pool_t* worker_pool_create(int thread_count, result_collector_t *collector) {
    worker_pool_t *pool = calloc(1, sizeof(worker_pool_t));
    if (!pool) return NULL;
    
    pool->thread_count = thread_count;
    pool->collector = collector;
    pool->threads = malloc(thread_count * sizeof(pthread_t));
    
    if (!pool->threads) {
        free(pool);
        return NULL;
    }
    
    pthread_mutex_init(&pool->work_lock, NULL);
    pthread_cond_init(&pool->work_cond, NULL);
    pthread_cond_init(&pool->done_cond, NULL);
    
    // 创建工作线程
    for (int i = 0; i < thread_count; i++) {
        if (pthread_create(&pool->threads[i], NULL, worker_thread, pool) != 0) {
            // 清理已创建的线程
            pool->shutdown = 1;
            pthread_cond_broadcast(&pool->work_cond);
            for (int j = 0; j < i; j++) {
                pthread_join(pool->threads[j], NULL);
            }
            worker_pool_destroy(pool);
            return NULL;
        }
    }
    
    return pool;
}

// 添加工作到线程池（阻塞式，确保不丢失）
int worker_pool_add_work(worker_pool_t *pool, const char *file_path) {
    work_unit_t *work = malloc(sizeof(work_unit_t));
    if (!work) return -1;
    
    strncpy(work->path, file_path, MAX_PATH_LEN - 1);
    work->path[MAX_PATH_LEN - 1] = '\0';
    work->next = NULL;
    
    pthread_mutex_lock(&pool->work_lock);
    
    // 简单的链表队列，没有大小限制（避免丢失文件）
    if (pool->work_tail) {
        pool->work_tail->next = work;
    } else {
        pool->work_head = work;
    }
    pool->work_tail = work;
    
    pthread_cond_signal(&pool->work_cond);
    pthread_mutex_unlock(&pool->work_lock);
    
    return 0;
}

// 等待所有工作完成
void worker_pool_wait_completion(worker_pool_t *pool) {
    pthread_mutex_lock(&pool->work_lock);
    
    while (pool->work_head != NULL || pool->active_workers > 0) {
        pthread_cond_wait(&pool->done_cond, &pool->work_lock);
    }
    
    pthread_mutex_unlock(&pool->work_lock);
}

// 销毁工作线程池
void worker_pool_destroy(worker_pool_t *pool) {
    if (!pool) return;
    
    pthread_mutex_lock(&pool->work_lock);
    pool->shutdown = 1;
    pthread_cond_broadcast(&pool->work_cond);
    pthread_mutex_unlock(&pool->work_lock);
    
    // 等待所有线程完成
    for (int i = 0; i < pool->thread_count; i++) {
        pthread_join(pool->threads[i], NULL);
    }
    
    // 清理剩余的工作
    while (pool->work_head) {
        work_unit_t *next = pool->work_head->next;
        free(pool->work_head);
        pool->work_head = next;
    }
    
    pthread_mutex_destroy(&pool->work_lock);
    pthread_cond_destroy(&pool->work_cond);
    pthread_cond_destroy(&pool->done_cond);
    
    free(pool->threads);
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
    
    if (!S_ISREG(st.st_mode)) {
        return -2;  // 不是普通文件
    }
    
    // 填充基本信息
    strncpy(entry->path, file_path, MAX_PATH_LEN - 1);
    entry->path[MAX_PATH_LEN - 1] = '\0';
    entry->size = st.st_size;
    entry->mtime = st.st_mtime;
    entry->flags = 0;
    
    // 计算哈希
    int hash_result;
    if (use_git_hash) {
        hash_result = calculate_git_hash(file_path, entry->hash);
    } else {
        hash_result = calculate_fast_hash(file_path, entry->hash);
    }
    
    if (hash_result < 0) {
        return -3;  // 哈希计算失败
    }
    
    // 转换为十六进制
    hash_to_hex(entry->hash, entry->hash_hex);
    
    return 0;
}

// Git兼容的SHA1哈希计算
int calculate_git_hash(const char *file_path, unsigned char *hash) {
    // 这里可以调用系统的sha1sum或者实现一个简单的SHA1
    // 为了简化，先用一个快速但不完全Git兼容的方法
    return calculate_fast_hash(file_path, hash);
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
    
    // 创建工作线程池
    int thread_count = config->thread_count > 0 ? config->thread_count : sysconf(_SC_NPROCESSORS_ONLN);
    worker_pool_t *pool = worker_pool_create(thread_count, collector);
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
        printf("\n文件扫描完成，共发现 %llu 个文件，等待处理完成...\n", total_files);
    }
    
    // 等待所有文件处理完成
    worker_pool_wait_completion(pool);
    
    // 保存快照到文件
    FILE *fp = fopen(snapshot_path, "w");
    if (!fp) {
        worker_pool_destroy(pool);
        result_collector_destroy(collector);
        strcpy(result->error_message, "无法创建快照文件");
        return -1;
    }
    
    // 写入头部信息
    fprintf(fp, "# Git-Style Snapshot v1.0\n");
    fprintf(fp, "# Created: %ld\n", time(NULL));
    fprintf(fp, "# Total Files: %llu\n", collector->count);
    fprintf(fp, "# Base Dir: %s\n", dir_path);
    
    // 写入文件条目
    result_entry_t *entry = collector->head;
    while (entry) {
        fprintf(fp, "%s;%llu;%llu;%s\n", 
               entry->entry.path, entry->entry.size, 
               entry->entry.mtime, entry->entry.hash_hex);
        entry = entry->next;
    }
    
    fclose(fp);
    
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
        printf("  扫描文件: %llu\n", result->total_files);
        printf("  成功处理: %llu\n", result->processed_files);
        printf("  失败文件: %llu\n", result->failed_files);
        printf("  耗时: %llu 毫秒\n", result->elapsed_ms);
        printf("  速度: %.1f 文件/秒\n", 
               result->elapsed_ms > 0 ? (double)result->processed_files * 1000.0 / result->elapsed_ms : 0);
    }
    
    worker_pool_destroy(pool);
    result_collector_destroy(collector);
    
    return 0;
}