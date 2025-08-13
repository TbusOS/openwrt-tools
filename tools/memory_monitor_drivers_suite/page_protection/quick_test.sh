#!/bin/bash

# 页面保护驱动运行时测试脚本
# 假设驱动已经加载，直接测试功能

set -e

DRIVER_NAME="page_monitor"
PROC_FILE="/proc/page_monitor"
LOG_FILE="/tmp/page_monitor_test.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# 检查驱动是否已加载
check_driver_loaded() {
    if ! lsmod | grep -q "$DRIVER_NAME"; then
        log_error "驱动 $DRIVER_NAME 未加载"
        log_info "请先加载驱动: sudo insmod page_monitor.ko"
        exit 1
    fi
    log_success "驱动已加载: $DRIVER_NAME"
}

# 检查proc接口是否可用
check_proc_interface() {
    if [ ! -e "$PROC_FILE" ]; then
        log_error "proc接口不存在: $PROC_FILE"
        log_info "请确认驱动已正确加载"
        exit 1
    fi
    
    if [ ! -r "$PROC_FILE" ] || [ ! -w "$PROC_FILE" ]; then
        log_error "proc接口权限不足: $PROC_FILE"
        log_info "请使用root权限运行"
        exit 1
    fi
    
    log_success "proc接口可用: $PROC_FILE"
}

# 显示系统信息
show_system_info() {
    log_info "=== 系统信息 ==="
    echo "内核版本: $(uname -r)" | tee -a "$LOG_FILE"
    echo "架构: $(uname -m)" | tee -a "$LOG_FILE"
    echo "系统: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo 'Unknown')" | tee -a "$LOG_FILE"
    echo "时间: $(date)" | tee -a "$LOG_FILE"
    echo "测试日志: $LOG_FILE" | tee -a "$LOG_FILE"
}

# 显示驱动状态
show_driver_status() {
    log_info "=== 驱动状态检查 ==="
    
    # 显示模块信息
    log_info "模块信息:"
    lsmod | grep "$DRIVER_NAME" | tee -a "$LOG_FILE"
    
    # 显示最近的驱动日志
    log_info "最近的驱动日志:"
    dmesg | tail -20 | grep -E "(page_monitor|内核兼容性|页面保护)" | tail -5 | tee -a "$LOG_FILE" || log_info "无相关日志"
}

# 基础功能测试
basic_test() {
    log_info "=== 基础功能测试 ==="
    
    # 读取驱动状态
    log_info "读取驱动状态..."
    cat "$PROC_FILE" | tee -a "$LOG_FILE"
    
    # 测试监控功能
    log_info "启动测试内存监控..."
    echo "monitor test_memory" > "$PROC_FILE"
    
    log_info "读取测试内存..."
    echo "read 0" > "$PROC_FILE"
    
    log_info "写入测试数据..."
    echo "write 0 Hello_Test_$(date +%s)" > "$PROC_FILE"
    
    # 检查监控日志
    log_info "监控检测日志:"
    dmesg | tail -20 | grep -E "(页面访问检测|故障地址|命中次数|访问类型)" | tee -a "$LOG_FILE"
    
    # 停止监控
    log_info "停止监控..."
    echo "stop test_memory" > "$PROC_FILE"
    
    log_success "基础功能测试完成"
}

# 压力测试
stress_test() {
    log_info "=== 压力测试 ==="
    
    # 启动监控
    echo "monitor test_memory" > "$PROC_FILE"
    
    # 快速连续访问
    log_info "执行快速连续访问测试..."
    for i in {1..5}; do
        echo "write 0 stress_test_$i" > "$PROC_FILE"
        usleep 100000  # 100ms延迟
    done
    
    # 检查命中统计
    log_info "命中统计:"
    dmesg | tail -20 | grep "命中次数" | tail -3 | tee -a "$LOG_FILE"
    
    # 停止监控
    echo "stop test_memory" > "$PROC_FILE"
    
    log_success "压力测试完成"
}

# 错误处理测试
error_test() {
    log_info "=== 错误处理测试 ==="
    
    # 测试无效命令
    log_info "测试无效命令处理..."
    echo "invalid_command_test" > "$PROC_FILE" 2>/dev/null || true
    
    # 测试无效参数
    echo "monitor" > "$PROC_FILE" 2>/dev/null || true
    
    log_info "错误处理日志:"
    dmesg | tail -10 | grep -E "(错误|失败|invalid)" | tee -a "$LOG_FILE" || log_info "无错误日志 (正常)"
    
    log_success "错误处理测试完成"
}

# 清理测试状态
cleanup_test() {
    log_info "=== 清理测试状态 ==="
    
    # 停止所有监控
    echo "stop test_memory" > "$PROC_FILE" 2>/dev/null || true
    
    # 显示最终状态
    log_info "最终驱动状态:"
    cat "$PROC_FILE" | head -10 | tee -a "$LOG_FILE"
    
    log_success "测试状态清理完成"
}

# 清理测试环境
cleanup() {
    log_info "=== 清理测试环境 ==="
    
    # 停止所有监控
    echo "stop test_memory" > "$PROC_FILE" 2>/dev/null || true
    
    log_success "清理完成"
}

# 主函数
main() {
    # 初始化日志文件
    echo "=== 页面保护驱动运行时测试开始 ===" > "$LOG_FILE"
    
    log_info "页面保护内存监控驱动运行时测试脚本"
    log_info "测试开始时间: $(date)"
    
    check_driver_loaded
    check_proc_interface
    show_system_info
    
    # 捕获中断信号，确保清理
    trap cleanup EXIT
    
    # 执行测试序列
    show_driver_status
    basic_test
    stress_test
    error_test
    cleanup_test
    
    log_success "=== 所有测试完成 ==="
    log_info "详细日志请查看: $LOG_FILE"
    
    # 显示测试摘要
    echo ""
    echo "=== 测试摘要 ==="
    echo "成功项目数量: $(grep -c "\[SUCCESS\]" "$LOG_FILE")"
    echo "警告项目数量: $(grep -c "\[WARNING\]" "$LOG_FILE")"
    echo "错误项目数量: $(grep -c "\[ERROR\]" "$LOG_FILE")"
    echo "测试日志: $LOG_FILE"
}

# 帮助信息
show_help() {
    echo "页面保护内存监控驱动运行时测试脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  -c, --cleanup  仅执行清理操作"
    echo ""
    echo "示例:"
    echo "  $0                # 执行完整测试"
    echo "  $0 --cleanup      # 仅清理环境"
    echo ""
    echo "注意:"
    echo "  1. 需要先手动加载驱动: sudo insmod page_monitor.ko"
    echo "  2. 需要root权限访问/proc/page_monitor"
    echo "  3. 测试过程大约需要30-60秒"
    echo "  4. 测试结束后驱动仍保持加载状态"
}

# 参数解析
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -c|--cleanup)
        cleanup
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "未知参数: $1"
        show_help
        exit 1
        ;;
esac
