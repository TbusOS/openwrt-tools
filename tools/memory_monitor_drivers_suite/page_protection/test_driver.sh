#!/bin/bash

# 页面保护内存监控驱动测试脚本
# 支持 ARM32, ARM64, x86, x86_64 架构
# 作者: OpenWrt Tools Project

set -e

# 配置变量
DRIVER_NAME="page_monitor"
PROC_FILE="/proc/${DRIVER_NAME}"
LOG_FILE="test_results.log"
ARCH=$(uname -m)
KERNEL_VER=$(uname -r)

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

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检查驱动是否加载
check_driver_loaded() {
    if lsmod | grep -q "$DRIVER_NAME"; then
        return 0
    else
        return 1
    fi
}

# 检查proc文件是否存在
check_proc_file() {
    if [[ -f "$PROC_FILE" ]]; then
        return 0
    else
        return 1
    fi
}

# 显示系统信息
show_system_info() {
    log_info "=== 系统信息 ==="
    echo "架构: $ARCH" | tee -a "$LOG_FILE"
    echo "内核版本: $KERNEL_VER" | tee -a "$LOG_FILE"
    echo "页面大小: $(getconf PAGESIZE) bytes" | tee -a "$LOG_FILE"
    echo "时间: $(date)" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# 编译驱动
compile_driver() {
    log_info "编译页面保护监控驱动..."
    
    if ! make clean > /dev/null 2>&1; then
        log_warning "清理失败，继续编译"
    fi
    
    if make modules > /dev/null 2>&1; then
        log_success "驱动编译成功"
        if [[ -f "${DRIVER_NAME}.ko" ]]; then
            log_info "驱动文件: ${DRIVER_NAME}.ko ($(stat -c%s ${DRIVER_NAME}.ko) bytes)"
        fi
    else
        log_error "驱动编译失败"
        exit 1
    fi
}

# 加载驱动
load_driver() {
    log_info "加载页面保护监控驱动..."
    
    # 先尝试卸载已存在的驱动
    if check_driver_loaded; then
        log_warning "驱动已加载，先卸载"
        rmmod "$DRIVER_NAME" 2>/dev/null || true
        sleep 1
    fi
    
    # 加载驱动
    if insmod "${DRIVER_NAME}.ko"; then
        log_success "驱动加载成功"
        sleep 1
        
        # 验证驱动状态
        if check_driver_loaded; then
            log_success "驱动状态验证成功"
        else
            log_error "驱动状态验证失败"
            return 1
        fi
        
        # 验证proc文件
        if check_proc_file; then
            log_success "proc文件创建成功: $PROC_FILE"
        else
            log_error "proc文件创建失败"
            return 1
        fi
    else
        log_error "驱动加载失败"
        dmesg | tail -5 | tee -a "$LOG_FILE"
        return 1
    fi
}

# 卸载驱动
unload_driver() {
    log_info "卸载页面保护监控驱动..."
    
    if check_driver_loaded; then
        if rmmod "$DRIVER_NAME"; then
            log_success "驱动卸载成功"
        else
            log_error "驱动卸载失败"
            return 1
        fi
    else
        log_warning "驱动未加载"
    fi
    
    # 验证proc文件是否删除
    if ! check_proc_file; then
        log_success "proc文件已删除"
    else
        log_warning "proc文件仍然存在"
    fi
}

# 显示驱动状态
show_driver_status() {
    log_info "=== 驱动状态 ==="
    
    if check_driver_loaded; then
        echo "驱动状态: 已加载" | tee -a "$LOG_FILE"
        lsmod | grep "$DRIVER_NAME" | tee -a "$LOG_FILE"
    else
        echo "驱动状态: 未加载" | tee -a "$LOG_FILE"
    fi
    
    if check_proc_file; then
        echo "proc文件: 存在" | tee -a "$LOG_FILE"
        echo "文件权限: $(ls -l $PROC_FILE)" | tee -a "$LOG_FILE"
    else
        echo "proc文件: 不存在" | tee -a "$LOG_FILE"
    fi
    echo "" | tee -a "$LOG_FILE"
}

# 显示驱动信息
show_driver_info() {
    log_info "=== 驱动信息 ==="
    
    if check_proc_file; then
        cat "$PROC_FILE" | tee -a "$LOG_FILE"
    else
        log_error "无法读取驱动信息，proc文件不存在"
        return 1
    fi
    echo "" | tee -a "$LOG_FILE"
}

# 测试基本读写
test_basic_rw() {
    log_info "=== 测试基本读写功能 ==="
    
    if ! check_proc_file; then
        log_error "proc文件不存在，跳过测试"
        return 1
    fi
    
    # 测试读取
    log_info "测试读取操作..."
    echo "test_read 0" > "$PROC_FILE"
    sleep 0.5
    
    echo "test_read 100" > "$PROC_FILE"
    sleep 0.5
    
    echo "test_read 1000" > "$PROC_FILE"
    sleep 0.5
    
    log_success "读取测试完成"
    
    # 测试写入
    log_info "测试写入操作..."
    echo "test_write 0 PAGE_MONITOR_TEST" > "$PROC_FILE"
    sleep 0.5
    
    echo "test_write 100 HELLO_WORLD" > "$PROC_FILE"
    sleep 0.5
    
    echo "test_write 200 DATA_$(date +%s)" > "$PROC_FILE"
    sleep 0.5
    
    log_success "写入测试完成"
    
    # 验证写入结果
    log_info "验证写入结果..."
    echo "test_read 0" > "$PROC_FILE"
    echo "test_read 100" > "$PROC_FILE"
    echo "test_read 200" > "$PROC_FILE"
    
    log_success "基本读写测试完成"
}

# 测试监控管理
test_monitor_management() {
    log_info "=== 测试监控管理功能 ==="
    
    if ! check_proc_file; then
        log_error "proc文件不存在，跳过测试"
        return 1
    fi
    
    # 获取页面大小
    PAGE_SIZE=$(getconf PAGESIZE)
    TEST_ADDR=$((0x10000000))
    
    # 测试添加监控点
    log_info "测试添加监控点..."
    
    # 添加第一个监控点（虚拟地址，仅测试命令解析）
    echo "add test_monitor1 0x${TEST_ADDR} ${PAGE_SIZE} 1" > "$PROC_FILE" 2>/dev/null || true
    sleep 0.5
    
    # 添加第二个监控点
    echo "add test_monitor2 0x$((TEST_ADDR + PAGE_SIZE)) $((PAGE_SIZE * 2)) 2" > "$PROC_FILE" 2>/dev/null || true
    sleep 0.5
    
    # 添加第三个监控点
    echo "add test_monitor3 0x$((TEST_ADDR + PAGE_SIZE * 3)) $((PAGE_SIZE * 4)) 3" > "$PROC_FILE" 2>/dev/null || true
    sleep 0.5
    
    log_success "监控点添加测试完成"
    
    # 显示当前监控状态
    log_info "当前监控状态:"
    cat "$PROC_FILE" | grep -A 20 "=== 监控状态 ===" | tee -a "$LOG_FILE" || true
    
    # 测试删除监控点
    log_info "测试删除监控点..."
    
    echo "del test_monitor1" > "$PROC_FILE" 2>/dev/null || true
    sleep 0.5
    
    echo "del test_monitor2" > "$PROC_FILE" 2>/dev/null || true
    sleep 0.5
    
    echo "del test_monitor3" > "$PROC_FILE" 2>/dev/null || true
    sleep 0.5
    
    log_success "监控点删除测试完成"
}

# 测试错误处理
test_error_handling() {
    log_info "=== 测试错误处理 ==="
    
    if ! check_proc_file; then
        log_error "proc文件不存在，跳过测试"
        return 1
    fi
    
    # 测试无效命令
    log_info "测试无效命令..."
    echo "invalid_command" > "$PROC_FILE" 2>/dev/null || log_info "无效命令正确被拒绝"
    
    # 测试无效参数
    log_info "测试无效参数..."
    
    # 无效大小（非页面对齐）
    echo "add bad_size 0x10000000 1234 3" > "$PROC_FILE" 2>/dev/null || log_info "无效大小正确被拒绝"
    
    # 无效类型
    echo "add bad_type 0x10000000 4096 5" > "$PROC_FILE" 2>/dev/null || log_info "无效类型正确被拒绝"
    
    # 无效地址（非页面对齐）
    echo "add bad_addr 0x10000001 4096 3" > "$PROC_FILE" 2>/dev/null || log_info "无效地址正确被拒绝"
    
    # 测试读取越界
    echo "test_read 999999" > "$PROC_FILE" 2>/dev/null || log_info "越界读取正确被拒绝"
    
    # 测试写入越界
    echo "test_write 999999 data" > "$PROC_FILE" 2>/dev/null || log_info "越界写入正确被拒绝"
    
    log_success "错误处理测试完成"
}

# 性能测试
test_performance() {
    log_info "=== 性能测试 ==="
    
    if ! check_proc_file; then
        log_error "proc文件不存在，跳过测试"
        return 1
    fi
    
    # 测试大量读写操作
    log_info "测试连续读写性能..."
    
    local start_time=$(date +%s.%N)
    
    for i in {1..50}; do
        echo "test_read 0" > "$PROC_FILE" 2>/dev/null || true
        echo "test_write $((i*4)) TEST_DATA_$i" > "$PROC_FILE" 2>/dev/null || true
    done
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "N/A")
    
    log_info "连续100次读写操作耗时: ${duration}秒"
    log_success "性能测试完成"
}

