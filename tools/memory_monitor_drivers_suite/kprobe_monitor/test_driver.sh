#!/bin/bash

# Kprobe 内存监控驱动测试脚本
# 支持 ARM32, ARM64, x86, x86_64 架构
# 作者: OpenWrt Tools Project

set -e

# 配置变量
DRIVER_NAME="kprobe_monitor"
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
    echo "时间: $(date)" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

# 检查内核配置
check_kernel_config() {
    log_info "=== 检查内核配置 ==="
    
    local config_found=0
    local config_file=""
    
    # 查找内核配置文件
    if [[ -f "/proc/config.gz" ]]; then
        config_file="/proc/config.gz"
        config_found=1
    elif [[ -f "/boot/config-$(uname -r)" ]]; then
        config_file="/boot/config-$(uname -r)"
        config_found=1
    fi
    
    if [[ $config_found -eq 1 ]]; then
        log_info "找到内核配置文件: $config_file"
        
        # 检查关键配置选项
        local configs=("CONFIG_KPROBES" "CONFIG_KRETPROBES" "CONFIG_KALLSYMS" "CONFIG_STACKTRACE")
        
        for config in "${configs[@]}"; do
            if [[ "$config_file" == "/proc/config.gz" ]]; then
                if zcat "$config_file" | grep -q "^${config}=y"; then
                    log_success "$config: 已启用"
                else
                    log_warning "$config: 未启用"
                fi
            else
                if grep -q "^${config}=y" "$config_file"; then
                    log_success "$config: 已启用"
                else
                    log_warning "$config: 未启用"
                fi
            fi
        done
    else
        log_warning "未找到内核配置文件"
    fi
    
    # 检查运行时支持
    if [[ -f "/proc/kallsyms" ]]; then
        log_success "kallsyms: 可用"
        local symbol_count=$(wc -l < /proc/kallsyms)
        log_info "可用符号数量: $symbol_count"
    else
        log_error "kallsyms: 不可用"
    fi
    
    echo "" | tee -a "$LOG_FILE"
}

