#!/bin/bash

# OpenWrt Quilt CVE Patch Manager v5.3
# 功能：自动化 CVE 补丁制作流程
# v5.3版本，支持保存原始补丁 + 智能冲突检测 + 文件冲突分析

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 工具信息
TOOL_NAME="OpenWrt Quilt CVE Patch Manager"
VERSION="v5.3"

# 配置
KERNEL_GIT_URL="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
TEMP_DIR="patch-tmp/patch_manager_$$"
PATCH_LIST_FILE="patch_files.txt"
PATCH_METADATA_FILE="patch_metadata.txt"

# 🔧 修复：保存原始工作目录
ORIGINAL_PWD="$(pwd)"

# 清理函数
cleanup() {
    # 清理具体的临时目录
    local temp_full_dir="$ORIGINAL_PWD/$TEMP_DIR"
    [[ -d "$temp_full_dir" ]] && rm -rf "$temp_full_dir"
    
    # 如果 patch-tmp 目录为空，也删除它
    local temp_base_dir="$ORIGINAL_PWD/patch-tmp"
    if [[ -d "$temp_base_dir" ]] && [[ -z "$(ls -A "$temp_base_dir" 2>/dev/null)" ]]; then
        rm -rf "$temp_base_dir"
    fi
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
    printf "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║                 %s %s                 ║${NC}\n" "$TOOL_NAME" "$VERSION"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
    printf "${CYAN}专为 OpenWrt 内核补丁制作设计的自动化工具${NC}\n"
    printf "\n"
    printf "${GREEN}版本信息:${NC}\n"
    printf "  📦 工具名称: ${CYAN}$TOOL_NAME${NC}\n"
    printf "  🏷️  版本号: ${YELLOW}$VERSION${NC}\n"
    printf "  📅 发布日期: $(date '+%Y-%m-%d')\n"
    printf "  🛠️  功能特性: CVE补丁自动化制作 + 智能冲突检测 + 文件冲突分析\n"
    printf "\n"
    printf "${GREEN}新功能 (v5.3):${NC}\n"
    printf "  🆕 增强的文件冲突检测\n"
    printf "  🆕 智能补丁兼容性分析\n"
    printf "  🆕 精确的补丁术语显示\n"
    printf "  🆕 完整的版本管理系统\n"
    printf "\n"
    printf "${CYAN}使用帮助: ${YELLOW}%s help${NC}\n" "$0"
    printf "\n"
}

# 打印帮助信息
print_help() {
    printf "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║                 %s %s                 ║${NC}\n" "$TOOL_NAME" "$VERSION"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
    printf "${CYAN}专为 OpenWrt 内核补丁制作设计的自动化工具${NC}\n"
    printf "\n"
    printf "${YELLOW}用法:${NC} %s <命令> [参数]\n" "$0"
    printf "\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}命令列表 (可在任意目录运行):${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  ${CYAN}demo${NC}                         - 演示所有功能 (推荐首次使用)\n"
    printf "  ${CYAN}fetch${NC} <commit_id>           - 下载原始补丁到临时目录\n"
    printf "  ${CYAN}save${NC} <commit_id> [filename] - 下载并保存原始补丁到当前目录\n"
    printf "  ${CYAN}test-patch${NC} <commit_id>      - 测试原始补丁兼容性 (🆕智能冲突检测+文件冲突分析)\n"
    printf "  ${CYAN}extract-files${NC} <commit_id>   - 提取文件列表 → ${PURPLE}%s${NC}\n" "$PATCH_LIST_FILE"
    printf "  ${CYAN}extract-metadata${NC} <commit_id> - 提取元数据 → ${PURPLE}%s${NC}\n" "$PATCH_METADATA_FILE"
    printf "\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}命令列表 (自动查找内核源码目录):${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  ${CYAN}add-files${NC} <file_list.txt>   - 添加文件列表到当前 quilt 补丁 (需先创建补丁)\n"
    printf "  ${CYAN}create-patch${NC} <name> [commit] - 创建新补丁 → ${PURPLE}patches/<name>.patch${NC}\n"
    printf "  ${CYAN}auto-patch${NC} <commit> <name>  - 自动化完整补丁制作流程\n"
    printf "  ${CYAN}clean${NC}                    - 清理补丁和临时文件 🆕\n"
    printf "\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}Quilt 常用命令 (自动查找内核源码目录):${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  ${CYAN}status${NC}                   - 显示补丁状态概览 📊\n"
    printf "  ${CYAN}series${NC}                   - 显示补丁系列列表 📋\n"
    printf "  ${CYAN}applied${NC}                  - 显示已应用的补丁 ✅\n"
    printf "  ${CYAN}unapplied${NC}                - 显示未应用的补丁 ❌\n"
    printf "  ${CYAN}top${NC}                      - 显示当前顶部补丁 🔝\n"
    printf "  ${CYAN}files${NC} [patch_name]      - 显示补丁涉及的文件 🔍\n"
    printf "  ${CYAN}push${NC} [patch_name|-a]    - 应用补丁 📌\n"
    printf "  ${CYAN}pop${NC} [patch_name|-a]     - 移除补丁 📌\n"
    printf "  ${CYAN}refresh${NC}                  - 生成/更新补丁文件 🔄\n"
    printf "\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}输出文件说明:${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  📄 ${PURPLE}%s${NC}      - 补丁涉及的文件列表 (持久保存)\n" "$PATCH_LIST_FILE"
    printf "  📋 ${PURPLE}%s${NC}   - 补丁完整元数据信息 (持久保存)\n" "$PATCH_METADATA_FILE"
    printf "  📥 ${PURPLE}<commit_id>.patch${NC}       - 原始补丁文件 (使用 save 命令)\n"
    printf "  🔧 ${PURPLE}patches/<name>.patch${NC}       - 最终生成的 OpenWrt 补丁文件\n"
    printf "  🗂️  ${PURPLE}patch-tmp/patch_manager_\$\$/*${NC}    - 临时文件 (脚本结束自动清理)\n"
    printf "\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}重要说明:${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  ${YELLOW}⚠️  临时目录路径:${NC} patch-tmp/patch_manager_<进程ID>\n"
    printf "  ${YELLOW}⚠️  临时文件清理:${NC} 脚本结束时自动删除临时目录\n"
    printf "  ${YELLOW}⚠️  持久化文件:${NC} 使用 extract-*、save 命令在当前目录生成持久文件\n"
    printf "  ${YELLOW}⚠️  内核源码目录:${NC} build_dir/target-*/linux-*/linux-*/\n"
    printf "\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}使用示例:${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "\n"
    printf "${CYAN}1. 快速演示 (任意目录):${NC}\n"
    printf "   %s demo\n" "$0"
    printf "\n"
    printf "${CYAN}2. 保存原始补丁到当前目录:${NC}\n"
    printf "   %s save 654b33ada4ab5e926cd9c570196fefa7bec7c1df\n" "$0"
    printf "   %s save 654b33ada4ab5e926cd9c570196fefa7bec7c1df proc-uaf-fix.patch\n" "$0"
    printf "\n"
    printf "${CYAN}3. 智能补丁冲突检测 (🆕):${NC}\n"
    printf "   %s test-patch 654b33ada4ab5e926cd9c570196fefa7bec7c1df\n" "$0"
    printf "\n"
    printf "${CYAN}4. 提取补丁信息 (任意目录):${NC}\n"
    printf "   %s extract-files 654b33ada4ab5e926cd9c570196fefa7bec7c1df\n" "$0"
    printf "   %s extract-metadata 654b33ada4ab5e926cd9c570196fefa7bec7c1df\n" "$0"
    printf "\n"
    printf "${CYAN}5. 完整补丁制作 (自动查找内核目录):${NC}\n"
    printf "   %s auto-patch 654b33ada4ab5e926cd9c570196fefa7bec7c1df 950-proc-fix-UAF\n" "$0"
    printf "\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}⚠️ 正确的使用顺序 (手动制作补丁):${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  ${YELLOW}1.${NC} %s create-patch <补丁名称> [commit_id]  # 先创建补丁\n" "$0"
    printf "  ${YELLOW}2.${NC} %s add-files <文件列表.txt>            # 再添加文件\n" "$0"
    printf "  ${YELLOW}3.${NC} 手动修改内核源码文件 (根据原始补丁内容)\n"
    printf "  ${YELLOW}4.${NC} %s refresh                         # 生成最终补丁\n" "$0"
    printf "\n"
    printf "${CYAN}💡 或者使用自动化命令一步完成:${NC}\n"
    printf "  %s auto-patch <commit_id> <补丁名称>\n" "$0"
    printf "\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}依赖要求:${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  📥 ${CYAN}curl${NC}  - 下载补丁 (必需)\n"
    printf "  🔧 ${CYAN}quilt${NC} - 补丁管理 (内核源码操作时必需)\n"
    printf "  🌐 网络访问 git.kernel.org (下载补丁时必需)\n"
    printf "\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}安装 quilt:${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  ${CYAN}macOS:${NC}        brew install quilt\n"
    printf "  ${CYAN}Ubuntu/Debian:${NC} sudo apt-get install quilt\n"
    printf "\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}版本信息:${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  ${CYAN}version | -v | --version${NC} - 显示工具版本信息\n"
    printf "  ${CYAN}help | -h | --help${NC}       - 显示此帮助信息\n"
    printf "\n"
}

