#ifndef WATCH_H
#define WATCH_H

#include "snapshot_core.h"
#include "file_monitor.h"

/**
 * @brief watch 命令的主入口函数
 * @param argc 参数数量
 * @param argv 参数数组
 * @param config 快照配置
 * @return 0成功，非0失败
 */
int cmd_watch(int argc, char *argv[], const snapshot_config_t *config);

/**
 * @brief 显示 watch 命令的帮助信息
 * @param program_name 程序名称
 */
void print_watch_usage(const char *program_name);

/**
 * @brief 从快照配置创建监控配置
 * @param snap_config 快照配置
 * @param monitor_dir 监控目录
 * @return 监控配置指针，需要调用者释放
 */
watch_config_t* create_watch_config_from_snapshot(const snapshot_config_t *snap_config, 
                                                  const char *monitor_dir);

#endif // WATCH_H 