#!/bin/bash
# 版本: v8.7.0 (Bash自动补全增强版本 - 新增智能命令补全功能)

# --- 全局变量与初始化 ---
# 获取脚本所在目录的绝对路径，确保路径引用的健壮性
# https://stackoverflow.com/questions/59895/how-to-get-the-source-directory-of-a-bash-script-from-within-the-script-itself
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$SCRIPT_DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

# --- 全局配置 ---
# set -e # 在调试路径问题时暂时禁用
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
TOOL_NAME="OpenWrt Quilt Linux Kernel Patch Manager"
VERSION="8.7.0"

# 统一工作目录配置
MAIN_WORK_DIR="patch_manager_work"
SESSION_TMP_DIR_PATTERN="$MAIN_WORK_DIR/session_tmp/patch_manager_$$"
CACHE_DIR="$MAIN_WORK_DIR/cache"
OUTPUT_DIR="$MAIN_WORK_DIR/outputs"
SNAPSHOT_FILE="$MAIN_WORK_DIR/snapshot.manifest"

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
    printf "支持使用 ${CYAN}commit-id${NC}、${CYAN}本地补丁文件路径${NC} 或 ${CYAN}网址链接${NC} 作为输入。\n\n"
    printf "示例 1: 使用 commit ${CYAN}abcde123${NC} 创建名为 ${CYAN}999-my-fix.patch${NC} 的补丁:\n"
    printf "  1. (可选) 测试兼容性: %s ${CYAN}test-patch abcde123${NC}\n" "$(basename "$0")"
    printf "  2. 创建新补丁:        %s ${CYAN}create-patch 999-my-fix.patch${NC}\n" "$(basename "$0")"
    printf "  3. 提取并添加文件:    %s ${CYAN}extract-files abcde123${NC} && %s ${CYAN}add-files patch_files.txt${NC}\n" "$(basename "$0")" "$(basename "$0")"
    printf "  4. 手动修改代码...\n"
    printf "  5. 生成最终补丁:      %s ${PURPLE}refresh-with-header abcde123${NC}\n\n" "$(basename "$0")"
    printf "示例 2: 使用本地文件 ${CYAN}/path/to/cve.patch${NC} 作为基础:\n"
    printf "  - 测试: %s ${CYAN}test-patch /path/to/cve.patch${NC}\n" "$(basename "$0")"
    printf "  - 提取: %s ${CYAN}extract-files /path/to/cve.patch${NC}\n\n" "$(basename "$0")"
    printf "示例 3: 使用网址 ${CYAN}https://example.com/patch.patch${NC} 作为基础:\n"
    printf "  - 保存: %s ${CYAN}save https://example.com/patch.patch cve-fix${NC}\n" "$(basename "$0")"
    printf "  - 测试: %s ${CYAN}test-patch https://example.com/patch.patch${NC}\n\n" "$(basename "$0")"
    
    printf "补丁文件将生成在内核的 ${GREEN}patches/${NC} 目录, 并自动拷贝一份到 ${GREEN}%s/${NC} 中。\n" "$OUTPUT_DIR"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

    printf "${GREEN}■ 命令列表 ■${NC}\n"
    
    printf "\n${YELLOW}>> 准备与分析 (可在任何目录运行)${NC}\n"
    printf "  ${CYAN}%-26s${NC} %s\n" "test-patch <id|file>" "【核心】测试补丁兼容性, 生成智能冲突分析报告。"
    printf "  ${CYAN}%-26s${NC} %s\n" "fetch <id|file|url>" "下载或复制原始补丁到缓存, 并打印路径。"
    printf "  ${CYAN}%-26s${NC} %s\n" "save <id|file|url> [name]" "保存原始补丁到 ${OUTPUT_DIR} 供查阅。"
    printf "  ${CYAN}%-26s${NC} %s\n" "extract-files <id|file>" "提取补丁影响的文件列表到 ${OUTPUT_DIR}/patch_files.txt。"
    printf "  ${CYAN}%-26s${NC} %s\n" "extract-metadata <id|file>" "提取补丁元数据 (作者, 描述等) 到 ${OUTPUT_DIR}/patch_metadata.txt。"

    printf "\n${YELLOW}>> 核心补丁操作 (自动查找内核目录)${NC}\n"
    printf "  ${CYAN}%-26s${NC} %s\n" "create-patch <name>" "创建一个新的空 quilt 补丁。"
    printf "  ${CYAN}%-26s${NC} %s\n" "add-files <file_list>" "从文件列表批量添加文件到当前 quilt 补丁 (如 patch_files.txt)。"
    printf "  ${CYAN}%-26s${NC} %s\n" "refresh" "【标准】刷新补丁, 生成纯代码 diff, 并拷贝到输出目录。"
    printf "  ${PURPLE}%-26s${NC} %s\n" "refresh-with-header <id|file>" "【核心】刷新并注入元数据, 生成最终补丁, 并拷贝到输出目录。"
    printf "  ${GREEN}%-26s${NC} %s\n" "auto-patch <id|file> <name>" "【全自动】执行完整流程 (test, create, add, refresh-with-header)。"

    printf "\n${YELLOW}>> 快速补丁应用 (OpenWrt 专用)${NC}\n"
    printf "  ${PURPLE}%-26s${NC} %s\n" "quick-apply <patch_path>" "【一键应用】复制补丁到目标目录，删除.prepare文件，执行make prepare。"

    printf "\n${YELLOW}>> 全局差异快照 (类 Git 功能, 可在任何目录运行)${NC}\n"
    printf "  ${CYAN}%-26s${NC} %s\n" "snapshot-create [dir]" "为指定目录(默认当前)创建快照, 作为后续对比的基准。"
    printf "  ${CYAN}%-26s${NC} %s\n" "snapshot-diff [dir]" "与快照对比, 找出指定目录(默认当前)下所有变更。"
    printf "  ${CYAN}%-26s${NC} %s\n" "snapshot-status [dir]" "检查指定目录(默认当前)的快照状态。"
    printf "  ${PURPLE}%-26s${NC} %s\n" "snapshot-diff > files.txt" "【推荐用法】将所有新增和修改的文件列表输出到文件。"
    
    printf "\n${YELLOW}>> 快照文件列表命令 (基于 kernel_snapshot_tool)${NC}\n"
    printf "  ${CYAN}%-26s${NC} %s\n" "snapshot-list-changes" "列出所有变更文件 (新增+修改), 适合生成 quilt 文件列表。"
    printf "  ${CYAN}%-26s${NC} %s\n" "snapshot-list-new" "仅列出新增文件。"
    printf "  ${CYAN}%-26s${NC} %s\n" "snapshot-list-modified" "仅列出修改文件。"
    printf "  ${CYAN}%-26s${NC} %s\n" "snapshot-clean [force]" "清理快照数据 (force 参数跳过确认)。"
    printf "  ${PURPLE}%-26s${NC} %s\n" "export-changed-files" "【新功能】导出变更文件到输出目录，保持原目录结构。"
    printf "  ${PURPLE}%-26s${NC} %s\n" "export-from-file <file>" "【新功能】基于指定文件列表导出文件，使用全局配置的default_workspace_dir作为根目录。"

    printf "\n${YELLOW}>> Quilt 状态查询 (自动查找内核目录)${NC}\n"
    printf "  ${CYAN}%-26s${NC} %s\n" "status" "显示补丁总体状态 (总数/已应用/未应用)。"
    printf "  ${CYAN}%-26s${NC} %s\n" "series" "显示所有补丁及状态列表。"
    printf "  ${CYAN}%-26s${NC} %s\n" "top" "显示当前在最顶层的补丁。"
    printf "  ${CYAN}%-26s${NC} %s\n" "applied" "仅列出所有已应用的补丁。"
    printf "  ${CYAN}%-26s${NC} %s\n" "unapplied" "仅列出所有未应用的补丁。"
    printf "  ${CYAN}%-26s${NC} %s\n" "files" "列出当前补丁所包含的所有文件。"
    printf "  ${CYAN}%-26s${NC} %s\n" "diff" "显示当前补丁的 diff 内容。"
    printf "  ${CYAN}%-26s${NC} %s\n" "graph [patch]" "生成补丁依赖关系图 (DOT格式)，可用 Graphviz 可视化。"
    printf "  ${CYAN}%-26s${NC} %s\n" "graph-pdf [--color] [--all] [patch] [file]" "生成PDF依赖图。--all显示所有补丁(即使无依赖)。"

    printf "\n${YELLOW}>> 快照文件列表命令 (基于 kernel_snapshot_tool)${NC}\n"
    printf "  ${CYAN}%-26s${NC} %s\n" "snapshot-list-changes" "列出所有变更文件 (新增+修改), 适合生成 quilt 文件列表。"
    printf "  ${CYAN}%-26s${NC} %s\n" "snapshot-list-new" "仅列出新增文件。"
    printf "  ${CYAN}%-26s${NC} %s\n" "snapshot-list-modified" "仅列出修改文件。"
    printf "  ${CYAN}%-26s${NC} %s\n" "snapshot-clean [force]" "清理快照数据 (force 参数跳过确认)。"
    printf "  ${PURPLE}%-26s${NC} %s\n" "export-changed-files" "【新功能】导出变更文件到输出目录，保持原目录结构。"
    printf "  ${PURPLE}%-26s${NC} %s\n" "export-from-file <file>" "【新功能】基于指定文件列表导出文件，使用全局配置的default_workspace_dir作为根目录。"

    printf "\n${YELLOW}>> Quilt 队列操作 (自动查找内核目录)${NC}\n"
    printf "  ${CYAN}%-26s${NC} %s\n" "push" "应用下一个未应用的补丁。"
    printf "  ${CYAN}%-26s${NC} %s\n" "pop" "撤销最顶层的补丁。"
    
    printf "\n${YELLOW}>> 环境与辅助命令${NC}\n"
    printf "  ${CYAN}%-26s${NC} %s\n" "clean" "交互式清理缓存和输出目录。"
    printf "  ${PURPLE}%-26s${NC} %s\n" "distclean" "【一键清理】强制清理快照+重置quilt+清理工作目录，完全还原到原始状态。"
    printf "  ${RED}%-26s${NC} %s\n" "reset-env" "(危险) 重置内核 quilt 状态, 用于开发测试。"
    printf "  ${CYAN}%-26s${NC} %s\n" "help, -h, --help" "显示此帮助信息。"
    printf "  ${CYAN}%-26s${NC} %s\n" "version, -v, --version" "显示脚本版本信息。"
    
    printf "\n${GREEN}■ export-changed-files 详细用法示例 ■${NC}\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf "该功能可将所有变更文件按原目录结构导出，便于代码审查、备份和分享。\n\n"
    printf "${YELLOW}典型使用流程:${NC}\n"
    printf "  1. 创建快照基线:     %s ${CYAN}snapshot-create${NC}\n" "$(basename "$0")"
    printf "  2. 修改内核代码 (添加/修改文件)...\n"
    printf "  3. 检查变更状态:     %s ${CYAN}snapshot-status${NC}\n" "$(basename "$0")"
    printf "  4. 导出变更文件:     %s ${PURPLE}export-changed-files${NC}\n\n" "$(basename "$0")"
    printf "${YELLOW}导出结果示例:${NC}\n"
    printf "  📁 ${OUTPUT_DIR}/changed_files/\n"
    printf "  ├── linux-4.1.15/            ${CYAN}# 内核目录 (动态获取)${NC}\n"
    printf "  │   ├── drivers/net/cve_fix.c ${GREEN}# 新增文件${NC}\n"
    printf "  │   ├── kernel/Kconfig        ${YELLOW}# 修改文件${NC}\n"
    printf "  │   └── fs/security/patch.h   ${GREEN}# 新增文件${NC}\n"
    printf "  └── EXPORT_INDEX.txt          ${CYAN}# 导出索引${NC}\n\n"
    printf "${YELLOW}适用场景:${NC}\n"
    printf "  • 📋 代码审查 - 整理所有变更文件\n"
    printf "  • 💾 补丁备份 - 防止代码丢失\n"
    printf "  • 👥 团队协作 - 分享具体修改内容\n"
    printf "  • 🔍 差异分析 - 按目录结构查看变更\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
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
    
    # 尝试从全局配置文件读取默认工作目录
    local config_file="$SCRIPT_DIR/kernel_snapshot_tool/.kernel_snapshot.conf"
    if [[ -f "$config_file" ]]; then
        local configured_dir
        configured_dir=$(grep "^default_workspace_dir=" "$config_file" | cut -d'=' -f2)
        
        if [[ -n "$configured_dir" && -d "$configured_dir" ]]; then
            if [[ -f "$configured_dir/Makefile" ]] && grep -q "KERNELRELEASE" "$configured_dir/Makefile" 2>/dev/null; then
                echo "$configured_dir"
                return 0
            fi
        fi
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