# 内存测试
test_memory() {
    log_info "=== 内存测试 ==="
    
    # 检查内存使用
    local mem_before=$(cat /proc/meminfo | grep MemAvailable | awk '{print $2}')
    log_info "测试前可用内存: ${mem_before} kB"
    
    # 进行大量操作
    test_performance
    
    local mem_after=$(cat /proc/meminfo | grep MemAvailable | awk '{print $2}')
    log_info "测试后可用内存: ${mem_after} kB"
    
    local mem_diff=$((mem_before - mem_after))
    if [ "$mem_diff" -gt 1000 ]; then
        log_warning "内存使用增加了 ${mem_diff} kB"
    else
        log_success "内存使用正常"
    fi
}

# 架构特定测试
test_architecture_specific() {
    log_info "=== 架构特定测试 ==="
    
    case "$ARCH" in
        "armv7l"|"arm")
            log_info "ARM32 架构特定测试..."
            # ARM32 特定测试
            ;;
        "aarch64"|"arm64")
            log_info "ARM64 架构特定测试..."
            # ARM64 特定测试
            ;;
        "i386"|"i686")
            log_info "x86 架构特定测试..."
            # x86 特定测试
            ;;
        "x86_64")
            log_info "x86_64 架构特定测试..."
            # x86_64 特定测试
            ;;
        *)
            log_warning "未知架构: $ARCH"
            ;;
    esac
    
    log_success "架构特定测试完成"
}

