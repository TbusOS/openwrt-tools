#include "watch.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <sys/stat.h>

// 显示 watch 命令帮助
void print_watch_usage(const char *program_name) {
    printf("使用方法: %s watch [选项] [目录]\n\n", program_name);
    printf("文件监控功能 - 实时显示文件系统变更\n\n");
    
    printf("参数:\n");
    printf("  目录                    要监控的目录路径 (默认: 当前目录或配置文件中的目录)\n\n");
    
    printf("选项:\n");
    printf("  -r, --recursive         递归监控子目录 (默认开启)\n");
    printf("  -n, --no-recursive      禁用递归监控\n");
    printf("  -v, --verbose           详细输出 (显示文件大小等信息)\n");
    printf("  -q, --quiet             安静模式 (仅显示统计信息)\n");
    printf("  -S, --stats[=间隔]      定期显示统计信息 (默认10秒)\n");
    printf("  -f, --filter=模式       额外的忽略模式 (逗号分隔)\n");
    printf("      --no-colors         禁用彩色输出\n");
    printf("  -h, --help              显示此帮助信息\n\n");
    
    printf("🎯 使用示例:\n");
    printf("  %s watch                           # 监控当前目录\n", program_name);
    printf("  %s watch /path/to/kernel           # 监控指定目录\n", program_name);
    printf("  %s watch -v -S=5                   # 详细模式，每5秒显示统计\n", program_name);
    printf("  %s watch -f=\"*.tmp,build/*\"        # 额外忽略模式\n", program_name);
    printf("  %s watch -n                        # 非递归监控\n", program_name);
    printf("  %s watch -q -S                     # 安静模式，显示统计\n\n", program_name);
    
    printf("📋 支持的平台:\n");
    printf("  Linux:   x86_64, ARM32, ARM64, MIPS, RISC-V (使用 inotify)\n");
    printf("  macOS:   Intel x86_64, Apple Silicon ARM64 (使用 FSEvents)\n\n");
    
    printf("🚫 忽略规则:\n");
    printf("  默认忽略: .snapshot, *.o, *.so, *.a, *.tmp, *.log, *.bak, .git\n");
    printf("  可通过 -f 选项添加额外的忽略模式\n");
    printf("  支持通配符: *, ?, [abc], 目录模式: dir/*\n\n");
    
    printf("💡 提示:\n");
    printf("  - 使用 Ctrl+C 停止监控\n");
    printf("  - 配合 .kernel_snapshot.conf 配置文件使用效果更佳\n");
    printf("  - 监控大型目录时建议使用忽略模式减少噪音\n");
}

// 从快照配置创建监控配置
watch_config_t* create_watch_config_from_snapshot(const snapshot_config_t *snap_config, 
                                                  const char *monitor_dir) {
    watch_config_t *watch_config = create_default_watch_config(monitor_dir);
    if (!watch_config) return NULL;
    
    // 从快照配置复制相关设置
    if (snap_config) {
        watch_config->verbose = snap_config->verbose;
        // 注意：snapshot_config_t 没有 ignore_patterns 字段
        // 忽略模式将从全局配置或默认值中获取
    }
    
    return watch_config;
}

