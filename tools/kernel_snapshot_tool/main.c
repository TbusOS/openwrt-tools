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
#include <inttypes.h>

static void print_usage(const char *program_name) {
    printf("Git风格快照工具 - 零文件丢失设计\n\n");
    printf("🎯 Git风格用法 (推荐):\n");
    printf("  %s create <目标目录> [项目名]           在指定目录创建工作区和基线快照\n", program_name);
    printf("  %s create [项目名]                     在当前目录创建工作区和基线快照\n", program_name);
    printf("  %s status                             检查当前工作区状态 (相对于基线快照)\n", program_name);
    printf("  %s clean [force]                      清理配置文件中指定的工作目录快照数据\n", program_name);
    printf("  %s diff <旧快照> <新快照>             对比两个快照文件\n\n", program_name);
    printf("🔧 兼容模式 (旧版本支持):\n");
    printf("  %s create <目录> <快照文件>           创建指定快照文件\n", program_name);
    printf("  %s status <快照文件> <目录>           检查指定目录状态\n\n", program_name);
    
    printf("选项:\n");
    printf("  -t, --threads=N    使用N个线程处理文件内容 (默认: CPU核心数)\n");
    printf("  -v, --verbose      详细输出\n");
    printf("  -g, --git-hash     使用Git兼容的SHA1哈希\n");
    printf("  -e, --exclude=PAT  排除包含指定模式的文件\n");
    printf("  -h, --help         显示此帮助\n\n");
    
    printf("🚀 使用示例:\n");
    printf("  # 方式1: 直接指定目录路径\n");
    printf("  %s create /path/to/kernel/source linux-6.6  # 在指定目录创建工作区\n", program_name);
    printf("  %s status                                   # 检查状态\n", program_name);
    printf("  \n");
    printf("  # 方式2: 先切换到目录，再执行\n");
    printf("  cd /path/to/kernel/source                   # 切换到内核目录\n");
    printf("  %s create linux-6.6                        # 在当前目录创建工作区\n", program_name);
    printf("  # ... 修改、添加、删除文件 ...\n");
    printf("  %s status                                   # 查看变更\n", program_name);
    printf("  \n");
    printf("  # 方式3: 使用全局配置文件（推荐）\n");
    printf("  %s create                                   # 使用配置文件中的默认目录\n", program_name);
    printf("  %s status                                   # 快速状态检查\n", program_name);
    printf("  \n");
    printf("  # 清理和重新测试\n");
    printf("  %s clean                                    # 清理配置文件中指定目录的快照数据\n", program_name);
    printf("  %s clean force                             # 强制清理（无确认提示）\n\n", program_name);
    
    printf("📁 工作区概念:\n");
    printf("  工具会在目标目录创建 .snapshot/ 隐藏目录，包含:\n");
    printf("  - baseline.snapshot  (基线快照文件)\n");
    printf("  - workspace.conf     (工作区配置)\n");
    printf("  - index.cache        (索引缓存，用于快速状态检查)\n\n");
    
    printf("⚙️  全局配置文件:\n");
    printf("  配置文件名: .kernel_snapshot.conf\n");
    printf("  查找优先级:\n");
    printf("    1. 工具所在目录    (推荐位置)\n");
    printf("    2. 当前执行目录\n");
    printf("    3. 用户主目录\n");
    printf("  \n");
    printf("  配置文件格式:\n");
    printf("    # 默认工作目录（绝对路径）\n");
    printf("    default_workspace_dir=/path/to/your/project\n");
    printf("    # 默认项目名称\n");
    printf("    default_project_name=my-project\n");
    printf("    # 忽略文件模式（用逗号分隔）\n");
    printf("    ignore_patterns=.git,*.tmp,*.log,*.bak,node_modules\n\n");
    
    printf("🚫 文件忽略功能:\n");
    printf("  支持的模式:\n");
    printf("    *.tmp, *.log        # 后缀匹配\n");
    printf("    temp_*              # 前缀匹配  \n");
    printf("    .git, node_modules  # 精确匹配\n");
    printf("  默认忽略: .snapshot（其他忽略模式请配置在配置文件中）\n\n");
    
    printf("🎯 设计特点:\n");
    printf("  ✅ 绝对不丢失文件 - 单线程遍历确保完整性\n");
    printf("  🚀 高性能处理 - 多线程并行处理文件内容\n");
    printf("  ⚡ 智能索引缓存 - Git风格的快速状态检查\n");
    printf("  🔍 Git兼容性 - 支持Git风格的哈希和格式\n");
    printf("  📊 详细统计 - 完整的错误报告和性能指标\n");
    printf("  🎯 用户友好 - 支持全局配置，无需重复输入参数\n\n");
}

