#!/bin/bash
# 内核快照工具与quilt补丁管理系统集成示例
# 
# 用法: ./quilt_integration.sh <内核目录>
# 
# 功能:
# - 自动创建补丁前后的快照
# - 生成quilt所需的文件列表
# - 提供详细的变更报告

set -e

# 工具配置
SNAPSHOT_TOOL="../kernel_snapshot"
KERNEL_DIR="${1:-/path/to/linux-kernel}"
WORK_DIR="snapshots"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查工具是否存在
check_tool() {
    if [[ ! -x "$SNAPSHOT_TOOL" ]]; then
        log_error "快照工具不存在: $SNAPSHOT_TOOL"
        log_info "请先编译工具: make"
        exit 1
    fi
}

# 检查内核目录
check_kernel_dir() {
    if [[ ! -d "$KERNEL_DIR" ]]; then
        log_error "内核目录不存在: $KERNEL_DIR"
        log_info "用法: $0 <内核目录>"
        exit 1
    fi
    
    log_info "使用内核目录: $KERNEL_DIR"
}

# 创建工作目录
setup_workspace() {
    mkdir -p "$WORK_DIR"
    log_info "工作目录: $WORK_DIR"
}

# 创建基线快照
create_baseline() {
    local snapshot_file="$WORK_DIR/baseline_$(date +%Y%m%d_%H%M%S).snapshot"
    
    log_info "创建基线快照..."
    if $SNAPSHOT_TOOL -g create "$KERNEL_DIR" "$snapshot_file"; then
        log_success "基线快照创建完成: $snapshot_file"
        echo "$snapshot_file" > "$WORK_DIR/current_baseline.txt"
    else
        log_error "基线快照创建失败"
        exit 1
    fi
}

# 创建修改后快照
create_modified() {
    local snapshot_file="$WORK_DIR/modified_$(date +%Y%m%d_%H%M%S).snapshot"
    
    log_info "创建修改后快照..."
    if $SNAPSHOT_TOOL -g create "$KERNEL_DIR" "$snapshot_file"; then
        log_success "修改快照创建完成: $snapshot_file"
        echo "$snapshot_file" > "$WORK_DIR/current_modified.txt"
    else
        log_error "修改快照创建失败"
        exit 1
    fi
}

# 生成差异报告
generate_diff() {
    local baseline=$(cat "$WORK_DIR/current_baseline.txt" 2>/dev/null)
    local modified=$(cat "$WORK_DIR/current_modified.txt" 2>/dev/null)
    
    if [[ -z "$baseline" || -z "$modified" ]]; then
        log_error "缺少快照文件，请先创建基线和修改快照"
        return 1
    fi
    
    log_info "生成差异报告..."
    
    # 生成完整差异报告
    local diff_report="$WORK_DIR/diff_report_$(date +%Y%m%d_%H%M%S).txt"
    $SNAPSHOT_TOOL diff "$baseline" "$modified" > "$diff_report"
    
    # 提取文件列表用于quilt
    local added_files="$WORK_DIR/added_files.list"
    local modified_files="$WORK_DIR/modified_files.list" 
    local deleted_files="$WORK_DIR/deleted_files.list"
    local all_changed="$WORK_DIR/all_changed_files.list"
    
    grep "^A[[:space:]]" "$diff_report" | cut -f2 > "$added_files" 2>/dev/null || touch "$added_files"
    grep "^M[[:space:]]" "$diff_report" | cut -f2 > "$modified_files" 2>/dev/null || touch "$modified_files"
    grep "^D[[:space:]]" "$diff_report" | cut -f2 > "$deleted_files" 2>/dev/null || touch "$deleted_files"
    
    # 合并所有变更文件（quilt通常需要）
    cat "$added_files" "$modified_files" > "$all_changed" 2>/dev/null
    
    # 显示统计信息
    local added_count=$(wc -l < "$added_files")
    local modified_count=$(wc -l < "$modified_files")  
    local deleted_count=$(wc -l < "$deleted_files")
    local total_count=$((added_count + modified_count + deleted_count))
    
    log_success "差异分析完成:"
    echo "  新增文件: $added_count"
    echo "  修改文件: $modified_count"
    echo "  删除文件: $deleted_count"
    echo "  总变更数: $total_count"
    echo ""
    echo "生成的文件:"
    echo "  完整报告: $diff_report"
    echo "  新增文件列表: $added_files"
    echo "  修改文件列表: $modified_files"
    echo "  删除文件列表: $deleted_files"
    echo "  所有变更文件: $all_changed"
}

