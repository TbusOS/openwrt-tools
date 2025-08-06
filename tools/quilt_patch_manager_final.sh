#!/bin/bash

# OpenWrt Quilt CVE Patch Manager - Final Version
# 功能：自动化 CVE 补丁制作流程，包含元数据合并
# 版本: Final-v10

set -e
set -o pipefail # 管道中的命令失败也会导致脚本退出

# 颜色定义
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'
CYAN=$'\033[0;36m'
PURPLE=$'\033[0;35m'
NC=$'\033[0m'

# 工具信息
TOOL_NAME="OpenWrt Quilt CVE Patch Manager"
VERSION="7.0.0"

# 统一工作目录配置
MAIN_WORK_DIR="patch_manager_work"
SESSION_TMP_DIR_PATTERN="$MAIN_WORK_DIR/session_tmp/patch_manager_$$"
CACHE_DIR="$MAIN_WORK_DIR/cache"
OUTPUT_DIR="$MAIN_WORK_DIR/outputs"

# 基础配置
KERNEL_GIT_URL="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
PATCH_LIST_FILE="patch_files.txt"
PATCH_METADATA_FILE="patch_metadata.txt"

# 保存原始工作目录
ORIGINAL_PWD="$(pwd)"

# 清理函数
cleanup() {
    # 只清理本次会话的临时目录，不清理缓存和输出
    local temp_full_dir="$ORIGINAL_PWD/$SESSION_TMP_DIR_PATTERN"
    [[ -d "$temp_full_dir" ]] && rm -rf "$temp_full_dir"
}
trap cleanup EXIT

# 打印状态信息
log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

log_success() {
    printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"
}

log_warning() {
    printf "${YELLOW}[WARNING]${NC} %s\n" "$1"
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1"
}

# 打印版本信息
print_version() {
    printf "%s v%s\n" "$TOOL_NAME" "$VERSION"
}

