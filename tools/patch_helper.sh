#!/bin/bash

# OpenWrt i.MX6UL 补丁管理助手脚本
# 用于在 macOS 环境下管理内核补丁

set -e

PATCHES_DIR="target/linux/imx/patches-6.6"
GENERIC_PATCHES_DIR="target/linux/generic/patches-6.6"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== OpenWrt i.MX6UL 补丁管理助手 ===${NC}"

# 功能：列出所有补丁
list_patches() {
    echo -e "\n${GREEN}📁 i.MX 平台补丁 (patches-6.6):${NC}"
    ls -la ${PATCHES_DIR}/ | grep "\.patch$" | awk '{printf "  %s\t%s\n", $9, $5" bytes"}'
    
    echo -e "\n${GREEN}📁 通用内核补丁数量:${NC}"
    echo "  $(ls ${GENERIC_PATCHES_DIR}/*.patch 2>/dev/null | wc -l | tr -d ' ') 个通用补丁"
}

# 功能：查看补丁内容
view_patch() {
    local patch_name="$1"
    if [[ -z "$patch_name" ]]; then
        echo -e "${RED}❌ 请提供补丁文件名${NC}"
        return 1
    fi
    
    local patch_file="${PATCHES_DIR}/${patch_name}"
    if [[ ! -f "$patch_file" ]]; then
        echo -e "${RED}❌ 补丁文件不存在: $patch_file${NC}"
        return 1
    fi
    
    echo -e "${GREEN}📄 补丁内容: $patch_name${NC}"
    echo "----------------------------------------"
    cat "$patch_file"
    echo "----------------------------------------"
}

# 显示帮助
show_help() {
    echo -e "\n${GREEN}用法:${NC}"
    echo "  $0 list                          - 列出所有补丁"
    echo "  $0 view <patch_name>             - 查看补丁内容"
    echo "  $0 help                          - 显示此帮助"
    echo ""
    echo -e "${GREEN}示例:${NC}"
    echo "  $0 list"
    echo "  $0 view 100-bootargs.patch"
}

# 主程序逻辑
case "${1:-help}" in
    "list")
        list_patches
        ;;
    "view")
        view_patch "$2"
        ;;
    "help"|*)
        show_help
        ;;
esac