# 编译驱动
compile_driver() {
    log_info "编译 Kprobe 监控驱动..."
    
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
    log_info "加载 Kprobe 监控驱动..."
    
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
    log_info "卸载 Kprobe 监控驱动..."
    
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

# 查找可用符号
find_available_symbols() {
    log_info "=== 查找可用符号 ==="
    
    if [[ ! -f "/proc/kallsyms" ]]; then
        log_error "kallsyms 不可用"
        return 1
    fi
    
    # 常用内存相关符号
    local symbols=("sys_mmap" "sys_munmap" "sys_brk" "do_mmap" "do_munmap" "vmalloc" "vfree" "kmalloc" "kfree")
    local available_symbols=()
    
    for symbol in "${symbols[@]}"; do
        if grep -q "\b${symbol}\b" /proc/kallsyms; then
            available_symbols+=("$symbol")
            log_success "符号可用: $symbol"
        else
            log_warning "符号不可用: $symbol"
        fi
    done
    
    echo "可用符号总数: ${#available_symbols[@]}" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # 返回第一个可用符号用于测试
    if [[ ${#available_symbols[@]} -gt 0 ]]; then
        echo "${available_symbols[0]}"
    else
        echo ""
    fi
}

# 测试基本功能
test_basic_functionality() {
    log_info "=== 测试基本功能 ==="
    
    if ! check_proc_file; then
        log_error "proc文件不存在，跳过测试"
        return 1
    fi
    
    # 查找可用符号
    local test_symbol=$(find_available_symbols)
    if [[ -z "$test_symbol" ]]; then
        log_error "没有找到可用的测试符号"
        return 1
    fi
    
    log_info "使用符号进行测试: $test_symbol"
    
    # 测试添加监控点
    log_info "测试添加监控点..."
    echo "add test_monitor $test_symbol 0" > "$PROC_FILE"
    sleep 0.5
    
    # 验证监控点是否添加成功
    if grep -q "test_monitor" "$PROC_FILE"; then
        log_success "监控点添加成功"
    else
        log_warning "监控点添加可能失败"
    fi
    
    # 测试列出符号
    log_info "测试列出符号功能..."
    echo "list_symbols" > "$PROC_FILE"
    sleep 0.5
    
    # 测试清除统计
    log_info "测试清除统计..."
    echo "clear_stats" > "$PROC_FILE"
    sleep 0.5
    
    # 测试删除监控点
    log_info "测试删除监控点..."
    echo "del test_monitor" > "$PROC_FILE"
    sleep 0.5
    
    log_success "基本功能测试完成"
}

# 测试进程过滤
test_process_filtering() {
    log_info "=== 测试进程过滤功能 ==="
    
    if ! check_proc_file; then
        log_error "proc文件不存在，跳过测试"
        return 1
    fi
    
    # 查找可用符号
    local test_symbol=$(find_available_symbols)
    if [[ -z "$test_symbol" ]]; then
        log_error "没有找到可用的测试符号"
        return 1
    fi
    
    # 测试PID过滤
    log_info "测试PID过滤..."
    local current_pid=$$
    echo "add pid_test $test_symbol 0 0 $current_pid" > "$PROC_FILE" 2>/dev/null || true
    sleep 0.5
    
    # 测试进程名过滤
    log_info "测试进程名过滤..."
    echo "add comm_test $test_symbol 0 0 0 bash" > "$PROC_FILE" 2>/dev/null || true
    sleep 0.5
    
    # 清理测试监控点
    echo "del pid_test" > "$PROC_FILE" 2>/dev/null || true
    echo "del comm_test" > "$PROC_FILE" 2>/dev/null || true
    
    log_success "进程过滤测试完成"
}

# 测试返回探针
test_kretprobe() {
    log_info "=== 测试返回探针功能 ==="
    
    if ! check_proc_file; then
        log_error "proc文件不存在，跳过测试"
        return 1
    fi
    
    # 查找可用符号
    local test_symbol=$(find_available_symbols)
    if [[ -z "$test_symbol" ]]; then
        log_error "没有找到可用的测试符号"
        return 1
    fi
    
    # 测试返回探针
    log_info "测试kretprobe..."
    echo "add kret_test $test_symbol 0 1" > "$PROC_FILE" 2>/dev/null || true
    sleep 0.5
    
    # 清理测试监控点
    echo "del kret_test" > "$PROC_FILE" 2>/dev/null || true
    
    log_success "返回探针测试完成"
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
    
    # 测试无效符号
    log_info "测试无效符号..."
    echo "add bad_symbol non_existent_symbol 0" > "$PROC_FILE" 2>/dev/null || log_info "无效符号正确被拒绝"
    
    # 测试无效类型
    log_info "测试无效类型..."
    echo "add bad_type sys_mmap 99" > "$PROC_FILE" 2>/dev/null || log_info "无效类型正确被拒绝"
    
    # 测试参数不足
    log_info "测试参数不足..."
    echo "add" > "$PROC_FILE" 2>/dev/null || log_info "参数不足正确被拒绝"
    
    log_success "错误处理测试完成"
}

# 触发监控测试
trigger_monitor_test() {
    log_info "=== 触发监控测试 ==="
    
    if ! check_proc_file; then
        log_error "proc文件不存在，跳过测试"
        return 1
    fi
    
    # 查找可用符号
    local test_symbol=$(find_available_symbols)
    if [[ -z "$test_symbol" ]]; then
        log_error "没有找到可用的测试符号"
        return 1
    fi
    
    log_info "设置监控点: $test_symbol"
    echo "add trigger_test $test_symbol 0" > "$PROC_FILE" 2>/dev/null || true
    sleep 1
    
    # 尝试触发监控的操作
    log_info "执行可能触发监控的操作..."
    
    case "$test_symbol" in
        "sys_mmap"|"do_mmap"|"vm_mmap_pgoff")
            # 创建一些内存映射来触发 mmap 相关调用
            dd if=/dev/zero of=/tmp/kprobe_test_file bs=1M count=1 2>/dev/null || true
            rm -f /tmp/kprobe_test_file
            ;;
        "vmalloc"|"vfree")
            # 这些是内核函数，用户空间难以直接触发
            log_info "内核函数 $test_symbol 需要其他内核模块触发"
            ;;
        *)
            # 执行一般性操作
            echo "test" > /tmp/kprobe_trigger_test
            cat /tmp/kprobe_trigger_test > /dev/null
            rm -f /tmp/kprobe_trigger_test
            ;;
    esac
    
    sleep 2
    
    # 检查是否有监控命中
    if grep -q "命中:" "$PROC_FILE"; then
        log_success "监控被触发"
        grep "命中:" "$PROC_FILE" | tee -a "$LOG_FILE"
    else
        log_warning "监控未被触发（这是正常的，取决于操作和符号）"
    fi
    
    # 清理监控点
    echo "del trigger_test" > "$PROC_FILE" 2>/dev/null || true
    
    log_success "触发监控测试完成"
}

# 性能测试
test_performance() {
    log_info "=== 性能测试 ==="
    
    if ! check_proc_file; then
        log_error "proc文件不存在，跳过测试"
        return 1
    fi
    
    # 查找可用符号
    local test_symbol=$(find_available_symbols)
    if [[ -z "$test_symbol" ]]; then
        log_error "没有找到可用的测试符号"
        return 1
    fi
    
    log_info "性能测试: 快速添加和删除监控点"
    
    local start_time=$(date +%s.%N)
    
    # 快速添加和删除多个监控点
    for i in {1..10}; do
        echo "add perf_test_$i $test_symbol 0" > "$PROC_FILE" 2>/dev/null || true
        echo "del perf_test_$i" > "$PROC_FILE" 2>/dev/null || true
    done
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "N/A")
    
    log_info "20次操作耗时: ${duration}秒"
    log_success "性能测试完成"
}