# 打印帮助信息 (最终版)
print_help() {
    printf "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║                 %s v%s                ║${NC}\n" "$TOOL_NAME" "$VERSION"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}\n"
    printf "${CYAN}一个专为 OpenWrt 内核补丁设计的自动化流程增强工具。${NC}\n"
    printf "${YELLOW}用法:${NC} %s <命令> [参数]\n\n" "$(basename "$0")"

    printf "${PURPLE}■ 典型工作流程 (推荐) ■\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf "假设要为 commit ${CYAN}abcde123${NC} 制作一个名为 ${CYAN}999-my-fix.patch${NC} 的补丁:\n\n"
    printf "  1. (可选) 测试兼容性: %s ${CYAN}test-patch abcde123${NC}\n" "$(basename "$0")"
    printf "  2. 创建新补丁:        %s ${CYAN}create-patch 999-my-fix.patch${NC}\n" "$(basename "$0")"
    printf "  3. 提取并添加文件:    %s ${CYAN}extract-files abcde123${NC} && %s ${CYAN}add-files patch_files.txt${NC}\n" "$(basename "$0")" "$(basename "$0")"
    printf "  4. 手动修改代码...\n"
    printf "  5. 生成最终补丁:      %s ${PURPLE}refresh-with-header abcde123${NC}\n\n" "$(basename "$0")"
    printf "补丁文件将生成在内核的 ${GREEN}patches/${NC} 目录, 并自动拷贝一份到 ${GREEN}%s/${NC} 中。\n" "$OUTPUT_DIR"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

    printf "${GREEN}■ 命令列表 ■${NC}\n"
    
    printf "\n${YELLOW}>> 准备与分析 (可在任何目录运行)${NC}\n"
    printf "  ${CYAN}%-26s${NC} %s\n" "test-patch <commit>" "测试补丁兼容性, 生成冲突分析报告。"
    printf "  ${CYAN}%-26s${NC} %s\n" "fetch <commit>" "下载原始补丁到缓存, 并打印路径。"
    printf "  ${CYAN}%-26s${NC} %s\n" "save <commit> [name]" "保存原始补丁到 ${OUTPUT_DIR} 供查阅。"
    printf "  ${CYAN}%-26s${NC} %s\n" "extract-files <commit>" "提取补丁影响的文件列表到 ${OUTPUT_DIR}/patch_files.txt。"
    printf "  ${CYAN}%-26s${NC} %s\n" "extract-metadata <commit>" "提取补丁元数据 (作者, 描述等) 到 ${OUTPUT_DIR}/patch_metadata.txt。"

    printf "\n${YELLOW}>> 核心补丁操作 (自动查找内核目录)${NC}\n"
    printf "  ${CYAN}%-26s${NC} %s\n" "create-patch <name>" "创建一个新的空 quilt 补丁。"
    printf "  ${CYAN}%-26s${NC} %s\n" "add-files <file_list>" "从文件列表批量添加文件到当前 quilt 补丁。"
    printf "  ${CYAN}%-26s${NC} %s\n" "refresh" "【标准】刷新补丁, 生成纯代码 diff, 并拷贝到输出目录。"
    printf "  ${PURPLE}%-26s${NC} %s\n" "refresh-with-header <commit>" "【核心】刷新并注入元数据, 生成最终补丁, 并拷贝到输出目录。"
    printf "  ${GREEN}%-26s${NC} %s\n" "auto-patch <commit> <name>" "【全自动】执行完整流程 (test, create, add, refresh-with-header)。"

    printf "\n${YELLOW}>> Quilt 状态查询 (自动查找内核目录)${NC}\n"
    printf "  ${CYAN}%-26s${NC} %s\n" "status" "显示补丁总体状态 (总数/已应用/未应用)。"
    printf "  ${CYAN}%-26s${NC} %s\n" "series" "显示所有补丁及状态列表。"
    printf "  ${CYAN}%-26s${NC} %s\n" "top" "显示当前在最顶层的补丁。"
    printf "  ${CYAN}%-26s${NC} %s\n" "applied" "仅列出所有已应用的补丁。"
    printf "  ${CYAN}%-26s${NC} %s\n" "unapplied" "仅列出所有未应用的补丁。"
    printf "  ${CYAN}%-26s${NC} %s\n" "files" "列出当前补丁所包含的所有文件。"
    printf "  ${CYAN}%-26s${NC} %s\n" "diff" "显示当前补丁的 diff 内容。"

    printf "\n${YELLOW}>> Quilt 队列操作 (自动查找内核目录)${NC}\n"
    printf "  ${CYAN}%-26s${NC} %s\n" "push" "应用下一个未应用的补丁。"
    printf "  ${CYAN}%-26s${NC} %s\n" "pop" "撤销最顶层的补丁。"
    
    printf "\n${YELLOW}>> 环境与辅助命令${NC}\n"
    printf "  ${CYAN}%-26s${NC} %s\n" "clean" "交互式清理缓存和输出目录。"
    printf "  ${RED}%-26s${NC} %s\n" "reset-env" "(危险) 重置内核 quilt 状态, 用于开发测试。"
    printf "  ${CYAN}%-26s${NC} %s\n" "help, -h, --help" "显示此帮助信息。"
    printf "  ${CYAN}%-26s${NC} %s\n" "version, -v, --version" "显示脚本版本信息。"
    printf "\n"
}

# 检查依赖
check_dependencies() {
    local deps=("curl" "awk" "sed" "grep" "xargs")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少以下依赖: ${missing_deps[*]}"; exit 1
    fi
    
    if [[ "$1" == "need_quilt" ]] && ! command -v "quilt" &> /dev/null; then
        log_error "缺少 quilt 工具"; exit 1
    fi
}

# 查找 OpenWrt 内核源码目录
find_kernel_source() {
    if [[ -f "Makefile" ]] && grep -q "KERNELRELEASE" Makefile 2>/dev/null; then
        pwd
        return 0
    fi
    
    local kernel_dir
    kernel_dir=$(find "$ORIGINAL_PWD" -path "*/build_dir/target-*/linux-*/linux-*" -type d -print -quit 2>/dev/null)

    if [[ -n "$kernel_dir" ]] && [[ -f "$kernel_dir/Makefile" ]] && grep -q "KERNELRELEASE" "$kernel_dir/Makefile" 2>/dev/null; then
        echo "$kernel_dir"
        return 0
    else
        return 1
    fi
}

