#!/bin/bash

# OpenWrt Quilt CVE Patch Manager
# 功能：自动化 CVE 补丁制作流程，包含元数据合并
# 版本: v7.0.0 (最终重构稳定版)

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

# 打印帮助信息
print_help() {
    printf "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "║                 %s v%s                   ║\n" "$TOOL_NAME" "$VERSION"
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
    printf "  ${CYAN}%-26s${NC} %s\n" "test-patch <commit>" "【核心】测试补丁兼容性, 生成智能冲突分析报告。"
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
    local deps=("curl" "awk" "sed" "grep" "xargs" "diff")
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

# 查找 OpenWrt 内核源码目录 (用于 dry-run)
find_kernel_source() {
    if [[ -f "Makefile" ]] && grep -q "KERNELRELEASE" Makefile 2>/dev/null; then
        pwd
        return 0
    fi
    
    local kernel_dir
    # 修正查找路径，移除不正确的 "target-*" 部分
    kernel_dir=$(find "$ORIGINAL_PWD" -path "*/build_dir/linux-*/linux-*" -type d -print -quit 2>/dev/null)

    if [[ -n "$kernel_dir" ]] && [[ -f "$kernel_dir/Makefile" ]] && grep -q "KERNELRELEASE" "$kernel_dir/Makefile" 2>/dev/null; then
        echo "$kernel_dir"
        return 0
    fi
    
    # 如果都找不到，则打印帮助信息
    printf "\n${YELLOW}提示:${NC} 脚本无法自动定位已解压的内核源码目录 (用于 dry-run)。\n" >&2
    printf "这通常是由于内核尚未编译造成的。\n\n" >&2
    printf "${YELLOW}建议解决方案:${NC}\n" >&2
    printf "  - 请确保您位于 OpenWrt 项目的根目录下。\n" >&2
    printf "  - 如果您尚未配置和编译，请运行以下命令之一来准备内核源码:\n" >&2
    printf "    ${GREEN}make target/linux/prepare V=s${NC} (仅准备内核源码，速度较快)\n" >&2
    printf "    ${GREEN}make V=s${NC} (执行完整编译，耗时较长)\n\n" >&2
    return 1
}

# 查找 OpenWrt 的内核补丁目录 (用于文件冲突检查)
find_openwrt_patches_dir() {
    local openwrt_root=""
    local current_dir="$ORIGINAL_PWD"

    # 1. 查找 OpenWrt 根目录 (标志: .config 文件和 target/linux 目录)
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/.config" && -d "$current_dir/target/linux" ]]; then
            openwrt_root="$current_dir"
            break
        fi
        current_dir=$(dirname "$current_dir")
    done

    if [[ -z "$openwrt_root" ]]; then
        log_error "无法定位 OpenWrt 根目录 (未找到 .config 或 target/linux)。" >&2
        log_info "请先在 OpenWrt 根目录运行 'make menuconfig' 进行基础配置。" >&2
        return 1
    fi

    # 2. 从 .config 中解析出当前选择的 target
    local selected_target_dir=""
    for d in "$openwrt_root/target/linux/"*/; do
        if [[ -d "$d" ]]; then
            local dir_name
            dir_name=$(basename "$d")
            # 检查 .config 中是否存在 CONFIG_TARGET_<dir_name>=y 的条目
            if grep -q -E "^CONFIG_TARGET_${dir_name}=y" "$openwrt_root/.config"; then
                selected_target_dir="$dir_name"
                break
            fi
        fi
    done

    if [[ -z "$selected_target_dir" ]]; then
        log_error "无法从 .config 文件中确定当前的目标架构。" >&2
        log_info "请运行 'make menuconfig' 并选择一个 'Target System'。" >&2
        return 1
    fi

    # 3. 构建并返回 patches 目录的路径
    local patches_dir="$openwrt_root/target/linux/$selected_target_dir/patches"
    if [[ -d "$patches_dir" ]]; then
        echo "$patches_dir"
        return 0
    else
        log_warning "在已选架构 '$selected_target_dir' 中未找到 'patches' 目录。" >&2
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


# 【V7.0 核心】终极重构版智能冲突分析器
analyze_patch_conflicts_v7() {
    local patch_file="$1"
    local kernel_source_dir="$2"
    local dry_run_log_file="$3"
    local final_report_file="$4"
    local session_tmp_dir="$5"

    {
        printf "\n\n"
        printf "${PURPLE}=======================================================================\n"
        printf "          智 能 冲 突 分 析 报 告 (Smart Conflict Analysis v7.0)\n"
        printf "=======================================================================${NC}\n"
    } >> "$final_report_file"

    local current_file=""
    local failed_hunks_info=()

    # 1. 从 dry-run 日志中解析出所有失败的 hunk 信息
    while IFS= read -r line; do
        if [[ "$line" =~ checking\ file\ (.*) ]]; then
            current_file="${BASH_REMATCH[1]}"
            # 移除行尾的空白字符
            current_file=$(echo "$current_file" | sed 's/[[:space:]]*$//')
        elif [[ "$line" =~ Hunk\ #([0-9]+)\ FAILED ]]; then
            hunk_num="${BASH_REMATCH[1]}"
            failed_hunks_info+=("$current_file:$hunk_num")
        fi
    done < "$dry_run_log_file"

    # 2. 循环处理每一个失败的 hunk
    for info in "${failed_hunks_info[@]}"; do
        local file="${info%%:*}"
        local hunk_num="${info#*:}"

        # 3. 使用 awk 从补丁文件中提取单个 hunk 的详细信息
        local hunk_details
        hunk_details=$(awk -v target_file="$file" -v target_hunk="$hunk_num" '
            BEGIN { hunk_counter=0; in_target_diff=0; in_target_hunk=0; }
            /^diff --git a\/(.+) b\// {
                current_file = gensub(/^diff --git a\/(.+) b\/.*/, "\\1", 1);
                if (current_file == target_file) {
                    in_target_diff = 1;
                    hunk_counter = 0;
                } else {
                    in_target_diff = 0;
                }
            }
            /^@@/ {
                if (in_target_diff) {
                    hunk_counter++;
                    if (hunk_counter == target_hunk) {
                        in_target_hunk = 1;
                        match($0, /@@ -([0-9]+,?[0-9]*)/, arr);
                        start_line = arr[1];
                        gsub(/,.*/, "", start_line);
                        print "START_LINE:" start_line;
                        print "HUNK_CONTENT_START";
                    } else {
                        if (in_target_hunk) {
                             print "HUNK_CONTENT_END";
                             in_target_hunk = 0;
                             exit;
                        }
                    }
                }
            }
            in_target_hunk {
                if ($0 !~ /^@@/) {
                     print $0;
                }
            }
            END {
                if (in_target_hunk) {
                    print "HUNK_CONTENT_END";
                }
            }
        ' "$patch_file")
        
        # 4. 解析 awk 的输出
        local start_line
        start_line=$(echo "$hunk_details" | grep "START_LINE:" | sed 's/START_LINE://')
        
        local expected_code
        expected_code=$(echo "$hunk_details" | sed -n '/HUNK_CONTENT_START/,/HUNK_CONTENT_END/p' | sed '1d;$d')

        local num_lines_to_read
        num_lines_to_read=$(echo "$expected_code" | grep -Ec '^( |-|\\)')

        # 5. 从本地内核源码读取实际代码
        local local_source_file="$kernel_source_dir/$file"
        local actual_code=""
        if [[ -f "$local_source_file" ]]; then
            actual_code=$(tail -n "+$start_line" "$local_source_file" | head -n "$num_lines_to_read")
        else
            actual_code="错误: 找不到本地源码文件: $local_source_file\n这可能是因为文件名在高低版本内核中已改变。"
        fi

        # 6. 准备并写入报告
        {
            printf "\n${PURPLE}══════════════════════════════════════════════════════════════════════════════${NC}\n"
            printf "${PURPLE}■ 分析: 文件 ${CYAN}%s${PURPLE}, 代码块 #${YELLOW}%s${NC}\n" "$file" "$hunk_num"
            printf "${PURPLE}══════════════════════════════════════════════════════════════════════════════${NC}\n"

            printf "\n${YELLOW}▼ 期望的代码 (来自补丁):${NC}\n"
            echo "$expected_code" | while IFS= read -r line; do
                if [[ "$line" == -* ]]; then
                    printf " ${RED}%s${NC}\n" "$line"
                else
                    printf " %s\n" "$line"
                fi
            done

            printf "\n${YELLOW}▼ 实际的代码 (来自本地 %s:%s):${NC}\n" "$file" "$start_line"
            printf "  %s\n" "$actual_code"
            
            printf "\n${YELLOW}▼ 代码差异分析 (Diff):${NC}\n"
        } >> "$final_report_file"

        # 7. 执行 diff 并将结果写入报告
        local tmp_expected="$session_tmp_dir/expected.tmp"
        local tmp_actual="$session_tmp_dir/actual.tmp"
        
        echo "$expected_code" | grep -E '^( |-|\\)' | sed 's/^.//' > "$tmp_expected"
        echo "$actual_code" > "$tmp_actual"

        if ! diff_output=$(diff -U 3 "$tmp_expected" "$tmp_actual"); then
            echo "$diff_output" | while IFS= read -r line; do
                case "$line" in
                    ---*|+++*) printf "${CYAN}%s${NC}\n" "$line" ;;
                    @@*) printf "${PURPLE}%s${NC}\n" "$line" ;;
                    -*) printf "${RED}%s${NC}\n" "$line" ;;
                    +*) printf "${GREEN}%s${NC}\n" "$line" ;;
                    *) printf "%s\n" "$line" ;;
                esac
            done >> "$final_report_file"
        else
            printf "${GREEN}注意: 两段代码内容完全一致。失败可能是由于前面的代码块应用失败导致行号偏移，或上下文中的某些行不匹配。${NC}\n" >> "$final_report_file"
        fi

        {
            printf "\n${PURPLE}智能提示:${NC}\n"
            printf "  • 请仔细比对上方【期望的代码】(红色部分是补丁要删除的) 与【实际的代码】。\n"
            printf "  • 使用上方的【代码差异分析】来定位最关键的不匹配行。\n"
            printf "  • ${YELLOW}在高低版本内核移植中，函数参数增减、宏定义变化、结构体成员变化是常见冲突原因。${NC}\n"
        } >> "$final_report_file"

    done
}


