#!/bin/bash

# 跨平台内存监控驱动测试脚本
# 支持 ARM32 Cortex-A5 和 x86/x64 架构
# 作者: OpenWrt Tools Project
# 版本: 1.0.0

set -e  # 遇到错误时退出

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_NAME="memory_monitor"
LOG_FILE="$SCRIPT_DIR/test_results.log"
ARCH=$(uname -m)
OS=$(uname -s)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

log_test() {
    log "${PURPLE}[TEST]${NC} $1"
}

# 显示帮助信息
show_help() {
    cat << EOF
🧪 跨平台内存监控驱动测试脚本

用法: $0 [选项]

选项:
    -h, --help          显示此帮助信息
    -c, --compile-only  仅编译测试，不加载驱动
    -f, --full-test     完整测试 (编译+加载+功能+性能)
    -a, --arch ARCH     指定架构 (native, arm32, x86_64)
    -k, --kernel-dir    指定内核源码目录
    -v, --verbose       详细输出
    --no-color          禁用彩色输出
    --clean             清理编译文件并退出

示例:
    $0 -f                    # 完整测试
    $0 -c -a arm32          # 仅ARM32交叉编译测试
    $0 -a native -v         # 详细模式本地测试
    
支持的架构:
    - native: 本机架构 ($ARCH)
    - arm32:  ARM32 Cortex-A5
    - x86_64: x86_64

EOF
}

# 检查运行环境
check_environment() {
    log_info "检查运行环境..."
    
    log "系统信息: $OS $ARCH"
    log "脚本目录: $SCRIPT_DIR"
    log "当前用户: $(whoami)"
    log "内核版本: $(uname -r)"
    
    # 检查是否有sudo权限
    if ! sudo -n true 2>/dev/null; then
        log_warning "需要sudo权限来加载/卸载驱动模块"
        log "请确保当前用户在sudoers文件中，或者使用 sudo $0"
    fi
    
    # 检查必要工具
    local missing_tools=()
    
    for tool in make gcc file; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "缺少必要工具: ${missing_tools[*]}"
        log "请安装: sudo apt-get install build-essential"
        return 1
    fi
    
    log_success "环境检查通过"
}

# 编译测试
test_compilation() {
    local target_arch="${1:-native}"
    
    log_test "编译测试 - 架构: $target_arch"
    
    cd "$SCRIPT_DIR"
    
    # 清理之前的编译文件
    make clean >/dev/null 2>&1 || true
    
    case "$target_arch" in
        native)
            if make native; then
                log_success "本地编译成功"
                file "$MODULE_NAME.ko" | tee -a "$LOG_FILE"
                return 0
            else
                log_error "本地编译失败"
                return 1
            fi
            ;;
        arm32)
            log_info "检查ARM32交叉编译环境..."
            if ! command -v arm-linux-gnueabihf-gcc >/dev/null 2>&1; then
                log_warning "ARM32交叉编译器未找到"
                log "安装: sudo apt-get install gcc-arm-linux-gnueabihf"
                return 1
            fi
            
            if make arm32 2>/dev/null; then
                log_success "ARM32交叉编译成功"
                file "$MODULE_NAME.ko" | tee -a "$LOG_FILE"
                return 0
            else
                log_warning "ARM32交叉编译失败 (可能缺少ARM32内核源码)"
                return 1
            fi
            ;;
        x86_64)
            if make x86_64; then
                log_success "x86_64编译成功"
                file "$MODULE_NAME.ko" | tee -a "$LOG_FILE"
                return 0
            else
                log_error "x86_64编译失败"
                return 1
            fi
            ;;
        *)
            log_error "不支持的架构: $target_arch"
            return 1
            ;;
    esac
}