# 检查依赖
check_dependencies() {
    local deps=("curl")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少以下依赖: ${missing_deps[*]}"
        log_info "请安装缺少的依赖后重试"
        exit 1
    fi
    
    # 检查 quilt（仅在需要时）
    if [[ "$1" == "need_quilt" ]] && ! command -v "quilt" &> /dev/null; then
        log_error "缺少 quilt 工具"
        log_info "安装命令: brew install quilt (macOS) 或 sudo apt-get install quilt (Ubuntu)"
        exit 1
    fi
}

# 查找 OpenWrt 内核源码目录
find_kernel_source() {
    local openwrt_root="$PWD"
    local kernel_dir=""
    
    # 检查当前是否已经在内核源码目录
    if [[ -f "Makefile" ]] && grep -q "KERNELRELEASE" Makefile 2>/dev/null; then
        log_info "当前已在内核源码目录: $(pwd)"
        return 0
    fi
    
    log_info "搜索 OpenWrt 内核源码目录..."
    
    # 查找 build_dir 下的内核目录
    local build_dirs=(
        "build_dir/target-*/linux-*/linux-*"
        "build_dir/linux-*/linux-*"
        "openwrt-source/openwrt/build_dir/target-*/linux-*/linux-*"
        "openwrt-source/openwrt/build_dir/linux-*/linux-*"
        "*/build_dir/target-*/linux-*/linux-*"
        "*/build_dir/linux-*/linux-*"
    )
    
    for pattern in "${build_dirs[@]}"; do
        # 使用 find 命令查找匹配的目录
        while IFS= read -r -d '' dir; do
            if [[ -f "$dir/Makefile" ]] && grep -q "KERNELRELEASE" "$dir/Makefile" 2>/dev/null; then
                kernel_dir="$dir"
                break 2
            fi
        done < <(find . -path "./$pattern" -type d -print0 2>/dev/null | head -5)
    done
    
    if [[ -n "$kernel_dir" ]]; then
        log_success "找到内核源码目录: $kernel_dir"
        log_info "切换到内核源码目录..."
        cd "$kernel_dir" || {
            log_error "无法切换到目录: $kernel_dir"
            return 1
        }
        log_success "已切换到: $(pwd)"
        return 0
    else
        log_error "未找到 OpenWrt 内核源码目录"
        log_info "请确保已执行 'make target/linux/prepare' 解压内核源码"
        log_info "或手动切换到内核源码目录后运行脚本"
        return 1
    fi
}

# 检查是否在内核源码目录
check_kernel_source() {
    if [[ ! -f "Makefile" ]] || ! grep -q "KERNELRELEASE" Makefile 2>/dev/null; then
        log_error "请在 Linux 内核源码目录中运行此脚本"
        log_info "正确路径示例: build_dir/target-*/linux-*/linux-*/"
        return 1
    fi
    return 0
}

# 创建临时目录
create_temp_dir() {
    # 确保从原始工作目录创建临时目录
    local temp_base_dir="$ORIGINAL_PWD/patch-tmp"
    local temp_full_dir="$ORIGINAL_PWD/$TEMP_DIR"
    
    # 创建 patch-tmp 基础目录
    mkdir -p "$temp_base_dir"
    # 创建具体的临时目录
    mkdir -p "$temp_full_dir"
    
    # 获取临时目录的绝对路径
    local abs_temp_dir="$(cd "$temp_full_dir" && pwd)"
    log_info "创建临时目录: $abs_temp_dir"
    log_warning "临时目录会在脚本结束时自动清理"
}

# 抓取原始补丁 (到临时目录) - 内部版本，不输出日志
_fetch_patch_internal() {
    local commit_id="$1"
    local patch_url="${KERNEL_GIT_URL}/patch/?id=${commit_id}"
    local patch_file="$ORIGINAL_PWD/$TEMP_DIR/original_${commit_id}.patch"
    
    if curl -s -f "$patch_url" -o "$patch_file"; then
        printf "%s" "$patch_file"
        return 0
    else
        return 1
    fi
}

# 抓取原始补丁 (到临时目录) - 公开版本，带日志
fetch_patch() {
    local commit_id="$1"
    if [[ -z "$commit_id" ]]; then
        log_error "请提供 commit ID"
        return 1
    fi
    
    log_info "抓取 commit $commit_id 的原始补丁..."
    
    local patch_file
    if patch_file=$(_fetch_patch_internal "$commit_id"); then
        log_success "补丁已下载到: $patch_file"
        log_warning "注意: 临时文件会在脚本结束时自动删除"
        printf "%s" "$patch_file"
        return 0
    else
        log_error "无法下载补丁，请检查 commit ID: $commit_id"
        return 1
    fi
}

# 保存原始补丁到当前目录 (新功能)
save_patch() {
    local commit_id="$1"
    local filename="$2"
    
    if [[ -z "$commit_id" ]]; then
        log_error "请提供 commit ID"
        return 1
    fi
    
    # 如果没有提供文件名，使用默认命名
    if [[ -z "$filename" ]]; then
        filename="${commit_id}.patch"
    fi
    
    # 确保文件名以 .patch 结尾
    if [[ ! "$filename" =~ \.patch$ ]]; then
        filename="${filename}.patch"
    fi
    
    log_info "保存 commit $commit_id 的原始补丁到当前目录..."
    
    local patch_url="${KERNEL_GIT_URL}/patch/?id=${commit_id}"
    
    if curl -s -f "$patch_url" -o "$filename"; then
        local file_size
        file_size=$(wc -c < "$filename")
        log_success "原始补丁已保存到: $filename"
        log_info "文件大小: $file_size 字节"
        log_info "文件位置: $(pwd)/$filename"
        return 0
    else
        log_error "无法下载补丁，请检查 commit ID: $commit_id"
        return 1
    fi
}