# 增强版内核目录查找函数 (用于需要quilt操作的命令)
find_kernel_source_enhanced() {
    local operation_name="$1"  # 操作名称，用于更好的错误提示
    
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source)
    
    # 如果find_kernel_source失败，尝试从全局配置文件读取目录
    if [[ $? -ne 0 || -z "$kernel_source_dir" ]]; then
        log_warning "标准方法未找到内核源码目录，尝试使用全局配置文件..."
        
        local config_file="$SCRIPT_DIR/kernel_snapshot_tool/.kernel_snapshot.conf"
        if [[ -f "$config_file" ]]; then
            local configured_dir
            configured_dir=$(grep "^default_workspace_dir=" "$config_file" | cut -d'=' -f2)
            
            if [[ -n "$configured_dir" && -d "$configured_dir" ]]; then
                log_info "发现全局配置中的工作目录: $configured_dir"
                
                # 检查是否是有效的内核目录（有Makefile且包含KERNELRELEASE）
                if [[ -f "$configured_dir/Makefile" ]] && grep -q "KERNELRELEASE" "$configured_dir/Makefile" 2>/dev/null; then
                    kernel_source_dir="$configured_dir"
                    log_success "✅ 使用全局配置中的内核目录: $kernel_source_dir"
                else
                    log_error "❌ 全局配置中的目录不是有效的内核源码目录"
                    log_error "   目录: $configured_dir"
                    log_error "   原因: 缺少Makefile或KERNELRELEASE标识"
                    log_info "💡 请检查全局配置文件: $config_file"
        return 1
    fi
            else
                log_error "❌ 全局配置文件中的default_workspace_dir无效或不存在"
                log_info "💡 配置文件: $config_file"
                [[ -n "$configured_dir" ]] && log_info "💡 配置的目录: $configured_dir"
                return 1
            fi
        else
            log_error "❌ 未找到全局配置文件: $config_file"
            log_info "💡 请确保kernel_snapshot_tool配置文件存在"
            return 1
        fi
    fi
    
    if [[ -z "$kernel_source_dir" ]]; then
        log_error "❌ 无法找到任何有效的内核源码目录用于操作: ${operation_name:-quilt操作}"
        log_info "💡 建议解决方案:"
        log_info "   1. 确保您位于OpenWrt项目根目录"
        log_info "   2. 运行 'make target/linux/prepare V=s' 准备内核源码"
        log_info "   3. 检查全局配置文件: $SCRIPT_DIR/kernel_snapshot_tool/.kernel_snapshot.conf"
        return 1
    fi
    
    echo "$kernel_source_dir"
    return 0
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

    # 3. 构建并返回 patches 目录的路径 (支持 patches-x.x 格式)
    local target_arch_dir="$openwrt_root/target/linux/$selected_target_dir"
    local patches_dir
    # 查找所有 patches* 目录, 按版本号反向排序并取第一个, 从而优先选择版本最高的
    patches_dir=$(find "$target_arch_dir" -maxdepth 1 -type d -name 'patches*' | sort -Vr | head -n 1)

    if [[ -n "$patches_dir" ]] && [[ -d "$patches_dir" ]]; then
        echo "$patches_dir"
        return 0
    else
        log_warning "在已选架构 '$selected_target_dir' 中未找到 'patches*' 目录。" >&2
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