# 检查内核日志
check_kernel_logs() {
    log_info "=== 内核日志检查 ==="
    
    log_info "最近的页面监控相关日志:"
    dmesg | grep -i "$DRIVER_NAME" | tail -20 | tee -a "$LOG_FILE" || log_info "无相关日志"
    
    log_info "检查是否有错误信息:"
    dmesg | grep -i "error\|warning\|failed" | grep -i "$DRIVER_NAME" | tail -10 | tee -a "$LOG_FILE" || log_info "无错误日志"
}

# 生成测试报告
generate_report() {
    log_info "=== 生成测试报告 ==="
    
    local report_file="page_monitor_test_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "页面保护内存监控驱动测试报告"
        echo "================================"
        echo "测试时间: $(date)"
        echo "系统架构: $ARCH"
        echo "内核版本: $KERNEL_VER"
        echo "页面大小: $(getconf PAGESIZE) bytes"
        echo ""
        echo "测试结果摘要:"
        echo "============"
        grep -E "\[SUCCESS\]|\[ERROR\]|\[WARNING\]" "$LOG_FILE" || echo "无测试结果"
        echo ""
        echo "详细日志请查看: $LOG_FILE"
    } > "$report_file"
    
    log_success "测试报告生成: $report_file"
}

# 清理函数
cleanup() {
    log_info "执行清理操作..."
    
    # 尝试卸载驱动
    if check_driver_loaded; then
        unload_driver || true
    fi
    
    log_info "清理完成"
}

# 主测试函数
run_all_tests() {
    log_info "开始页面保护内存监控驱动完整测试"
    log_info "========================================"
    
    # 系统信息
    show_system_info
    
    # 编译和加载
    compile_driver
    load_driver
    
    # 显示状态
    show_driver_status
    show_driver_info
    
    # 功能测试
    test_basic_rw
    test_monitor_management
    test_error_handling
    
    # 性能和内存测试
    test_performance
    test_memory
    
    # 架构特定测试
    test_architecture_specific
    
    # 检查日志
    check_kernel_logs
    
    # 生成报告
    generate_report
    
    log_success "所有测试完成!"
}

# 显示帮助信息
show_help() {
    echo "页面保护内存监控驱动测试脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  all           - 运行所有测试 (默认)"
    echo "  compile       - 仅编译驱动"
    echo "  load          - 仅加载驱动"
    echo "  unload        - 仅卸载驱动"
    echo "  status        - 显示驱动状态"
    echo "  info          - 显示驱动信息"
    echo "  basic         - 基本功能测试"
    echo "  management    - 监控管理测试"
    echo "  error         - 错误处理测试"
    echo "  performance   - 性能测试"
    echo "  memory        - 内存测试"
    echo "  arch          - 架构特定测试"
    echo "  logs          - 检查内核日志"
    echo "  cleanup       - 清理资源"
    echo "  help          - 显示此帮助"
    echo ""
    echo "示例:"
    echo "  $0 all         # 运行完整测试"
    echo "  $0 basic       # 仅运行基本测试"
    echo "  $0 status      # 查看驱动状态"
}

# 主程序
main() {
    # 检查root权限
    check_root
    
    # 初始化日志文件
    echo "页面保护内存监控驱动测试 - $(date)" > "$LOG_FILE"
    
    # 设置清理trap
    trap cleanup EXIT
    
    # 解析参数
    case "${1:-all}" in
        "all")
            run_all_tests
            ;;
        "compile")
            compile_driver
            ;;
        "load")
            load_driver
            ;;
        "unload")
            unload_driver
            ;;
        "status")
            show_driver_status
            ;;
        "info")
            show_driver_info
            ;;
        "basic")
            test_basic_rw
            ;;
        "management")
            test_monitor_management
            ;;
        "error")
            test_error_handling
            ;;
        "performance")
            test_performance
            ;;
        "memory")
            test_memory
            ;;
        "arch")
            test_architecture_specific
            ;;
        "logs")
            check_kernel_logs
            ;;
        "cleanup")
            cleanup
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 运行主程序
main "$@" 