# 模块加载测试
test_module_loading() {
    log_test "模块加载测试"
    
    if [ ! -f "$MODULE_NAME.ko" ]; then
        log_error "模块文件不存在: $MODULE_NAME.ko"
        return 1
    fi
    
    # 卸载可能已存在的模块
    if lsmod | grep -q "$MODULE_NAME"; then
        log_info "卸载已存在的模块..."
        sudo rmmod "$MODULE_NAME" || true
    fi
    
    # 加载模块
    log_info "加载模块..."
    if sudo insmod "$MODULE_NAME.ko"; then
        log_success "模块加载成功"
        
        # 检查模块是否真的加载了
        if lsmod | grep -q "$MODULE_NAME"; then
            log_success "模块在系统中可见"
            lsmod | grep "$MODULE_NAME" | tee -a "$LOG_FILE"
        else
            log_error "模块加载后未在系统中找到"
            return 1
        fi
        
        # 检查proc文件是否创建
        if [ -f "/proc/$MODULE_NAME" ]; then
            log_success "proc文件创建成功: /proc/$MODULE_NAME"
        else
            log_error "proc文件未创建"
            return 1
        fi
        
        return 0
    else
        log_error "模块加载失败"
        dmesg | tail -5 | tee -a "$LOG_FILE"
        return 1
    fi
}

# 功能测试
test_functionality() {
    log_test "功能测试"
    
    if [ ! -f "/proc/$MODULE_NAME" ]; then
        log_error "proc文件不存在，请先加载模块"
        return 1
    fi
    
    log_info "1. 读取驱动状态..."
    if cat "/proc/$MODULE_NAME" | tee -a "$LOG_FILE"; then
        log_success "状态读取成功"
    else
        log_error "状态读取失败"
        return 1
    fi
    
    log_info "2. 测试写入操作..."
    if echo "test_write 12345" | sudo tee "/proc/$MODULE_NAME" >/dev/null; then
        log_success "写入测试成功"
        
        # 检查内核日志
        log_info "检查内核日志..."
        dmesg | tail -5 | grep -i "$MODULE_NAME" | tee -a "$LOG_FILE" || true
    else
        log_error "写入测试失败"
        return 1
    fi
    
    log_info "3. 测试读取操作..."
    if echo "test_read" | sudo tee "/proc/$MODULE_NAME" >/dev/null; then
        log_success "读取测试成功"
        
        # 再次检查内核日志
        dmesg | tail -5 | grep -i "$MODULE_NAME" | tee -a "$LOG_FILE" || true
    else
        log_error "读取测试失败"
        return 1
    fi
    
    log_info "4. 测试监控点管理..."
    
    # 添加自定义监控点 (使用一个安全的内核地址)
    local test_addr="0xffffffff"  # 这只是个示例，实际使用需要有效地址
    if echo "add custom_test $test_addr 4 3" | sudo tee "/proc/$MODULE_NAME" >/dev/null 2>&1; then
        log_info "自定义监控点添加命令已发送"
    fi
    
    # 删除监控点
    if echo "del custom_test" | sudo tee "/proc/$MODULE_NAME" >/dev/null 2>&1; then
        log_info "监控点删除命令已发送"
    fi
    
    log_success "功能测试完成"
}

# 性能测试
test_performance() {
    log_test "性能测试"
    
    if [ ! -f "/proc/$MODULE_NAME" ]; then
        log_error "proc文件不存在，请先加载模块"
        return 1
    fi
    
    log_info "进行性能测试 (多次读写操作)..."
    
    local start_time=$(date +%s.%N)
    
    # 执行多次读写操作
    for i in {1..10}; do
        echo "test_write $i" | sudo tee "/proc/$MODULE_NAME" >/dev/null 2>&1
        echo "test_read" | sudo tee "/proc/$MODULE_NAME" >/dev/null 2>&1
    done
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "无法计算")
    
    log_info "性能测试完成，耗时: ${duration}秒"
    
    # 检查是否有内存泄漏等问题
    log_info "检查系统状态..."
    free -h | tee -a "$LOG_FILE"
    
    log_success "性能测试完成"
}

# 模块卸载测试
test_module_unloading() {
    log_test "模块卸载测试"
    
    if ! lsmod | grep -q "$MODULE_NAME"; then
        log_warning "模块未加载，跳过卸载测试"
        return 0
    fi
    
    log_info "卸载模块..."
    if sudo rmmod "$MODULE_NAME"; then
        log_success "模块卸载成功"
        
        # 检查模块是否真的卸载了
        if lsmod | grep -q "$MODULE_NAME"; then
            log_error "模块卸载后仍在系统中"
            return 1
        else
            log_success "模块已从系统中移除"
        fi
        
        # 检查proc文件是否删除
        if [ -f "/proc/$MODULE_NAME" ]; then
            log_error "proc文件未删除"
            return 1
        else
            log_success "proc文件已删除"
        fi
        
        return 0
    else
        log_error "模块卸载失败"
        return 1
    fi
}