# quilt集成助手
quilt_helper() {
    local all_changed="$WORK_DIR/all_changed_files.list"
    
    if [[ ! -f "$all_changed" ]]; then
        log_error "未找到变更文件列表，请先运行差异分析"
        return 1
    fi
    
    local file_count=$(wc -l < "$all_changed")
    if [[ $file_count -eq 0 ]]; then
        log_warning "没有检测到文件变更"
        return 0
    fi
    
    log_info "quilt集成建议:"
    echo ""
    echo "1. 添加变更文件到quilt:"
    echo "   cd $KERNEL_DIR"
    echo "   quilt add \$(cat $(pwd)/$all_changed | tr '\n' ' ')"
    echo ""
    echo "2. 或逐个添加:"
    echo "   while read file; do quilt add \"\$file\"; done < $(pwd)/$all_changed"
    echo ""
    echo "3. 创建补丁:"
    echo "   quilt new your-patch-name.patch"
    echo "   # 进行你的修改..."
    echo "   quilt refresh"
    echo ""
    echo "4. 查看补丁:"
    echo "   quilt diff"
}

# 清理工作目录
cleanup() {
    log_info "清理旧快照文件（保留最新3个）..."
    
    # 保留最新的基线快照
    ls -t "$WORK_DIR"/baseline_*.snapshot 2>/dev/null | tail -n +4 | xargs rm -f
    
    # 保留最新的修改快照
    ls -t "$WORK_DIR"/modified_*.snapshot 2>/dev/null | tail -n +4 | xargs rm -f
    
    log_success "清理完成"
}

# 显示帮助信息
show_help() {
    echo "内核快照工具 - quilt集成助手"
    echo ""
    echo "用法: $0 [选项] <内核目录>"
    echo ""
    echo "选项:"
    echo "  baseline                创建基线快照"
    echo "  modified                创建修改后快照"  
    echo "  diff                    生成差异报告"
    echo "  quilt                   显示quilt集成建议"
    echo "  cleanup                 清理旧文件"
    echo "  auto                    自动模式（修改后快照+差异分析）"
    echo "  help                    显示此帮助"
    echo ""
    echo "典型工作流:"
    echo "  1. $0 baseline /path/to/kernel    # 开始修改前"
    echo "  2. # 进行内核修改..."
    echo "  3. $0 auto /path/to/kernel        # 分析变更"
    echo "  4. $0 quilt                       # 获取quilt命令"
}

# 主函数
main() {
    local action="${1:-help}"
    
    case "$action" in
        "baseline")
            shift
            KERNEL_DIR="${1:-$KERNEL_DIR}"
            check_tool
            check_kernel_dir
            setup_workspace
            create_baseline
            ;;
        "modified")
            shift
            KERNEL_DIR="${1:-$KERNEL_DIR}"
            check_tool
            check_kernel_dir
            setup_workspace
            create_modified
            ;;
        "diff")
            check_tool
            setup_workspace
            generate_diff
            ;;
        "quilt")
            quilt_helper
            ;;
        "auto")
            shift
            KERNEL_DIR="${1:-$KERNEL_DIR}"
            check_tool
            check_kernel_dir
            setup_workspace
            create_modified
            generate_diff
            quilt_helper
            ;;
        "cleanup")
            setup_workspace
            cleanup
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            if [[ -d "$action" ]]; then
                # 如果第一个参数是目录，则为自动模式
                KERNEL_DIR="$action"
                check_tool
                check_kernel_dir
                setup_workspace
                create_modified
                generate_diff
                quilt_helper
            else
                log_error "未知选项: $action"
                show_help
                exit 1
            fi
            ;;
    esac
}

# 运行主函数
main "$@"