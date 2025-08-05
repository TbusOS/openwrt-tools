#!/bin/bash

# OpenWrt 补丁管理助手脚本 (通用版本)
# 支持 macOS 和 Ubuntu 20.04+ 环境

set -e

# 版本信息
SCRIPT_VERSION="1.3"
SUPPORTED_SYSTEMS="macOS, Ubuntu 20.04+"

# 系统检测
detect_system() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macOS"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v lsb_release >/dev/null 2>&1; then
            local distro=$(lsb_release -si 2>/dev/null)
            echo "$distro"
        else
            echo "Linux"
        fi
    else
        echo "Unknown"
    fi
}

CURRENT_SYSTEM=$(detect_system)

# 自动检测 OpenWrt 补丁目录
detect_patch_directories() {
    local base_dirs=()
    
    # 查找可能的目标平台目录
    if [[ -d "target/linux" ]]; then
        # 当前目录是 OpenWrt 根目录
        for platform_dir in target/linux/*/; do
            if [[ -d "${platform_dir}" && "${platform_dir}" != "target/linux/generic/" ]]; then
                local platform=$(basename "$platform_dir")
                
                # 查找 patches-* 格式的目录
                for kernel_dir in "${platform_dir}patches-"*; do
                    if [[ -d "$kernel_dir" ]]; then
                        local kernel_ver=$(basename "$kernel_dir" | sed 's/patches-//')
                        base_dirs+=("${platform}:${kernel_ver}:${kernel_dir}")
                    fi
                done
                
                # 查找普通的 patches 目录
                if [[ -d "${platform_dir}patches" ]]; then
                    base_dirs+=("${platform}:default:${platform_dir}patches")
                fi
            fi
        done
    fi
    
    # 默认通用目录
    if [[ -d "target/linux/generic" ]]; then
        # 查找 patches-* 格式的目录
        for kernel_dir in target/linux/generic/patches-*; do
            if [[ -d "$kernel_dir" ]]; then
                local kernel_ver=$(basename "$kernel_dir" | sed 's/patches-//')
                base_dirs+=("generic:${kernel_ver}:${kernel_dir}")
            fi
        done
        
        # 查找普通的 patches 目录
        if [[ -d "target/linux/generic/patches" ]]; then
            base_dirs+=("generic:default:target/linux/generic/patches")
        fi
    fi
    
    printf '%s\n' "${base_dirs[@]}"
}

# 颜色定义（兼容不同终端）
setup_colors() {
    if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
        RED=$(tput setaf 1 2>/dev/null || echo '\033[0;31m')
        GREEN=$(tput setaf 2 2>/dev/null || echo '\033[0;32m')
        YELLOW=$(tput setaf 3 2>/dev/null || echo '\033[0;33m')
        BLUE=$(tput setaf 4 2>/dev/null || echo '\033[0;34m')
        BOLD=$(tput bold 2>/dev/null || echo '\033[1m')
        NC=$(tput sgr0 2>/dev/null || echo '\033[0m')
    else
        RED=''
        GREEN=''
        YELLOW=''
        BLUE=''
        BOLD=''
        NC=''
    fi
}

setup_colors

echo -e "${BLUE}${BOLD}=== OpenWrt 补丁管理助手 v${SCRIPT_VERSION} ===${NC}"
echo -e "${YELLOW}运行环境: ${CURRENT_SYSTEM}${NC}"

# 跨平台的文件大小格式化
format_file_size() {
    local size=$1
    if [[ "$CURRENT_SYSTEM" == "macOS" ]]; then
        # macOS 使用 BSD 版本的工具
        if command -v numfmt >/dev/null 2>&1; then
            echo "$size" | numfmt --to=iec-i --suffix=B
        else
            echo "${size} bytes"
        fi
    else
        # Linux 使用 GNU 版本的工具
        if command -v numfmt >/dev/null 2>&1; then
            echo "$size" | numfmt --to=iec-i --suffix=B
        else
            echo "${size} bytes"
        fi
    fi
}

# 跨平台的文件列表功能
list_files_cross_platform() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        echo -e "${RED}❌ 目录不存在: $dir${NC}"
        return 1
    fi
    
    # 简化的文件列表，避免复杂的管道操作
    find "$dir" -maxdepth 1 -name "*.patch" -type f 2>/dev/null | sort | while read -r patch_file; do
        if [[ -f "$patch_file" ]]; then
            local filename=$(basename "$patch_file")
            local size=$(stat -c%s "$patch_file" 2>/dev/null || stat -f%z "$patch_file" 2>/dev/null || echo "0")
            local formatted_size=$(format_file_size "$size")
            printf "  %-50s %s\n" "$filename" "$formatted_size"
        fi
    done
}

# 功能：列出所有补丁
list_patches() {
    local patch_dirs=($(detect_patch_directories))
    
    if [[ ${#patch_dirs[@]} -eq 0 ]]; then
        echo -e "${RED}❌ 未找到 OpenWrt 补丁目录${NC}"
        echo -e "${YELLOW}💡 请确保在 OpenWrt 项目根目录中运行此脚本${NC}"
        return 1
    fi
    
    for dir_info in "${patch_dirs[@]}"; do
        IFS=':' read -r platform kernel_ver patch_dir <<< "$dir_info"
        
        if [[ "$kernel_ver" == "default" ]]; then
            echo -e "\n${GREEN}📦 ${platform} 平台补丁:${NC}"
        else
            echo -e "\n${GREEN}📦 ${platform} 平台补丁 (patches-${kernel_ver}):${NC}"
        fi
        
        local patch_count=$(find "$patch_dir" -maxdepth 1 -name "*.patch" -type f 2>/dev/null | wc -l | tr -d ' ')
        
        if [[ "$patch_count" -eq 0 ]]; then
            echo -e "  ${YELLOW}📋 没有找到补丁文件${NC}"
        else
            list_files_cross_platform "$patch_dir"
            echo -e "\n  ${BLUE}📊 总计: $patch_count 个补丁${NC}"
        fi
    done
}

# 功能：查看补丁内容
view_patch() {
    local patch_name="$1"
    if [[ -z "$patch_name" ]]; then
        echo -e "${RED}❌ 请提供补丁文件名${NC}"
        return 1
    fi
    
    local patch_dirs=($(detect_patch_directories))
    local found_patch=""
    local found_platform=""
    
    # 在所有平台目录中搜索补丁
    for dir_info in "${patch_dirs[@]}"; do
        IFS=':' read -r platform kernel_ver patch_dir <<< "$dir_info"
        local patch_file="${patch_dir}/${patch_name}"
        
        if [[ -f "$patch_file" ]]; then
            found_patch="$patch_file"
            found_platform="$platform"
            break
        fi
    done
    
    if [[ -z "$found_patch" ]]; then
        echo -e "${RED}❌ 补丁文件不存在: $patch_name${NC}"
        echo -e "${YELLOW}💡 使用 '$0 list' 查看可用的补丁文件${NC}"
        return 1
    fi
    
    echo -e "${GREEN}📄 补丁内容: $patch_name${NC}"
    echo -e "${BLUE}📍 平台: $found_platform${NC}"
    echo -e "${BLUE}📁 路径: $found_patch${NC}"
    echo "----------------------------------------"
    
    # 使用 cat 确保跨平台兼容性
    if command -v bat >/dev/null 2>&1; then
        # 如果有 bat 命令（更好的语法高亮）
        bat --style=plain --language=diff "$found_patch" 2>/dev/null || cat "$found_patch"
    else
        cat "$found_patch"
    fi
    echo "----------------------------------------"
}

# 功能：搜索补丁
search_patches() {
    local search_term="$1"
    local platform_filter="$2"
    
    if [[ -z "$search_term" ]]; then
        echo -e "${RED}❌ 请提供搜索关键词${NC}"
        return 1
    fi
    
    if [[ -n "$platform_filter" ]]; then
        echo -e "${GREEN}🔍 在 '$platform_filter' 平台搜索包含 '$search_term' 的补丁:${NC}"
    else
        echo -e "${GREEN}🔍 搜索包含 '$search_term' 的补丁:${NC}"
    fi
    
    local patch_dirs=($(detect_patch_directories))
    local found_results=()
    
    for dir_info in "${patch_dirs[@]}"; do
        IFS=':' read -r platform kernel_ver patch_dir <<< "$dir_info"
        
        # 如果指定了平台过滤器，跳过不匹配的平台
        if [[ -n "$platform_filter" && "$platform" != "$platform_filter" ]]; then
            continue
        fi
        
        while read -r patch_file; do
            if [[ -n "$patch_file" ]]; then
                local filename=$(basename "$patch_file")
                if echo "$filename" | grep -i "$search_term" >/dev/null 2>&1; then
                    found_results+=("$filename ($platform)")
                fi
            fi
        done < <(find "$patch_dir" -maxdepth 1 -name "*.patch" -type f 2>/dev/null)
    done
    
    if [[ ${#found_results[@]} -eq 0 ]]; then
        echo -e "  ${YELLOW}📋 未找到匹配的补丁${NC}"
    else
        # 按字母顺序排序并显示结果
        printf '%s\n' "${found_results[@]}" | sort | while read -r result; do
            echo -e "  ${YELLOW}📄 $result${NC}"
        done
    fi
}

# 显示系统信息
show_system_info() {
    echo -e "\n${GREEN}🖥️  系统信息:${NC}"
    echo -e "  操作系统: $CURRENT_SYSTEM"
    echo -e "  脚本版本: $SCRIPT_VERSION"
    echo -e "  支持系统: $SUPPORTED_SYSTEMS"
    echo -e "  Shell: $SHELL"
    
    if [[ "$CURRENT_SYSTEM" == "Linux" ]] && command -v lsb_release >/dev/null 2>&1; then
        echo -e "  发行版: $(lsb_release -d 2>/dev/null | cut -f2-)"
    fi
    
    echo -e "\n${GREEN}🔧 依赖工具检查:${NC}"
    local tools=("find" "grep" "awk" "sed" "sort")
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo -e "  ✅ $tool"
        else
            echo -e "  ❌ $tool (缺失)"
        fi
    done
}

# 显示帮助
show_help() {
    echo -e "\n${GREEN}用法:${NC}"
    echo "  $0 list                              - 列出所有补丁"
    echo "  $0 view <patch_name>                 - 查看补丁内容"
    echo "  $0 search <keyword> [platform]      - 搜索补丁文件名（按字母顺序排序）"
    echo "  $0 info                              - 显示系统信息"
    echo "  $0 help                              - 显示此帮助"
    echo ""
    echo -e "${GREEN}可用平台:${NC}"
    echo "  brcm5830, goldfish, imx6ul"
    echo ""
    echo -e "${GREEN}示例:${NC}"
    echo "  $0 list"
    echo "  $0 view CVE-2021-40490.patch"
    echo "  $0 search CVE                       # 搜索所有平台的CVE补丁"
    echo "  $0 search CVE imx6ul                # 仅搜索imx6ul平台的CVE补丁"
    echo "  $0 search imx6                      # 搜索包含imx6的补丁"
    echo "  $0 search driver brcm5830           # 搜索brcm5830平台的driver相关补丁"
    echo ""
    echo -e "${BLUE}💡 提示: 请在 OpenWrt 项目根目录中运行此脚本${NC}"
}

# 主程序逻辑
case "${1:-help}" in
    "list")
        list_patches
        ;;
    "view")
        view_patch "$2"
        ;;
    "search")
        search_patches "$2" "$3"
        ;;
    "info")
        show_system_info
        ;;
    "help"|*)
        show_help
        ;;
esac