# 创建临时目录
create_temp_dir() {
    mkdir -p "$ORIGINAL_PWD/$MAIN_WORK_DIR"/{cache,outputs,session_tmp}
    local temp_full_dir="$ORIGINAL_PWD/$SESSION_TMP_DIR_PATTERN"
    mkdir -p "$temp_full_dir"
    
    if [[ "$1" != "reset-env" ]]; then
        log_info "工作目录: $ORIGINAL_PWD/$MAIN_WORK_DIR"
    fi
}

# 抓取原始补丁 (内部函数)
_fetch_patch_internal() {
    local commit_id="$1"
    local patch_url="${KERNEL_GIT_URL}/patch/?id=${commit_id}"
    local patch_file="$ORIGINAL_PWD/$CACHE_DIR/original_${commit_id}.patch"

    if [[ -f "$patch_file" ]] && [[ -s "$patch_file" ]]; then
        printf "%s" "$patch_file"
        return 2 # 2 = cache hit
    fi

    if curl -s -f "$patch_url" -o "$patch_file" && [[ -s "$patch_file" ]]; then
                printf "%s" "$patch_file"
        return 0 # 0 = downloaded
    else
        [[ -f "$patch_file" ]] && rm -f "$patch_file"
        return 1 # 1 = failure
    fi
}

# (公开) 抓取原始补丁
fetch_patch() {
    local commit_id="$1"
    [[ -z "$commit_id" ]] && { log_error "请提供 commit ID"; return 1; }
    
    log_info "抓取 commit $commit_id 的原始补丁..."
    
    local patch_file
    local fetch_result
    set +e
    patch_file=$(_fetch_patch_internal "$commit_id")
    fetch_result=$?
    set -e
    
    if [[ $fetch_result -eq 0 ]]; then
        log_success "补丁已下载并缓存到: $patch_file"
    elif [[ $fetch_result -eq 2 ]]; then
        log_success "使用已缓存的补丁: $patch_file"
    else
        log_error "无法下载补丁，请检查 commit ID: $commit_id"
        return 1
    fi
}

# 保存原始补丁到输出目录
save_patch() {
    local commit_id="$1"
    local filename="$2"
    [[ -z "$commit_id" ]] && { log_error "请提供 commit ID"; return 1; }
    
    [[ -z "$filename" ]] && filename="${commit_id}.patch"
    [[ ! "$filename" =~ \.patch$ ]] && filename="${filename}.patch"
    
    local output_path="$ORIGINAL_PWD/$OUTPUT_DIR/$filename"

    log_info "保存 commit $commit_id 的原始补丁到输出目录..."
    
    local patch_file
    set +e
    patch_file=$(_fetch_patch_internal "$commit_id")
    local fetch_result=$?
    set -e

    if [[ $fetch_result -eq 0 ]] || [[ $fetch_result -eq 2 ]]; then
        cp "$patch_file" "$output_path"
        log_success "原始补丁已保存到: $output_path"
    else
        log_error "无法获取补丁: $commit_id"
        return 1
    fi
}

# 测试补丁兼容性
test_patch_compatibility() {
    local commit_id="$1"
    [[ -z "$commit_id" ]] && { log_error "请提供 commit ID"; return 1; }

    log_info "测试 commit $commit_id 的补丁兼容性..."
    local patch_file
    set +e
    patch_file=$(_fetch_patch_internal "$commit_id")
    local fetch_result=$?
    set -e
    if [[ $fetch_result -eq 1 ]]; then
        log_error "无法获取补丁: $commit_id"
        return 1
    fi
    

    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source) || { log_error "无法找到内核源码目录"; return 1; }
    log_success "找到内核源码目录: $kernel_source_dir"
    
    (
        cd "$kernel_source_dir" || exit 1
        log_info "开始干跑 (dry-run) 测试..."
        local patch_test_output_file
        patch_test_output_file=$(mktemp "$ORIGINAL_PWD/$SESSION_TMP_DIR_PATTERN/patch_output.XXXXXX")
        
        if patch --dry-run -p1 --verbose --force --no-backup-if-mismatch < "$patch_file" > "$patch_test_output_file" 2>&1; then
            log_success "🎉 补丁完全兼容！"
            return 0
        else
            log_warning "⚠️ 补丁有冲突！"
            grep -E "^(Hunk|patching file|hunks failed)" "$patch_test_output_file" | sed 's/^/  /'
            return 1
        fi
    )
}