# 清理函数
cleanup() {
    log_info "清理测试环境..."
    
    # 卸载模块
    if lsmod | grep -q "$MODULE_NAME" 2>/dev/null; then
        sudo rmmod "$MODULE_NAME" 2>/dev/null || true
    fi
    
    # 清理编译文件
    cd "$SCRIPT_DIR"
    make clean >/dev/null 2>&1 || true
    
    log_success "清理完成"
}

# 主测试函数
run_tests() {
    local test_arch="${1:-native}"
    local compile_only="${2:-false}"
    local full_test="${3:-false}"
    
    log "========================================"
    log "🧪 开始跨平台内存监控驱动测试"
    log "========================================"
    log "测试架构: $test_arch"
    log "测试模式: $([ "$full_test" = "true" ] && echo "完整测试" || echo "基础测试")"
    log "开始时间: $(date)"
    log "========================================"
    
    local failed_tests=0
    local total_tests=0
    
    # 环境检查
    ((total_tests++))
    if ! check_environment; then
        ((failed_tests++))
        log_error "环境检查失败"
        return 1
    fi
    
    # 编译测试
    ((total_tests++))
    if ! test_compilation "$test_arch"; then
        ((failed_tests++))
        log_error "编译测试失败"
        if [ "$compile_only" = "true" ]; then
            return 1
        fi
    fi
    
    # 如果只是编译测试，到这里就结束
    if [ "$compile_only" = "true" ]; then
        log_success "编译测试完成"
        return 0
    fi
    
    # 只有在本地架构下才能进行模块加载测试
    if [ "$test_arch" = "native" ]; then
        # 模块加载测试
        ((total_tests++))
        if ! test_module_loading; then
            ((failed_tests++))
            log_error "模块加载测试失败"
        else
            # 功能测试
            ((total_tests++))
            if ! test_functionality; then
                ((failed_tests++))
                log_error "功能测试失败"
            fi
            
            # 完整测试包括性能测试
            if [ "$full_test" = "true" ]; then
                ((total_tests++))
                if ! test_performance; then
                    ((failed_tests++))
                    log_error "性能测试失败"
                fi
            fi
            
            # 模块卸载测试
            ((total_tests++))
            if ! test_module_unloading; then
                ((failed_tests++))
                log_error "模块卸载测试失败"
            fi
        fi
    else
        log_warning "非本地架构 ($test_arch)，跳过模块加载和功能测试"
    fi
    
    # 测试总结
    log "========================================"
    log "🏁 测试完成"
    log "========================================"
    log "总测试数: $total_tests"
    log "失败测试: $failed_tests"
    log "成功率: $(( (total_tests - failed_tests) * 100 / total_tests ))%"
    log "结束时间: $(date)"
    log "日志文件: $LOG_FILE"
    log "========================================"
    
    if [ $failed_tests -eq 0 ]; then
        log_success "🎉 所有测试通过！"
        return 0
    else
        log_error "❌ 有 $failed_tests 个测试失败"
        return 1
    fi
}

# 参数解析
COMPILE_ONLY=false
FULL_TEST=false
TEST_ARCH="native"
VERBOSE=false
CLEAN_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--compile-only)
            COMPILE_ONLY=true
            shift
            ;;
        -f|--full-test)
            FULL_TEST=true
            shift
            ;;
        -a|--arch)
            TEST_ARCH="$2"
            shift 2
            ;;
        -k|--kernel-dir)
            export KERNEL_DIR="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --no-color)
            # 禁用颜色
            RED=''
            GREEN=''
            YELLOW=''
            BLUE=''
            PURPLE=''
            CYAN=''
            NC=''
            shift
            ;;
        --clean)
            CLEAN_ONLY=true
            shift
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 初始化日志文件
> "$LOG_FILE"

# 设置陷阱函数，确保退出时清理
trap cleanup EXIT

# 如果只是清理，执行清理后退出
if [ "$CLEAN_ONLY" = "true" ]; then
    cleanup
    exit 0
fi

# 详细模式设置
if [ "$VERBOSE" = "true" ]; then
    set -x
fi

# 运行测试
if run_tests "$TEST_ARCH" "$COMPILE_ONLY" "$FULL_TEST"; then
    exit 0
else
    exit 1
fi 