# 🆕 测试补丁兼容性和冲突检测
test_patch_compatibility() {
    local commit_id="$1"
    if [[ -z "$commit_id" ]]; then
        log_error "请提供 commit ID"
        return 1
    fi
    
    printf "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║            🔍 智能补丁兼容性检测 + 文件冲突分析                      ║${NC}\n"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}\n"
    log_info "测试 commit $commit_id 的补丁兼容性..."
    printf "\n"
    
    # 步骤1: 下载原始补丁
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "📥 步骤 1/5: 下载原始补丁..."
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    local patch_file
    if patch_file=$(_fetch_patch_internal "$commit_id"); then
        log_success "补丁已下载: $patch_file"
    else
        log_error "无法下载补丁，请检查 commit ID: $commit_id"
        return 1
    fi
    
    # 步骤2: 检查内核目录
    printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "📂 步骤 2/5: 检查内核目录..."
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    if ! find_kernel_source; then
        log_error "无法找到内核源码目录"
        return 1
    fi
    
    # 步骤3: 分析补丁涉及的文件
    printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "🔍 步骤 3/5: 分析补丁文件..."
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    # 提取文件列表
    local affected_files=()
    while IFS= read -r file; do
        if [[ -n "$file" ]]; then
            affected_files+=("$file")
        fi
    done < <(grep -E "^(diff --git|--- a/)" "$patch_file" | sed -E 's/^(diff --git a\/|--- a\/)([^[:space:]]+).*/\2/' | sort -u)
    
    if [[ ${#affected_files[@]} -eq 0 ]]; then
        log_error "无法从补丁中提取文件信息"
        return 1
    fi
    
    log_info "发现 ${#affected_files[@]} 个受影响文件："
    for file in "${affected_files[@]}"; do
        printf "  📄 $file\n"
    done
    
    # 步骤4: 检查文件存在性
    printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "📋 步骤 4/5: 检查文件存在性..."
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    local missing_files=()
    local existing_files=()
    
    for file in "${affected_files[@]}"; do
        if [[ -f "$file" ]]; then
            printf "  ✅ ${GREEN}$file${NC} (存在)\n"
            existing_files+=("$file")
        else
            printf "  ❌ ${RED}$file${NC} (不存在)\n"
            missing_files+=("$file")
        fi
    done
    
    # 步骤5: 检查文件冲突
    printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "🔍 步骤 5/6: 检查文件冲突..."
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    # 检查受影响的文件是否被现有补丁修改过
    local conflicted_files=()
    local file_patch_map=()
    
    log_info "检查 ${#existing_files[@]} 个文件是否与已应用补丁冲突..."
    
    for file in "${existing_files[@]}"; do
        local patches_modifying_file=()
        
        # 获取所有已应用的补丁
        while IFS= read -r applied_patch; do
            if [[ -n "$applied_patch" ]]; then
                # 检查此补丁是否修改了当前文件
                if quilt files "$applied_patch" 2>/dev/null | grep -Fxq "$file"; then
                    patches_modifying_file+=("$applied_patch")
                fi
            fi
        done < <(quilt applied 2>/dev/null)
        
        if [[ ${#patches_modifying_file[@]} -gt 0 ]]; then
            conflicted_files+=("$file")
            printf "  ⚠️  ${YELLOW}$file${NC} (被 ${#patches_modifying_file[@]} 个补丁修改)\n"
            for patch in "${patches_modifying_file[@]}"; do
                printf "      📄 $patch\n"
                file_patch_map+=("$file -> $patch")
            done
        else
            printf "  ✅ ${GREEN}$file${NC} (无冲突)\n"
        fi
    done
    
    # 显示冲突检查结果
    printf "\n${CYAN}🔍 文件冲突检查结果:${NC}\n"
    printf "  📄 检查文件总数: ${#existing_files[@]}\n"
    printf "  ✅ 无冲突文件: $((${#existing_files[@]} - ${#conflicted_files[@]}))\n"
    printf "  ⚠️  有冲突文件: ${#conflicted_files[@]}\n"
    
    if [[ ${#conflicted_files[@]} -gt 0 ]]; then
        printf "\n${YELLOW}⚠️ 警告: 检测到文件冲突${NC}\n"
        printf "以下文件已被现有补丁修改，可能会产生冲突:\n"
        for file in "${conflicted_files[@]}"; do
            printf "  ⚠️  $file\n"
        done
        printf "\n${YELLOW}💡 建议:${NC}\n"
        printf "   • 仔细检查这些文件的修改内容\n"
        printf "   • 考虑是否需要合并修改\n"
        printf "   • 可能需要手动解决冲突\n"
        printf "   • 建议在测试环境中先尝试应用\n"
    else
        printf "\n${GREEN}✅ 无文件冲突检测到${NC}\n"
        printf "所有受影响的文件都未被现有补丁修改。\n"
    fi

    # 步骤6: 尝试应用补丁 (dry-run)
    printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "🧪 步骤 6/6: 干运行补丁测试..."
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    # 保存应用测试结果
    local patch_test_output
    local patch_test_result=0
    
    # 使用 patch 命令进行 dry-run 测试 (非交互式，获取详细输出)
    patch_test_output=$(patch --dry-run -p1 --verbose --force --no-backup-if-mismatch < "$patch_file" 2>&1) || patch_test_result=$?
    
    # 分析结果并提供建议
    printf "\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf "${PURPLE}📊 兼容性检测结果${NC}\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    # 显示统计信息
    printf "📈 ${CYAN}文件统计${NC}:\n"
    printf "  📄 涉及文件总数: ${#affected_files[@]}\n"
    printf "  ✅ 存在文件数量: ${#existing_files[@]}\n"
    printf "  ❌ 缺失文件数量: ${#missing_files[@]}\n"
    printf "  ⚠️  有冲突文件数: ${#conflicted_files[@]}\n"
    printf "  🟢 无冲突文件数: $((${#existing_files[@]} - ${#conflicted_files[@]}))\n"
    printf "\n"
    
    # 判断兼容性状态
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        printf "🚨 ${RED}结果: 补丁不兼容 - 缺失必要文件${NC}\n"
        printf "\n${YELLOW}⚠️ 缺失的文件:${NC}\n"
        for file in "${missing_files[@]}"; do
            printf "  ❌ $file\n"
        done
        printf "\n${RED}🛑 建议: 此补丁无法直接应用，需要手动适配${NC}\n"
        printf "   • 检查文件路径是否正确\n"
        printf "   • 确认内核版本是否匹配\n"
        printf "   • 考虑寻找适用于当前内核版本的等效补丁\n"
        printf "\n"
        return 2  # 不兼容退出码
    elif [[ $patch_test_result -eq 0 ]]; then
        if [[ ${#conflicted_files[@]} -eq 0 ]]; then
            printf "🎉 ${GREEN}结果: 补丁完全兼容 - 可以直接应用${NC}\n"
            printf "\n${GREEN}✅ 补丁测试详情:${NC}\n"
            echo "$patch_test_output" | sed 's/^/  /'
            printf "\n${GREEN}💡 建议: 可以安全地应用此补丁${NC}\n"
            printf "   • 无文件冲突，可以安全应用\n"
            printf "   • 使用 auto-patch 命令自动创建 OpenWrt 补丁\n"
            printf "   • 或按照手动流程逐步创建补丁\n"
        else
            printf "⚠️ ${YELLOW}结果: 补丁技术兼容但有文件冲突${NC}\n"
            printf "\n${GREEN}✅ 补丁测试详情:${NC}\n"
            echo "$patch_test_output" | sed 's/^/  /'
            printf "\n${YELLOW}⚠️ 文件冲突详情:${NC}\n"
            for file in "${conflicted_files[@]}"; do
                printf "  ⚠️  $file (已被其他补丁修改)\n"
            done
            printf "\n${YELLOW}💡 建议: 谨慎应用此补丁${NC}\n"
            printf "   • 补丁本身可以应用，但文件已被修改\n"
            printf "   • 建议先在测试环境中验证\n"
            printf "   • 检查是否会覆盖重要修改\n"
            printf "   • 考虑手动合并修改内容\n"
        fi
        printf "\n"
        
        # 询问用户是否要继续自动创建补丁
        if [[ ${#conflicted_files[@]} -eq 0 ]]; then
            printf "${CYAN}🤔 是否要立即创建 OpenWrt 补丁? (y/N): ${NC}"
        else
            printf "${YELLOW}⚠️  检测到文件冲突，是否仍要创建补丁? (y/N): ${NC}"
        fi
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            printf "请输入补丁名称 (例如: 950-proc-fix-UAF): "
            read -r patch_name
            if [[ -n "$patch_name" ]]; then
                printf "\n"
                if [[ ${#conflicted_files[@]} -gt 0 ]]; then
                    log_warning "⚠️ 注意：存在文件冲突，创建的补丁可能需要手动调整"
                fi
                log_info "🚀 启动自动补丁创建流程..."
                auto_patch "$commit_id" "$patch_name"
            else
                log_warning "未提供补丁名称，跳过自动创建"
            fi
        fi
        
        return 0  # 完全兼容
    else
        printf "⚠️ ${YELLOW}结果: 补丁有冲突 - 需要手动解决${NC}\n"
        printf "\n${YELLOW}🔍 冲突详情:${NC}\n"
        echo "$patch_test_output" | sed 's/^/  /'
        
        # 🆕 生成详细冲突报告文件
        local conflict_report_file="$ORIGINAL_PWD/conflict_report_${commit_id}_$(date +%Y%m%d_%H%M%S).md"
        log_info "📄 正在生成详细冲突报告..."
        generate_conflict_report "$commit_id" "$patch_file" "$patch_test_output" "$conflict_report_file" "${affected_files[@]}"
        
        printf "\n${YELLOW}⚠️ 建议: 存在冲突，需要手动处理${NC}\n"
        printf "   • 检查冲突的具体内容\n"
        printf "   • 手动修改相关文件以解决冲突\n"
        printf "   • 使用手动补丁创建流程\n"
        printf "   • 考虑修改补丁内容以适配当前内核\n"
        printf "   • 📄 查看详细冲突报告: ${PURPLE}$conflict_report_file${NC}\n"
        printf "\n${RED}🛑 警告: 不要直接应用此补丁，会导致代码损坏${NC}\n"
        printf "\n"
        return 1  # 有冲突退出码
    fi
}

# 🆕 生成详细冲突报告文件
generate_conflict_report() {
    local commit_id="$1"
    local patch_file="$2"
    local patch_test_output="$3"
    local report_file="$4"
    shift 4
    local affected_files=("$@")
    
    # 创建详细的冲突报告
    cat > "$report_file" << EOF
# 补丁冲突详细报告

## 📊 基本信息

- **Commit ID**: \`$commit_id\`
- **报告生成时间**: $(date '+%Y-%m-%d %H:%M:%S')
- **内核目录**: \`$(pwd)\`
- **原始补丁文件**: \`$patch_file\`

## 🚨 冲突概览

\`\`\`
$patch_test_output
\`\`\`

## 📋 涉及文件列表

EOF

    # 添加文件列表
    local file_index=1
    for file in "${affected_files[@]}"; do
        echo "### $file_index. \`$file\`" >> "$report_file"
        if [[ -f "$file" ]]; then
            echo "- **状态**: ✅ 文件存在" >> "$report_file"
        else
            echo "- **状态**: ❌ 文件不存在" >> "$report_file"
        fi
        echo "" >> "$report_file"
        ((file_index++))
    done
    
    # 添加原始补丁内容
    cat >> "$report_file" << EOF
## 📄 原始补丁内容

\`\`\`diff
EOF
    cat "$patch_file" >> "$report_file"
    cat >> "$report_file" << EOF
\`\`\`

## 🔍 详细冲突分析

EOF

    # 分析每个失败的文件
    local failed_files=()
    while IFS= read -r failed_line; do
        local failed_file=$(echo "$failed_line" | sed -E "s/.*while patching '([^']*)'.*$/\1/")
        failed_files+=("$failed_file")
    done < <(echo "$patch_test_output" | grep "failed while patching")
    
    # 🆕 为每个失败的文件生成精确的冲突分析
    for failed_file in "${failed_files[@]}"; do
        if [[ -f "$failed_file" ]]; then
            # 使用新的精确冲突分析函数
            analyze_precise_conflicts "$patch_file" "$failed_file" "$patch_test_output" >> "$report_file"
        else
            cat >> "$report_file" << EOF

### ❌ 文件: \`$failed_file\` - 文件不存在

**问题**: 补丁尝试修改的文件在当前内核中不存在
**建议**: 
- 检查文件路径是否正确
- 确认当前内核版本是否包含此文件
- 考虑这可能是版本差异导致的问题

EOF
        fi
    done
    
    # 添加解决建议
    cat >> "$report_file" << EOF

## 💡 解决建议

### 1. 手动应用补丁步骤

1. **创建备份**:
   \`\`\`bash
   cp -r . ../backup_$(date +%Y%m%d_%H%M%S)
   \`\`\`

2. **手动修改冲突文件**:
   根据上述对比，手动修改相关文件

3. **验证修改**:
   \`\`\`bash
   # 重新运行测试
   ../tools/quilt_patch_manager_final.sh test-patch $commit_id
   \`\`\`

### 2. 使用手动补丁流程

\`\`\`bash
# 1. 创建补丁
../tools/quilt_patch_manager_final.sh create-patch <patch_name>

# 2. 添加文件
../tools/quilt_patch_manager_final.sh add-files <file_list.txt>

# 3. 手动修改文件（根据原始补丁内容）

# 4. 生成最终补丁
../tools/quilt_patch_manager_final.sh refresh
\`\`\`

### 3. 寻找替代方案

- 检查是否有适用于当前内核版本的等效补丁
- 考虑修改补丁内容以适配当前内核版本
- 查看OpenWrt官方是否已有类似的补丁

---

**⚠️ 警告**: 请不要直接强制应用此补丁，这可能会损坏内核代码。
EOF

    log_success "冲突报告已生成: $report_file"
}

# 🔧 辅助函数：从补丁文件中提取特定文件的补丁部分
extract_file_patch_section() {
    local patch_file="$1"
    local target_file="$2"
    
    local in_target_section=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^diff\ --git.*"$target_file" ]]; then
            in_target_section=true
            echo "$line"
        elif [[ "$line" =~ ^diff\ --git ]] && [[ "$in_target_section" == true ]]; then
            break
        elif [[ "$in_target_section" == true ]]; then
            echo "$line"
        fi
    done < "$patch_file"
}

# 🆕 精确分析冲突位置和上下文
analyze_precise_conflicts() {
    local patch_file="$1"
    local failed_file="$2"
    local patch_verbose_output="$3"
    
    local result_file=$(mktemp)
    
    # 解析补丁中的 hunk 信息
    local hunks=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^@@\ -([0-9]+),?([0-9]*)\ \+([0-9]+),?([0-9]*)\ @@ ]]; then
            local old_start=${BASH_REMATCH[1]}
            local old_count=${BASH_REMATCH[2]:-1}
            local new_start=${BASH_REMATCH[3]}
            local new_count=${BASH_REMATCH[4]:-1}
            hunks+=("$old_start:$old_count:$new_start:$new_count")
        fi
    done < <(extract_file_patch_section "$patch_file" "$failed_file")
    
    if [[ ${#hunks[@]} -eq 0 ]]; then
        echo "# 无法解析补丁的 hunk 信息" > "$result_file"
        cat "$result_file"
        rm -f "$result_file"
        return
    fi
    
    cat > "$result_file" << EOF
### 🎯 文件: \`$failed_file\` - 精确冲突分析

EOF
    
    local hunk_index=1
    for hunk in "${hunks[@]}"; do
        IFS=':' read -r old_start old_count new_start new_count <<< "$hunk"
        
        cat >> "$result_file" << EOF
#### 🔍 冲突点 $hunk_index - 行号范围: $old_start-$((old_start + old_count - 1))

**🚨 冲突位置**: 原文件第 $old_start 行开始，共 $old_count 行
**📝 期望修改**: 应该变成第 $new_start 行开始，共 $new_count 行

**📄 当前文件内容 (冲突区域 + 上下文)**:
\`\`\`c
EOF
        
        # 提取冲突区域的上下文 (前后各5行)
        local context_start=$((old_start - 5))
        local context_end=$((old_start + old_count + 4))
        
        if [[ $context_start -lt 1 ]]; then
            context_start=1
        fi
        
        # 显示带行号的代码，突出显示冲突区域
        local line_num=$context_start
        while IFS= read -r code_line; do
            if [[ $line_num -ge $old_start && $line_num -lt $((old_start + old_count)) ]]; then
                echo "→ $line_num: $code_line    ⟸ 此行有冲突" >> "$result_file"
            else
                echo "  $line_num: $code_line" >> "$result_file"
            fi
            ((line_num++))
        done < <(sed -n "${context_start},${context_end}p" "$failed_file" 2>/dev/null)
        
        cat >> "$result_file" << EOF
\`\`\`

**🎯 补丁期望的修改**:
\`\`\`diff
EOF
        
        # 提取这个特定 hunk 的补丁内容
        extract_specific_hunk "$patch_file" "$failed_file" "$hunk_index" >> "$result_file"
        
        cat >> "$result_file" << EOF
\`\`\`

**💡 冲突原因分析**:
- 当前代码在第 $old_start 行附近与补丁期望的内容不匹配
- 可能的原因: 代码已被其他补丁修改、版本差异、或上下文变化

EOF
        
        ((hunk_index++))
    done
    
    cat "$result_file"
    rm -f "$result_file"
}

# 🔧 提取特定 hunk 的补丁内容
extract_specific_hunk() {
    local patch_file="$1"
    local target_file="$2"
    local hunk_number="$3"
    
    local in_target_section=false
    local current_hunk=0
    local in_target_hunk=false
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^diff\ --git.*"$target_file" ]]; then
            in_target_section=true
        elif [[ "$line" =~ ^diff\ --git ]] && [[ "$in_target_section" == true ]]; then
            break
        elif [[ "$in_target_section" == true ]]; then
            if [[ "$line" =~ ^@@.*@@ ]]; then
                ((current_hunk++))
                if [[ $current_hunk -eq $hunk_number ]]; then
                    in_target_hunk=true
                    echo "$line"
                elif [[ $in_target_hunk == true ]]; then
                    break
                fi
            elif [[ "$in_target_hunk" == true ]]; then
                if [[ "$line" =~ ^@@.*@@ ]]; then
                    break
                fi
                echo "$line"
            fi
        fi
    done < "$patch_file"
}

# 提取补丁涉及的文件列表
extract_files() {
    local commit_id="$1"
    if [[ -z "$commit_id" ]]; then
        log_error "请提供 commit ID"
        return 1
    fi
    
    log_info "提取 commit $commit_id 涉及的文件列表..."
    
    log_info "抓取 commit $commit_id 的原始补丁..."
    local patch_file
    if patch_file=$(_fetch_patch_internal "$commit_id"); then
        log_success "补丁已下载到: $patch_file"
        log_warning "注意: 临时文件会在脚本结束时自动删除"
    else
        log_error "无法下载补丁，请检查 commit ID: $commit_id"
        return 1
    fi
    
    if [[ ! -f "$patch_file" ]]; then
        log_error "补丁文件不存在: $patch_file"
        return 1
    fi
    
    # 提取文件路径
    > "$PATCH_LIST_FILE"  # 清空文件
    
    # 从 diff --git 行提取
    grep "^diff --git" "$patch_file" | \
        sed 's/^diff --git a\/\([^ ]*\) b\/.*$/\1/' >> "$PATCH_LIST_FILE" 2>/dev/null || true
    
    # 从 --- 行提取（备用方法）
    grep "^--- a/" "$patch_file" | \
        sed 's/^--- a\/\([^[:space:]]*\).*$/\1/' >> "$PATCH_LIST_FILE" 2>/dev/null || true
    
    # 去重并过滤空行
    sort -u "$PATCH_LIST_FILE" | grep -v "^$" > "${PATCH_LIST_FILE}.tmp" && \
        mv "${PATCH_LIST_FILE}.tmp" "$PATCH_LIST_FILE"
    
    local file_count
    file_count=$(wc -l < "$PATCH_LIST_FILE" 2>/dev/null || echo 0)
    
    if [[ $file_count -gt 0 ]]; then
        log_success "找到 $file_count 个文件，已保存到: $PATCH_LIST_FILE"
        log_info "文件列表已保存到当前目录，不会被自动删除"
        printf "\n"
        printf "文件列表:\n"
        cat "$PATCH_LIST_FILE" | sed 's/^/  📄 /'
    else
        log_warning "未找到文件，可能是补丁格式问题"
        log_info "显示补丁内容前20行进行调试:"
        head -20 "$patch_file" | sed 's/^/  /'
    fi
    
    return 0
}

# 添加文件到 quilt
add_files() {
    local file_list="$1"
    
    # 🔧 修复：在切换目录前保存文件的绝对路径
    if [[ -z "$file_list" ]]; then
        log_error "请提供有效的文件列表"
        return 1
    fi
    
    # 如果是相对路径，转换为绝对路径
    if [[ ! "$file_list" =~ ^/ ]]; then
        # 从当前工作目录或调用脚本的目录查找文件
        local original_dir="$ORIGINAL_PWD"
        if [[ -f "$original_dir/$file_list" ]]; then
            file_list="$original_dir/$file_list"
        elif [[ -f "$file_list" ]]; then
            file_list="$(realpath "$file_list")"
        fi
    fi
    
    if [[ ! -f "$file_list" ]]; then
        log_error "请提供有效的文件列表: $file_list"
        return 1
    fi
    
    log_info "添加文件到当前 quilt 补丁..."
    
    local added_count=0
    local failed_count=0
    local skipped_count=0
    
    while IFS= read -r file; do
        # 跳过空行和注释
        if [[ -z "$file" ]] || [[ "$file" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        if [[ -f "$file" ]]; then
            # 🔧 修复：检查是否有 quilt 环境
            if ! quilt series >/dev/null 2>&1; then
                log_error "请先创建 quilt 补丁，使用: quilt new <patch_name>"
                return 1
            fi
            
            local add_output
            add_output=$(quilt add "$file" 2>&1)
            local add_result=$?
            
            if [[ $add_result -eq 0 ]]; then
                log_success "已添加: $file"
                ((added_count++))
            elif [[ "$add_output" =~ "already in series" || "$add_output" =~ "already exists" ]]; then
                log_warning "跳过 (已存在): $file"
                ((skipped_count++))
            else
                log_error "添加失败: $file ($add_output)"
                ((failed_count++))
            fi
        else
            log_warning "文件不存在: $file"
            ((failed_count++))
        fi
    done < "$file_list"
    
    printf "\n"
    log_info "添加完成: 成功 $added_count 个，跳过 $skipped_count 个，失败 $failed_count 个"
    return 0
}

# 提取补丁元数据
extract_metadata() {
    local commit_id="$1"
    if [[ -z "$commit_id" ]]; then
        log_error "请提供 commit ID"
        return 1
    fi
    
    log_info "提取 commit $commit_id 的元数据..."
    
    log_info "抓取 commit $commit_id 的原始补丁..."
    local patch_file
    if patch_file=$(_fetch_patch_internal "$commit_id"); then
        log_success "补丁已下载到: $patch_file"
        log_warning "注意: 临时文件会在脚本结束时自动删除"
    else
        log_error "无法下载补丁，请检查 commit ID: $commit_id"
        return 1
    fi
    
    if [[ ! -f "$patch_file" ]]; then
        log_error "补丁文件不存在: $patch_file"
        return 1
    fi
    
    # 生成元数据文件
    {
        echo "# ======================================"
        echo "# CVE 补丁元数据信息"
        echo "# ======================================"
        echo "# 生成时间: $(date)"
        echo "# Commit ID: $commit_id"
        echo "# 原始补丁 URL: ${KERNEL_GIT_URL}/commit/?id=${commit_id}"
        echo "# 临时补丁文件: $patch_file (脚本结束后自动删除)"
        echo "# ======================================"
        echo ""
        
        # 提取基本信息
        echo "## 基本信息"
        local from_line author_name author_email date_line subject_line
        from_line=$(grep "^From: " "$patch_file" | head -1)
        date_line=$(grep "^Date: " "$patch_file" | head -1)
        subject_line=$(grep "^Subject: " "$patch_file" | head -1)
        
        if [[ -n "$from_line" ]]; then
            echo "作者: $from_line"
            # 提取作者姓名和邮箱
            author_name=$(echo "$from_line" | sed 's/^From: \(.*\) <.*>$/\1/' 2>/dev/null || echo "Unknown")
            author_email=$(echo "$from_line" | sed 's/^From: .* <\(.*\)>$/\1/' 2>/dev/null || echo "unknown@example.com")
            echo "作者姓名: $author_name"
            echo "作者邮箱: $author_email"
        fi
        
        if [[ -n "$date_line" ]]; then
            echo "日期: $date_line"
        fi
        
        if [[ -n "$subject_line" ]]; then
            echo "主题: $subject_line"
        fi
        
        echo ""
        echo "## 补丁描述"
        
        # 提取补丁描述
        local in_description=false
        while IFS= read -r line; do
            if [[ "$line" =~ ^Subject: ]]; then
                in_description=true
                continue
            fi
            
            if [[ "$in_description" == true ]]; then
                if [[ "$line" =~ ^(diff\ --git|---|^\+\+\+|^Index:) ]]; then
                    break
                fi
                if [[ -n "$line" ]] && [[ ! "$line" =~ ^[[:space:]]*$ ]]; then
                    echo "$line"
                fi
            fi
        done < "$patch_file"
        
        echo ""
        echo "## 签名和标签信息"
        grep -E "^(Signed-off-by|Cc|Fixes|Reported-by|Tested-by|Acked-by|Reviewed-by): " "$patch_file" 2>/dev/null || echo "无签名信息"
        
        echo ""
        echo "## 统计信息"
        local added_lines removed_lines
        added_lines=$(grep "^+" "$patch_file" | wc -l)
        removed_lines=$(grep "^-" "$patch_file" | wc -l)
        echo "新增行数: $added_lines"
        echo "删除行数: $removed_lines"
        
    } > "$PATCH_METADATA_FILE"
    
    log_success "元数据已保存到: $PATCH_METADATA_FILE"
    log_info "元数据文件已保存到当前目录，不会被自动删除"
    printf "\n"
    printf "元数据预览:\n"
    head -30 "$PATCH_METADATA_FILE" | sed 's/^/  /'
    return 0
}

# 创建补丁
create_patch() {
    local patch_name="$1"
    local commit_id="$2"
    
    if [[ -z "$patch_name" ]]; then
        log_error "请提供补丁名称"
        return 1
    fi
    
    # 确保补丁名称以 .patch 结尾
    if [[ ! "$patch_name" =~ \.patch$ ]]; then
        patch_name="${patch_name}.patch"
    fi
    
    log_info "创建新补丁: $patch_name"
    
    # 创建新补丁
    if quilt new "$patch_name"; then
        log_success "补丁 $patch_name 创建成功"
        
        # 如果提供了 commit_id，自动提取文件列表并添加
        if [[ -n "$commit_id" ]]; then
            log_info "自动添加 commit $commit_id 涉及的文件..."
            if extract_files "$commit_id" && [[ -f "$PATCH_LIST_FILE" ]]; then
                add_files "$PATCH_LIST_FILE"
            fi
        fi
        return 0
    else
        log_error "补丁创建失败"
        return 1
    fi
}

# 演示功能
demo() {
    local commit_id="654b33ada4ab5e926cd9c570196fefa7bec7c1df"
    
    printf "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║               🚀 Quilt 补丁管理工具功能演示                           ║${NC}\n"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}\n"
    log_info "使用 CVE commit: $commit_id"
    printf "\n"
    
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf "📥 功能 1: 保存原始补丁到当前目录 (新功能)\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    if save_patch "$commit_id" "demo_${commit_id}_original.patch"; then
        log_success "原始补丁已持久保存，不会被自动删除"
    fi
    printf "\n"
    
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf "📄 功能 2: 提取文件列表 (持久保存)\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    extract_files "$commit_id"
    printf "\n"
    
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf "📋 功能 3: 提取元数据 (持久保存)\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    extract_metadata "$commit_id"
    printf "\n"
    
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf "📊 功能演示总结\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_success "演示完成！生成的持久文件:"
    if [[ -f "demo_${commit_id}_original.patch" ]]; then
        printf "  📥 demo_${commit_id}_original.patch (%s 字节) - 原始补丁\n" "$(wc -c < "demo_${commit_id}_original.patch")"
    fi
    if [[ -f "$PATCH_LIST_FILE" ]]; then
        printf "  📄 %s (%s 个文件) - 文件列表\n" "$PATCH_LIST_FILE" "$(wc -l < "$PATCH_LIST_FILE")"
    fi
    if [[ -f "$PATCH_METADATA_FILE" ]]; then
        printf "  📋 %s (%s 行) - 元数据\n" "$PATCH_METADATA_FILE" "$(wc -l < "$PATCH_METADATA_FILE")"
    fi
    printf "\n"
    printf "${GREEN}💡 文件保存说明:${NC}\n"
    printf "  🗂️  临时目录: %s (脚本结束时删除)\n" "$ORIGINAL_PWD/$TEMP_DIR"
    printf "  💾 持久文件: 上述文件保留在当前目录\n"
    printf "  📥 新功能: 使用 'save' 命令可保存原始补丁\n"
    printf "\n"
    log_info "在内核源码目录中使用 'auto-patch' 命令可以完成完整的补丁制作流程"
    return 0
}

# 自动化完整补丁制作流程
auto_patch() {
    local commit_id="$1"
    local patch_name="$2"
    
    if [[ -z "$commit_id" ]] || [[ -z "$patch_name" ]]; then
        log_error "请提供 commit_id 和 patch_name"
        printf "用法: %s auto-patch <commit_id> <patch_name>\n" "$0"
        return 1
    fi
    
    log_info "🚀 开始自动化补丁制作流程..."
    log_info "Commit ID: $commit_id"
    log_info "补丁名称: $patch_name"
    printf "\n"
    
    # 0. 首先检测补丁兼容性 🆕
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "🔍 步骤 0: 智能补丁兼容性检测"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    local compatibility_result
    compatibility_result=$(test_patch_compatibility "$commit_id") || {
        local exit_code=$?
        if [[ $exit_code -eq 2 ]]; then
            log_error "补丁不兼容 - 缺失必要文件，自动化流程终止"
            printf "\n${RED}🛑 自动补丁制作流程被安全终止${NC}\n"
            printf "建议：手动检查补丁内容和内核版本兼容性\n"
            return 2
        elif [[ $exit_code -eq 1 ]]; then
            log_warning "检测到补丁冲突，继续执行将需要手动解决"
            printf "\n${YELLOW}⚠️ 继续执行 auto-patch 可能会创建有问题的补丁${NC}\n"
            printf "${CYAN}是否要继续? (y/N): ${NC}"
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                log_info "用户选择终止，流程安全退出"
                printf "\n${GREEN}💡 建议使用手动补丁制作流程${NC}\n"
                return 0
            fi
            log_warning "用户选择继续，请注意后续手动修改的必要性"
        fi
    }
    
    printf "\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_success "✅ 兼容性检测通过，继续补丁制作流程"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf "\n"
    
    # 1. 创建补丁并添加文件
    if ! create_patch "$patch_name" "$commit_id"; then
        return 1
    fi
    
    printf "\n"
    
    # 2. 提取元数据
    if ! extract_metadata "$commit_id"; then
        return 1
    fi
    
    # 3. 保存原始补丁到当前目录 (可选)
    log_info "保存原始补丁到当前目录以供参考..."
    save_patch "$commit_id" "original_${commit_id}.patch" || log_warning "无法保存原始补丁，继续流程"
    
    # 4. 提示用户进行手动修改
    printf "\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_warning "⚠️  请手动修改源码文件，然后按回车继续..."
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "📄 涉及的文件列表: $PATCH_LIST_FILE"
    log_info "📋 参考元数据信息: $PATCH_METADATA_FILE"
    if [[ -f "original_${commit_id}.patch" ]]; then
        log_info "📥 原始补丁参考: original_${commit_id}.patch"
    fi
    printf "\n"
    printf "修改完成后按回车继续，或按 Ctrl+C 退出...\n"
    read -r
    
    # 5. 生成最终补丁
    log_info "生成补丁..."
    if quilt refresh; then
        log_success "补丁生成成功"
    else
        log_error "补丁生成失败"
        return 1
    fi
    
    # 6. 显示结果
    printf "\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_success "🎉 自动化补丁制作完成！"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "🔧 补丁文件: patches/$patch_name"
    log_info "📄 文件列表: $PATCH_LIST_FILE"
    log_info "📋 元数据: $PATCH_METADATA_FILE"
    if [[ -f "original_${commit_id}.patch" ]]; then
        log_info "📥 原始补丁: original_${commit_id}.patch"
    fi
    
    # 显示补丁统计
    if [[ -f "patches/$patch_name" ]]; then
        local patch_size
        patch_size=$(wc -c < "patches/$patch_name")
        log_info "📏 补丁大小: $patch_size 字节"
    fi
    
    return 0
}

# 清理补丁和临时文件
clean_patches() {
    local clean_type="$1"
    
    log_info "🧹 开始清理操作..."
    
    # 如果在内核源码目录，提供更多清理选项
    if [[ -f "Makefile" ]] && grep -q "KERNELRELEASE" Makefile 2>/dev/null; then
        log_info "检测到当前在内核源码目录，提供完整清理选项"
        clean_kernel_patches
    else
        # 尝试自动找到内核目录
        if find_kernel_source; then
            clean_kernel_patches
        else
            log_warning "未找到内核源码目录，只清理当前目录的临时文件"
        fi
    fi
    
    # 清理当前目录的临时文件
    clean_current_dir
    
    log_success "🎉 清理完成！"
}

# 清理内核目录中的补丁
clean_kernel_patches() {
    local current_dir=$(pwd)
    
    printf "\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "🔍 内核源码目录清理选项："
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    # 检查是否有patches目录
    if [[ -d "patches" ]]; then
        local patch_count=$(ls -1 patches/*.patch 2>/dev/null | wc -l)
        log_info "📄 发现 $patch_count 个补丁文件"
        
        if [[ $patch_count -gt 0 ]]; then
            printf "补丁列表:\n"
            ls -1 patches/*.patch 2>/dev/null | sed 's/^/  📄 /'
            printf "\n"
            
            # 询问用户是否要清理补丁
            printf "${YELLOW}是否要清理所有补丁? (y/N): ${NC}"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                # 移除所有应用的补丁
                log_info "移除所有应用的补丁..."
                quilt pop -a 2>/dev/null || true
                
                # 删除patches目录
                log_info "删除 patches 目录..."
                rm -rf patches/
                log_success "✅ 已清理所有补丁"
            else
                log_info "跳过补丁清理"
            fi
        fi
    else
        log_info "📄 没有发现 patches 目录"
    fi
    
    # 清理quilt相关的隐藏文件
    if [[ -d ".pc" ]]; then
        printf "\n${YELLOW}是否要清理 quilt 工作目录 (.pc)? (y/N): ${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rm -rf .pc/
            log_success "✅ 已清理 quilt 工作目录"
        fi
    fi
}

# 清理当前目录的临时文件
clean_current_dir() {
    local files_to_clean=(
        "patch_files.txt"
        "patch_metadata.txt"
        "original_*.patch"
        "demo_*.patch"
        "*.patch"
    )
    
    printf "\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "🗂️ 当前目录清理选项："
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    local found_files=()
    for pattern in "${files_to_clean[@]}"; do
        while IFS= read -r -d '' file; do
            found_files+=("$file")
        done < <(find . -maxdepth 1 -name "$pattern" -type f -print0 2>/dev/null)
    done
    
    if [[ ${#found_files[@]} -gt 0 ]]; then
        printf "发现以下临时文件:\n"
        for file in "${found_files[@]}"; do
            printf "  🗑️  $file\n"
        done
        printf "\n"
        
        printf "${YELLOW}是否要清理这些临时文件? (y/N): ${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            for file in "${found_files[@]}"; do
                rm -f "$file"
                log_info "已删除: $file"
            done
            log_success "✅ 已清理当前目录的临时文件"
        else
            log_info "跳过临时文件清理"
        fi
    else
        log_info "🗑️ 当前目录没有发现临时文件"
    fi
}

# ===================== QUILT 常用命令支持 =====================

# quilt status - 显示补丁状态
quilt_status() {
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
}

# quilt series - 显示补丁系列
quilt_series() {
    log_info "📋 补丁系列列表："
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    if ! quilt series >/dev/null 2>&1; then
        log_warning "📄 没有发现补丁系列"
        return 0
    fi
    
    # 获取已应用的补丁列表
    local applied_list=""
    if quilt applied >/dev/null 2>&1; then
        applied_list=$(quilt applied 2>/dev/null)
    fi
    
    # 显示补丁系列，标记已应用状态
    local index=1
    while IFS= read -r patch; do
        if echo "$applied_list" | grep -q "^$patch$"; then
            printf "  %2d. ✅ ${GREEN}%s${NC} (已应用)\n" "$index" "$patch"
        else
            printf "  %2d. ❌ ${YELLOW}%s${NC} (未应用)\n" "$index" "$patch"
        fi
        ((index++))
    done < <(quilt series 2>/dev/null)
    
    printf "\n"
}

# quilt applied - 显示已应用的补丁
quilt_applied() {
    log_info "✅ 已应用的补丁："
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    if ! quilt applied >/dev/null 2>&1; then
        log_warning "📄 没有已应用的补丁"
        return 0
    fi
    
    local index=1
    while IFS= read -r patch; do
        printf "  %2d. ✅ ${GREEN}%s${NC}\n" "$index" "$patch"
        ((index++))
    done < <(quilt applied 2>/dev/null)
    
    printf "\n"
}

# quilt unapplied - 显示未应用的补丁
quilt_unapplied() {
    log_info "❌ 未应用的补丁："
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    if ! quilt unapplied >/dev/null 2>&1; then
        log_warning "📄 所有补丁都已应用"
        return 0
    fi
    
    local index=1
    while IFS= read -r patch; do
        printf "  %2d. ❌ ${YELLOW}%s${NC}\n" "$index" "$patch"
        ((index++))
    done < <(quilt unapplied 2>/dev/null)
    
    printf "\n"
}

# quilt top - 显示当前顶部补丁
quilt_top() {
    log_info "🔝 当前顶部补丁："
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    local top_patch=$(quilt top 2>/dev/null)
    if [[ -n "$top_patch" ]]; then
        printf "  🔝 ${PURPLE}%s${NC}\n" "$top_patch"
        
        # 显示补丁详细信息
        if [[ -f "patches/$top_patch" ]]; then
            printf "\n  📄 ${CYAN}补丁文件位置${NC}: patches/$top_patch\n"
            local patch_size=$(wc -c < "patches/$top_patch" 2>/dev/null || echo "未知")
            printf "  📏 ${CYAN}文件大小${NC}: $patch_size 字节\n"
        fi
    else
        log_warning "📄 没有已应用的补丁"
    fi
    
    printf "\n"
}

# quilt files - 显示顶部补丁涉及的文件
quilt_files() {
    local patch_name="$1"
    
    if [[ -z "$patch_name" ]]; then
        patch_name=$(quilt top 2>/dev/null)
        if [[ -z "$patch_name" ]]; then
            log_error "没有指定补丁名称，且没有顶部补丁"
            return 1
        fi
        log_info "🔍 显示顶部补丁 ($patch_name) 涉及的文件："
    else
        log_info "🔍 显示补丁 ($patch_name) 涉及的文件："
    fi
    
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    local files_output
    if [[ -n "$patch_name" ]]; then
        files_output=$(quilt files "$patch_name" 2>/dev/null)
    else
        files_output=$(quilt files 2>/dev/null)
    fi
    
    if [[ -n "$files_output" ]]; then
        local index=1
        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                printf "  %2d. 📄 ${GREEN}%s${NC} (存在)\n" "$index" "$file"
            else
                printf "  %2d. ❌ ${RED}%s${NC} (不存在)\n" "$index" "$file"
            fi
            ((index++))
        done <<< "$files_output"
    else
        log_warning "📄 补丁没有涉及任何文件"
    fi
    
    printf "\n"
}

# quilt push - 应用补丁
quilt_push() {
    local patch_name="$1"
    local push_all="$2"
    
    if [[ "$push_all" == "-a" || "$push_all" == "--all" ]]; then
        log_info "📌 应用所有未应用的补丁："
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        
        if quilt push -a; then
            log_success "✅ 所有补丁应用成功"
        else
            log_error "❌ 补丁应用失败"
            return 1
        fi
    elif [[ -n "$patch_name" ]]; then
        log_info "📌 应用补丁: $patch_name"
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        
        if quilt push "$patch_name"; then
            log_success "✅ 补丁 $patch_name 应用成功"
        else
            log_error "❌ 补丁 $patch_name 应用失败"
            return 1
        fi
    else
        log_info "📌 应用下一个补丁："
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        
        if quilt push; then
            log_success "✅ 补丁应用成功"
        else
            log_error "❌ 补丁应用失败"
            return 1
        fi
    fi
    
    printf "\n"
}

# quilt pop - 移除补丁
quilt_pop() {
    local patch_name="$1"
    local pop_all="$2"
    
    if [[ "$pop_all" == "-a" || "$pop_all" == "--all" ]]; then
        log_info "📌 移除所有已应用的补丁："
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        
        if quilt pop -a; then
            log_success "✅ 所有补丁移除成功"
        else
            log_error "❌ 补丁移除失败"
            return 1
        fi
    elif [[ -n "$patch_name" ]]; then
        log_info "📌 移除补丁: $patch_name"
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        
        if quilt pop "$patch_name"; then
            log_success "✅ 补丁 $patch_name 移除成功"
        else
            log_error "❌ 补丁 $patch_name 移除失败"
            return 1
        fi
    else
        log_info "📌 移除顶部补丁："
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        
        if quilt pop; then
            log_success "✅ 补丁移除成功"
        else
            log_error "❌ 补丁移除失败"
            return 1
        fi
    fi
    
    printf "\n"
}

# quilt refresh - 生成/更新补丁文件
quilt_refresh() {
    local patch_name="$1"
    
    log_info "🔄 刷新补丁 (将修改写入补丁文件)："
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    # 检查是否有当前补丁
    local current_patch=$(quilt top 2>/dev/null)
    if [[ -z "$current_patch" ]]; then
        log_error "没有顶部补丁，请先创建或应用一个补丁"
        return 1
    fi
    
    log_info "📝 顶部补丁: $current_patch"
    
    # 检查是否有修改
    if quilt diff --no-timestamps >/dev/null 2>&1; then
        log_info "📋 检测到文件修改，正在生成补丁..."
        
        if quilt refresh; then
            log_success "✅ 补丁刷新成功"
            
            # 显示补丁信息
            if [[ -f "patches/$current_patch" ]]; then
                local patch_size=$(wc -c < "patches/$current_patch" 2>/dev/null || echo "未知")
                local patch_lines=$(wc -l < "patches/$current_patch" 2>/dev/null || echo "未知")
                log_info "📄 补丁文件: patches/$current_patch"
                log_info "📏 文件大小: $patch_size 字节"
                log_info "📝 总行数: $patch_lines 行"
                
                # 显示补丁摘要
                printf "\n${CYAN}📋 补丁内容摘要:${NC}\n"
                quilt diff --no-timestamps | head -20
                if [[ $(quilt diff --no-timestamps | wc -l) -gt 20 ]]; then
                    printf "${YELLOW}... (显示前20行，完整内容请查看补丁文件)${NC}\n"
                fi
            fi
        else
            log_error "❌ 补丁刷新失败"
            return 1
        fi
    else
        log_warning "⚠️ 没有检测到文件修改"
        log_info "提示: 请先修改代码文件，然后再执行 refresh"
    fi
    
    printf "\n"
}

# 主函数
main() {
    # 检查参数
    if [[ $# -eq 0 ]]; then
        print_help
        exit 0
    fi
    
    local command="$1"
    shift
    
    # 显示工具标识
    if [[ "$command" != "help" && "$command" != "version" ]]; then
        printf "${CYAN}[INFO]${NC} $TOOL_NAME $VERSION - 正在执行: ${YELLOW}$command${NC}\n"
    fi
    
    # 基本初始化
    check_dependencies
    create_temp_dir
    
    case "$command" in
        "fetch")
            fetch_patch "$@"
            ;;
        "save")
            save_patch "$@"
            ;;
        "test-patch")
            check_dependencies "need_quilt"
            test_patch_compatibility "$@"
            ;;
        "extract-files")
            extract_files "$@"
            ;;
        "add-files")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            add_files "$@"
            ;;
        "extract-metadata")
            extract_metadata "$@"
            ;;
        "create-patch")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            create_patch "$@"
            ;;
        "auto-patch")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            auto_patch "$@"
            ;;
        "demo")
            demo
            ;;
        "clean")
            clean_patches "$@"
            ;;
        "status")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            quilt_status "$@"
            ;;
        "series")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            quilt_series "$@"
            ;;
        "applied")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            quilt_applied "$@"
            ;;
        "unapplied")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            quilt_unapplied "$@"
            ;;
        "top")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            quilt_top "$@"
            ;;
        "files")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            quilt_files "$@"
            ;;
        "push")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            quilt_push "$@"
            ;;
        "pop")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            quilt_pop "$@"
            ;;
        "refresh")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            quilt_refresh "$@"
            ;;
        "version"|"-v"|"--version")
            print_version
            ;;
        "help"|"-h"|"--help")
            print_help
            ;;
        *)
            log_error "未知命令: $command"
            printf "\n"
            print_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