// 全局配置文件路径
#define GLOBAL_CONFIG_FILE ".kernel_snapshot.conf"

static int cmd_create(int argc, char *argv[], const snapshot_config_t *config) {
    const char *project_name = NULL;
    const char *dir_path = ".";  // 默认当前目录
    char *snapshot_path = NULL;
    
    // 读取全局配置文件
    workspace_config_t global_config = {0};
    char global_config_path[MAX_PATH_LEN];
    
    // 获取工具所在目录
    char tool_dir[MAX_PATH_LEN];
    char *argv0_copy = strdup(argv[0] ? argv[0] : "kernel_snapshot");
    char *tool_dir_end = strrchr(argv0_copy, '/');
    if (tool_dir_end) {
        *tool_dir_end = '\0';
        // 转换为绝对路径
        if (realpath(argv0_copy, tool_dir) == NULL) {
            strncpy(tool_dir, argv0_copy, MAX_PATH_LEN - 1);
            tool_dir[MAX_PATH_LEN - 1] = '\0';
        }
    } else {
        // 在PATH中查找或使用当前目录
        strncpy(tool_dir, ".", MAX_PATH_LEN - 1);
        tool_dir[MAX_PATH_LEN - 1] = '\0';
    }
    free(argv0_copy);
    
    // 首先尝试工具所在目录的配置文件
    snprintf(global_config_path, sizeof(global_config_path), "%s/%s", tool_dir, GLOBAL_CONFIG_FILE);
    int has_global_config = 0;
    
    if (access(global_config_path, R_OK) == 0) {
        FILE *fp = fopen(global_config_path, "r");
        if (fp) {
            printf("📖 读取全局配置文件: %s\n", global_config_path);
            load_global_config(fp, &global_config);
            fclose(fp);
            has_global_config = 1;
        }
    } else {
        // 尝试当前目录的配置文件
        snprintf(global_config_path, sizeof(global_config_path), "./%s", GLOBAL_CONFIG_FILE);
        if (access(global_config_path, R_OK) == 0) {
            FILE *fp = fopen(global_config_path, "r");
            if (fp) {
                printf("📖 读取全局配置文件: %s\n", global_config_path);
                load_global_config(fp, &global_config);
                fclose(fp);
                has_global_config = 1;
            }
        } else {
            // 最后尝试用户主目录的配置文件
            const char *home = getenv("HOME");
            if (home) {
                snprintf(global_config_path, sizeof(global_config_path), "%s/%s", home, GLOBAL_CONFIG_FILE);
                if (access(global_config_path, R_OK) == 0) {
                    FILE *fp = fopen(global_config_path, "r");
                    if (fp) {
                        printf("📖 读取全局配置文件: %s\n", global_config_path);
                        load_global_config(fp, &global_config);
                        fclose(fp);
                        has_global_config = 1;
                    }
                }
            }
        }
    }
    
    // 应用全局配置中的默认工作目录和项目名
    if (has_global_config && strlen(global_config.workspace_dir) > 0) {
        dir_path = global_config.workspace_dir;
        printf("🔧 使用全局配置的默认工作目录: %s\n", dir_path);
    }
    
    if (has_global_config && strlen(global_config.project_name) > 0 && !project_name) {
        project_name = global_config.project_name;
        printf("🔧 使用全局配置的默认项目名: %s\n", project_name);
    }
    
    // 命令行参数可以覆盖全局配置
    // 新的使用方式: ./kernel_snapshot create <target_dir> [project_name]
    if (argc == 0) {
        // 无参数，如果没有全局配置，使用当前目录
        if (!has_global_config || strlen(global_config.workspace_dir) == 0) {
            dir_path = ".";
        }
        
        // 如果没有项目名，从目录名提取
        if (!project_name) {
            char *cwd = getcwd(NULL, 0);
            if (cwd) {
                char *basename = strrchr(dir_path, '/');
                project_name = basename ? basename + 1 : (strcmp(dir_path, ".") == 0 ? 
                              (strrchr(cwd, '/') ? strrchr(cwd, '/') + 1 : cwd) : dir_path);
                free(cwd);
            } else {
                project_name = "unnamed";
            }
        }
    } else if (argc == 1) {
        // 一个参数，可能是目录路径或项目名
        struct stat st;
        if (stat(argv[0], &st) == 0 && S_ISDIR(st.st_mode)) {
            // 参数是一个存在的目录，使用该目录
            dir_path = argv[0];
            // 从目录路径提取项目名
            char *basename = strrchr(argv[0], '/');
            project_name = basename ? basename + 1 : argv[0];
        } else {
            // 参数作为项目名，使用当前目录
            project_name = argv[0];
            dir_path = ".";
        }
    } else if (argc == 2) {
        // 两个参数，检查是否为新格式: <target_dir> <project_name>
        struct stat st;
        if (stat(argv[0], &st) == 0 && S_ISDIR(st.st_mode)) {
            // 第一个参数是目录，第二个参数是项目名
            dir_path = argv[0];
            project_name = argv[1];
        } else {
            // 兼容旧格式: ./kernel_snapshot create <dir> <snapshot_file>
            dir_path = argv[0];
            snapshot_path = argv[1];
        }
    } else {
        fprintf(stderr, "❌ 参数过多，请查看帮助信息\n");
        return 1;
    }
    
    // 新的工作区模式
    if (!snapshot_path) {
        // 初始化工作区（在目标目录内）
        if (init_workspace_in_dir(dir_path, project_name) != 0) {
            fprintf(stderr, "❌ 工作区初始化失败\n");
            return 1;
        }
        
        printf("🎯 初始化工作区: %s (目录: %s)\n", project_name, dir_path);
        
        // 获取工作区根目录的绝对路径
        char abs_dir_path[MAX_PATH_LEN];
        if (!realpath(dir_path, abs_dir_path)) {
            fprintf(stderr, "❌ 获取目录绝对路径失败: %s\n", dir_path);
            return 1;
        }
        
        snapshot_path = get_baseline_snapshot_path(abs_dir_path);
        if (!snapshot_path) {
            fprintf(stderr, "❌ 快照路径生成失败\n");
            return 1;
        }
    }
    
    // 检查目录是否存在
    if (access(dir_path, R_OK) != 0) {
        fprintf(stderr, "错误: 无法访问目录 %s\n", dir_path);
        return 1;
    }
    
    // 创建config的副本以便修改
    snapshot_config_t local_config = *config;
    
    // 应用全局配置的忽略模式
    if (has_global_config && strlen(global_config.ignore_patterns) > 0) {
        // 如果有全局配置的忽略模式，将其应用到local_config中
        local_config.exclude_patterns = strdup(global_config.ignore_patterns);
        printf("🚫 应用忽略模式: %s\n", local_config.exclude_patterns);
    }
    
    // 计算实际线程数并显示系统信息
    int actual_thread_count = local_config.thread_count > 0 ? local_config.thread_count : sysconf(_SC_NPROCESSORS_ONLN);
    show_system_info(actual_thread_count);
    
    if (local_config.show_progress) {
        printf("🔍 开始创建基线快照: %s\n", dir_path);
    } else {
        printf("🔍 开始创建基线快照: %s\n", dir_path);
    }
    
    snapshot_result_t result;
    int ret = git_snapshot_create(dir_path, snapshot_path, &local_config, &result);
    
    if (ret == 0) {
        if (local_config.show_progress) {
            // 使用简洁的进度条总结
            printf("\n✅ 快照创建完成!\n");
            printf("📊 处理摘要: %"PRIu64"/%"PRIu64" 文件 (%.1f%%), 耗时: %"PRIu64" ms\n",
                   result.processed_files, result.total_files,
                   result.total_files > 0 ? (double)result.processed_files * 100.0 / result.total_files : 0,
                   result.elapsed_ms);
        } else {
            // 传统详细输出
            printf("✅ 快照创建成功!\n");
            printf("📊 统计信息:\n");
            printf("   扫描文件: %"PRIu64"\n", result.total_files);
            printf("   成功处理: %"PRIu64"\n", result.processed_files);
            printf("   失败文件: %"PRIu64"\n", result.failed_files);
            printf("   文件完整率: %.2f%%\n", 
                   result.total_files > 0 ? 
                   (double)result.processed_files * 100.0 / result.total_files : 0);
            printf("   处理速度: %.1f 文件/秒\n",
                   result.elapsed_ms > 0 ? 
                   (double)result.processed_files * 1000.0 / result.elapsed_ms : 0);
            printf("   总耗时: %"PRIu64" 毫秒\n", result.elapsed_ms);
        }
        
        // 创建索引缓存以优化后续status命令性能
        char abs_dir_path[MAX_PATH_LEN];
        if (realpath(dir_path, abs_dir_path)) {
            const char *actual_snapshot_path = snapshot_path ? snapshot_path : get_baseline_snapshot_path(abs_dir_path);
            if (actual_snapshot_path) {
                create_index_during_snapshot(abs_dir_path, actual_snapshot_path, &local_config);
            }
        }
        
        // 更新全局配置文件（如果命令行指定了新的目录）
        if (argc > 0) {
            // 检查是否需要更新全局配置
            char abs_new_dir[MAX_PATH_LEN];
            if (realpath(dir_path, abs_new_dir)) {
                int should_update = 0;
                
                // 如果全局配置中没有工作目录，或者指定了不同的目录
                if (!has_global_config || strlen(global_config.workspace_dir) == 0 ||
                    strcmp(global_config.workspace_dir, abs_new_dir) != 0) {
                    should_update = 1;
                    strncpy(global_config.workspace_dir, abs_new_dir, MAX_PATH_LEN - 1);
                    global_config.workspace_dir[MAX_PATH_LEN - 1] = '\0';
                }
                
                // 更新项目名
                if (project_name && (!has_global_config || strlen(global_config.project_name) == 0 ||
                    strcmp(global_config.project_name, project_name) != 0)) {
                    should_update = 1;
                    strncpy(global_config.project_name, project_name, MAX_PATH_LEN - 1);
                    global_config.project_name[MAX_PATH_LEN - 1] = '\0';
                }
                
                if (should_update) {
                    global_config.updated_time = time(NULL);
                    if (!has_global_config) {
                        global_config.created_time = global_config.updated_time;
                    }
                    
                    if (save_global_config(global_config_path, &global_config) == 0) {
                        printf("🔧 已更新全局配置文件: %s\n", global_config_path);
                    } else {
                        printf("⚠️  警告: 无法更新全局配置文件\n");
                    }
                }
            }
        }
        
        if (result.failed_files > 0) {
            printf("⚠️  警告: 有 %"PRIu64" 个文件处理失败\n", result.failed_files);
        }
    } else {
        printf("❌ 快照创建失败: %s\n", result.error_message);
    }
    
    return ret;
}