# 提取补丁涉及的文件列表
extract_files() {
    local commit_id="$1"
    [[ -z "$commit_id" ]] && { log_error "请提供 commit ID"; return 1; }
    
    log_info "提取 commit $commit_id 涉及的文件列表..."
    
    local patch_file
    set +e
    patch_file=$(_fetch_patch_internal "$commit_id")
    local fetch_result=$?
    set -e
    
    if [[ $fetch_result -eq 1 ]]; then
        log_error "无法获取或找到有效的补丁文件 for $commit_id"; return 1
    fi
    
    local output_path="$ORIGINAL_PWD/$OUTPUT_DIR/$PATCH_LIST_FILE"
    
    # 使用 awk 提取更可靠
    awk '/^--- a\// {print $2}' "$patch_file" | sed 's|^a/||' | sort -u > "$output_path"
    
    local file_count
    file_count=$(wc -l < "$output_path" | tr -d ' ')
    
    if [[ $file_count -gt 0 ]]; then
        log_success "找到 $file_count 个文件，已保存到: $output_path"
    else
        log_warning "未找到任何文件。"
    fi
}

# 【仅供查阅】提取补丁元数据
extract_metadata() {
    local commit_id="$1"
    [[ -z "$commit_id" ]] && { log_error "请提供 commit ID"; return 1; }
    
    log_info "提取 commit $commit_id 的元数据 (仅供查阅)..."
    
    local patch_file
    set +e
    patch_file=$(_fetch_patch_internal "$commit_id")
    local fetch_result=$?
    set -e
    
    if [[ $fetch_result -eq 1 ]]; then
        log_error "无法获取补丁: $commit_id"; return 1
    fi
    
    local output_path="$ORIGINAL_PWD/$OUTPUT_DIR/$PATCH_METADATA_FILE"
    
    awk '/^diff --git/ {exit} {print}' "$patch_file" > "$output_path"

    log_success "元数据已保存到: $output_path"
}


# 创建新补丁
create_patch() {
    local patch_name="$1"
    [[ -z "$patch_name" ]] && { log_error "请提供补丁名称"; return 1; }
    [[ ! "$patch_name" =~ \.patch$ ]] && patch_name="${patch_name}.patch"
    
    log_info "准备创建新补丁: $patch_name"

    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source) || { log_error "未找到内核源码目录"; return 1; }

    (
        cd "$kernel_source_dir" || exit 1
        log_info "正在创建补丁..."
    if quilt new "$patch_name"; then
            log_success "补丁 '$patch_name' 创建成功"
    else
        log_error "补丁创建失败"
            exit 1
        fi
    )
}