# 测试补丁兼容性
test_patch_compatibility() {
    local commit_id="$1"
    [[ -z "$commit_id" ]] && { log_error "请提供 commit ID"; return 1; }

    log_info "测试 commit $commit_id 的补丁兼容性..."
    
    # 步骤 1: 获取补丁
    log_info "  -> 步骤 1/3: 获取补丁文件..."
    local potential_patch_file="$ORIGINAL_PWD/$CACHE_DIR/original_${commit_id}.patch"
    local patch_url="${KERNEL_GIT_URL}/patch/?id=${commit_id}"
    local patch_file
    local fetch_result

    if [[ -f "$potential_patch_file" ]] && [[ -s "$potential_patch_file" ]]; then
        log_info "     检测到本地缓存, 将直接使用。"
    else
        log_info "     本地无缓存, 准备从网络下载..."
        printf "       ${CYAN}命令: curl -fL -o \"%s\" \\\n             \"%s\"${NC}\n" "$potential_patch_file" "$patch_url"
    fi
    
    set +e
    patch_file=$(_fetch_patch_internal "$commit_id")
    fetch_result=$?
    set -e
    
    if [[ $fetch_result -eq 0 ]]; then
        log_success "     补丁已成功下载并缓存。"
        printf "       ${CYAN}保存至: %s${NC}\n" "$patch_file"
    elif [[ $fetch_result -eq 2 ]]; then
        log_success "     成功使用已缓存的补丁:"
        printf "       ${CYAN}路径: %s${NC}\n" "$patch_file"
    else
        log_error "无法下载或找到补丁，请检查 Commit ID 或网络连接: $commit_id"
        return 1
    fi

    # 步骤 2: 检查与现有补丁的文件冲突
    log_info "  -> 步骤 2/3: 检查与 OpenWrt 现有内核补丁的文件冲突..."
    local patches_dir
    patches_dir=$(find_openwrt_patches_dir)
    if [[ $? -ne 0 ]]; then
        log_warning "     跳过文件冲突检查 (原因见上)。"
    else
        log_success "     成功定位到当前架构的补丁目录: $patches_dir"
        
        local new_patch_files
        new_patch_files=$(awk '/^--- a\// {print $2}' "$patch_file" | sed 's|^a/||' | sort -u)
        
        if [[ -z "$new_patch_files" ]]; then
            log_success "     无需执行冲突检查 (原因: 新补丁无文件变更)。"
        else
            local existing_patches
            mapfile -t existing_patches < <(find "$patches_dir" -type f -name "*.patch" 2>/dev/null)
            
            if [[ ${#existing_patches[@]} -eq 0 ]]; then
                log_success "     补丁目录为空, 无需执行冲突检查。"
            else
                log_info "     发现 ${#existing_patches[@]} 个现有补丁, 开始扫描..."
                
                declare -A conflicts_map
                local total_patches=${#existing_patches[@]}
                
                for i in "${!existing_patches[@]}"; do
                    local p="${existing_patches[$i]}"
                    local current_pos=$((i + 1))
                    local percent=$(( (current_pos * 100) / total_patches ))
                    local bar_len=$(( percent / 2 ))
                    local bar
                    bar=$(printf "%-${bar_len}s" "#" | tr ' ' '#')
                    printf "\r     扫描中: [%-50s] %d/%d (%d%%)" "$bar" "$current_pos" "$total_patches" "$percent"

                    local old_patch_files
                    old_patch_files=$(awk '/^--- a\// {print $2}' "$p" | sed 's|^a/||' | sort -u)
                    
                    if [[ -n "$old_patch_files" ]]; then
                        local common_files
                        common_files=$(comm -12 <(echo "$new_patch_files") <(echo "$old_patch_files"))
                        
                        if [[ -n "$common_files" ]]; then
                            for f in $common_files; do
                                conflicts_map[$f]+="$(basename "$p") "
                            done
                        fi
                    fi
                done
                printf "\n"
                
                if [[ ${#conflicts_map[@]} -gt 0 ]]; then
                    log_warning "     ⚠️  发现潜在文件冲突！以下文件也被其他补丁修改过:"
                    for file in "${!conflicts_map[@]}"; do
                        printf "       - 文件: ${CYAN}%s${NC}\n" "$file"
                        printf "         被补丁修改: ${YELLOW}%s${NC}\n" "${conflicts_map[$file]}"
                    done
                else
                    log_success "     ✅ 未发现与现有补丁的文件冲突。"
                fi
            fi
        fi
    fi

    # 步骤 3: Dry-run 测试
    log_info "  -> 步骤 3/3: 在解压后的内核源码中执行干跑 (dry-run) 测试..."
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source) || {
        log_warning "     因未找到已编译的内核源码, 跳过 dry-run 测试。您可以先根据文件冲突报告进行手动分析。"
        return 0 # 仅警告，不视为致命错误
    }
    log_success "     成功定位内核源码 (用于 dry-run): $kernel_source_dir"
    
    (
        cd "$kernel_source_dir" || exit 1
        log_info "     开始干跑 (dry-run) 测试..."
        
        local short_commit_id=${commit_id:0:7}
        local final_report_file="$ORIGINAL_PWD/$OUTPUT_DIR/test-patch-report-${short_commit_id}.log"
        local temp_log_file
        temp_log_file=$(mktemp "$ORIGINAL_PWD/$SESSION_TMP_DIR_PATTERN/patch_output.XXXXXX")

        # 重定向 dry-run 的输出到临时文件
        if patch --dry-run -p1 --verbose --force --no-backup-if-mismatch < "$patch_file" > "$temp_log_file" 2>&1; then
            log_success "🎉 补丁完全兼容！"
            [[ -f "$temp_log_file" ]] && rm -f "$temp_log_file" # 清理临时日志
            return 0
        else
            log_warning "⚠️  补丁存在冲突或问题！正在启动智能分析器..."
            
            # 将原始 dry-run 日志作为最终报告的开头
            cat "$temp_log_file" > "$final_report_file"
            
            # 调用新的高效分析函数，并传入安全的会话临时目录
            analyze_patch_conflicts_v7 "$patch_file" "$kernel_source_dir" "$temp_log_file" "$final_report_file" "$ORIGINAL_PWD/$SESSION_TMP_DIR_PATTERN"
            
            # 清理临时的 dry-run 日志
            rm -f "$temp_log_file"

            log_info "智能分析报告已生成。请查看:"
            printf "  ${GREEN}%s${NC}\n" "$final_report_file"
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