static int cmd_status(int argc, char *argv[], const snapshot_config_t *config) {
    const char *snapshot_path = NULL;
    const char *dir_path = ".";  // 默认当前目录
    
    // 新的使用方式: ./kernel_snapshot status (自动查找工作区)
    if (argc == 0) {
        // 先尝试读取全局配置
        workspace_config_t global_config = {0};
        char global_config_path[MAX_PATH_LEN];
        
        // 获取工具所在目录
        char tool_dir[MAX_PATH_LEN];
        char *argv0 = getenv("_") ? getenv("_") : "kernel_snapshot";
        char *argv0_copy = strdup(argv0);
        char *tool_dir_end = strrchr(argv0_copy, '/');
        if (tool_dir_end) {
            *tool_dir_end = '\0';
            if (realpath(argv0_copy, tool_dir) == NULL) {
                strncpy(tool_dir, argv0_copy, MAX_PATH_LEN - 1);
                tool_dir[MAX_PATH_LEN - 1] = '\0';
            }
        } else {
            strncpy(tool_dir, ".", MAX_PATH_LEN - 1);
            tool_dir[MAX_PATH_LEN - 1] = '\0';
        }
        free(argv0_copy);
        
        // 查找全局配置文件
        int has_global_config = 0;
        snprintf(global_config_path, sizeof(global_config_path), "%s/%s", tool_dir, GLOBAL_CONFIG_FILE);
        
        if (access(global_config_path, R_OK) == 0) {
            FILE *fp = fopen(global_config_path, "r");
            if (fp) {
                printf("📖 读取全局配置文件: %s\n", global_config_path);
                load_global_config(fp, &global_config);
                fclose(fp);
                has_global_config = 1;
            }
        } else {
            snprintf(global_config_path, sizeof(global_config_path), "./%s", GLOBAL_CONFIG_FILE);
            if (access(global_config_path, R_OK) == 0) {
                FILE *fp = fopen(global_config_path, "r");
                if (fp) {
                    printf("📖 读取全局配置文件: %s\n", global_config_path);
                    load_global_config(fp, &global_config);
                    fclose(fp);
                    has_global_config = 1;
                }
            } else {
                const char *home = getenv("HOME");
                if (home) {
                    snprintf(global_config_path, sizeof(global_config_path), "%s/%s", home, GLOBAL_CONFIG_FILE);
                    if (access(global_config_path, R_OK) == 0) {
                        FILE *fp = fopen(global_config_path, "r");
                        if (fp) {
                            printf("📖 读取全局配置文件: %s\n", global_config_path);
                            load_global_config(fp, &global_config);
                            fclose(fp);
                            has_global_config = 1;
                        }
                    }
                }
            }
        }
        
        // 确定工作区目录
        if (has_global_config && strlen(global_config.workspace_dir) > 0) {
            dir_path = global_config.workspace_dir;
            printf("🎯 使用配置文件中的工作目录: %s\n", dir_path);
        } else {
            printf("📂 未找到全局配置，在当前目录查找工作区\n");
        }
        
        // 查找工作区
        char *workspace_root = find_workspace_root(dir_path);
        if (!workspace_root) {
            fprintf(stderr, "❌ 在目录 %s 中未找到工作区，请先运行 'create' 命令初始化\n", dir_path);
            return 1;
        }
        
        snapshot_path = get_baseline_snapshot_path(workspace_root);
        dir_path = workspace_root;
        
        if (!snapshot_path) {
            fprintf(stderr, "❌ 基线快照不存在，请重新运行 'create' 命令\n");
            return 1;
        }
        
        // 构建包含忽略模式的配置
        static snapshot_config_t local_config;
        local_config = *config;
        if (has_global_config && strlen(global_config.ignore_patterns) > 0) {
            local_config.exclude_patterns = strdup(global_config.ignore_patterns);
        }
        config = &local_config;
    } else if (argc == 2) {
        // 兼容旧格式: ./kernel_snapshot status <snapshot_file> <dir>
        snapshot_path = argv[0];
        dir_path = argv[1];
    } else {
        fprintf(stderr, "错误: status命令参数格式错误\n");
        return 1;
    }
    
    if (argc == 0) {
        printf("🔍 检查工作区状态 (基于基线快照)\n");
        
        // 尝试使用快速索引缓存检查
        int ret = git_status_with_index(dir_path, config);
        if (ret == 0) {
            return 0;  // 索引缓存检查成功
        }
        
        // 索引缓存失败，降级到传统检查
        printf("\n⚠️  索引缓存不可用，使用传统状态检查...\n");
    } else {
        printf("🔍 检查目录状态: %s (基于快照 %s)\n", dir_path, snapshot_path);
    }
    
    // 传统的快照状态检查
    snapshot_result_t result;
    int ret = git_snapshot_status(snapshot_path, dir_path, config, &result);
    
    if (ret == 0) {
        printf("📊 状态统计:\n");
        printf("   新增文件: %"PRIu64"\n", result.added_files);
        printf("   修改文件: %"PRIu64"\n", result.modified_files);
        printf("   删除文件: %"PRIu64"\n", result.deleted_files);
        printf("   总变化: %"PRIu64"\n", 
               result.added_files + result.modified_files + result.deleted_files);
    } else {
        printf("❌ 状态检查失败: %s\n", result.error_message);
    }
    
    return ret;
}