# 添加文件到 quilt (最稳健版本)
add_files() {
    local file_list_name="$1"
    [[ -z "$file_list_name" ]] && { log_error "请提供文件列表名"; return 1; }

    local file_list_path
    if [[ -f "$file_list_name" ]]; then
        file_list_path=$(realpath "$file_list_name")
    elif [[ -f "$ORIGINAL_PWD/$OUTPUT_DIR/$file_list_name" ]]; then
        file_list_path="$ORIGINAL_PWD/$OUTPUT_DIR/$file_list_name"
    else
        log_error "找不到文件列表 '$file_list_name'"; return 1
    fi

    log_info "准备将文件添加到 quilt 补丁..."
    
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source) || { log_error "未找到内核源码目录"; return 1; }

    (
        cd "$kernel_source_dir" || exit 1
        log_info "从 '$file_list_path' 添加文件..."
        
        quilt top >/dev/null 2>&1 || { log_error "没有活动的 quilt 补丁"; exit 1; }

        local valid_files=()
        while IFS= read -r file; do
            if [[ -n "$file" && -f "$file" ]]; then
                valid_files+=("$file")
            elif [[ -n "$file" ]]; then
                log_warning "文件不存在，跳过: $file"
            fi
        done < "$file_list_path"

        if [[ ${#valid_files[@]} -gt 0 ]]; then
            printf "%s\n" "${valid_files[@]}" | xargs quilt add
            log_success "批量添加 ${#valid_files[@]} 个文件完成。"
        else
            log_warning "没有找到任何有效的文件来添加。"
        fi
    )
}

# quilt refresh 的封装 (带拷贝功能)
quilt_refresh() {
    log_info "🔄 [标准] 刷新补丁..."
    
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source) || { log_error "未找到内核源码目录"; return 1; }
    
    (
        cd "$kernel_source_dir" || exit 1
        
        local patch_path
        patch_path=$(quilt top 2>/dev/null) || { log_error "没有活动的 quilt 补丁"; exit 1; }
        
        if quilt refresh; then
            log_success "✅ 补丁刷新成功"
            local output_patch_path="$ORIGINAL_PWD/$OUTPUT_DIR/$(basename "$patch_path")"
            cp "$patch_path" "$output_patch_path"
            log_success "📄 最终补丁已拷贝到: $output_patch_path"
        else
            log_error "❌ 补丁刷新失败"
            exit 1
        fi
    )
}


# 刷新补丁并注入元数据 (带拷贝功能)
quilt_refresh_with_header() {
    local commit_id="$1"
    [[ -z "$commit_id" ]] && { log_error "请提供 commit_id 以注入元数据"; return 1; }

    log_info "🔄 [核心] 刷新补丁并注入来自 commit '$commit_id' 的元数据..."

    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source) || { log_error "未找到内核源码目录"; return 1; }
    
    (
        cd "$kernel_source_dir" || exit 1
        
        local patch_path
        patch_path=$(quilt top 2>/dev/null) || { log_error "没有活动的 quilt 补丁"; exit 1; }
        log_info "当前补丁: $patch_path"
        
        local original_patch_file
        set +e
        original_patch_file=$(_fetch_patch_internal "$commit_id")
        local fetch_result=$?
        set -e
        if [[ $fetch_result -eq 1 ]]; then
             log_error "无法获取原始补丁 $commit_id 以提取元数据"; exit 1
        fi
        
        local header
        header=$(awk '/^diff --git/ {exit} {print}' "$original_patch_file")
        
        if [[ -z "$header" ]]; then
            log_warning "无法从原始补丁中提取元数据头部，将只执行标准 refresh"
            quilt refresh
        else
            log_info "元数据头已提取, 正在生成纯代码 diff..."
            quilt refresh
            
            [[ -f "$patch_path" ]] || { log_error "刷新后找不到补丁文件: $patch_path"; exit 1; }
            local diff_content
            diff_content=$(cat "$patch_path")

            log_info "正在将元数据注入补丁..."
            {
                echo "$header"
                        echo ""
                echo "$diff_content"
            } > "$patch_path"
        fi

        log_success "🎉 补丁已成功生成: $patch_path"
        local output_patch_path="$ORIGINAL_PWD/$OUTPUT_DIR/$(basename "$patch_path")"
        cp "$patch_path" "$output_patch_path"
        log_success "📄 最终补丁已拷贝到: $output_patch_path"
    )
}

# 全自动补丁制作流程
auto_patch() {
    local commit_id="$1"
    local patch_name="$2"
    [[ -z "$commit_id" || -z "$patch_name" ]] && { print_help; return 1; }
    
    log_info "🚀 开始自动化补丁制作流程 for $commit_id..."
    
    log_info "\n${YELLOW}--- 步骤 1/4: 兼容性测试 ---${NC}"
    if ! test_patch_compatibility "$commit_id"; then
        log_warning "检测到冲突。请在后续步骤手动解决。"
        printf "${CYAN}是否要继续? (y/N): ${NC}"; read -r response
        [[ ! "$response" =~ ^[Yy]$ ]] && { log_info "用户终止流程"; return 0; }
    fi
    
    log_info "\n${YELLOW}--- 步骤 2/4: 创建补丁并添加文件 ---${NC}"
    create_patch "$patch_name"
    extract_files "$commit_id"
    add_files "$PATCH_LIST_FILE"

    log_info "\n${YELLOW}--- 步骤 3/4: 等待手动修改 ---${NC}"
    log_warning "补丁已创建，文件已添加。现在是手动修改代码以解决冲突的最佳时机。"
    log_info "修改完成后，按 ${GREEN}Enter${NC}键继续以生成最终补丁..."
    read -r

    log_info "\n${YELLOW}--- 步骤 4/4: 生成带元数据的最终补丁 ---${NC}"
    quilt_refresh_with_header "$commit_id"
    
    log_success "🎉 自动化流程完成!"
}

