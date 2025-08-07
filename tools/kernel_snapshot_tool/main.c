/**
 * Git风格快照工具 - 主程序
 * 专注于零文件丢失的高性能实现
 */

#include "snapshot_core.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include <unistd.h>

static void print_usage(const char *program_name) {
    printf("Git风格快照工具 - 零文件丢失设计\n\n");
    printf("用法:\n");
    printf("  %s create <目录> <快照文件>     创建快照\n", program_name);
    printf("  %s status <快照文件> <目录>     检查状态\n", program_name);
    printf("  %s diff <旧快照> <新快照>       对比快照\n\n", program_name);
    
    printf("选项:\n");
    printf("  -t, --threads=N    使用N个线程处理文件内容 (默认: CPU核心数)\n");
    printf("  -v, --verbose      详细输出\n");
    printf("  -g, --git-hash     使用Git兼容的SHA1哈希\n");
    printf("  -e, --exclude=PAT  排除包含指定模式的文件\n");
    printf("  -h, --help         显示此帮助\n\n");
    
    printf("设计特点:\n");
    printf("  ✅ 绝对不丢失文件 - 单线程遍历确保完整性\n");
    printf("  🚀 高性能处理 - 多线程并行处理文件内容\n");
    printf("  🔍 Git兼容性 - 支持Git风格的哈希和格式\n");
    printf("  📊 详细统计 - 完整的错误报告和性能指标\n\n");
}

static int cmd_create(int argc, char *argv[], const snapshot_config_t *config) {
    if (argc < 2) {
        fprintf(stderr, "错误: create命令需要<目录>和<快照文件>参数\n");
        return 1;
    }
    
    const char *dir_path = argv[0];
    const char *snapshot_path = argv[1];
    
    // 检查目录是否存在
    if (access(dir_path, R_OK) != 0) {
        fprintf(stderr, "错误: 无法访问目录 %s\n", dir_path);
        return 1;
    }
    
    printf("🔍 开始创建快照: %s -> %s\n", dir_path, snapshot_path);
    
    snapshot_result_t result;
    int ret = git_snapshot_create(dir_path, snapshot_path, config, &result);
    
    if (ret == 0) {
        printf("✅ 快照创建成功!\n");
        printf("📊 统计信息:\n");
        printf("   扫描文件: %llu\n", result.total_files);
        printf("   成功处理: %llu\n", result.processed_files);
        printf("   失败文件: %llu\n", result.failed_files);
        printf("   文件完整率: %.2f%%\n", 
               result.total_files > 0 ? 
               (double)result.processed_files * 100.0 / result.total_files : 0);
        printf("   处理速度: %.1f 文件/秒\n",
               result.elapsed_ms > 0 ? 
               (double)result.processed_files * 1000.0 / result.elapsed_ms : 0);
        printf("   总耗时: %llu 毫秒\n", result.elapsed_ms);
        
        if (result.failed_files > 0) {
            printf("⚠️  警告: 有 %llu 个文件处理失败\n", result.failed_files);
        }
    } else {
        printf("❌ 快照创建失败: %s\n", result.error_message);
    }
    
    return ret;
}

static int cmd_status(int argc, char *argv[], const snapshot_config_t *config) {
    if (argc < 2) {
        fprintf(stderr, "错误: status命令需要<快照文件>和<目录>参数\n");
        return 1;
    }
    
    const char *snapshot_path = argv[0];
    const char *dir_path = argv[1];
    
    printf("🔍 检查目录状态: %s (基于快照 %s)\n", dir_path, snapshot_path);
    
    snapshot_result_t result;
    int ret = git_snapshot_status(snapshot_path, dir_path, config, &result);
    
    if (ret == 0) {
        printf("📊 状态统计:\n");
        printf("   新增文件: %llu\n", result.added_files);
        printf("   修改文件: %llu\n", result.modified_files);
        printf("   删除文件: %llu\n", result.deleted_files);
        printf("   总变化: %llu\n", 
               result.added_files + result.modified_files + result.deleted_files);
    } else {
        printf("❌ 状态检查失败: %s\n", result.error_message);
    }
    
    return ret;
}

static int cmd_diff(int argc, char *argv[], const snapshot_config_t *config) {
    if (argc < 2) {
        fprintf(stderr, "错误: diff命令需要<旧快照>和<新快照>参数\n");
        return 1;
    }
    
    const char *old_snapshot = argv[0];
    const char *new_snapshot = argv[1];
    
    printf("🔍 对比快照: %s -> %s\n", old_snapshot, new_snapshot);
    
    snapshot_result_t result;
    int ret = git_snapshot_diff(old_snapshot, new_snapshot, config, &result);
    
    if (ret == 0) {
        printf("📊 差异统计:\n");
        printf("   新增文件: %llu\n", result.added_files);
        printf("   修改文件: %llu\n", result.modified_files);
        printf("   删除文件: %llu\n", result.deleted_files);
    } else {
        printf("❌ 快照对比失败: %s\n", result.error_message);
    }
    
    return ret;
}

int main(int argc, char *argv[]) {
    snapshot_config_t config = {
        .thread_count = 0,  // 0 = 自动检测
        .verbose = 0,
        .exclude_patterns = NULL,
        .use_git_hash = 0,
        .streaming_mode = 1
    };
    
    static struct option long_options[] = {
        {"threads",  required_argument, 0, 't'},
        {"verbose",  no_argument,       0, 'v'},
        {"git-hash", no_argument,       0, 'g'},
        {"exclude",  required_argument, 0, 'e'},
        {"help",     no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "t:vge:h", long_options, NULL)) != -1) {
        switch (opt) {
            case 't':
                config.thread_count = atoi(optarg);
                if (config.thread_count < 1 || config.thread_count > WORKERS_MAX) {
                    fprintf(stderr, "错误: 线程数必须在1-%d之间\n", WORKERS_MAX);
                    return 1;
                }
                break;
            case 'v':
                config.verbose = 1;
                break;
            case 'g':
                config.use_git_hash = 1;
                break;
            case 'e':
                config.exclude_patterns = optarg;
                break;
            case 'h':
                print_usage(argv[0]);
                return 0;
            default:
                print_usage(argv[0]);
                return 1;
        }
    }
    
    if (optind >= argc) {
        fprintf(stderr, "错误: 缺少命令\n\n");
        print_usage(argv[0]);
        return 1;
    }
    
    const char *command = argv[optind];
    char **cmd_args = &argv[optind + 1];
    int cmd_argc = argc - optind - 1;
    
    if (strcmp(command, "create") == 0) {
        return cmd_create(cmd_argc, cmd_args, &config);
    } else if (strcmp(command, "status") == 0) {
        return cmd_status(cmd_argc, cmd_args, &config);
    } else if (strcmp(command, "diff") == 0) {
        return cmd_diff(cmd_argc, cmd_args, &config);
    } else {
        fprintf(stderr, "错误: 未知命令 '%s'\n\n", command);
        print_usage(argv[0]);
        return 1;
    }
}