// 获取有效的监控目录
static int get_effective_monitor_dir(const char *arg_dir, const snapshot_config_t *config, 
                                    char *result_dir, size_t result_size) {
    (void)config; // 暂时未使用，避免编译警告
    
    // 优先级: 命令行参数 > 全局配置 > 当前目录
    if (arg_dir && strlen(arg_dir) > 0) {
        strncpy(result_dir, arg_dir, result_size - 1);
        result_dir[result_size - 1] = '\0';
        return 0;
    }
    
    // 尝试从全局配置读取 (复用现有的配置查找逻辑)
    char tool_dir[MAX_PATH_LEN];
    char global_config_path[MAX_PATH_LEN];
    workspace_config_t global_config = {0};
    
    // 获取工具目录
#ifdef __APPLE__
    uint32_t path_size = sizeof(tool_dir);
    extern int _NSGetExecutablePath(char* buf, uint32_t* bufsize);
    if (_NSGetExecutablePath(tool_dir, &path_size) == 0) {
        char *last_slash = strrchr(tool_dir, '/');
        if (last_slash) *last_slash = '\0';
    } else {
        strncpy(tool_dir, ".", sizeof(tool_dir) - 1);
    }
#else
    ssize_t len = readlink("/proc/self/exe", tool_dir, sizeof(tool_dir) - 1);
    if (len != -1) {
        tool_dir[len] = '\0';
        char *last_slash = strrchr(tool_dir, '/');
        if (last_slash) *last_slash = '\0';
    } else {
        strncpy(tool_dir, ".", sizeof(tool_dir) - 1);
    }
#endif
    
    snprintf(global_config_path, sizeof(global_config_path), "%s/.kernel_snapshot.conf", tool_dir);
    
    // 尝试读取全局配置
    FILE *fp = fopen(global_config_path, "r");
    if (fp) {
        load_global_config(fp, &global_config);
        fclose(fp);
        
        if (strlen(global_config.workspace_dir) > 0) {
            strncpy(result_dir, global_config.workspace_dir, result_size - 1);
            result_dir[result_size - 1] = '\0';
            return 0;
        }
    }
    
    // 默认使用当前目录
    strncpy(result_dir, ".", result_size - 1);
    result_dir[result_size - 1] = '\0';
    return 0;
}