# 清理工作目录
clean_work_dir() {
    log_info "🧹 清理工作目录: $MAIN_WORK_DIR..."
    printf "\n${YELLOW}是否要清理所有缓存? ($ORIGINAL_PWD/$CACHE_DIR) (y/N): ${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -rf "$ORIGINAL_PWD/$CACHE_DIR"
        log_success "✅ 已清理缓存目录"
    fi

    printf "\n${YELLOW}是否要清理所有输出文件? ($ORIGINAL_PWD/$OUTPUT_DIR) (y/N): ${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -rf "$ORIGINAL_PWD/$OUTPUT_DIR"
        log_success "✅ 已清理输出目录"
    fi
    log_success "🎉 清理完成！"
}

# 重置 quilt 和内核源码树的状态
reset_env() {
    log_warning "🔥 [危险] 此操作将重置 Quilt 和内核源码状态 🔥"
    printf "${YELLOW}该操作将: 1. quilt pop -a -f  2. 删除所有补丁文件  3. 清理工作区\n"
    printf "确定要继续吗? (y/N): ${NC}"
    read -r response
    [[ ! "$response" =~ ^[Yy]$ ]] && { log_info "用户取消操作"; return 0; }
    
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source) || { log_error "未找到内核源码目录"; return 1; }
    
    (
        cd "$kernel_source_dir" || exit 1
        log_info "1/2 强制撤销所有补丁..."
        quilt pop -a -f > /dev/null 2>&1 || true
        log_success "✅ 所有补丁已撤销"

        log_info "2/2 删除旧的补丁文件..."
        find patches -type f ! -name "series" -delete 2>/dev/null || true
        # 确保 patches 目录存在
        mkdir -p patches
        log_success "✅ 补丁文件已删除"
    )

    clean_work_dir
    log_success "🎉 环境重置完成！"
}

# quilt 命令的通用执行器
run_quilt_command() {
    local quilt_cmd="$1"; shift
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source) || { log_error "未找到内核源码目录"; return 1; }
    ( cd "$kernel_source_dir" || exit 1; quilt "$quilt_cmd" "$@"; )
}

# 主函数
main() {
    [[ $# -eq 0 ]] && { print_help; exit 0; }
    
    local command="$1"; shift
    
    check_dependencies
    create_temp_dir "$command"
    
    case "$command" in
        "fetch") fetch_patch "$@";;
        "save") save_patch "$@";;
        "test-patch") check_dependencies "need_quilt"; test_patch_compatibility "$@";;
        "extract-files") extract_files "$@";;
        "extract-metadata") extract_metadata "$@";;
        "add-files") check_dependencies "need_quilt"; add_files "$@";;
        "create-patch") check_dependencies "need_quilt"; create_patch "$@";;
        "refresh") check_dependencies "need_quilt"; quilt_refresh "$@";;
        "refresh-with-header") check_dependencies "need_quilt"; quilt_refresh_with_header "$@";;
        "auto-patch") check_dependencies "need_quilt"; auto_patch "$@";;
        "clean") clean_work_dir "$@";;
        "reset-env") check_dependencies "need_quilt"; reset_env "$@";;
        "status"|"series"|"applied"|"unapplied"|"top"|"files"|"push"|"pop"|"diff")
            check_dependencies "need_quilt"; run_quilt_command "$command" "$@";;
        "help"|"-h"|"--help") print_help;;
        "version"|"-v"|"--version") print_version;;
        *)
            log_error "未知命令: $command"
            print_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