static int cmd_clean(int argc, char *argv[], const snapshot_config_t *config) {
    (void)config;  // 暂时未使用
    
    int force = 0;
    
    // 解析参数 - 只需要检查force参数
    for (int i = 0; i < argc; i++) {
        if (strcmp(argv[i], "force") == 0) {
            force = 1;
        }
    }
    
    // 读取全局配置文件
    workspace_config_t global_config = {0};
    char global_config_path[MAX_PATH_LEN];
    
    // 获取工具所在目录
    char tool_dir[MAX_PATH_LEN];
    char *argv0 = getenv("_") ? getenv("_") : "kernel_snapshot";
    char *argv0_copy = strdup(argv0);
    char *tool_dir_end = strrchr(argv0_copy, '/');
    if (tool_dir_end) {
        *tool_dir_end = '\0';
        if (realpath(argv0_copy, tool_dir) == NULL) {
            strncpy(tool_dir, argv0_copy, MAX_PATH_LEN - 1);
            tool_dir[MAX_PATH_LEN - 1] = '\0';
        }
    } else {
        strncpy(tool_dir, ".", MAX_PATH_LEN - 1);
        tool_dir[MAX_PATH_LEN - 1] = '\0';
    }
    free(argv0_copy);
    
    // 查找全局配置文件
    int has_global_config = 0;
    snprintf(global_config_path, sizeof(global_config_path), "%s/%s", tool_dir, GLOBAL_CONFIG_FILE);
    
    if (access(global_config_path, R_OK) == 0) {
        FILE *fp = fopen(global_config_path, "r");
        if (fp) {
            printf("📖 读取全局配置文件: %s\n", global_config_path);
            load_global_config(fp, &global_config);
            fclose(fp);
            has_global_config = 1;
        }
    } else {
        snprintf(global_config_path, sizeof(global_config_path), "./%s", GLOBAL_CONFIG_FILE);
        if (access(global_config_path, R_OK) == 0) {
            FILE *fp = fopen(global_config_path, "r");
            if (fp) {
                printf("📖 读取全局配置文件: %s\n", global_config_path);
                load_global_config(fp, &global_config);
                fclose(fp);
                has_global_config = 1;
            }
        } else {
            const char *home = getenv("HOME");
            if (home) {
                snprintf(global_config_path, sizeof(global_config_path), "%s/%s", home, GLOBAL_CONFIG_FILE);
                if (access(global_config_path, R_OK) == 0) {
                    FILE *fp = fopen(global_config_path, "r");
                    if (fp) {
                        printf("📖 读取全局配置文件: %s\n", global_config_path);
                        load_global_config(fp, &global_config);
                        fclose(fp);
                        has_global_config = 1;
                    }
                }
            }
        }
    }
    
    // 确定目标目录
    const char *target_dir = ".";
    if (has_global_config && strlen(global_config.workspace_dir) > 0) {
        target_dir = global_config.workspace_dir;
        printf("🎯 使用配置文件中的工作目录: %s\n", target_dir);
    } else {
        printf("📂 未找到全局配置，使用当前目录: %s\n", target_dir);
    }
    
    // 构建快照目录路径
    char snapshot_dir[MAX_PATH_LEN];
    snprintf(snapshot_dir, sizeof(snapshot_dir), "%s/.snapshot", target_dir);
    
    // 检查快照目录是否存在
    if (access(snapshot_dir, F_OK) != 0) {
        printf("📂 目录 %s 中没有找到快照数据(.snapshot目录不存在)\n", target_dir);
        return 0;
    }
    
    // 显示将要清理的内容
    printf("🧹 准备清理快照数据\n");
    printf("========================\n");
    printf("📁 目标目录: %s\n", target_dir);
    printf("🗂️  快照目录: %s\n", snapshot_dir);
    
    // 列出快照目录内容
    printf("\n📋 将被删除的文件:\n");
    char ls_cmd[MAX_PATH_LEN + 20];
    snprintf(ls_cmd, sizeof(ls_cmd), "ls -la %s 2>/dev/null || echo '   (目录为空或无法访问)'", snapshot_dir);
    int ls_result = system(ls_cmd);
    (void)ls_result;  // ls失败不影响清理逻辑，但显式接收返回值避免警告
    
    // 确认删除（除非使用--force）
    if (!force) {
        printf("\n⚠️  警告: 这将永久删除所有快照数据!\n");
        printf("❓ 确定要继续吗? (y/N): ");
        fflush(stdout);
        
        char response[10];
        if (fgets(response, sizeof(response), stdin) == NULL ||
            (response[0] != 'y' && response[0] != 'Y')) {
            printf("❌ 用户取消操作\n");
            return 0;
        }
    }
    
    // 执行清理
    printf("🧹 正在清理快照数据...\n");
    
    // 使用rm -rf删除.snapshot目录
    char rm_cmd[MAX_PATH_LEN + 20];
    snprintf(rm_cmd, sizeof(rm_cmd), "rm -rf %s", snapshot_dir);
    
    int result = system(rm_cmd);
    if (result == 0) {
        printf("✅ 快照数据清理完成!\n");
        printf("📁 目录 %s 已恢复到初始状态\n", target_dir);
        printf("💡 现在可以重新运行 create 命令进行测试\n");
        return 0;
    } else {
        printf("❌ 清理失败 (退出码: %d)\n", result);
        printf("💡 请检查目录权限或手动删除: rm -rf %s\n", snapshot_dir);
        return 1;
    }
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
        printf("   新增文件: %"PRIu64"\n", result.added_files);
        printf("   修改文件: %"PRIu64"\n", result.modified_files);
        printf("   删除文件: %"PRIu64"\n", result.deleted_files);
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
        .streaming_mode = 1,
        .show_progress = 1   // 默认显示进度条
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
    } else if (strcmp(command, "clean") == 0) {
        return cmd_clean(cmd_argc, cmd_args, &config);
    } else {
        fprintf(stderr, "错误: 未知命令 '%s'\n\n", command);
        print_usage(argv[0]);
        return 1;
    }
}