# 内存测试
test_memory() {
    log_info "=== 内存测试 ==="
    
    # 检查内存使用
    local mem_before=$(cat /proc/meminfo | grep MemAvailable | awk '{print $2}')
    log_info "测试前可用内存: ${mem_before} kB"
    
    # 进行一些操作
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
            # 检查ARM32特定符号
            if grep -q "sys_mmap2" /proc/kallsyms; then
                log_success "ARM32 sys_mmap2 符号可用"
            fi
            ;;
        "aarch64"|"arm64")
            log_info "ARM64 架构特定测试..."
            # 检查ARM64特定符号
            if grep -q "compat_sys_mmap" /proc/kallsyms; then
                log_success "ARM64 compat_sys_mmap 符号可用"
            fi
            ;;
        "i386"|"i686")
            log_info "x86 架构特定测试..."
            # 检查x86特定符号
            if grep -q "sys_mmap2" /proc/kallsyms; then
                log_success "x86 sys_mmap2 符号可用"
            fi
            ;;
        "x86_64")
            log_info "x86_64 架构特定测试..."
            # 检查x86_64特定符号
            if grep -q "sys_mmap" /proc/kallsyms; then
                log_success "x86_64 sys_mmap 符号可用"
            fi
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
    
    log_info "最近的 Kprobe 监控相关日志:"
    dmesg | grep -i "$DRIVER_NAME" | tail -20 | tee -a "$LOG_FILE" || log_info "无相关日志"
    
    log_info "检查是否有错误信息:"
    dmesg | grep -i "error\|warning\|failed" | grep -i "$DRIVER_NAME" | tail -10 | tee -a "$LOG_FILE" || log_info "无错误日志"
}

# 生成测试报告
generate_report() {
    log_info "=== 生成测试报告 ==="
    
    local report_file="kprobe_monitor_test_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "Kprobe 内存监控驱动测试报告"
        echo "=========================="
        echo "测试时间: $(date)"
        echo "系统架构: $ARCH"
        echo "内核版本: $KERNEL_VER"
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
    
    # 尝试清理所有测试监控点
    if check_proc_file; then
        echo "clear_stats" > "$PROC_FILE" 2>/dev/null || true
        for name in test_monitor pid_test comm_test kret_test trigger_test; do
            echo "del $name" > "$PROC_FILE" 2>/dev/null || true
        done
    fi
    
    # 尝试卸载驱动
    if check_driver_loaded; then
        unload_driver || true
    fi
    
    log_info "清理完成"
}

# 主测试函数
run_all_tests() {
    log_info "开始 Kprobe 内存监控驱动完整测试"
    log_info "======================================"
    
    # 系统信息
    show_system_info
    
    # 内核配置检查
    check_kernel_config
    
    # 编译和加载
    compile_driver
    load_driver
    
    # 显示状态
    show_driver_status
    show_driver_info
    
    # 功能测试
    test_basic_functionality
    test_process_filtering
    test_kretprobe
    test_error_handling
    
    # 监控测试
    trigger_monitor_test
    
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
    echo "Kprobe 内存监控驱动测试脚本"
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
    echo "  config        - 检查内核配置"
    echo "  symbols       - 查找可用符号"
    echo "  basic         - 基本功能测试"
    echo "  process       - 进程过滤测试"
    echo "  kretprobe     - 返回探针测试"
    echo "  error         - 错误处理测试"
    echo "  trigger       - 触发监控测试"
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
    echo "  $0 config      # 检查内核配置"
    echo "  $0 symbols     # 查找可用符号"
}

# 主程序
main() {
    # 检查root权限
    check_root
    
    # 初始化日志文件
    echo "Kprobe 内存监控驱动测试 - $(date)" > "$LOG_FILE"
    
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
        "config")
            check_kernel_config
            ;;
        "symbols")
            find_available_symbols > /dev/null
            ;;
        "basic")
            test_basic_functionality
            ;;
        "process")
            test_process_filtering
            ;;
        "kretprobe")
            test_kretprobe
            ;;
        "error")
            test_error_handling
            ;;
        "trigger")
            trigger_monitor_test
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