# (内部函数) 统一获取补丁文件
# 接受 commit_id 或本地补丁文件路径
# 返回值: patch_file_path
# 退出码: 0=新下载成功, 1=失败, 2=缓存命中, 3=本地文件
_fetch_patch_internal() {
    local identifier="$1"
    
    # 检查 identifier 是否是一个存在且不为空的文件路径
    if [[ -f "$identifier" ]] && [[ -s "$identifier" ]]; then
        realpath "$identifier"
        return 3 # 3 = local file
    fi
    
    # 检查 identifier 是否是网址
    if [[ "$identifier" =~ ^https?:// ]]; then
        local url="$identifier"
        # 为网址生成缓存文件名：使用URL的哈希值避免特殊字符问题
        local url_hash=$(echo -n "$url" | md5sum | cut -d' ' -f1)
        local patch_file="$ORIGINAL_PWD/$CACHE_DIR/url_${url_hash}.patch"
        
        # 检查缓存
        if [[ -f "$patch_file" ]] && [[ -s "$patch_file" ]]; then
            printf "%s" "$patch_file"
            return 2 # 2 = cache hit
        fi
        
        # 下载网址内容
        log_info "正在从网址下载: $url" >&2
        if curl -s -f -L "$url" -o "$patch_file" && [[ -s "$patch_file" ]]; then
            log_success "网址下载成功" >&2
            printf "%s" "$patch_file"
            return 0 # 0 = downloaded
        else
            [[ -f "$patch_file" ]] && rm -f "$patch_file"
            log_error "网址下载失败: $url" >&2
            return 1 # 1 = failure
        fi
    fi
    
    # 如果不是文件也不是网址，则假定为 commit_id，并使用下载/缓存逻辑
    local commit_id="$identifier"
    local patch_url="${KERNEL_GIT_URL}/patch/?id=${commit_id}"
    local patch_file="$ORIGINAL_PWD/$CACHE_DIR/original_${commit_id}.patch"

    if [[ -f "$patch_file" ]] && [[ -s "$patch_file" ]]; then
        printf "%s" "$patch_file"
        return 2 # 2 = cache hit
    fi

    log_info "正在从 kernel.org 下载 commit: $commit_id" >&2
    if curl -s -f "$patch_url" -o "$patch_file" && [[ -s "$patch_file" ]]; then
        log_success "commit 下载成功" >&2
                printf "%s" "$patch_file"
        return 0 # 0 = downloaded
    else
        [[ -f "$patch_file" ]] && rm -f "$patch_file"
        log_error "commit 下载失败: $commit_id" >&2
        return 1 # 1 = failure
    fi
}

# (公开) 抓取原始补丁
fetch_patch() {
    local identifier="$1"
    [[ -z "$identifier" ]] && { log_error "请提供 commit ID 或补丁文件路径"; return 1; }
    
    log_info "获取 '$identifier' 的补丁..."
    
    local patch_file
    local fetch_result
    set +e
    patch_file=$(_fetch_patch_internal "$identifier")
    fetch_result=$?
    set -e
    
    if [[ $fetch_result -eq 0 ]]; then
        log_success "补丁已下载并缓存到: $patch_file"
    elif [[ $fetch_result -eq 2 ]]; then
        log_success "使用已缓存的补丁: $patch_file"
    elif [[ $fetch_result -eq 3 ]]; then
        log_success "使用本地补丁文件: $patch_file"
    else
        log_error "无法找到补丁。请检查 commit ID 或文件路径: $identifier"
        return 1
    fi
}

# 保存原始补丁到输出目录
save_patch() {
    local identifier="$1"
    local filename="$2"
    [[ -z "$identifier" ]] && { 
        log_error "请提供 commit ID、补丁文件路径或网址"
        log_info "可以使用以下格式："
        log_info "  - commit ID: abcdef123456 [filename]"
        log_info "  - 网址: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/patch/?id=<commit> [filename]"
        log_info "  - 本地文件: /path/to/patch.patch [filename]"
        log_info "输出目录: $ORIGINAL_PWD/$OUTPUT_DIR/"
        return 1
    }
    
    if [[ -z "$filename" ]]; then
        if [[ -f "$identifier" ]]; then
            filename=$(basename "$identifier")
        elif [[ "$identifier" =~ ^https?:// ]]; then
            # 对于网址，生成基于哈希的文件名
            local url_hash=$(echo -n "$identifier" | md5sum | cut -d' ' -f1)
            filename="url_${url_hash}.patch"
        else
            filename="${identifier}.patch"
        fi
    fi
    [[ ! "$filename" =~ \.patch$ ]] && filename="${filename}.patch"
    
    local output_path="$ORIGINAL_PWD/$OUTPUT_DIR/$filename"

    log_info "保存 '$identifier' 的原始补丁到输出目录..."
    
    local patch_file
    set +e
    patch_file=$(_fetch_patch_internal "$identifier")
    local fetch_result=$?
    set -e

    if [[ $fetch_result -eq 0 ]] || [[ $fetch_result -eq 2 ]] || [[ $fetch_result -eq 3 ]]; then
        cp "$patch_file" "$output_path"
        log_success "原始补丁已保存到: $output_path"
    else
        log_error "无法获取补丁: $identifier"
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
        printf "          智 能 冲 突 分 析 报 告 (Smart Conflict Analysis v7.3)\n"
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
    local identifier="$1"
    [[ -z "$identifier" ]] && { 
        log_error "请提供 commit ID、补丁文件路径或网址"
        log_info "可以使用以下格式："
        log_info "  - commit ID: abcdef123456"
        log_info "  - 网址: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/patch/?id=<commit>"
        log_info "  - 本地文件: /path/to/patch.patch 或 ./patch.patch"
        return 1
    }

    log_info "测试 '$identifier' 的补丁兼容性..."
    
    # 步骤 1: 获取补丁
    log_info "  -> 步骤 1/3: 获取补丁文件..."
    local patch_file
    local fetch_result
    
    # 打印用户友好的信息
    if [[ -f "$identifier" ]]; then
        log_info "     准备使用本地文件: $identifier"
    else
        local potential_patch_file="$ORIGINAL_PWD/$CACHE_DIR/original_${identifier}.patch"
        if [[ -f "$potential_patch_file" ]] && [[ -s "$potential_patch_file" ]]; then
            log_info "     检测到 commit '$identifier' 的本地缓存, 将直接使用。"
        else
            log_info "     本地无缓存, 准备从网络下载 commit '$identifier'..."
            local patch_url="${KERNEL_GIT_URL}/patch/?id=${identifier}"
            printf "       ${CYAN}命令: curl -fL -o \"%s\" \\\n             \"%s\"${NC}\n" "$potential_patch_file" "$patch_url"
        fi
    fi
    
    set +e
    patch_file=$(_fetch_patch_internal "$identifier")
    fetch_result=$?
    set -e
    
    if [[ $fetch_result -eq 0 ]]; then
        log_success "     补丁已成功下载并缓存。"
        printf "       ${CYAN}保存至: %s${NC}\n" "$patch_file"
    elif [[ $fetch_result -eq 2 ]]; then
        log_success "     成功使用已缓存的补丁。"
        printf "       ${CYAN}路径: %s${NC}\n" "$patch_file"
    elif [[ $fetch_result -eq 3 ]]; then
        log_success "     成功读取本地补丁文件。"
        printf "       ${CYAN}路径: %s${NC}\n" "$patch_file"
    else
        log_error "无法下载或找到补丁，请检查 Commit ID/文件路径或网络连接: $identifier"
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
        
        local report_name
        if [[ -f "$identifier" ]]; then
            report_name=$(basename "$identifier" .patch)
        elif [[ "$identifier" =~ ^https?:// ]]; then
            # 对于网址，生成基于哈希的报告名称
            local url_hash=$(echo -n "$identifier" | md5sum | cut -d' ' -f1)
            report_name="url_${url_hash:0:8}"
        else
            report_name=${identifier:0:7}
        fi
        local final_report_file="$ORIGINAL_PWD/$OUTPUT_DIR/test-patch-report-${report_name}.log"
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
    local identifier="$1"
    [[ -z "$identifier" ]] && { 
        log_error "请提供 commit ID、补丁文件路径或网址"
        log_info "可以使用以下格式："
        log_info "  - commit ID: abcdef123456"
        log_info "  - 网址: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/patch/?id=<commit>"
        log_info "  - 本地文件: /path/to/patch.patch 或 ./patch.patch"
        log_info "输出文件将保存到: $ORIGINAL_PWD/$OUTPUT_DIR/patch_files.txt"
        return 1
    }
    
    log_info "提取 '$identifier' 涉及的文件列表..."
    
    local patch_file
    set +e
    patch_file=$(_fetch_patch_internal "$identifier")
    local fetch_result=$?
    set -e
    
    if [[ $fetch_result -eq 1 ]]; then
        log_error "无法获取或找到有效的补丁文件 for '$identifier'"; return 1
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
    local identifier="$1"
    [[ -z "$identifier" ]] && { log_error "请提供 commit ID 或补丁文件路径"; return 1; }
    
    log_info "提取 '$identifier' 的元数据 (仅供查阅)..."
    
    local patch_file
    set +e
    patch_file=$(_fetch_patch_internal "$identifier")
    local fetch_result=$?
    set -e
    
    if [[ $fetch_result -eq 1 ]]; then
        log_error "无法获取补丁: $identifier"; return 1
    fi
    
    local output_path="$ORIGINAL_PWD/$OUTPUT_DIR/$PATCH_METADATA_FILE"
    
    # 如果是本地文件，可能没有元数据，提醒用户
    if [[ $fetch_result -eq 3 ]]; then
        log_warning "输入为本地补丁文件，它可能不包含标准的元数据头。"
    fi
    awk '/^diff --git/ {exit} {print}' "$patch_file" > "$output_path"

    log_success "元数据已保存到: $output_path"
}


# 创建新补丁
create_patch() {
    local patch_name="$1"
    [[ -z "$patch_name" ]] && { log_error "请提供补丁名称"; return 1; }
    [[ ! "$patch_name" =~ \.patch$ ]] && patch_name="${patch_name}.patch"
    
    # 自动保存原始 quilt 状态（首次调用时）
    save_original_quilt_state || return 1
    
    log_info "准备创建新补丁: $patch_name"

    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source_enhanced "创建补丁") || return 1

    (
        cd "$kernel_source_dir" || exit 1
        log_info "正在在目录 '$kernel_source_dir' 中创建补丁..."
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
    [[ -z "$file_list_name" ]] && { 
        log_error "请提供文件列表名"
        log_info "可以使用以下格式："
        log_info "  - 相对路径: patch_files.txt"
        log_info "  - 绝对路径: /path/to/file_list.txt"  
        log_info "  - 默认位置: $ORIGINAL_PWD/$OUTPUT_DIR/patch_files.txt"
        return 1
    }

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
    kernel_source_dir=$(find_kernel_source_enhanced "添加文件到补丁") || return 1

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
    kernel_source_dir=$(find_kernel_source_enhanced "刷新补丁") || return 1
    
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
    local identifier="$1"
    if [[ -z "$identifier" ]]; then
        # 检查是否存在默认的元数据文件
        local default_metadata_file="$ORIGINAL_PWD/$OUTPUT_DIR/patch_metadata.txt"
        if [[ -f "$default_metadata_file" ]]; then
            log_info "发现默认元数据文件，将使用: $default_metadata_file"
            identifier="$default_metadata_file"
        else
            log_error "请提供 commit_id 或本地文件路径以注入元数据"
            log_info "可以使用以下格式："
            log_info "  - commit ID: abcdef123456"
            log_info "  - 网址: https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/patch/?id=<commit>"
            log_info "  - 本地文件 (绝对路径): /path/to/patch.patch"
            log_info "  - 本地文件 (相对路径): ./my-patch.patch"
            log_info "  - 输出目录中的文件: $ORIGINAL_PWD/$OUTPUT_DIR/filename.patch"
            log_info "  - 或者先运行: extract-metadata <id|file|url> 生成默认元数据文件"
            return 1
        fi
    fi

    log_info "🔄 [核心] 刷新补丁并尝试从 '$identifier' 注入元数据..."

    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source_enhanced "刷新补丁并注入元数据") || return 1
    
    (
        cd "$kernel_source_dir" || exit 1
        
        local patch_path
        patch_path=$(quilt top 2>/dev/null) || { log_error "没有活动的 quilt 补丁"; exit 1; }
        log_info "当前补丁: $patch_path"
        
        local original_patch_file
        set +e
        original_patch_file=$(_fetch_patch_internal "$identifier")
        local fetch_result=$?
        set -e
        if [[ $fetch_result -eq 1 ]]; then
             log_error "无法获取原始补丁 '$identifier' 以提取元数据"; exit 1
        fi
        
        local header
        # 检查是否是 patch_metadata.txt 文件
        if [[ "$(basename "$original_patch_file")" == "$PATCH_METADATA_FILE" ]]; then
            # 如果是元数据文件，直接使用其内容作为头部
            header=$(cat "$original_patch_file")
            log_info "使用预提取的元数据文件: $(basename "$original_patch_file")"
        else
            # 否则从补丁文件中提取元数据头
            header=$(awk '/^diff --git/ {exit} {print}' "$original_patch_file")
        fi
        
        if [[ -z "$header" ]]; then
            log_warning "无法从 '$identifier' 提取元数据头 (可能不是标准的 commit 补丁)。"
            log_warning "将只执行标准 refresh 操作。"
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
    local identifier="$1"
    local patch_name="$2"
    [[ -z "$identifier" || -z "$patch_name" ]] && { print_help; return 1; }
    
    log_info "🚀 开始自动化补丁制作流程 for '$identifier'..."
    
    log_info "\n${YELLOW}--- 步骤 1/4: 兼容性测试 ---${NC}"
    if ! test_patch_compatibility "$identifier"; then
        log_warning "检测到冲突。请在后续步骤手动解决。"
        printf "${CYAN}是否要继续? (y/N): ${NC}"; read -r response
        [[ ! "$response" =~ ^[Yy]$ ]] && { log_info "用户终止流程"; return 0; }
    fi
    
    log_info "\n${YELLOW}--- 步骤 2/4: 创建补丁并添加文件 ---${NC}"
    create_patch "$patch_name"
    extract_files "$identifier"
    add_files "$PATCH_LIST_FILE"

    log_info "\n${YELLOW}--- 步骤 3/4: 等待手动修改 ---${NC}"
    log_warning "补丁已创建，文件已添加。现在是手动修改代码以解决冲突的最佳时机。"
    log_info "修改完成后，按 ${GREEN}Enter${NC}键继续以生成最终补丁..."
    read -r

    log_info "\n${YELLOW}--- 步骤 4/4: 生成带元数据的最终补丁 ---${NC}"
    quilt_refresh_with_header "$identifier"
    
    log_success "🎉 自动化流程完成!"
}

# 快速应用补丁到 OpenWrt (新增功能)
quick_apply_patch() {
    local patch_file_path="$1"
    
    # 参数验证
    if [[ -z "$patch_file_path" ]]; then
        log_error "请提供补丁文件的绝对路径"
        log_info "用法: quick-apply <补丁文件绝对路径>"
        log_info "示例: quick-apply /home/user/my-fix.patch"
        return 1
    fi
    
    # 检查补丁文件是否存在
    if [[ ! -f "$patch_file_path" ]]; then
        log_error "补丁文件不存在: $patch_file_path"
        return 1
    fi
    
    # 获取补丁文件名
    local patch_filename=$(basename "$patch_file_path")
    
    log_info "🚀 开始快速应用补丁: $patch_filename"
    log_info "📄 补丁文件: $patch_file_path"
    
    # 步骤 1: 查找 OpenWrt 补丁目录
    log_info "  -> 步骤 1/3: 查找目标补丁目录..."
    local patches_dir
    patches_dir=$(find_openwrt_patches_dir)
    if [[ $? -ne 0 ]]; then
        log_error "无法找到 OpenWrt 补丁目录"
        return 1
    fi
    
    log_success "     找到补丁目录: $patches_dir"
    
    # 复制补丁文件
    log_info "     复制补丁文件到目标目录..."
    local target_patch_path="$patches_dir/$patch_filename"
    
    if cp "$patch_file_path" "$target_patch_path"; then
        log_success "     ✅ 补丁已复制到: $target_patch_path"
    else
        log_error "     ❌ 补丁复制失败"
        return 1
    fi
    
    # 步骤 2: 删除 .prepare 文件
    log_info "  -> 步骤 2/3: 删除内核 .prepared 文件以触发重新准备..."
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source)
    
    if [[ $? -ne 0 || -z "$kernel_source_dir" ]]; then
        log_warning "     ⚠️  未找到已解压的内核源码目录"
        log_info "     这是正常的，make prepare 会重新解压并应用所有补丁"
    else
        local prepare_file="$kernel_source_dir/.prepared"
        if [[ -f "$prepare_file" ]]; then
            if rm "$prepare_file"; then
                log_success "     ✅ 已删除 .prepared 文件: $prepare_file"
            else
                log_warning "     ⚠️  删除 .prepared 文件失败，但不影响后续步骤"
            fi
        else
            log_info "     💡 .prepare 文件不存在，无需删除"
        fi
    fi
    
    # 步骤 3: 执行 make target/linux/prepare
    log_info "  -> 步骤 3/3: 执行 make V=s target/linux/prepare..."
    log_info "     这将重新准备内核源码并应用所有补丁（包括新添加的补丁）"
    
    # 确保在 OpenWrt 根目录执行
    local openwrt_root=""
    local current_dir="$ORIGINAL_PWD"
    
    # 查找 OpenWrt 根目录
    while [[ "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/.config" && -d "$current_dir/target/linux" ]]; then
            openwrt_root="$current_dir"
            break
        fi
        current_dir=$(dirname "$current_dir")
    done
    
    if [[ -z "$openwrt_root" ]]; then
        log_error "     ❌ 无法找到 OpenWrt 根目录"
        log_info "     💡 请在 OpenWrt 项目根目录下运行此命令"
        return 1
    fi
    
    log_info "     OpenWrt 根目录: $openwrt_root"
    
    # 执行 make 命令
    (
        cd "$openwrt_root" || exit 1
        log_info "     执行命令: make V=s target/linux/prepare"
        log_info "     请耐心等待，这可能需要几分钟时间..."
        
        if make V=s target/linux/prepare; then
            log_success "     ✅ make target/linux/prepare 执行成功"
        else
            log_error "     ❌ make target/linux/prepare 执行失败"
            log_info "     💡 请检查补丁是否有语法错误或冲突"
            exit 1
        fi
    )
    
    if [[ $? -eq 0 ]]; then
        log_success "🎉 补丁快速应用完成！"
        log_info "📋 执行总结:"
        log_info "   • 补丁文件: $patch_filename"
        log_info "   • 目标位置: $target_patch_path" 
        log_info "   • 内核已重新准备，新补丁已生效"
        log_info ""
        log_info "💡 后续建议:"
        log_info "   • 使用 'test-patch' 命令验证补丁应用情况"
        log_info "   • 继续编译: make V=s 或 make -j$(nproc)"
    else
        log_error "❌ 补丁应用过程中出现错误"
        return 1
    fi
}

    # --- 方案 C: 基于文件哈希的全局差异检测功能 ---

# (内部辅助函数) 绘制进度条
# 参数1: 当前值, 参数2: 总值
_draw_progress_bar() {
    local current=$1
    local total=$2
    local width=50
    local percentage=$(( current * 100 / total ))
    local completed_width=$(( width * percentage / 100 ))
    local remaining_width=$(( width - completed_width ))

    # 构建进度条字符串
    local completed_bar
    printf -v completed_bar "%*s" "$completed_width" ""
    local remaining_bar
    printf -v remaining_bar "%*s" "$remaining_width" ""

    # 使用 ANSI 转义字符 \r 将光标移到行首以实现动态刷新
    printf "\r[%s%s] %d%% (%d/%d)" "${completed_bar// /#}" "${remaining_bar}" "$percentage" "$current" "$total"
}

    # (内部辅助函数) 为快照处理单个文件
_process_file_for_snapshot() {
    local file="$1"
    local os_type="$2"
    local hash_cmd="$3"

    # 获取元数据: path;size;mtime
    local metadata
    if [[ "$os_type" == "Darwin" ]]; then
        # macOS: 手动构建格式字符串
        metadata="$file;$(stat -f "%z;%m" "$file")"
    else
        # Linux: 使用标准格式
        metadata=$(stat -c "%n;%s;%Y" "$file")
    fi
    
    # 计算哈希
    local hash
    hash=$($hash_cmd "$file" | cut -d " " -f 1)
    # 输出格式: <path>;<size>;<mtime>;<hash>
    printf "%s;%s\n" "$metadata" "$hash"
}

# 创建源码树快照 (基于 kernel_snapshot_tool)
snapshot_create() {
    local target_dir="${1:-.}" # 如果未提供参数，则默认为当前目录
    local project_name="${2:-snapshot-project}" # 可选的项目名称

    if [[ ! -d "$target_dir" ]]; then
        log_error "指定的目录不存在: $target_dir"
        return 1
    fi
    
    log_info "📸 正在为目录 '$target_dir' 创建源码树快照..."
    
    # 读取 kernel_snapshot_tool 的配置文件获取实际工作目录
    local config_file="$SCRIPT_DIR/kernel_snapshot_tool/.kernel_snapshot.conf"
    local actual_work_dir="$target_dir"
    
    if [[ -f "$config_file" ]]; then
        # 解析配置文件中的 default_workspace_dir
        local configured_dir
        configured_dir=$(grep "^default_workspace_dir=" "$config_file" | cut -d'=' -f2)
        
        if [[ -n "$configured_dir" && -d "$configured_dir" ]]; then
            actual_work_dir="$configured_dir"
            log_info "使用配置文件中的工作目录: $actual_work_dir"
        fi
    fi
    
    # 使用实际工作目录进行文件统计
    log_info "正在计算文件总数..."
    local total_files
    
    # 解析配置文件中的忽略模式
    local ignore_patterns=""
    if [[ -f "$config_file" ]]; then
        ignore_patterns=$(grep "^ignore_patterns=" "$config_file" | cut -d'=' -f2)
    fi
    
    # 构建find命令的排除参数
    local find_excludes="-not -path '*/.snapshot/*' -not -path './$MAIN_WORK_DIR/*'"
    
    if [[ -n "$ignore_patterns" ]]; then
        log_info "应用忽略模式: $ignore_patterns"
        # 将逗号分隔的模式转换为find命令的排除参数
        IFS=',' read -ra patterns <<< "$ignore_patterns"
        for pattern in "${patterns[@]}"; do
            # 去除前后空格
            pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ -n "$pattern" ]]; then
                if [[ "$pattern" == *.* ]]; then
                    # 处理文件扩展名模式 (如 *.o, *.so)
                    find_excludes="$find_excludes -not -name '$pattern'"
                elif [[ "$pattern" == *\** ]]; then
                    # 处理通配符模式 (如 temp*)
                    find_excludes="$find_excludes -not -name '$pattern'"
                else
                    # 处理目录名或精确匹配 (如 .git, .svn)
                    find_excludes="$find_excludes -not -path '*/$pattern' -not -path '*/$pattern/*' -not -name '$pattern'"
                fi
            fi
        done
    fi
    
    # 执行find命令统计文件数量
    local find_cmd="find \"$actual_work_dir\" -type f $find_excludes"
    log_info "执行统计命令: $find_cmd"
    total_files=$(eval "$find_cmd" | wc -l | tr -d ' ')
    
    if [[ $total_files -eq 0 ]]; then
        log_warning "在 '$actual_work_dir' 中没有找到任何文件。"
        return 1
    fi
    log_info "共计 $total_files 个文件需要处理。"
    
    # 尝试调用 kernel_snapshot_tool 的 create 命令
    local tool_path="$SCRIPT_DIR/kernel_snapshot_tool/kernel_snapshot"
    if [[ -f "$tool_path" ]]; then
        log_info "使用 kernel_snapshot_tool 创建快照..."
        if [[ "$target_dir" == "." ]]; then
            # 当前目录模式
            "$tool_path" create "$project_name"
        else
            # 指定目录模式
            "$tool_path" create "$target_dir" "$project_name"
        fi
        return $?
    else
        log_error "kernel_snapshot_tool 未找到: $tool_path"
        log_info "请先编译 kernel_snapshot_tool: cd kernel_snapshot_tool && make"
        return 1
    fi
}

# 对比快照并输出差异文件列表
snapshot_diff() {
    local user_dir="$1" # 用户可能指定的子目录
    
    # 尝试调用 kernel_snapshot_tool 的 diff 命令
    local tool_path="$SCRIPT_DIR/kernel_snapshot_tool/kernel_snapshot"
    if [[ -f "$tool_path" ]]; then
        log_info "🔎 使用 kernel_snapshot_tool 对比快照..."
        if [[ -n "$user_dir" ]]; then
            cd "$user_dir" || { log_error "无法进入目录: $user_dir"; return 1; }
        fi
        
        local snapshot_output
        snapshot_output=$("$tool_path" diff -Q 2>&1)
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]]; then
            log_error "快照对比失败: $snapshot_output"
            return 1
        fi
        
        # 保存文件列表到工作目录
        mkdir -p "$ORIGINAL_PWD/$MAIN_WORK_DIR"
        echo "$snapshot_output" | tee "$ORIGINAL_PWD/$MAIN_WORK_DIR/patch_files.txt"
        
        if [[ -z "$snapshot_output" ]]; then
            log_info "✅ 没有检测到文件变化"
            return 0
        fi
        
        local file_count
        file_count=$(echo "$snapshot_output" | wc -l | tr -d ' ')
        log_info "📝 检测到 $file_count 个文件变化，文件列表已保存到: $ORIGINAL_PWD/$MAIN_WORK_DIR/patch_files.txt"
        
        return 0
    else
        log_error "kernel_snapshot_tool 未找到: $tool_path"
        log_info "请先编译 kernel_snapshot_tool: cd kernel_snapshot_tool && make"
        return 1
    fi
    
    local current_manifest
    current_manifest=$(mktemp)
    
    find "$final_target_dir" -type f -not -path "./$MAIN_WORK_DIR/*" -exec bash -c '
        file="$1"
        os_type="$2"
        hash_cmd="$3"
        if [[ "$os_type" == "Darwin" ]]; then
            metadata="$file;$(stat -f "%z;%m" "$file")"
        else
            metadata=$(stat -c "%n;%s;%Y" "$file")
        fi
        hash=$($hash_cmd "$file" | cut -d " " -f 1)
        printf "%s;%s\n" "$metadata" "$hash"
    ' _ {} "$(uname)" "$hash_cmd" \; | sed 's|^\./||' > "$current_manifest"

    # 2. 调用 C 语言编写的高性能辅助工具
    local helper_path="$SCRIPT_DIR/snapshot_tool/snapshot_helper"
    if [[ ! -f "$helper_path" ]]; then
        log_warning "快照辅助工具 '$helper_path' 未找到, 尝试在 '$SCRIPT_DIR/snapshot_tool' 编译..."
        if ! (cd "$SCRIPT_DIR/snapshot_tool" && make); then
            log_error "编译失败, 请检查 'snapshot_tool' 目录下的源码和 Makefile。"; return 1
        fi
        log_success "辅助工具编译成功。"
    fi
    
    local old_manifest_no_meta
    old_manifest_no_meta=$(mktemp)
    grep -v '^#' "$manifest_path" | sed 's|^\./||' > "$old_manifest_no_meta"

    local diff_output
    diff_output=$("$helper_path" "$old_manifest_no_meta" "$current_manifest" "$final_target_dir")
    
    rm "$current_manifest"
    rm "$old_manifest_no_meta"

    # 3. 报告结果
    local end_time; end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_info "对比完成, 耗时 ${duration} 秒。"
    
    local report_part; report_part=$(echo "$diff_output" | sed '/^---$/,$d')
    local file_list_part; file_list_part=$(echo "$diff_output" | sed '1,/^---$/d')

    if [[ -z "$report_part" ]]; then
        log_info "✅ 未发现任何文件变更。"
    else
        echo "$report_part" | sed \
            -e 's/^\[+\] /\'$'\033[0;32m''[SUCCESS]\'$'\033[0m'' Found new file: /' \
            -e 's/^\[M\] /\'$'\033[0;32m''[SUCCESS]\'$'\033[0m'' Found modified file: /' \
            -e 's/^\[-\] /\'$'\033[1;33m''[WARNING]\'$'\033[0m'' Found deleted file: /'
    fi

    if [[ -n "$file_list_part" ]]; then
        echo "$file_list_part"
    fi
}

# 检查快照状态 (基于 kernel_snapshot_tool)
snapshot_status() {
    local user_dir="$1" # 用户可能指定的子目录
    
    # 尝试调用 kernel_snapshot_tool 的 status 命令
    local tool_path="$SCRIPT_DIR/kernel_snapshot_tool/kernel_snapshot"
    if [[ -f "$tool_path" ]]; then
        log_info "🔍 使用 kernel_snapshot_tool 检查快照状态..."
        if [[ -n "$user_dir" ]]; then
            cd "$user_dir" || { log_error "无法进入目录: $user_dir"; return 1; }
        fi
        "$tool_path" status
        return $?
    else
        log_error "kernel_snapshot_tool 未找到: $tool_path"
        log_info "请先编译 kernel_snapshot_tool: cd kernel_snapshot_tool && make"
        return 1
    fi
}

# 列出所有变更文件 (新增+修改)
snapshot_list_changes() {
    local user_dir="$1"
    
    local tool_path="$SCRIPT_DIR/kernel_snapshot_tool/kernel_snapshot"
    if [[ -f "$tool_path" ]]; then
        log_info "📝 使用 kernel_snapshot_tool 列出所有变更文件..."
        if [[ -n "$user_dir" ]]; then
            cd "$user_dir" || { log_error "无法进入目录: $user_dir"; return 1; }
        fi
        
        # 确保输出目录存在
        mkdir -p "$MAIN_WORK_DIR"
        local output_file="$MAIN_WORK_DIR/changed_files.txt"
        
        # 执行命令并同时输出到终端和文件
        "$tool_path" list-changes | tee "$output_file"
        local exit_code=${PIPESTATUS[0]}
        
        if [[ $exit_code -eq 0 && -f "$output_file" ]]; then
            log_info "💾 变更文件列表已保存到: $output_file"
        fi
        return $exit_code
    else
        log_error "kernel_snapshot_tool 未找到: $tool_path"
        log_info "请先编译 kernel_snapshot_tool: cd kernel_snapshot_tool && make"
        return 1
    fi
}

# 仅列出新增文件
snapshot_list_new() {
    local user_dir="$1"
    
    local tool_path="$SCRIPT_DIR/kernel_snapshot_tool/kernel_snapshot"
    if [[ -f "$tool_path" ]]; then
        log_info "🆕 使用 kernel_snapshot_tool 列出新增文件..."
        if [[ -n "$user_dir" ]]; then
            cd "$user_dir" || { log_error "无法进入目录: $user_dir"; return 1; }
        fi
        
        # 确保输出目录存在
        mkdir -p "$MAIN_WORK_DIR"
        local output_file="$MAIN_WORK_DIR/new_files.txt"
        
        # 执行命令并同时输出到终端和文件
        "$tool_path" list-new | tee "$output_file"
        local exit_code=${PIPESTATUS[0]}
        
        if [[ $exit_code -eq 0 && -f "$output_file" ]]; then
            log_info "💾 新增文件列表已保存到: $output_file"
        fi
        return $exit_code
    else
        log_error "kernel_snapshot_tool 未找到: $tool_path"
        log_info "请先编译 kernel_snapshot_tool: cd kernel_snapshot_tool && make"
        return 1
    fi
}

# 仅列出修改文件
snapshot_list_modified() {
    local user_dir="$1"
    
    local tool_path="$SCRIPT_DIR/kernel_snapshot_tool/kernel_snapshot"
    if [[ -f "$tool_path" ]]; then
        log_info "✏️ 使用 kernel_snapshot_tool 列出修改文件..."
        if [[ -n "$user_dir" ]]; then
            cd "$user_dir" || { log_error "无法进入目录: $user_dir"; return 1; }
        fi
        
        # 确保输出目录存在
        mkdir -p "$MAIN_WORK_DIR"
        local output_file="$MAIN_WORK_DIR/modified_files.txt"
        
        # 执行命令并同时输出到终端和文件
        "$tool_path" list-modified | tee "$output_file"
        local exit_code=${PIPESTATUS[0]}
        
        if [[ $exit_code -eq 0 && -f "$output_file" ]]; then
            log_info "💾 修改文件列表已保存到: $output_file"
        fi
        return $exit_code
    else
        log_error "kernel_snapshot_tool 未找到: $tool_path"
        log_info "请先编译 kernel_snapshot_tool: cd kernel_snapshot_tool && make"
        return 1
    fi
}

# 导出变更文件到输出目录，保持原目录结构
export_changed_files() {
    local output_base_dir="$ORIGINAL_PWD/$OUTPUT_DIR/changed_files"
    
    log_info "🚀 开始导出变更文件到输出目录..."
    
    # 1. 先获取变更文件列表
    local changed_files_list="$ORIGINAL_PWD/$MAIN_WORK_DIR/changed_files.txt"
    
    # 调用 snapshot-list-changes 获取变更文件列表
    if ! ./quilt_patch_manager_final.sh snapshot-list-changes > /dev/null; then
        log_error "获取变更文件列表失败"
        return 1
    fi
    
    if [[ ! -f "$changed_files_list" || ! -s "$changed_files_list" ]]; then
        log_warning "📝 没有检测到文件变化，无需导出"
        return 0
    fi
    
    # 2. 创建输出根目录（先清理再创建）
    rm -rf "$output_base_dir" 2>/dev/null || true
    mkdir -p "$output_base_dir"
    
    # 3. 获取内核源码目录
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source_enhanced "导出文件") || { log_error "未找到内核源码目录"; return 1; }
    
    # 4. 动态获取内核目录名（只取最后一级目录名）
    local kernel_dir_name
    kernel_dir_name=$(basename "$kernel_source_dir")
    local kernel_output_dir="$output_base_dir/$kernel_dir_name"
    
    # 创建内核目录
    mkdir -p "$kernel_output_dir"
    
    # 5. 按原目录结构复制文件
    local file_count=0
    local success_count=0
    
    while IFS= read -r relative_file_path; do
        # 跳过空行
        [[ -z "$relative_file_path" ]] && continue
        
        file_count=$((file_count + 1))
        
        local src_file="$kernel_source_dir/$relative_file_path"
        local dst_file="$kernel_output_dir/$relative_file_path"
        local dst_dir=$(dirname "$dst_file")
        
        # 创建目标目录结构
        if ! mkdir -p "$dst_dir"; then
            log_warning "⚠️ 无法创建目录: $dst_dir"
            continue
        fi
        
        # 复制文件
        if [[ -f "$src_file" ]]; then
            if cp "$src_file" "$dst_file"; then
                log_info "✅ 已复制: $relative_file_path"
                success_count=$((success_count + 1))
            else
                log_warning "⚠️ 复制失败: $relative_file_path"
            fi
        else
            log_warning "⚠️ 源文件不存在: $src_file"
        fi
    done < "$changed_files_list"
    
    # 6. 创建索引文件
    local index_file="$output_base_dir/EXPORT_INDEX.txt"
    {
        echo "# 变更文件导出索引"
        echo "# 导出时间: $(date)"
        echo "# 内核源码目录: $kernel_source_dir"
        echo "# 内核目录名: $kernel_dir_name"
        echo "# 总文件数: $file_count"
        echo "# 成功复制: $success_count"
        echo ""
        echo "# 导出结构:"
        echo "# $output_base_dir/"
        echo "#   ├── $kernel_dir_name/          <- 内核文件目录"
        echo "#   │   ├── (变更的文件...)"
        echo "#   └── EXPORT_INDEX.txt          <- 本文件"
        echo ""
        echo "# 文件列表 (相对于 $kernel_dir_name/ 目录):"
        cat "$changed_files_list"
    } > "$index_file"
    
    log_success "🎉 变更文件导出完成！"
    log_info "📁 导出根目录: $output_base_dir"
    log_info "📁 内核文件目录: $kernel_output_dir"
    log_info "📊 统计: 成功 $success_count/$file_count 个文件"
    log_info "📄 索引文件: $index_file"
}

# 基于指定文件列表导出文件到输出目录，保持原目录结构
export_from_file() {
    local file_list_path="$1"
    
    if [[ -z "$file_list_path" ]]; then
        log_error "❌ 用法: export-from-file <文件列表路径>"
        log_info "💡 示例: ./quilt_patch_manager_final.sh export-from-file /path/to/file_list.txt"
        return 1
    fi
    
    # 验证文件列表文件是否存在
    if [[ ! -f "$file_list_path" ]]; then
        log_error "❌ 文件列表不存在: $file_list_path"
        return 1
    fi
    
    # 验证文件列表是否为空
    if [[ ! -s "$file_list_path" ]]; then
        log_warning "📝 文件列表为空，无需导出"
        return 0
    fi
    
    log_info "🚀 开始基于文件列表导出文件..."
    log_info "📝 文件列表: $file_list_path"
    
    # 1. 获取全局配置中的default_workspace_dir
    local config_file="$SCRIPT_DIR/kernel_snapshot_tool/.kernel_snapshot.conf"
    local kernel_source_dir=""
    
    if [[ -f "$config_file" ]]; then
        kernel_source_dir=$(grep "^default_workspace_dir=" "$config_file" | cut -d'=' -f2)
        
        if [[ -z "$kernel_source_dir" ]]; then
            log_error "❌ 全局配置文件中的 default_workspace_dir 为空"
            log_info "💡 配置文件: $config_file"
            log_info "💡 请设置 default_workspace_dir=/path/to/your/kernel/source"
            return 1
        fi
        
        if [[ ! -d "$kernel_source_dir" ]]; then
            log_error "❌ default_workspace_dir 指向的目录不存在: $kernel_source_dir"
            log_info "💡 请检查配置文件: $config_file"
            return 1
        fi
        
        # 验证是否是有效的内核目录
        if [[ ! -f "$kernel_source_dir/Makefile" ]] || ! grep -q "KERNELRELEASE" "$kernel_source_dir/Makefile" 2>/dev/null; then
            log_warning "⚠️ 目录不是有效的内核源码目录，但继续执行"
            log_warning "   目录: $kernel_source_dir"
            log_warning "   原因: 缺少Makefile或KERNELRELEASE标识"
        fi
    else
        log_error "❌ 未找到全局配置文件: $config_file"
        log_info "💡 请确保kernel_snapshot_tool配置文件存在"
        return 1
    fi
    
    log_success "✅ 使用内核源码目录: $kernel_source_dir"
    
    # 2. 创建输出目录
    local output_base_dir="$ORIGINAL_PWD/$OUTPUT_DIR/exported_files"
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    local export_session_dir="$output_base_dir/export_$timestamp"
    
    rm -rf "$export_session_dir" 2>/dev/null || true
    mkdir -p "$export_session_dir"
    
    # 3. 动态获取内核目录名（只取最后一级目录名）
    local kernel_dir_name
    kernel_dir_name=$(basename "$kernel_source_dir")
    local kernel_output_dir="$export_session_dir/$kernel_dir_name"
    
    # 创建内核目录
    mkdir -p "$kernel_output_dir"
    
    # 4. 按原目录结构复制文件
    local file_count=0
    local success_count=0
    local failed_files=()
    
    while IFS= read -r relative_file_path; do
        # 跳过空行和注释行
        [[ -z "$relative_file_path" || "$relative_file_path" =~ ^[[:space:]]*# ]] && continue
        
        # 去除行首行尾空格
        relative_file_path=$(echo "$relative_file_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$relative_file_path" ]] && continue
        
        file_count=$((file_count + 1))
        
        local src_file="$kernel_source_dir/$relative_file_path"
        local dst_file="$kernel_output_dir/$relative_file_path"
        local dst_dir=$(dirname "$dst_file")
        
        # 创建目标目录结构
        if ! mkdir -p "$dst_dir"; then
            log_warning "⚠️ 无法创建目录: $dst_dir"
            failed_files+=("$relative_file_path (目录创建失败)")
            continue
        fi
        
        # 复制文件
        if [[ -f "$src_file" ]]; then
            if cp "$src_file" "$dst_file"; then
                log_info "✅ 已复制: $relative_file_path"
                success_count=$((success_count + 1))
            else
                log_warning "⚠️ 复制失败: $relative_file_path"
                failed_files+=("$relative_file_path (复制失败)")
            fi
        else
            log_warning "⚠️ 源文件不存在: $src_file"
            failed_files+=("$relative_file_path (源文件不存在)")
        fi
    done < "$file_list_path"
    
    # 5. 创建详细的索引文件
    local index_file="$export_session_dir/EXPORT_INDEX.txt"
    {
        echo "# 基于文件列表的导出索引"
        echo "# 导出时间: $(date)"
        echo "# 导出会话: export_$timestamp"
        echo "# 文件列表: $file_list_path"
        echo "# 内核源码目录: $kernel_source_dir"
        echo "# 内核目录名: $kernel_dir_name"
        echo "# 总文件数: $file_count"
        echo "# 成功复制: $success_count"
        echo "# 失败文件: $((file_count - success_count))"
        echo ""
        echo "# 导出结构:"
        echo "# $export_session_dir/"
        echo "#   ├── $kernel_dir_name/          <- 内核文件目录"
        echo "#   │   ├── (导出的文件...)"
        echo "#   └── EXPORT_INDEX.txt          <- 本文件"
        echo ""
        echo "# 成功导出的文件列表 (相对于 $kernel_dir_name/ 目录):"
        while IFS= read -r relative_file_path; do
            [[ -z "$relative_file_path" || "$relative_file_path" =~ ^[[:space:]]*# ]] && continue
            relative_file_path=$(echo "$relative_file_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            [[ -z "$relative_file_path" ]] && continue
            
            if [[ -f "$kernel_output_dir/$relative_file_path" ]]; then
                echo "$relative_file_path"
            fi
        done < "$file_list_path"
        
        if [[ ${#failed_files[@]} -gt 0 ]]; then
            echo ""
            echo "# 失败文件列表:"
            for failed_file in "${failed_files[@]}"; do
                echo "# $failed_file"
            done
        fi
    } > "$index_file"
    
    # 6. 创建简化的成功文件列表（便于后续使用）
    local success_files_list="$export_session_dir/successful_files.txt"
    while IFS= read -r relative_file_path; do
        [[ -z "$relative_file_path" || "$relative_file_path" =~ ^[[:space:]]*# ]] && continue
        relative_file_path=$(echo "$relative_file_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$relative_file_path" ]] && continue
        
        if [[ -f "$kernel_output_dir/$relative_file_path" ]]; then
            echo "$relative_file_path"
        fi
    done < "$file_list_path" > "$success_files_list"
    
    # 7. 显示结果
    log_success "🎉 基于文件列表的导出完成！"
    log_info "📁 导出会话目录: $export_session_dir"
    log_info "📁 内核文件目录: $kernel_output_dir"
    log_info "📊 统计: 成功 $success_count/$file_count 个文件"
    log_info "📄 详细索引: $index_file"
    log_info "📄 成功文件列表: $success_files_list"
    
    if [[ ${#failed_files[@]} -gt 0 ]]; then
        log_warning "⚠️ 有 ${#failed_files[@]} 个文件导出失败，详情请查看索引文件"
    fi
    
    # 8. 创建最新导出的软链接（便于快速访问）
    local latest_link="$output_base_dir/latest"
    rm -f "$latest_link" 2>/dev/null || true
    ln -sf "export_$timestamp" "$latest_link"
    log_info "🔗 最新导出链接: $latest_link"
}


# 清理快照数据 (基于 kernel_snapshot_tool)
snapshot_clean() {
    local force_flag="$1"
    
    local tool_path="$SCRIPT_DIR/kernel_snapshot_tool/kernel_snapshot"
    if [[ -f "$tool_path" ]]; then
        log_info "🧹 使用 kernel_snapshot_tool 清理快照数据..."
        if [[ "$force_flag" == "force" ]]; then
            "$tool_path" clean force
        else
            "$tool_path" clean
        fi
        return $?
    else
        log_error "kernel_snapshot_tool 未找到: $tool_path"
        log_info "请先编译 kernel_snapshot_tool: cd kernel_snapshot_tool && make"
        return 1
    fi
}

# 强制重置 quilt 状态到原始状态 (无需用户确认，用于 distclean)
force_reset_env() {
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source_enhanced "重置quilt环境") || { log_error "未找到内核源码目录"; return 1; }
    
    local backup_file="$MAIN_WORK_DIR/original_quilt_state.backup"
    local backup_dir="$MAIN_WORK_DIR/original_patches_backup"
    
    if [[ ! -f "$ORIGINAL_PWD/$backup_file" ]]; then
        log_warning "⚠️ 未找到原始状态备份文件: $backup_file"
        log_warning "⚠️ 为安全起见，跳过 quilt 重置操作，避免意外删除现有补丁"
        log_info "💡 如需创建备份文件，请先运行 'create-patch' 命令"
        return 0
    fi
    
    log_info "📖 强制重置到原始 quilt 状态..."
    
    (
        cd "$kernel_source_dir" || exit 1
        
        log_info "撤销所有补丁..."
        quilt pop -a -f > /dev/null 2>&1 || true
        
        log_info "还原原始 patches 目录..."
        # 只有当有备份文件时才删除现有的 patches 目录
        rm -rf patches 2>/dev/null || true
        
        if grep -q "PATCHES_DIR_EXISTS: YES" "$backup_file"; then
            if [[ -d "$backup_dir" ]]; then
                cp -r "$backup_dir" patches
                log_info "✅ 已还原原始 patches 目录"
            fi
        else
            log_info "💡 原始状态无 patches 目录"
        fi
        
        log_info "清理 quilt 状态..."
        rm -rf .pc 2>/dev/null || true
    )
    
    log_success "✅ quilt 状态已重置到原始状态"
}

# 彻底清理环境 (distclean: snapshot-clean force + reset-env force + clean)
distclean_env() {
    log_info "🚀 开始彻底清理环境到最干净状态..."
    
    echo "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "📊 第1步: 强制清理快照数据 (snapshot-clean force)"
    echo "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if ! snapshot_clean force; then
        log_warning "快照清理失败或无快照数据，继续执行下一步..."
    else
        log_success "✅ 快照数据清理完成。"
    fi
    
    echo ""
    echo "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "📊 第2步: 强制重置内核 quilt 状态到原始状态"
    echo "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 检查是否有备份文件
    local backup_file="$MAIN_WORK_DIR/original_quilt_state.backup"
    if [[ -f "$ORIGINAL_PWD/$backup_file" ]]; then
        force_reset_env
    else
        log_warning "⚠️ 未找到原始状态备份文件，跳过 quilt 重置步骤"
        log_info "💡 当前 quilt 环境将保持不变"
    fi
    
    echo ""
    echo "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "📊 第3步: 清理工作目录和缓存 (clean)"
    echo "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 强制清理工作目录，无需用户确认
    force_clean_work_dir
    
    echo ""
    echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_success "🎉 环境彻底清理完成！现在处于最干净的原始状态。"
    log_info "💡 提示: 内核已恢复到最初的 quilt 环境，可以安全地开始新的补丁制作流程。"
    echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    return 0
}



# 强制清理工作目录 (无需用户确认，用于 distclean)
force_clean_work_dir() {
    log_info "🧹 强制清理工作目录: $MAIN_WORK_DIR..."
    
    # 强制清理缓存目录
    if [[ -d "$ORIGINAL_PWD/$CACHE_DIR" ]]; then
        log_info "清理缓存目录: $ORIGINAL_PWD/$CACHE_DIR"
        rm -rf "$ORIGINAL_PWD/$CACHE_DIR"
        log_success "✅ 缓存目录已清理。"
    else
        log_info "💡 缓存目录不存在，跳过。"
    fi
    
    # 强制清理输出目录
    if [[ -d "$ORIGINAL_PWD/$OUTPUT_DIR" ]]; then
        log_info "清理输出目录: $ORIGINAL_PWD/$OUTPUT_DIR"
        rm -rf "$ORIGINAL_PWD/$OUTPUT_DIR"
        log_success "✅ 输出目录已清理。"
    else
        log_info "💡 输出目录不存在，跳过。"
    fi
    
    # 强制清理工作目录
    if [[ -d "$MAIN_WORK_DIR" ]]; then
        log_info "清理工作目录: $MAIN_WORK_DIR"
        rm -rf "$MAIN_WORK_DIR"
        log_success "✅ 工作目录已清理。"
    else
        log_info "💡 工作目录不存在，跳过。"
    fi
    
    log_success "🎉 工作目录强制清理完成！"
}

# 清理工作目录 (交互式)
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

# 保存内核的原始 quilt 状态
save_original_quilt_state() {
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source_enhanced "保存quilt状态") || { log_error "未找到内核源码目录"; return 1; }
    
    local backup_file="$MAIN_WORK_DIR/original_quilt_state.backup"
    local backup_dir="$MAIN_WORK_DIR/original_patches_backup"
    
    # 如果已经有备份，跳过
    if [[ -f "$backup_file" ]]; then
        log_info "💡 原始状态备份已存在，跳过保存。"
        return 0
    fi
    
    log_info "💾 保存内核原始 quilt 状态..."
    
    # 确保工作目录存在
    mkdir -p "$MAIN_WORK_DIR"
    
    (
        cd "$kernel_source_dir" || exit 1
        
        # 保存当前 quilt 应用状态
        echo "# 内核原始 quilt 状态备份" > "$ORIGINAL_PWD/$backup_file"
        echo "# 备份时间: $(date)" >> "$ORIGINAL_PWD/$backup_file"
        echo "# 内核目录: $kernel_source_dir" >> "$ORIGINAL_PWD/$backup_file"
        echo "" >> "$ORIGINAL_PWD/$backup_file"
        
        # 保存当前应用的补丁列表
        echo "APPLIED_PATCHES:" >> "$ORIGINAL_PWD/$backup_file"
        if quilt applied 2>/dev/null; then
            quilt applied >> "$ORIGINAL_PWD/$backup_file" 2>/dev/null || echo "NONE" >> "$ORIGINAL_PWD/$backup_file"
        else
            echo "NONE" >> "$ORIGINAL_PWD/$backup_file"
        fi
        echo "" >> "$ORIGINAL_PWD/$backup_file"
        
        # 保存未应用的补丁列表
        echo "UNAPPLIED_PATCHES:" >> "$ORIGINAL_PWD/$backup_file"
        if quilt unapplied 2>/dev/null; then
            quilt unapplied >> "$ORIGINAL_PWD/$backup_file" 2>/dev/null || echo "NONE" >> "$ORIGINAL_PWD/$backup_file"
        else
            echo "NONE" >> "$ORIGINAL_PWD/$backup_file"
        fi
        echo "" >> "$ORIGINAL_PWD/$backup_file"
        
        # 备份 patches 目录（如果存在）
        if [[ -d "patches" ]]; then
            log_info "📁 备份 patches 目录..."
            cp -r patches "$ORIGINAL_PWD/$backup_dir" 2>/dev/null || true
            echo "PATCHES_DIR_EXISTS: YES" >> "$ORIGINAL_PWD/$backup_file"
        else
            echo "PATCHES_DIR_EXISTS: NO" >> "$ORIGINAL_PWD/$backup_file"
        fi
        
        # 备份 .pc 目录状态信息
        if [[ -d ".pc" ]]; then
            echo "QUILT_PC_EXISTS: YES" >> "$ORIGINAL_PWD/$backup_file"
            echo "PC_DIR_CONTENTS:" >> "$ORIGINAL_PWD/$backup_file"
            find .pc -type f 2>/dev/null | head -20 >> "$ORIGINAL_PWD/$backup_file" || true
        else
            echo "QUILT_PC_EXISTS: NO" >> "$ORIGINAL_PWD/$backup_file"
        fi
    )
    
    log_success "✅ 原始状态已保存到: $backup_file"
}

# 重置 quilt 和内核源码树到原始状态
reset_env() {
    log_warning "🔥 [危险] 此操作将重置 Quilt 和内核源码到原始状态 🔥"
    printf "${YELLOW}该操作将还原到最初的内核 quilt 环境状态\n"
    printf "确定要继续吗? (y/N): ${NC}"
    read -r response
    [[ ! "$response" =~ ^[Yy]$ ]] && { log_info "用户取消操作"; return 0; }
    
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source_enhanced "重置quilt环境") || { log_error "未找到内核源码目录"; return 1; }
    
    local backup_file="$MAIN_WORK_DIR/original_quilt_state.backup"
    local backup_dir="$MAIN_WORK_DIR/original_patches_backup"
    
    if [[ ! -f "$ORIGINAL_PWD/$backup_file" ]]; then
        log_error "❌ 未找到原始状态备份文件: $backup_file"
        log_info "💡 提示: 请先运行一些补丁操作，系统会自动创建备份。"
        return 1
    fi
    
    log_info "📖 读取原始状态备份..."
    
    (
        cd "$kernel_source_dir" || exit 1
        
        log_info "1/3 强制撤销所有补丁..."
        quilt pop -a -f > /dev/null 2>&1 || true
        log_success "✅ 所有补丁已撤销"

        log_info "2/3 还原原始 patches 目录..."
        # 删除当前的 patches 目录
        rm -rf patches 2>/dev/null || true
        
        # 检查原始状态是否有 patches 目录
        if grep -q "PATCHES_DIR_EXISTS: YES" "$ORIGINAL_PWD/$backup_file"; then
            if [[ -d "$ORIGINAL_PWD/$backup_dir" ]]; then
                cp -r "$ORIGINAL_PWD/$backup_dir" patches
                log_success "✅ 已还原原始 patches 目录"
            else
                log_warning "⚠️ 备份的 patches 目录不存在"
            fi
        else
            log_info "💡 原始状态无 patches 目录，保持删除状态"
        fi
        
        log_info "3/3 清理 quilt 状态..."
        rm -rf .pc 2>/dev/null || true
        log_success "✅ quilt 状态已清理"
    )

    clean_work_dir
    log_success "🎉 环境已重置到原始状态！"
}

# quilt status - 显示补丁状态
show_quilt_status() {
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source_enhanced "quilt status") || { log_error "未找到内核源码目录"; return 1; }
    
    ( 
        cd "$kernel_source_dir" || exit 1
        
        log_info "📊 Quilt 补丁状态："
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        
        # 检查是否有补丁目录
        if [[ ! -d "patches" ]]; then
            log_warning "📄 没有发现 patches 目录"
            return 0
        fi
        
        # 获取补丁系列信息
        local total_patches=0
        local applied_patches=0
        local current_patch=""
        
        if quilt series >/dev/null 2>&1; then
            total_patches=$(quilt series 2>/dev/null | wc -l | tr -d ' ')
            applied_patches=$(quilt applied 2>/dev/null | wc -l | tr -d ' ')
            current_patch=$(quilt top 2>/dev/null || echo "无")
        fi
        
        printf "  📦 ${CYAN}补丁总数${NC}: $total_patches\n"
        printf "  ✅ ${GREEN}已应用${NC}: $applied_patches\n"
        printf "  ❌ ${YELLOW}未应用${NC}: $((total_patches - applied_patches))\n"
        printf "  🔝 ${PURPLE}顶部补丁${NC}: $current_patch\n"
        
        printf "\n"
    )
}

# quilt 命令的通用执行器
run_quilt_command() {
    local quilt_cmd="$1"; shift
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source_enhanced "quilt $quilt_cmd") || { log_error "未找到内核源码目录"; return 1; }
    ( cd "$kernel_source_dir" || exit 1; quilt "$quilt_cmd" "$@"; )
}

# quilt graph 的专用执行器 (确保输出纯净的 DOT 格式)
run_quilt_graph() {
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source_enhanced "quilt graph") || { log_error "未找到内核源码目录"; return 1; }
    
    # 禁用颜色输出，确保生成纯净的 DOT 格式
    ( 
        cd "$kernel_source_dir" || exit 1
        # 设置环境变量禁用颜色输出
        export NO_COLOR=1
        export TERM=dumb
        # 执行 quilt graph 并移除任何可能的 ANSI 代码
        quilt graph "$@" | sed 's/\x1b\[[0-9;]*m//g'
    )
}

# quilt graph 的彩色版本执行器 (生成带颜色属性的 DOT 格式)
run_quilt_graph_with_colors() {
    local kernel_source_dir
    kernel_source_dir=$(find_kernel_source_enhanced "quilt graph") || { log_error "未找到内核源码目录"; return 1; }
    
    # 过滤掉 --color 参数，只保留其他参数传给 quilt graph
    local quilt_args=()
    for arg in "$@"; do
        if [[ "$arg" != "--color" ]]; then
            quilt_args+=("$arg")
        fi
    done
    
    ( 
        cd "$kernel_source_dir" || exit 1
        
        # 获取基本的 DOT 输出
        export NO_COLOR=1
        export TERM=dumb
        local base_dot
        base_dot=$(quilt graph "${quilt_args[@]}" | sed 's/\x1b\[[0-9;]*m//g')
        
        # 获取已应用和未应用的补丁列表
        local applied_patches
        local unapplied_patches
        applied_patches=$(quilt applied 2>/dev/null || true)
        unapplied_patches=$(quilt unapplied 2>/dev/null || true)
        
        # 处理 DOT 输出，添加颜色属性
        echo "$base_dot" | awk -v applied="$applied_patches" -v unapplied="$unapplied_patches" '
        BEGIN {
            # 将已应用补丁列表转换为哈希表 (map)
            n_applied = split(applied, applied_arr, "\n");
            for (i = 1; i <= n_applied; i++) {
                if (applied_arr[i] != "") {
                    patch_name = applied_arr[i];
                    # 移除 quilt 输出中固有的 "patches/" 前缀
                    gsub(/^patches\//, "", patch_name);
                    applied_map[patch_name] = 1;
                }
            }

            # 将未应用补丁列表转换为哈希表 (map)
            n_unapplied = split(unapplied, unapplied_arr, "\n");
            for (i = 1; i <= n_unapplied; i++) {
                if (unapplied_arr[i] != "") {
                    patch_name = unapplied_arr[i];
                    gsub(/^patches\//, "", patch_name);
                    unapplied_map[patch_name] = 1;
                }
            }
        }
        {
            # 只处理定义节点的行, e.g., n62 [label="platform/CVE-2020-12826.patch"];
            if ($0 ~ /n[0-9]+ \[.*label=/) {
                # 从 label="<patch_name>" 中提取出 <patch_name>
                if (match($0, /label="([^"]*)"/, arr)) {
                    patch_label = arr[1];

                    # 移除节点定义中所有可能存在的旧样式属性
                    gsub(/,style=[^,\]]*/, "", $0);
                    gsub(/,fillcolor=[^,\]]*/, "", $0);
                    gsub(/,color=[^,\]]*/, "", $0);
                    gsub(/,fontcolor=[^,\]]*/, "", $0);
                    gsub(/style=[^,\]]*/, "", $0);
                    # 关键修复：清理可能由gsub留下的 "[," 或 ",,"
                    gsub(/\[,/, "[", $0);
                    gsub(/,,/, ",", $0);

                    # 根据补丁状态，构建新的样式字符串
                    new_style = "";
                    if (patch_label in applied_map) {
                        # 绿色: 已应用
                        new_style = "style=filled,fillcolor=lightgreen,color=darkgreen,fontcolor=black";
                    } else if (patch_label in unapplied_map) {
                        # 红色: 未应用
                        new_style = "style=filled,fillcolor=lightcoral,color=darkred,fontcolor=white";
                    } else {
                        # 灰色: 未知 (e.g., a generic patch)
                        new_style = "style=filled,fillcolor=lightgray,color=gray,fontcolor=black";
                    }

                    # 将新样式插入到 ] 前面
                    gsub(/\];$/, "," new_style "];", $0);
                }
            }
            # 打印处理后（或未处理）的行
            print $0;
        }'
    )
}

# 生成补丁依赖关系图的PDF文件
generate_patch_graph_pdf() {
    # 使用更健壮的方式解析参数，支持 --color 和 --all 标志在任意位置
    local patch_name=""
    local output_file=""
    local use_colors=false
    local show_all=false
    local quilt_args=()
    local other_args=()

    for arg in "$@"; do
        case "$arg" in
            --color)
                use_colors=true
                ;;
            --all)
                show_all=true
                quilt_args+=("--all")
                ;;
            *)
                # 将非标志参数收集起来
                other_args+=("$arg")
                ;;
        esac
    done

    # 从非标志参数中确定 patch_name 和 output_file
    # 假设第一个是 patch_name, 第二个是 output_file (如果存在)
    if [[ ${#other_args[@]} -gt 0 ]]; then
        patch_name="${other_args[0]}"
        quilt_args+=("$patch_name")
    fi
    if [[ ${#other_args[@]} -gt 1 ]]; then
        output_file="${other_args[1]}"
    fi

    # 检查是否安装了 graphviz
    if ! command -v dot &> /dev/null; then
        log_error "未找到 'dot' 命令，请安装 Graphviz："
        log_info "  Ubuntu/Debian: sudo apt install graphviz"
        log_info "  CentOS/RHEL:   sudo yum install graphviz"
        log_info "  macOS:         brew install graphviz"
        return 1
    fi
    
    # 确保输出目录存在
    mkdir -p "$ORIGINAL_PWD/$OUTPUT_DIR"

    # 设置默认输出文件名（保存到 patch_manager_work/outputs 目录）
    if [[ -z "$output_file" ]]; then
        local color_suffix=""
        [[ "$use_colors" == true ]] && color_suffix="_colored"
        local all_suffix=""
        [[ "$show_all" == true ]] && all_suffix="_all"
        
        if [[ -n "$patch_name" ]]; then
            # 将补丁名称中的斜杠替换为下划线，避免路径问题
            local safe_patch_name="${patch_name//\//_}"
            safe_patch_name="${safe_patch_name%.*}"  # 移除扩展名
            output_file="$ORIGINAL_PWD/$OUTPUT_DIR/patch_graph_${safe_patch_name}${color_suffix}${all_suffix}"
        else
            output_file="$ORIGINAL_PWD/$OUTPUT_DIR/patches_graph${color_suffix}${all_suffix}"
        fi
    else
        # 如果用户指定了输出文件，也放到 patch_manager_work 目录下
        # 如果用户提供的是绝对路径，则使用绝对路径；否则放到输出目录
        if [[ "$output_file" == /* ]]; then
            # 绝对路径，去掉扩展名
            output_file="${output_file%.*}"
        else
            # 相对路径，放到输出目录，并处理可能的斜杠
            local safe_output_file="${output_file//\//_}"
            output_file="$ORIGINAL_PWD/$OUTPUT_DIR/${safe_output_file%.*}"
        fi
    fi
    
    # 设置DOT和PDF文件路径
    local dot_file="${output_file}.dot"
    local pdf_file="${output_file}.pdf"
    
    if [[ "$use_colors" == true ]]; then
        log_info "🎨 正在生成彩色补丁依赖关系图..."
        log_info "🎨 颜色说明: 🟢 已应用补丁 | 🔴 未应用补丁 | ⚪ 未知状态"
    else
        log_info "🎨 正在生成补丁依赖关系图..."
    fi
    [[ "$show_all" == true ]] && log_info "📊 显示模式: 所有补丁 (--all)"
    log_info "📄 DOT 文件: $dot_file"
    log_info "📄 PDF 文件: $pdf_file"
    
    # 第一步：生成 DOT 文件
    log_info "📊 步骤 1/2: 生成 DOT 文件..."
    
    # 根据是否使用颜色选择不同的函数
    if [[ "$use_colors" == true ]]; then
        log_info "📊 正在分析补丁（彩色模式）..."
        run_quilt_graph_with_colors "${quilt_args[@]}" > "$dot_file"
    else
        log_info "📊 正在分析补丁..."
        run_quilt_graph "${quilt_args[@]}" > "$dot_file"
    fi
    
    # 检查 DOT 文件是否生成成功
    if [[ ! -s "$dot_file" ]]; then
        log_error "❌ 生成 DOT 文件失败"
        return 1
    fi
    
    log_success "✅ DOT 文件生成成功: $dot_file"
    
    # 显示DOT文件内容的前几行用于调试
    log_info "📝 DOT 文件内容预览:"
    head -10 "$dot_file" | sed 's/^/   /'
    
    # 第二步：转换为 PDF
    log_info "📊 步骤 2/2: 转换 DOT 为 PDF..."
    
    if dot -Tpdf "$dot_file" -o "$pdf_file" 2>/dev/null; then
        if [[ "$use_colors" == true ]]; then
            log_success "✅ 彩色 PDF 文件生成成功: $pdf_file"
        else
            log_success "✅ PDF 文件生成成功: $pdf_file"
        fi
        
        # 显示文件信息
        local dot_size pdf_size
        dot_size=$(ls -lh "$dot_file" | awk '{print $5}')
        pdf_size=$(ls -lh "$pdf_file" | awk '{print $5}')
        log_info "📊 DOT 文件大小: $dot_size"
        log_info "📊 PDF 文件大小: $pdf_size"
        
        # 显示相对于工作目录的路径
        local relative_dot_path relative_pdf_path
        relative_dot_path=$(echo "$dot_file" | sed "s|^$ORIGINAL_PWD/||")
        relative_pdf_path=$(echo "$pdf_file" | sed "s|^$ORIGINAL_PWD/||")
        log_info "🔗 DOT 相对路径: $relative_dot_path"
        log_info "🔗 PDF 相对路径: $relative_pdf_path"
        
        # 如果可能的话，显示绝对路径
        local abs_dot_path abs_pdf_path
        abs_dot_path=$(realpath "$dot_file" 2>/dev/null || echo "$dot_file")
        abs_pdf_path=$(realpath "$pdf_file" 2>/dev/null || echo "$pdf_file")
        log_info "🔗 DOT 完整路径: $abs_dot_path"
        log_info "🔗 PDF 完整路径: $abs_pdf_path"
        
        # 提示如何查看
        log_info ""
        log_info "💡 查看方式:"
        log_info "   • 查看DOT文件: cat '$dot_file'"
        log_info "   • 图形界面查看PDF: xdg-open '$pdf_file' 或双击文件"
        log_info "   • 命令行查看PDF: evince '$pdf_file' 或 okular '$pdf_file'"
        
        if [[ "$use_colors" == true ]]; then
            log_info ""
            log_info "�� 颜色图例:"
            log_info "   • 绿色节点: 已应用的补丁"
            log_info "   • 红色节点: 未应用的补丁"
            log_info "   • 灰色节点: 未知状态的补丁"
        fi
        
    else
        log_error "❌ PDF 生成失败"
        log_error "请检查 DOT 文件内容:"
        log_info "DOT 文件: $dot_file"
        return 1
    fi
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
        "quick-apply") quick_apply_patch "$@";;
        "snapshot-create") snapshot_create "$@";;
        "snapshot-diff") snapshot_diff "$@";;
        "snapshot-status") snapshot_status "$@";;
        "snapshot-list-changes") snapshot_list_changes "$@";;
        "snapshot-list-new") snapshot_list_new "$@";;
        "snapshot-list-modified") snapshot_list_modified "$@";;
        "snapshot-clean") snapshot_clean "$@";;
        "export-changed-files") export_changed_files "$@";;
        "export-from-file") export_from_file "$@";;
        "distclean") distclean_env "$@";;
        "clean") clean_work_dir "$@";;
        "reset-env") check_dependencies "need_quilt"; reset_env "$@";;
        "status") check_dependencies "need_quilt"; show_quilt_status "$@";;
        "series"|"applied"|"unapplied"|"top"|"files"|"push"|"pop"|"diff")
            check_dependencies "need_quilt"; run_quilt_command "$command" "$@";;
        "graph")
            check_dependencies "need_quilt"; run_quilt_graph "$@";;
        "graph-pdf")
            check_dependencies "need_quilt"; generate_patch_graph_pdf "$@";;
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