// watch 命令的主实现
int cmd_watch(int argc, char *argv[], const snapshot_config_t *config) {
    // 重置 optind，因为它是全局变量，可能在 main.c 中已被修改
    optind = 1;
    
    // 检查平台支持
    if (!file_monitor_is_supported()) {
        fprintf(stderr, "错误: 当前平台不支持文件监控功能\n");
        fprintf(stderr, "平台信息: %s\n", file_monitor_get_platform_name());
        return 1;
    }
    
    // 命令行选项
    int recursive = 1;         // 默认递归
    int verbose = config->verbose;  // 继承全局的 verbose 设置
    int quiet = 0;             // 默认非安静模式
    int show_stats = 0;        // 默认不显示统计
    int stats_interval = 10;   // 默认10秒统计间隔
    char extra_filters[512] = {0}; // 额外的过滤模式
    char monitor_dir[MAX_PATH_LEN] = {0};
    
    // 长选项定义
    static struct option long_options[] = {
        {"recursive",    no_argument,       0, 'r'},
        {"no-recursive", no_argument,       0, 'n'},
        {"verbose",      no_argument,       0, 'v'},
        {"quiet",        no_argument,       0, 'q'},
        {"stats",        optional_argument, 0, 'S'},  // 使用大写 S 避免冲突
        {"filter",       required_argument, 0, 'f'},
        {"no-colors",    no_argument,       0, 0},
        {"help",         no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    // 解析命令行选项
    int opt, option_index = 0;
    while ((opt = getopt_long(argc, argv, "rnvqS::f:h", long_options, &option_index)) != -1) {
        switch (opt) {
            case 'r':
                recursive = 1;
                break;
            case 'n':
                recursive = 0;
                break;
            case 'v':
                verbose = 1;  // watch 命令自己的 -v 选项也能生效
                break;
            case 'q':
                quiet = 1;
                break;
            case 'S': // 使用大写 S 避免冲突
                show_stats = 1;
                if (optarg) {
                    stats_interval = atoi(optarg);
                    if (stats_interval <= 0) stats_interval = 10;
                }
                break;
            case 'f':
                strncpy(extra_filters, optarg, sizeof(extra_filters) - 1);
                break;
            case 0:
                // 长选项处理
                if (strcmp(long_options[option_index].name, "no-colors") == 0) {
                    // no_colors = 1; // This line was removed as per the edit hint.
                }
                break;
            case 'h':
                print_watch_usage(argv[0]);
                return 0;
            default:
                fprintf(stderr, "使用 '%s watch --help' 查看帮助信息\n", argv[0]);
                return 1;
        }
    }
    
    // 获取监控目录
    // 注意：main.c 只传递位置参数，选项已经被 main.c 处理了
    // 所以 argv[0] 就是第一个位置参数（目录）
    const char *arg_dir = (argc > 0) ? argv[0] : NULL;
    if (get_effective_monitor_dir(arg_dir, config, monitor_dir, sizeof(monitor_dir)) != 0) {
        fprintf(stderr, "错误: 无法确定监控目录\n");
        return 1;
    }
    
    // 检查目录是否存在
    struct stat st;
    if (stat(monitor_dir, &st) != 0) {
        fprintf(stderr, "错误: 监控目录不存在: %s\n", monitor_dir);
        return 1;
    }
    if (!S_ISDIR(st.st_mode)) {
        fprintf(stderr, "错误: 指定路径不是目录: %s\n", monitor_dir);
        return 1;
    }
    
    // 创建监控配置
    watch_config_t *watch_config = create_watch_config_from_snapshot(config, monitor_dir);
    if (!watch_config) {
        fprintf(stderr, "错误: 无法创建监控配置\n");
        return 1;
    }
    
    // 应用命令行选项
    watch_config->recursive = recursive;
    watch_config->verbose = verbose && !quiet;
    watch_config->show_stats = show_stats;
    watch_config->stats_interval = stats_interval;
    
    // 合并额外的过滤模式
    if (strlen(extra_filters) > 0) {
        size_t current_len = strlen(watch_config->ignore_patterns);
        if (current_len > 0 && watch_config->ignore_patterns[current_len - 1] != ',') {
            strncat(watch_config->ignore_patterns, ",", 
                    sizeof(watch_config->ignore_patterns) - current_len - 1);
        }
        strncat(watch_config->ignore_patterns, extra_filters,
                sizeof(watch_config->ignore_patterns) - strlen(watch_config->ignore_patterns) - 1);
    }
    
    // 显示启动信息
    printf("🚀 文件监控启动\n");
    printf("=================\n");
    printf("监控目录: %s\n", monitor_dir);
    printf("平台支持: %s\n", file_monitor_get_platform_name());
    printf("递归监控: %s\n", recursive ? "是" : "否");
    printf("详细输出: %s (全局:%s, 局部:%s)\n", 
           watch_config->verbose ? "是" : "否",
           config->verbose ? "是" : "否",
           verbose ? "是" : "否");
    printf("显示统计: %s", show_stats ? "是" : "否");
    if (show_stats) {
        printf(" (每 %d 秒)", stats_interval);
    }
    printf("\n");
    if (strlen(watch_config->ignore_patterns) > 0) {
        printf("忽略规则: %s\n", watch_config->ignore_patterns);
    }
    printf("\n");
    
    // 创建统计结构
    watch_stats_t stats = {0};
    
    // 开始监控
    int result = file_monitor_start(watch_config, &stats);
    
    // 显示最终统计
    if (result == 0) {
        uint64_t total_events = stats.created_count + stats.modified_count + 
                               stats.deleted_count + stats.moved_count;
        uint64_t duration_ms = get_current_timestamp_ms() - stats.start_time;
        
        printf("\n📊 监控统计\n");
        printf("===========\n");
        printf("运行时间: %.1f 秒\n", duration_ms / 1000.0);
        printf("新增文件: %llu\n", stats.created_count);
        printf("修改文件: %llu\n", stats.modified_count);
        printf("删除文件: %llu\n", stats.deleted_count);
        printf("移动文件: %llu\n", stats.moved_count);
        printf("总事件数: %llu\n", total_events);
        
        if (duration_ms > 0 && total_events > 0) {
            printf("事件频率: %.1f 事件/秒\n", (double)total_events * 1000.0 / duration_ms);
        }
    }
    
    // 清理
    destroy_watch_config(watch_config);
    
    return result;
} 