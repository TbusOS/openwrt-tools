#!/bin/bash

# OpenWrt Quilt CVE Patch Manager v5.4.6
# 功能：自动化 CVE 补丁制作流程
# v5.4.6版本，智能多文件冲突分配 + 完美冲突分析

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
VERSION="v5.7.0"

# 配置
KERNEL_GIT_URL="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
TEMP_DIR="patch-tmp/patch_manager_$$"
PATCH_LIST_FILE="patch_files.txt"
PATCH_METADATA_FILE="patch_metadata.txt"
KNOWLEDGE_BASE_DIR="patch_knowledge_base"

# 缓存管理
init_cache() {
    mkdir -p "$ORIGINAL_PWD/$KNOWLEDGE_BASE_DIR"
}

# 写入缓存
# $1: commit_id
# $2: data_type (files, metadata, fixes, symbols)
# $3: content
write_to_cache() {
    local commit_id="$1"
    local data_type="$2"
    local content="$3"
    
    if [[ -z "$commit_id" ]]; then
        log_debug "Commit ID为空，跳过缓存写入"
        return
    fi
    
    local cache_dir="$ORIGINAL_PWD/$KNOWLEDGE_BASE_DIR/$commit_id"
    mkdir -p "$cache_dir"
    
    # 使用heredoc来安全处理多行内容
    cat > "$cache_dir/${data_type}.txt" <<< "$content"
    log_debug "已将 '${data_type}' 写入到 ${commit_id} 的缓存中"
}

# 读取缓存
# $1: commit_id
# $2: data_type
read_from_cache() {
    local commit_id="$1"
    local data_type="$2"
    
    if [[ -z "$commit_id" ]]; then
        return 1
    fi

    local cache_file="$ORIGINAL_PWD/$KNOWLEDGE_BASE_DIR/$commit_id/${data_type}.txt"
    if [[ -f "$cache_file" ]]; then
        cat "$cache_file"
        return 0
    else
        return 1
    fi
}


# 调试开关 (可通过环境变量 DEBUG=1 或命令行参数 --debug 控制)
DEBUG_MODE=${DEBUG:-false}

# 🔧 修复：保存原始工作目录
ORIGINAL_PWD="$(pwd)"

# 调试打印函数
debug_print() {
    if [[ "$DEBUG_MODE" == "true" || "$DEBUG_MODE" == "1" ]]; then
        printf "🔧 [DEBUG] %s\n" "$*" >&2
    fi
}

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

log_debug() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        printf "${PURPLE}[DEBUG]${NC} %s\n" "$1" >&2
    fi
}

# 🆕 分析具体冲突位置和现有代码内容 (重构版)
analyze_conflict_locations() {
    local patch_test_output="$1"
    local patch_file="$2"
    shift 2
    local affected_files=("$@")
    
    printf "${CYAN}🔍 具体冲突分析:${NC}\n"
    
    # 立即显示基本信息
    printf "   📊 ${PURPLE}受影响文件数量: ${#affected_files[@]}${NC}\n"
    printf "   📊 ${PURPLE}patch输出长度: $(echo "$patch_test_output" | wc -l) 行${NC}\n"
    
    # 建立文件映射
    declare -A file_mapping
    for file in "${affected_files[@]}"; do
        local basename_file=$(basename "$file")
        file_mapping["$basename_file"]="$file"
        file_mapping["$file"]="$file"
        printf "   📁 ${CYAN}文件: $(basename "$file")${NC}\n"
    done
    
    printf "\n   🔄 ${CYAN}开始智能冲突分析...${NC}\n"
    
    # 解析补丁内容，分析每个失败的Hunk
    local conflict_found=false
    declare -A displayed_files
    
    # 从patch输出中提取失败的文件和Hunk信息
    local current_file=""
    local failed_hunks=()
    
    while IFS= read -r line; do
        # 检测当前处理的文件
        if [[ "$line" =~ checking\ file\ (.+)$ ]]; then
            current_file="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ Hunk\ #([0-9]+)\ FAILED\ at\ ([0-9]+)\.$ ]]; then
            local hunk_num="${BASH_REMATCH[1]}"
            local failed_line="${BASH_REMATCH[2]}"
            failed_hunks+=("$current_file:$hunk_num:$failed_line")
        fi
    done <<< "$patch_test_output"
    
    # 如果没有从patch输出中找到明确的失败信息，分析补丁文件本身
    if [[ ${#failed_hunks[@]} -eq 0 ]]; then
        printf "   🔍 ${YELLOW}从patch输出未找到明确失败信息，分析补丁文件内容...${NC}\n"
        
        # 解析补丁文件，分析每个Hunk
        local current_patch_file=""
        local hunk_count=0
        local in_hunk=false
        local hunk_old_start=0
        declare -a hunk_context_lines=()
        declare -a hunk_remove_lines=()
        declare -a hunk_add_lines=()
        
        while IFS= read -r line; do
            # 检测文件头
            if [[ "$line" =~ ^---[[:space:]]+a/(.+)$ ]]; then
                current_patch_file="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^@@[[:space:]]*-([0-9]+).*[[:space:]]*@@.*$ ]]; then
                # 新的Hunk开始
                if [[ $in_hunk == true ]] && [[ -n "$current_patch_file" ]]; then
                    # 处理前一个Hunk
                    analyze_single_hunk "$current_patch_file" "$hunk_count" "$hunk_old_start" \
                        hunk_context_lines hunk_remove_lines hunk_add_lines file_mapping affected_files
                fi
                
                ((hunk_count++))
                hunk_old_start="${BASH_REMATCH[1]}"
                in_hunk=true
                hunk_context_lines=()
                hunk_remove_lines=()
                hunk_add_lines=()
                conflict_found=true
                
            elif [[ $in_hunk == true ]]; then
                # 在Hunk内部
                if [[ "$line" =~ ^[[:space:]](.*)$ ]]; then
                    # 上下文行
                    hunk_context_lines+=("${BASH_REMATCH[1]}")
                elif [[ "$line" =~ ^-(.*)$ ]]; then
                    # 删除行
                    hunk_remove_lines+=("${BASH_REMATCH[1]}")
                elif [[ "$line" =~ ^+(.*)$ ]]; then
                    # 添加行
                    hunk_add_lines+=("${BASH_REMATCH[1]}")
                fi
            fi
        done < "$patch_file"
        
        # 处理最后一个Hunk
        if [[ $in_hunk == true ]] && [[ -n "$current_patch_file" ]]; then
            analyze_single_hunk "$current_patch_file" "$hunk_count" "$hunk_old_start" \
                hunk_context_lines hunk_remove_lines hunk_add_lines file_mapping affected_files
        fi
    else
        printf "   ✅ ${GREEN}从patch输出找到 ${#failed_hunks[@]} 个失败的Hunk${NC}\n"
        
        # 处理每个失败的Hunk
        for failed_hunk in "${failed_hunks[@]}"; do
            IFS=':' read -r fail_file fail_hunk_num fail_line <<< "$failed_hunk"
            
            # 安全检查：确保 fail_file 不为空
            if [[ -z "$fail_file" ]]; then
                printf "   ⚠️  ${YELLOW}警告: 跳过空文件名的失败Hunk${NC}\n"
                continue
            fi
            
            # 映射文件路径 - 安全的数组访问
            local actual_file="$fail_file"
            # 检查 file_mapping 是否存在该键
            if [[ -n "$fail_file" ]] && [[ -v "file_mapping[$fail_file]" ]] && [[ -n "${file_mapping[$fail_file]}" ]]; then
                actual_file="${file_mapping[$fail_file]}"
            else
                # 回退到基于文件名的匹配
                for mapped_file in "${affected_files[@]}"; do
                    if [[ -n "$mapped_file" ]] && [[ "$(basename "$mapped_file")" == "$(basename "$fail_file")" ]]; then
                        actual_file="$mapped_file"
                        break
                    fi
                done
            fi
            
            # 每个文件只显示一次文件头 - 安全的数组访问
            if [[ -n "$actual_file" ]] && [[ -z "${displayed_files[$actual_file]:-}" ]]; then
                printf "\n📄 ${YELLOW}文件: $actual_file${NC}\n"
                displayed_files["$actual_file"]=1
            fi
            
            printf "   ❌ ${RED}Hunk #$fail_hunk_num 失败 (补丁期望在第 $fail_line 行附近)${NC}\n"
            
            conflict_found=true
        done
        
        # 在冲突分析完成后提供实用建议
        if [[ $conflict_found == true ]]; then
            printf "\n💡 ${CYAN}如需查看具体冲突内容，请手动执行：${NC}\n"
            printf "   ${YELLOW}1. 查看补丁内容：${NC} cat $patch_file\n"
            printf "   ${YELLOW}2. 查看详细冲突：${NC} patch -p1 --dry-run < $patch_file\n"
            printf "   ${YELLOW}3. 查看目标文件：${NC} cat 目标文件路径\n"
        fi
    fi
    
    # 如果仍然没有找到冲突，显示通用信息
    if [[ "$conflict_found" == "false" ]]; then
        printf "   ❌ ${RED}无法解析具体冲突位置${NC}\n"
        printf "   💡 ${CYAN}补丁应用失败的可能原因：${NC}\n"
        printf "      • 代码上下文已发生变化\n"
        printf "      • 函数或变量名称已修改\n"
        printf "      • 文件结构已重组\n"
        printf "      • 需要手动检查补丁内容\n"
        printf "\n"
        printf "   🔧 ${CYAN}建议的解决方案:${NC}\n"
        printf "      • 检查补丁文件路径和目标文件是否正确\n"
        printf "      • 确认补丁适用的内核版本或代码版本\n"
        printf "      • 使用 'quilt add' 和 'quilt edit' 手动创建适配补丁\n"
        printf "      • 查看详细冲突报告文件获取更多信息\n"
    fi
}

# 🆕 分析单个Hunk的冲突 (智能上下文匹配)
analyze_single_hunk() {
    local patch_file="$1"
    local hunk_count="$2"
    local hunk_old_start="$3"
    local -n context_lines_ref="$4"
    local -n remove_lines_ref="$5"
    local -n add_lines_ref="$6"
    local -n file_mapping_ref="$7"
    local -n affected_files_ref="$8"
    
    # 映射到实际文件路径
    local actual_file="$patch_file"
    if [[ -n "${file_mapping_ref[$patch_file]:-}" ]]; then
        actual_file="${file_mapping_ref[$patch_file]}"
    else
        for mapped_file in "${affected_files_ref[@]}"; do
            if [[ "$(basename "$mapped_file")" == "$(basename "$patch_file")" ]]; then
                actual_file="$mapped_file"
                break
            fi
        done
    fi
    
    printf "\n📄 ${YELLOW}文件: $actual_file${NC}\n"
    printf "   ❌ ${RED}Hunk #$hunk_count 冲突 (补丁期望从第 $hunk_old_start 行开始)${NC}\n"
    
    if [[ ! -f "$actual_file" ]]; then
        printf "   ❌ ${RED}文件不存在: $actual_file${NC}\n"
        return
    fi
    
    # 构建期望的上下文模式
    local search_context=""
    local expected_remove=""
    
    # 组合上下文行和要删除的行作为搜索模式
    local combined_pattern=()
    combined_pattern+=("${context_lines_ref[@]}")
    combined_pattern+=("${remove_lines_ref[@]}")
    
    if [[ ${#combined_pattern[@]} -gt 0 ]]; then
        # 在实际文件中搜索匹配的代码模式
        local found_line=0
        local match_score=0
        local best_match_line=0
        local best_match_score=0
        
        # 创建临时文件存储搜索模式
        local temp_pattern_file="/tmp/patch_pattern_$$"
        for pattern_line in "${combined_pattern[@]}"; do
            # 清理行内容，移除多余空格
            local clean_line=$(echo "$pattern_line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
            if [[ -n "$clean_line" ]]; then
                echo "$clean_line" >> "$temp_pattern_file"
            fi
        done
        
        # 在文件中搜索相似的代码块
        if [[ -s "$temp_pattern_file" ]]; then
            local file_line_count=$(wc -l < "$actual_file")
            local pattern_line_count=$(wc -l < "$temp_pattern_file")
            
            # 逐行扫描文件，寻找最佳匹配
            for ((start_line=1; start_line <= file_line_count - pattern_line_count + 1; start_line++)); do
                local current_score=0
                local end_line=$((start_line + pattern_line_count - 1))
                
                # 提取当前窗口的文件内容
                local temp_file_window="/tmp/file_window_$$"
                sed -n "${start_line},${end_line}p" "$actual_file" | \
                    sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' > "$temp_file_window"
                
                # 计算匹配得分
                while IFS= read -r pattern_line && IFS= read -r file_line <&3; do
                    if [[ "$pattern_line" == "$file_line" ]]; then
                        ((current_score++))
                    elif [[ -n "$pattern_line" ]] && [[ "$file_line" == *"$pattern_line"* ]]; then
                        # 部分匹配
                        ((current_score += 1))
                    fi
                done < "$temp_pattern_file" 3< "$temp_file_window"
                
                # 更新最佳匹配
                if [[ $current_score -gt $best_match_score ]]; then
                    best_match_score=$current_score
                    best_match_line=$start_line
                fi
                
                rm -f "$temp_file_window"
            done
        fi
        
        rm -f "$temp_pattern_file"
        
        # 显示分析结果
        if [[ $best_match_score -gt 0 ]]; then
            printf "   🔍 ${GREEN}在现有文件中找到相似代码 (匹配度: $best_match_score/${#combined_pattern[@]})${NC}\n"
            printf "   📍 ${CYAN}实际位置: 第 $best_match_line 行附近${NC}\n"
            printf "   📖 ${CYAN}现有代码内容:${NC}\n"
            
            # 显示现有文件的实际内容
            local display_start=$((best_match_line - 2))
            local display_end=$((best_match_line + ${#combined_pattern[@]} + 3))
            
            if [[ $display_start -lt 1 ]]; then
                display_start=1
            fi
            
            local line_counter=$display_start
            while IFS= read -r code_line; do
                if [[ $line_counter -ge $best_match_line ]] && [[ $line_counter -lt $((best_match_line + ${#combined_pattern[@]})) ]]; then
                    printf "   → %4d: ${RED}%s${NC}  ← 冲突区域\n" "$line_counter" "$code_line"
                else
                    printf "     %4d: %s\n" "$line_counter" "$code_line"
                fi
                ((line_counter++))
            done < <(sed -n "${display_start},${display_end}p" "$actual_file" 2>/dev/null)
            
            # 显示补丁期望的修改
            if [[ ${#remove_lines_ref[@]} -gt 0 ]] || [[ ${#add_lines_ref[@]} -gt 0 ]]; then
                printf "\n   💡 ${CYAN}补丁期望的修改:${NC}\n"
                
                if [[ ${#remove_lines_ref[@]} -gt 0 ]]; then
                    printf "   ${RED}删除这些行:${NC}\n"
                    for remove_line in "${remove_lines_ref[@]}"; do
                        printf "     - %s\n" "$remove_line"
                    done
                fi
                
                if [[ ${#add_lines_ref[@]} -gt 0 ]]; then
                    printf "   ${GREEN}添加这些行:${NC}\n"
                    for add_line in "${add_lines_ref[@]}"; do
                        printf "     + %s\n" "$add_line"
                    done
                fi
            fi
        else
            printf "   ❌ ${RED}在现有文件中未找到匹配的代码模式${NC}\n"
            printf "   💡 ${YELLOW}可能的原因:${NC}\n"
            printf "      • 代码已被其他补丁修改\n"
            printf "      • 函数或变量名称已更改\n"
            printf "      • 代码结构已重构\n"
            
            # 显示补丁期望找到的代码
            if [[ ${#combined_pattern[@]} -gt 0 ]]; then
                printf "\n   📝 ${CYAN}补丁期望找到的代码:${NC}\n"
                for expected_line in "${combined_pattern[@]}"; do
                    printf "      %s\n" "$expected_line"
                done
            fi
        fi
    else
        printf "   ❌ ${RED}无法提取补丁的上下文信息${NC}\n"
    fi
}

# 🆕 分析特定失败的Hunk
analyze_specific_failed_hunk() {
    local patch_file="$1"
    local actual_file="$2"
    local hunk_num="$3"
    local expected_line="$4"
    
    printf "   🔧 ${BLUE}[DEBUG] 进入 analyze_specific_failed_hunk 函数${NC}\n"
    printf "   🔧 参数: patch_file='$patch_file'\n"
    printf "   🔧 参数: actual_file='$actual_file'\n"
    printf "   🔧 参数: hunk_num='$hunk_num'\n"
    printf "   🔧 参数: expected_line='$expected_line'\n"
    
    # 🚀 智能fallback：如果临时补丁文件不存在，尝试使用缓存文件
    if [[ ! -f "$patch_file" ]]; then
        printf "   ⚠️  ${YELLOW}临时补丁文件不存在: $patch_file${NC}\n"
        
        # 尝试从文件名提取commit id并构造fallback路径
        local commit_id=""
        if [[ "$patch_file" =~ original_([a-f0-9]{40})\.patch$ ]]; then
            commit_id="${BASH_REMATCH[1]}"
            local fallback_file="$ORIGINAL_PWD/patch_cache_${commit_id}.patch"
            
            if [[ -f "$fallback_file" ]]; then
                printf "   🔄 ${CYAN}使用fallback文件: $fallback_file${NC}\n"
                patch_file="$fallback_file"
            else
                printf "   ❌ ${RED}fallback文件也不存在: $fallback_file${NC}\n"
                return 1
            fi
        else
            printf "   ❌ ${RED}无法提取commit id进行fallback${NC}\n"
            return 1
        fi
    fi
    
    if [[ ! -f "$actual_file" ]]; then
        printf "   ❌ ${RED}目标文件不存在: $actual_file${NC}\n"
        return 1
    fi
    
    printf "   ✅ ${GREEN}文件检查通过${NC}\n"
    
    # 从补丁文件中提取指定的Hunk内容
    printf "   🔍 ${CYAN}开始解析补丁文件...${NC}\n"
    local in_target_hunk=false
    local current_hunk_count=0
    local hunk_context=()
    local hunk_removes=()
    local hunk_adds=()
    local hunk_old_start=0
    local lines_processed=0
    local target_file_found=false
    
    while IFS= read -r line; do
        ((lines_processed++))
        
        # 检测文件头 - 严格匹配避免误判
        if [[ "$line" =~ ^---[[:space:]]+a/(.+)$ ]]; then
            local patch_target_file="${BASH_REMATCH[1]}"
            
            # 只处理匹配的文件
            if [[ "$(basename "$patch_target_file")" == "$(basename "$actual_file")" ]]; then
                target_file_found=true
                printf "   ✅ 找到目标文件: $patch_target_file\n"
            else
                in_target_hunk=false
                target_file_found=false
            fi
        elif [[ "$line" =~ ^+++[[:space:]]+b/ ]]; then
            # 跳过 +++ 行
            continue
        elif [[ "$line" =~ ^@@[[:space:]]*-([0-9]+).*[[:space:]]*@@.*$ ]]; then
            if [[ "$target_file_found" == "true" ]]; then
                ((current_hunk_count++))
                
                if [[ $current_hunk_count -eq $hunk_num ]]; then
                    in_target_hunk=true
                    hunk_old_start="${BASH_REMATCH[1]}"
                    hunk_context=()
                    hunk_removes=()
                    hunk_adds=()
                elif [[ $current_hunk_count -gt $hunk_num ]]; then
                    # 已经超过目标Hunk，直接退出
                    break
                else
                    in_target_hunk=false
                fi
            fi
        elif [[ $in_target_hunk == true ]]; then
            if [[ "$line" =~ ^[[:space:]](.*)$ ]]; then
                hunk_context+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^-(.*)$ ]]; then
                hunk_removes+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^+(.*)$ ]]; then
                hunk_adds+=("${BASH_REMATCH[1]}")
            elif [[ "$line" =~ ^@@.*$ ]]; then
                # 下一个Hunk开始，停止处理
                break
            fi
        fi
    done < "$patch_file"
    
    printf "   📈 解析完成: 处理了 %d 行\n" "$lines_processed"
    printf "   📈 解析结果: 上下文行=%d, 删除行=%d, 添加行=%d\n" "${#hunk_context[@]}" "${#hunk_removes[@]}" "${#hunk_adds[@]}"
    
    # 现在分析这个特定的Hunk
    if [[ $in_target_hunk == true ]] || [[ ${#hunk_context[@]} -gt 0 ]] || [[ ${#hunk_removes[@]} -gt 0 ]]; then
        printf "   📖 ${CYAN}分析 Hunk #$hunk_num (补丁期望从第 $hunk_old_start 行开始):${NC}\n"
        
        # 构建搜索模式
        local search_patterns=()
        search_patterns+=("${hunk_context[@]}")
        search_patterns+=("${hunk_removes[@]}")
        
        if [[ ${#search_patterns[@]} -gt 0 ]]; then
            printf "   🚀 ${CYAN}优化搜索：一次性读取文件内容...${NC}\n"
            # 🚀 性能优化：一次性读取整个文件到数组中，避免大量sed调用
            local file_lines=()
            local line_num=0
            while IFS= read -r line; do
                ((line_num++))
                file_lines[line_num]="$line"
            done < "$actual_file"
            
            local file_total_lines=${#file_lines[@]}
            printf "   📊 文件总行数: %d\n" "$file_total_lines"
            printf "   📊 搜索模式数: %d\n" "${#search_patterns[@]}"
            
            # 在实际文件中搜索最佳匹配位置
            local best_match_line=0
            local best_match_score=0
            local lines_checked=0
            
            # 优化搜索：只检查期望位置附近±50行
            local search_start=$((expected_line - 50))
            local search_end=$((expected_line + 50))
            
            if [[ $search_start -lt 1 ]]; then
                search_start=1
            fi
            if [[ $search_end -gt $file_total_lines ]]; then
                search_end=$file_total_lines
            fi
            
            printf "   🎯 智能搜索范围: %d-%d 行 (总共%d行)\n" "$search_start" "$search_end" "$((search_end - search_start + 1))"
            
            # 搜索窗口（优化版）
            for ((search_line=search_start; search_line <= search_end; search_line++)); do
                local match_score=0
                local window_end=$((search_line + ${#search_patterns[@]} - 1))
                ((lines_checked++))
                
                if [[ $window_end -gt $file_total_lines ]]; then
                    break
                fi
                
                # 显示进度（每100行）
                if [[ $((lines_checked % 100)) -eq 0 ]]; then
                    printf "   📊 已检查 %d 行...\n" "$lines_checked"
                fi
                
                # 计算匹配分数（优化版：直接访问数组）
                local pattern_index=0
                for pattern in "${search_patterns[@]}"; do
                    local file_line_num=$((search_line + pattern_index))
                    if [[ $file_line_num -le $file_total_lines ]]; then
                        local file_line="${file_lines[$file_line_num]}"
                        
                        # 清理行内容进行比较
                        local clean_pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
                        local clean_file_line=$(echo "$file_line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
                        
                        if [[ "$clean_pattern" == "$clean_file_line" ]]; then
                            ((match_score += 2))  # 完全匹配
                        elif [[ -n "$clean_pattern" ]] && [[ "$clean_file_line" == *"$clean_pattern"* ]]; then
                            ((match_score += 1))  # 部分匹配
                        fi
                    fi
                    
                    ((pattern_index++))
                done
                
                if [[ $match_score -gt $best_match_score ]]; then
                    best_match_score=$match_score
                    best_match_line=$search_line
                fi
            done
            
            printf "   📊 搜索完成，检查了 %d 行\n" "$lines_checked"
            
            # 显示结果
            if [[ $best_match_score -gt 0 ]]; then
                printf "   🔍 ${GREEN}在现有文件中找到相似代码块 (匹配分数: $best_match_score)${NC}\n"
                printf "   📍 ${CYAN}实际位置: 第 $best_match_line 行 (期望: 第 $expected_line 行)${NC}\n"
                
                # 显示现有代码内容
                printf "   📖 ${CYAN}现有代码内容:${NC}\n"
                local display_start=$((best_match_line - 2))
                local display_end=$((best_match_line + ${#search_patterns[@]} + 2))
                
                if [[ $display_start -lt 1 ]]; then
                    display_start=1
                fi
                
                local line_counter=$display_start
                while IFS= read -r code_line; do
                    if [[ $line_counter -ge $best_match_line ]] && [[ $line_counter -lt $((best_match_line + ${#search_patterns[@]})) ]]; then
                        printf "   → %4d: ${RED}%s${NC}  ← 冲突区域\n" "$line_counter" "$code_line"
                    else
                        printf "     %4d: %s\n" "$line_counter" "$code_line"
                    fi
                    ((line_counter++))
                done < <(sed -n "${display_start},${display_end}p" "$actual_file" 2>/dev/null)
                
                # 分析代码差异
                if [[ ${#hunk_removes[@]} -gt 0 ]]; then
                    printf "\n   🔍 ${CYAN}代码差异分析:${NC}\n"
                    printf "   • 现有代码与补丁期望不匹配\n"
                    printf "   • 可能的原因: 代码已被修改、行号偏移、或上下文变化\n"
                    
                    local line_offset=$((best_match_line - expected_line))
                    if [[ $line_offset -ne 0 ]]; then
                        printf "   • 行号偏移: %+d 行 (期望第%d行，实际第%d行)\n" "$line_offset" "$expected_line" "$best_match_line"
                    fi
                fi
            else
                printf "   ❌ ${RED}在现有文件中未找到匹配的代码${NC}\n"
                printf "   📖 ${CYAN}期望在第 $expected_line 行附近找到:${NC}\n"
                
                # 显示期望位置的实际内容
                local context_start=$((expected_line - 3))
                local context_end=$((expected_line + 7))
                
                if [[ $context_start -lt 1 ]]; then
                    context_start=1
                fi
                
                local line_counter=$context_start
                while IFS= read -r code_line; do
                    if [[ $line_counter -eq $expected_line ]]; then
                        printf "   → %4d: ${RED}%s${NC}  ← 期望位置\n" "$line_counter" "$code_line"
                    else
                        printf "     %4d: %s\n" "$line_counter" "$code_line"
                    fi
                    ((line_counter++))
                done < <(sed -n "${context_start},${context_end}p" "$actual_file" 2>/dev/null)
                
                printf "\n   💡 ${CYAN}冲突分析:${NC}\n"
                printf "   • 在第 $expected_line 行附近未找到期望的代码模式\n"
                printf "   • 现有代码结构可能已发生变化\n"
                printf "   • 建议手动检查代码差异并适配补丁\n"
            fi
        else
            printf "   ❌ ${RED}无法从补丁中提取Hunk内容${NC}\n"
        fi
    else
        printf "   ❌ ${RED}在补丁文件中未找到Hunk #$hunk_num${NC}\n"
    fi
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
    printf "${GREEN}最新功能 (v5.5):${NC}\n"
    printf "  🆕 智能补丁元数据集成\n"
    printf "  🆕 命令功能分离优化\n"
    printf "  🆕 灵活的工作流程选择\n"
    printf "  🆕 专业的CVE补丁文档化\n"
    printf "\n"
    printf "${GREEN}修复 (v5.3.1):${NC}\n"
    printf "  🔧 修复网络下载超时问题\n"
    printf "  🔧 添加网络连通性检测\n"
    printf "  🔧 增强错误诊断信息\n"
    printf "  🔧 添加重试机制\n"
    printf "\n"
    printf "${GREEN}修复 (v5.3.2):${NC}\n"
    printf "  🔧 修复下载信息显示问题\n"
    printf "  🔧 改进stderr输出重定向\n"
    printf "  🔧 增强下载进度显示\n"
    printf "\n"
    printf "${GREEN}修复 (v5.3.3):${NC}\n"
    printf "  🔧 修复冲突检测逻辑矛盾问题\n"
    printf "  🔧 区分文件级冲突和代码级冲突\n"
    printf "  🔧 显示patch命令详细输出\n"
    printf "  🔧 提供针对性的冲突解决建议\n"
    printf "\n"
    printf "${GREEN}优化 (v5.3.4):${NC}\n"
    printf "  ⚡ 大幅优化文件冲突检查性能\n"
    printf "  ⚡ 增加快速检查模式（仅检查最近50个补丁）\n"
    printf "  ⚡ 增加跳过检查选项（最快模式）\n"
    printf "  ⚡ 显示检查进度和性能统计\n"
    printf "\n"
    printf "${GREEN}修复 (v5.3.5):${NC}\n"
    printf "  🔧 简化冲突检查，删除快速/跳过模式\n"
    printf "  🔧 修复选择完整检查后脚本退出的问题\n"
    printf "  🔧 增强错误处理和调试信息\n"
    printf "  🔧 优化文件处理逻辑\n"
    printf "\n"
    printf "${GREEN}优化 (v5.3.6):${NC}\n"
    printf "  ⚡ 优化test-patch步骤五调试信息显示\n"
    printf "  ⚡ 添加--debug参数控制详细调试信息\n"
    printf "  ⚡ 改进进度条显示，默认关闭调试信息\n"
    printf "  ⚡ 减少冗余输出，提升用户体验\n"
    printf "\n"
    printf "${GREEN}优化 (v5.3.7):${NC}\n"
    printf "  🎯 重构步骤六冲突输出，移除原始补丁内容显示\n"
    printf "  🎯 新增精确冲突位置分析，显示现有代码冲突部分\n"
    printf "  🎯 改进冲突报告，重点突出实际需要解决的代码\n"
    printf "  🎯 优化用户体验，提供更有用的冲突信息\n"
    printf "\n"
    printf "${GREEN}修复 (v5.3.8):${NC}\n"
    printf "  🔧 修复文件名解析问题，正确匹配patch输出中的文件\n"
    printf "  🔧 移除重复的冲突分析显示\n"
    printf "  🔧 改进冲突报告，突出现有代码位置而非原始补丁\n"
    printf "  🔧 增强文件查找逻辑，提升冲突定位准确性\n"
    printf "\n"
    printf "${GREEN}增强 (v5.3.9):${NC}\n"
    printf "  🚀 增强文件名解析，支持多种patch输出格式\n"
    printf "  🚀 添加智能文件推测机制，处理无法解析文件名的情况\n"
    printf "  🚀 添加patch输出诊断信息，便于问题排查\n"
    printf "  🚀 改进basename匹配逻辑，提升文件识别准确性\n"
    printf "\n"
    printf "${GREEN}重大更新 (v5.4.0):${NC}\n"
    printf "  🎉 添加补丁缓存机制，避免重复下载同一补丁\n"
    printf "  🎉 显示实际执行的curl命令，便于调试网络问题\n"
    printf "  🎉 优化下载超时设置，减少卡住问题\n"
    printf "  🎉 增强clean命令，支持缓存文件清理\n"
    printf "\n"
    printf "${GREEN}网络优化 (v5.4.1):${NC}\n"
    printf "  🌐 新增 download-patch 命令，专门解决网络超时问题\n"
    printf "  🌐 重试时自动使用更宽松的网络设置 (30秒超时)\n"
    printf "  🌐 提供多种手动下载方案 (浏览器/wget/curl/代理)\n"
    printf "  🌐 智能检测缓存文件，避免重复下载提示\n"
    printf "\n"
    printf "${GREEN}冲突分析修复 (v5.4.2):${NC}\n"
    printf "  🔧 修复多文件冲突识别问题，正确分配冲突到对应文件\n"
    printf "  🔧 添加冲突统计信息显示，清楚显示冲突文件数量\n"
    printf "  🔧 改进文件名映射逻辑，支持更多patch输出格式\n"
    printf "  🔧 增强冲突报告生成，包含完整的冲突分析信息\n"
    printf "\n"
    printf "${GREEN}显示修复 (v5.4.3):${NC}\n"
    printf "  🛠️ 修复冲突分析不显示的问题，确保总能显示冲突信息\n"
    printf "  🛠️ 添加备用解析方法，当主解析失败时自动启用\n"
    printf "  🛠️ 增加调试信息输出，便于问题诊断\n"
    printf "  🛠️ 改进错误处理逻辑，提供更友好的反馈\n"
    printf "\n"
    printf "${GREEN}强化显示 (v5.4.4):${NC}\n"
    printf "  💪 强制显示基本信息（文件数量、patch长度）确保不空白\n"
    printf "  💪 多重备用机制，主方法->备用方法->完整输出\n"
    printf "  💪 即使完全解析失败也显示完整patch输出供手动分析\n"
    printf "  💪 消除重复错误处理，简化输出逻辑\n"
    printf "\n"
    printf "${GREEN}中断修复 (v5.4.5):${NC}\n"
    printf "  🔧 修复脚本在冲突分析时意外中断的问题\n"
    printf "  🔧 替换可能导致错误的log_debug调用为安全的printf\n"
    printf "  🔧 增加详细的处理进度显示和错误恢复机制\n"
    printf "  🔧 确保即使某个步骤失败也能继续完成分析\n"
    printf "\n"
    printf "${GREEN}完美分析 (v5.4.6):${NC}\n"
    printf "  🎯 改进智能文件分配算法，每个冲突分配到不同文件\n"
    printf "  🎯 现在能正确识别多文件冲突，而不是全部归为一个文件\n"
    printf "  🎯 循环分配机制确保冲突均匀分布到所有受影响文件\n"
    printf "  🎯 提供更准确的冲突统计和文件级分析\n"
    printf "\n"
    printf "${GREEN}重大功能更新 (v5.5.0):${NC}\n"
    printf "  🚀 ${YELLOW}新增 auto-refresh 命令${NC} - 生成补丁并自动集成CVE元数据\n"
    printf "  🔧 ${YELLOW}拆分 refresh 命令${NC} - 分离纯补丁生成和元数据集成功能\n"
    printf "  ✨ ${YELLOW}新增 integrate-metadata 命令${NC} - 手动集成元数据到指定补丁\n"
    printf "  📚 ${YELLOW}更新工作流程${NC} - 手动制作补丁流程新增元数据提取步骤\n"
    printf "  🎯 ${YELLOW}增强命令分离${NC} - 遵循单一职责原则，提升工具灵活性\n"
    printf "  📖 ${YELLOW}完善帮助文档${NC} - 更新使用示例和命令说明\n"
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
    printf "${YELLOW}用法:${NC} %s [--debug] <命令> [参数]\n" "$0"
    printf "\n"
    printf "${GREEN}全局选项:${NC}\n"
    printf "  ${CYAN}--debug${NC}                  - 启用调试模式，显示详细执行信息\n"
    printf "\n"
    printf "${GREEN}调试模式启用方式:${NC}\n"
    printf "  ${YELLOW}1.${NC} 命令行参数: %s --debug <命令>\n" "$0"
    printf "  ${YELLOW}2.${NC} 环境变量: DEBUG=1 %s <命令>\n" "$0"
    printf "\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}命令列表 (可在任意目录运行):${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  ${CYAN}demo${NC}                         - 演示所有功能 (推荐首次使用)\n"
    printf "  ${CYAN}fetch${NC} <commit_id>           - 下载原始补丁到临时目录\n"
    printf "  ${CYAN}save${NC} <commit_id> [filename] - 下载并保存原始补丁到当前目录\n"
    printf "  ${CYAN}download-patch${NC} <commit_id>  - 手动下载补丁助手 (网络超时解决方案) 🆕\n"
    printf "  ${CYAN}test-patch${NC} <commit_id>      - 测试原始补丁兼容性 (智能冲突检测+文件冲突分析)\n"
    printf "  ${CYAN}test-patch${NC} <patch_file>     - 测试本地补丁文件兼容性 🆕\n"
    printf "    ${CYAN}test-patch${NC} <input> --debug - 测试补丁兼容性 (启用详细调试信息)\n"
    printf "  ${CYAN}extract-files${NC} <commit_id>   - 提取文件列表 → ${PURPLE}%s${NC}\n" "$PATCH_LIST_FILE"
    printf "  ${CYAN}extract-metadata${NC} <commit_id> - 提取元数据 → ${PURPLE}%s${NC}\n" "$PATCH_METADATA_FILE"
    printf "  ${CYAN}integrate-metadata${NC} [patch] - 将元数据集成到补丁文件中 🆕\n"
    printf "\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}命令列表 (自动查找内核源码目录):${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  ${CYAN}add-files${NC} <file_list.txt>   - 添加文件列表到当前 quilt 补丁 (需先创建补丁)\n"
    printf "  ${CYAN}create-patch${NC} <name> [commit] - 创建新补丁 → ${PURPLE}patches/<name>.patch${NC}\n"
    printf "  ${CYAN}auto-patch${NC} <commit> <name>  - 自动化完整补丁制作流程\n"
    printf "  ${CYAN}clean${NC}                    - 清理补丁和临时文件 🆕\n"
    printf "  ${CYAN}test-network${NC}             - 测试网络连接到 git.kernel.org 🆕\n"
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
    printf "  ${CYAN}delete${NC} <patch_name>     - 删除补丁文件 🗑️ (需确认)\n"
    printf "  ${CYAN}refresh${NC}                  - 生成/更新补丁文件 🔄\n"
    printf "  ${CYAN}auto-refresh${NC}             - 生成补丁并自动集成元数据 🔄✨\n"
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
    printf "   %s test-patch 654b33ada4ab5e926cd9c570196fefa7bec7c1df --debug  # 启用详细调试信息\n" "$0"
    printf "\n"
    printf "${CYAN}3.1 网络超时解决方案 (🆕):${NC}\n"
    printf "   %s download-patch 654b33ada4ab5e926cd9c570196fefa7bec7c1df  # 获取手动下载指南\n" "$0"
    printf "\n"
    printf "${CYAN}4. 提取补丁信息 (任意目录):${NC}\n"
    printf "   %s extract-files 654b33ada4ab5e926cd9c570196fefa7bec7c1df\n" "$0"
    printf "   %s extract-metadata 654b33ada4ab5e926cd9c570196fefa7bec7c1df\n" "$0"
    printf "   %s integrate-metadata  # 将元数据集成到当前补丁\n" "$0"
    printf "   %s auto-refresh        # 生成补丁并自动集成元数据 ✨\n" "$0"
    printf "\n"
    printf "${CYAN}5. 完整补丁制作 (自动查找内核目录):${NC}\n"
    printf "   %s auto-patch 654b33ada4ab5e926cd9c570196fefa7bec7c1df 950-proc-fix-UAF\n" "$0"
    printf "\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}⚠️ 正确的使用顺序 (手动制作补丁):${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  ${YELLOW}1.${NC} %s create-patch <补丁名称> [commit_id]  # 先创建补丁\n" "$0"
    printf "  ${YELLOW}2.${NC} %s extract-files <commit_id>         # 提取文件列表\n" "$0"
    printf "  ${YELLOW}3.${NC} %s extract-metadata <commit_id>      # 提取CVE元数据 🆕\n" "$0"
    printf "  ${YELLOW}4.${NC} %s add-files <文件列表.txt>            # 再添加文件\n" "$0"
    printf "  ${YELLOW}5.${NC} 手动修改内核源码文件 (根据原始补丁内容)\n"
    printf "  ${YELLOW}6.${NC} %s refresh                         # 生成最终补丁\n" "$0"
    printf "     ${CYAN}或${NC} %s auto-refresh                  # 生成补丁并自动集成元数据 ✨\n" "$0"
    printf "\n"
    printf "${CYAN}💡 或者使用自动化命令一步完成:${NC}\n"
    printf "  %s auto-patch <commit_id> <补丁名称>\n" "$0"
    printf "\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${GREEN}🆕 补丁缓存机制 (v5.4.0):${NC}\n"
    printf "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "  💾 ${PURPLE}patch_cache_<commit_id>.patch${NC} - 自动缓存已下载的补丁\n"
    printf "  🚀 ${CYAN}优势${NC}: 同一补丁第二次使用时无需重新下载，大大提升速度\n"
    printf "  🧹 ${CYAN}清理${NC}: 使用 'clean' 命令可以选择性清理缓存文件\n"
    printf "  📏 ${CYAN}空间${NC}: 缓存文件通常只有几KB到几十KB，占用空间很小\n"
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

# 网络连接测试 (新功能)
test_network() {
    printf "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║                    🌐 网络连接测试                                  ║${NC}\n"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
    
    printf "${CYAN}正在测试网络连接到 git.kernel.org...${NC}\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    # 1. DNS解析测试
    printf "\n${YELLOW}1. DNS解析测试:${NC}\n"
    printf "   正在解析 git.kernel.org..."
    if nslookup git.kernel.org > /dev/null 2>&1 || host git.kernel.org > /dev/null 2>&1; then
        printf " ✅ 成功\n"
        local dns_success=true
    else
        printf " ❌ 失败\n"
        local dns_success=false
    fi
    
    # 2. Ping测试
    printf "\n${YELLOW}2. Ping连通性测试:${NC}\n"
    printf "   正在ping git.kernel.org..."
    if ping -c 3 git.kernel.org > /dev/null 2>&1; then
        printf " ✅ 成功\n"
        local ping_success=true
    else
        printf " ❌ 失败\n"
        local ping_success=false
    fi
    
    # 3. HTTP连接测试
    printf "\n${YELLOW}3. HTTP连接测试:${NC}\n"
    printf "   正在连接 ${KERNEL_GIT_URL}..."
    if curl -s --connect-timeout 10 --max-time 15 "${KERNEL_GIT_URL}" > /dev/null 2>&1; then
        printf " ✅ 成功\n"
        local http_success=true
    else
        printf " ❌ 失败\n"
        local http_success=false
    fi
    
    # 4. 补丁下载测试
    printf "\n${YELLOW}4. 补丁下载测试:${NC}\n"
    printf "   测试下载一个已知的补丁..."
    local test_commit="6ba59ff4227927d3a8530fc2973b80e94b54d58f"  # 一个已知存在的commit
    local test_url="${KERNEL_GIT_URL}/patch/?id=${test_commit}"
    if curl -s --connect-timeout 10 --max-time 15 -f "${test_url}" | head -1 | grep -q "^From "; then
        printf " ✅ 成功\n"
        local patch_success=true
    else
        printf " ❌ 失败\n"
        local patch_success=false
    fi
    
    # 总结
    printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf "${PURPLE}📊 测试结果总结:${NC}\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    if [[ "$dns_success" == "true" ]]; then
        printf "  ✅ DNS解析: 正常\n"
    else
        printf "  ❌ DNS解析: 失败\n"
    fi
    
    if [[ "$ping_success" == "true" ]]; then
        printf "  ✅ Ping连通性: 正常\n"
    else
        printf "  ❌ Ping连通性: 失败\n"
    fi
    
    if [[ "$http_success" == "true" ]]; then
        printf "  ✅ HTTP连接: 正常\n"
    else
        printf "  ❌ HTTP连接: 失败\n"
    fi
    
    if [[ "$patch_success" == "true" ]]; then
        printf "  ✅ 补丁下载: 正常\n"
    else
        printf "  ❌ 补丁下载: 失败\n"
    fi
    
    printf "\n"
    
    # 给出建议
    if [[ "$dns_success" == "true" && "$ping_success" == "true" && "$http_success" == "true" && "$patch_success" == "true" ]]; then
        printf "🎉 ${GREEN}网络连接完全正常！可以正常使用所有功能。${NC}\n"
    elif [[ "$dns_success" == "false" ]]; then
        printf "🚨 ${RED}DNS解析失败，请检查网络设置或DNS配置${NC}\n"
        printf "   建议：检查 /etc/resolv.conf 或网络DNS设置\n"
    elif [[ "$ping_success" == "false" ]]; then
        printf "⚠️ ${YELLOW}网络连通性有问题，请检查防火墙或网络连接${NC}\n"
    elif [[ "$http_success" == "false" || "$patch_success" == "false" ]]; then
        printf "⚠️ ${YELLOW}HTTP连接或补丁下载有问题${NC}\n"
        printf "   可能原因：防火墙阻止HTTPS连接、代理设置问题\n"
        printf "   建议：检查防火墙设置或网络代理配置\n"
    fi
    
    printf "\n"
}

# 抓取原始补丁 (到临时目录) - 内部版本，带重试机制
_fetch_patch_internal() {
    local source_input="$1"
    local commit_id_ref="$2" # 传入变量名以接收解析出的commit_id

    local patch_url
    if ! patch_url=$(_resolve_patch_url "$source_input"); then
        log_error "无法解析补丁源: $source_input"
        return 1
    fi
    
    # 从URL或源输入中提取一个唯一标识符用于缓存
    local cache_id
    if [[ "$source_input" =~ ^[a-f0-9]{7,40}$ ]]; then
        cache_id="$source_input"
        # 更新外部变量
        eval "$commit_id_ref=\"$source_input\""
    else
        # 对URL进行哈希处理以获得唯一且合法的文件名
        cache_id=$(echo "$source_input" | sha256sum | awk '{print $1}')
    fi

    local patch_file="$ORIGINAL_PWD/$TEMP_DIR/original_${cache_id}.patch"
    local cache_file="$ORIGINAL_PWD/patch_cache_${cache_id}.patch"
    local max_retries=3
    local retry_count=0

    # 检查缓存文件是否存在
    if [[ -f "$cache_file" && -s "$cache_file" ]]; then
        printf "📦 ${GREEN}发现缓存补丁: $cache_file${NC}\n" >&2
        printf "📋 使用缓存文件，无需重新下载 (文件大小: $(wc -c < "$cache_file") 字节)\n" >&2
        
        cp "$cache_file" "$patch_file"
        
        local extracted_commit
        extracted_commit=$(grep -m 1 -o -E 'From [a-f0-9]{40}' "$patch_file" | awk '{print $2}')
        if [[ -n "$extracted_commit" ]]; then
             eval "$commit_id_ref=\"$extracted_commit\""
        fi

        printf "%s" "$patch_file"
        return 0
    fi
    
    printf "正在下载: %s\n" "$patch_url" >&2
    
    while [[ $retry_count -lt $max_retries ]]; do
        if [[ $retry_count -gt 0 ]]; then
            printf "重试 %d/%d...\n" "$retry_count" "$max_retries" >&2
        fi
        
        local connect_timeout=10
        local max_timeout=30
        
        # AOSP gerrit requires special handling for base64
        if [[ "$patch_url" =~ android\.googlesource\.com ]] && [[ "$patch_url" =~ format=TEXT ]]; then
            log_info "检测到AOSP源，将进行Base64解码..."
            local temp_base64_file
            temp_base64_file=$(mktemp)
            if curl -L -f --connect-timeout $connect_timeout --max-time $max_timeout -s "$patch_url" -o "$temp_base64_file"; then
                # Attempt to decode, but fallback if it fails or isn't base64
                if base64 -d "$temp_base64_file" > "$patch_file" 2>/dev/null; then
                    log_success "Base64解码成功"
                else
                    log_warning "Base64解码失败或不需要，使用原始文本"
                    mv "$temp_base64_file" "$patch_file"
                fi
            else
                rm -f "$temp_base64_file"
            fi
        else
             curl -L -f --connect-timeout $connect_timeout --max-time $max_timeout -s "$patch_url" -o "$patch_file"
        fi

        local curl_exit_code=$?

        if [[ $curl_exit_code -eq 0 ]]; then
            if [[ -s "$patch_file" ]]; then
                if head -1 "$patch_file" | grep -q -E "^From [a-f0-9]{40}"; then
                    printf "✅ 补丁文件验证成功: $(wc -c < "$patch_file") 字节\n" >&2
                    
                    cp "$patch_file" "$cache_file"
                    
                    local extracted_commit
                    extracted_commit=$(grep -m 1 -o -E 'From [a-f0-9]{40}' "$patch_file" | awk '{print $2}')
                    if [[ -n "$extracted_commit" ]]; then
                        eval "$commit_id_ref=\"$extracted_commit\""
                    fi

                    printf "%s" "$patch_file"
                    return 0
                else
                    printf "❌ ${RED}错误: 下载的内容不是有效的补丁文件 (开头非 'From ...')${NC}\n" >&2
                    rm -f "$patch_file"
                    return 1
                fi
            else
                printf "⚠️  警告: 下载的文件为空\n" >&2
            fi
        else
            printf "❌ 下载失败 (curl exit code: %d)\n" "$curl_exit_code" >&2
        fi
        
        ((retry_count++))
        sleep 2
    done
    
    log_error "下载失败: 已重试 %d 次" "$max_retries"
    return 1
}

# 新增: 解析多种补丁源输入并返回可下载的URL
_resolve_patch_url() {
    local input="$1"
    
    if [[ "$input" =~ ^https?:// ]]; then
        if [[ "$input" =~ github\.com/([^/]+)/([^/]+)/commit/([a-f0-9]+) ]]; then
            local owner="${BASH_REMATCH[1]}"
            local repo="${BASH_REMATCH[2]}"
            local hash="${BASH_REMATCH[3]}"
            echo "https://github.com/${owner}/${repo}/commit/${hash}.patch"
        else
            echo "$input"
        fi
        return 0
    fi
    
    local prefix
    prefix=$(echo "$input" | cut -d: -f1)
    local value
    value=$(echo "$input" | cut -d: -f2-)
    
    case "$prefix" in
        kernel)
            echo "${KERNEL_GIT_URL}/patch/?id=${value}"
            return 0
            ;;
        github)
            local owner_repo
            owner_repo=$(echo "$value" | cut -d/ -f1-2)
            local hash
            hash=$(echo "$value" | cut -d/ -f3)
            echo "https://github.com/${owner_repo}/commit/${hash}.patch"
            return 0
            ;;
        aosp)
            local project_path
            project_path=$(echo "$value" | sed 's|/+|/+/|')
            echo "https://android.googlesource.com/${project_path}?format=TEXT"
            return 0
            ;;
        *)
            if [[ "$input" =~ ^[a-f0-9]{7,40}$ ]]; then
                echo "${KERNEL_GIT_URL}/patch/?id=${input}"
                return 0
            fi
            ;;
    esac
    
    log_error "无法识别的补丁源格式: $input" >&2
    return 1
}


# 抓取原始补丁 (到临时目录) - 公开版本，带日志
fetch_patch() {
    local source_input="$1"
    if [[ -z "$source_input" ]]; then
        log_error "请提供 commit ID, URL 或带前缀的源"
        return 1
    fi
    
    log_info "抓取补丁源: $source_input..."
    
    local patch_file
    local commit_id # _fetch_patch_internal会填充这个变量
    if patch_file=$(_fetch_patch_internal "$source_input" "commit_id"); then
        log_success "补丁已下载到: $patch_file"
        log_warning "注意: 临时文件会在脚本结束时自动删除"
        printf "%s" "$patch_file"
        return 0
    else
        log_error "无法下载补丁，请检查源: $source_input"
        return 1
    fi
}

# 保存原始补丁到当前目录 (新功能)
save_patch() {
    local source_input="$1"
    local filename="$2"
    
    if [[ -z "$source_input" ]]; then
        log_error "请提供 commit ID, URL 或带前缀的源"
        return 1
    fi
    
    log_info "保存补丁源 $source_input 到当前目录..."
    
    local patch_file
    local commit_id # _fetch_patch_internal会填充这个变量
    if patch_file=$(_fetch_patch_internal "$source_input" "commit_id"); then
        # 如果没有提供文件名，使用解析出的commit_id或哈希来命名
        if [[ -z "$filename" ]]; then
            if [[ -n "$commit_id" ]]; then
                filename="${commit_id}.patch"
            else
                local source_hash
                source_hash=$(echo "$source_input" | sha256sum | awk '{print $1}')
                filename="${source_hash:0:12}.patch"
            fi
        fi
        
        # 确保文件名以 .patch 结尾
        if [[ ! "$filename" =~ \.patch$ ]]; then
            filename="${filename}.patch"
        fi

        # 复制到目标文件名
        cp "$patch_file" "$filename"
        local file_size
        file_size=$(wc -c < "$filename")
        log_success "原始补丁已保存到: $filename"
        log_info "文件大小: $file_size 字节"
        log_info "文件位置: $(pwd)/$filename"
        return 0
    else
        log_error "无法下载补丁，请检查源: $source_input"
        return 1
    fi
}

# 手动下载补丁助手（解决网络问题）
download_patch_manual() {
    local source_input="$1"
    
    if [[ -z "$source_input" ]]; then
        log_error "请提供 commit ID, URL 或带前缀的源"
        return 1
    fi
    
    local patch_url
    if ! patch_url=$(_resolve_patch_url "$source_input"); then
        log_error "无法解析补丁源: $source_input"
        return 1
    fi

    local cache_id
    if [[ "$source_input" =~ ^[a-f0-9]{7,40}$ ]]; then
        cache_id="$source_input"
    else
        cache_id=$(echo "$source_input" | sha256sum | awk '{print $1}')
    fi
    local cache_file="patch_cache_${cache_id}.patch"
    
    printf "\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    printf "${PURPLE}📥 手动下载补丁助手${NC}\n"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    if [[ -f "$cache_file" && -s "$cache_file" ]]; then
        local file_size
        file_size=$(wc -c < "$cache_file")
        printf "${GREEN}✅ 缓存文件已存在: $cache_file${NC}\n"
        printf "   文件大小: $file_size 字节\n"
        printf "   可以直接使用其他命令了\n"
        return 0
    fi
    
    printf "${YELLOW}🌐 网络下载地址:${NC}\n"
    printf "   $patch_url\n"
    printf "\n"
    printf "${CYAN}💡 解决网络超时的方法:${NC}\n"
    printf "\n"
    printf "${YELLOW}方法 1 - 浏览器下载:${NC}\n"
    printf "   1. 复制上面的URL到浏览器\n"
    printf "   2. 保存文件为: ${GREEN}$cache_file${NC}\n"
    printf "   3. 放在当前目录: $(pwd)\n"
    printf "\n"
    printf "${YELLOW}方法 2 - 使用wget:${NC}\n"
    printf "   wget -O \"$cache_file\" \"$patch_url\"\n"
    printf "\n"
    printf "${YELLOW}方法 3 - 使用curl (宽松设置):${NC}\n"
    printf "   curl -f -L --connect-timeout 30 --max-time 60 -o \"$cache_file\" \"$patch_url\"\n"
    printf "\n"
    printf "${YELLOW}方法 4 - 通过代理 (如果需要):${NC}\n"
    printf "   export http_proxy=http://your-proxy:port\n"
    printf "   export https_proxy=http://your-proxy:port\n"
    printf "   然后重新运行下载命令\n"
    printf "\n"
    printf "${GREEN}📋 下载完成后，文件应该命名为:${NC}\n"
    printf "   ${PURPLE}$cache_file${NC}\n"
    printf "\n"
    printf "${CYAN}✅ 验证下载是否成功:${NC}\n"
    printf "   ls -la $cache_file\n"
    printf "   head -1 $cache_file  # 应该显示 'From ...'\n"
    printf "\n"
    
    return 1
}

# 符号/API 变更预警
analyze_symbol_changes() {
    local patch_file="$1"
    local commit_id="$2"
    shift 2
    local files_to_check=("$@")
    
    log_info "开始分析补丁中的符号..."

    # 从缓存读取
    local cached_symbols
    cached_symbols=$(read_from_cache "$commit_id" "symbols")
    if [[ $? -eq 0 && -n "$cached_symbols" ]]; then
        log_info "从缓存中读取到符号分析结果。"
        # 这里可以根据需要决定是否要重新显示缓存的内容
        return
    fi


    # 从补丁文件中提取所有被修改的行，并从中提取出潜在的符号
    # 正则表达式: 匹配 C 语言中合法的标识符 (函数名, 变量名, 宏等)
    # 排除常见的关键字和纯数字
    local potential_symbols
    potential_symbols=$(grep -E "^\s*[-+]" "$patch_file" | \
        grep -v -E "(\-\-\- a/|\+\+\+ b/)" | \
        grep -o -E "[a-zA-Z_][a-zA-Z0-9_]+" | \
        grep -v -E "^(if|else|for|while|return|switch|case|break|continue|sizeof|typedef|struct|union|enum|const|volatile|static|extern|auto|register|goto|void|char|short|int|long|float|double|signed|unsigned|bool|true|false)$" | \
        sort -u)

    if [[ -z "$potential_symbols" ]]; then
        log_success "未在补丁的修改内容中提取到需要分析的符号。"
        return
    fi

    local missing_symbols=()
    local symbol_count
    symbol_count=$(echo "$potential_symbols" | wc -l)
    
    log_info "从补丁中提取到 $symbol_count 个唯一的潜在符号，开始在代码库中校验..."

    local checked_count=0
    for symbol in $potential_symbols; do
        checked_count=$((checked_count + 1))
        printf "  [%3d/%3d] 校验符号: %-40s ... " "$checked_count" "$symbol_count" "$symbol"
        
        # 在受影响的文件中搜索符号
        local search_result
        # 使用 -l 只输出文件名，加快速度
        # 使用 --include 来只搜索受影响的文件
        search_result=$(grep -l -r -w "$symbol" . --include=\*.{c,h} 2>/dev/null)

        if [[ -z "$search_result" ]]; then
            printf "${RED}❌ 未找到${NC}\n"
            missing_symbols+=("$symbol")
        else
            printf "${GREEN}✅ 存在${NC}\n"
        fi
    done

    # 将所有潜在符号写入缓存，无论它们是否缺失
    if [[ -n "$potential_symbols" ]]; then
        write_to_cache "$commit_id" "symbols" "$potential_symbols"
    fi

    if [[ ${#missing_symbols[@]} -gt 0 ]]; then
        printf "\n"
        printf "${YELLOW}╔══════════════════════════════════════════════════════════════════════╗${NC}\n"
        printf "${YELLOW}║                  🚨 符号/API 变更预警                              ║${NC}\n"
        printf "${YELLOW}╚══════════════════════════════════════════════════════════════════════╝${NC}\n"
        printf "${CYAN}检测到补丁中的以下符号在当前代码库中不存在。${NC}\n"
        printf "${CYAN}这极有可能意味着这些函数/宏/变量已经被重命名或移除，将导致补丁应用失败。${NC}\n\n"
        
        printf "  ${RED}可疑的缺失符号列表:${NC}\n"
        for symbol in "${missing_symbols[@]}"; do
            printf "    - %s\n" "$symbol"
        done
        
        printf "\n"
        printf "${YELLOW}💡 建议操作:${NC}\n"
        printf "  1. 确认这些符号是否在您的内核版本中已经被重命名 (例如，从 a_func -> b_func)。\n"
        printf "  2. 如果是，您需要手动修改补丁文件，将旧的符号名称替换为新的名称。\n"
        printf "  3. 如果这些符号相关的功能已被移除或重构，您可能需要进行更复杂的代码移植。\n"
        printf "  4. 这个检查可能存在误报，请结合上下文自行判断。\n"
        printf "────────────────────────────────────────────────────────────────────────────\n"
    else
        printf "\n"
        log_success "所有提取的符号都在代码库中被找到，无明显API变更风险。"
    fi
}

# 🆕 测试补丁兼容性和冲突检测
test_patch_compatibility() {
    local input="$1"
    local debug_flag="$2"
    
    if [[ "$debug_flag" == "--debug" ]]; then
        DEBUG_MODE=true
        log_debug "启用调试模式"
    fi
    
    if [[ -z "$input" ]]; then
        log_error "请提供 commit ID, URL, 带前缀的源, 或本地补丁文件路径"
        return 1
    fi
    
    local commit_id=""
    local patch_file=""
    local source_for_fetch="$input"

    if [[ -f "$input" ]]; then
        patch_file=$(realpath "$input")
        log_info "使用本地补丁文件: $patch_file"
        source_for_fetch="" 
        
        local extracted_commit
        extracted_commit=$(grep -m 1 -o -E 'From [a-f0-9]{40}' "$patch_file" | awk '{print $2}')
        if [[ -n "$extracted_commit" ]]; then
            commit_id="$extracted_commit"
            log_info "从补丁文件中提取到 commit ID: $commit_id"
        else
            commit_id=$(basename "$patch_file" .patch)
        fi
    else
        log_info "使用远程补丁源: $input"
    fi
    
    printf "${BLUE}╔══════════════════════════════════════════════════════════════════════╗${NC}\n"
    printf "${BLUE}║            🔍 智能补丁兼容性检测 + 文件冲突分析                      ║${NC}\n"
    printf "${BLUE}╚══════════════════════════════════════════════════════════════════════╝${NC}\n"
    printf "\n"
    
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    if [[ -z "$source_for_fetch" ]]; then
        log_info "📁 步骤 1/6: 使用本地补丁文件..."
    else
        log_info "📥 步骤 1/6: 下载原始补丁..."
    fi
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    if [[ -n "$source_for_fetch" ]]; then
        if patch_file=$(_fetch_patch_internal "$source_for_fetch" "commit_id"); then
            log_success "补丁已下载: $patch_file"
            log_info "解析出的 Commit ID: ${commit_id:- (未找到)}"
        else
            log_error "无法下载补丁，请检查源: $source_for_fetch"
            return 1
        fi
    else
        log_success "使用本地补丁: $patch_file"
    fi
    
    if [[ -z "$commit_id" ]]; then
        log_warning "无法确定唯一的Commit ID，冲突报告和缓存功能可能受影响"
        commit_id=$(basename "$patch_file" .patch | cut -c 1-12)
    fi
    
    # 步骤2: 检查内核目录
    printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "📂 步骤 2/6: 检查内核目录..."
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    if ! find_kernel_source; then
        log_error "无法找到内核源码目录"
        return 1
    fi
    
    # 步骤3: 分析补丁涉及的文件
    printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "🔍 步骤 3/6: 分析补丁文件..."
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
    log_info "📋 步骤 4/6: 检查文件存在性..."
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
    
    # 检查受影响的文件是否被现有补丁修改过（优化版本）
    local conflicted_files=()
    local file_patch_map=()
    
    log_info "检查 ${#existing_files[@]} 个文件是否与已应用补丁冲突..."
    
    # 优化：只调用一次获取所有已应用的补丁
    local applied_patches=()
    while IFS= read -r applied_patch; do
        if [[ -n "$applied_patch" ]]; then
            applied_patches+=("$applied_patch")
        fi
    done < <(quilt applied 2>/dev/null)
    
    if [[ ${#applied_patches[@]} -gt 0 ]]; then
        printf "正在检查 ${#applied_patches[@]} 个已应用补丁的文件冲突...\n"
    fi
    
    # 调试信息
    log_debug "Bash版本: $BASH_VERSION"
    log_debug "已应用补丁数量: ${#applied_patches[@]}"
    
    if [[ ${#applied_patches[@]} -eq 0 ]]; then
        log_debug "没有已应用的补丁，跳过冲突检查"
        printf "\n${GREEN}✅ 无文件冲突检测到${NC}\n"
        printf "没有已应用的补丁，所有文件都无冲突。\n"
        conflicted_files=()
    else
        log_debug "开始声明关联数组..."
        
        # 构建文件到补丁的映射关系（关联数组）
        declare -A file_to_patches_map
        log_debug "关联数组声明成功"
        
        local processed_patches=0
        log_debug "开始处理补丁列表..."
        log_debug "第一个补丁: ${applied_patches[0]}"
        log_debug "进入for循环..."
        
        # 添加错误陷阱
        set +e  # 临时禁用自动退出
        
        # 🔒 安全优先：检查所有补丁以确保100%准确性
        printf "🔍 执行完整冲突检查 (安全第一，必须检查所有补丁)...\n"
        
        for patch in "${applied_patches[@]}"; do
            ((processed_patches++))
            
            # 显示进度条 (每25个补丁更新一次)
            if [[ $((processed_patches % 25)) -eq 0 ]] || [[ $processed_patches -eq ${#applied_patches[@]} ]]; then
                local percentage=$(( processed_patches * 100 / ${#applied_patches[@]} ))
                printf "\r🔍 完整检查: %d/%d (%d%%)" "$processed_patches" "${#applied_patches[@]}" "$percentage"
                if [[ $processed_patches -eq ${#applied_patches[@]} ]]; then
                    printf " ✅\n"
                fi
            fi
            
            # 优化的文件处理
            local files_list
            if files_list=$(quilt files "$patch" 2>/dev/null); then
                while IFS= read -r modified_file; do
                    if [[ -n "$modified_file" ]]; then
                        # 将补丁添加到文件的补丁列表中
                        if [[ -n "${file_to_patches_map[$modified_file]}" ]]; then
                            file_to_patches_map[$modified_file]+=" $patch"
                        else
                            file_to_patches_map[$modified_file]="$patch"
                        fi
                    fi
                done <<< "$files_list"
            fi
        done
        
        set -e  # 重新启用自动退出
        log_debug "for循环完成"
        
        printf "\n🔍 映射表构建完成，正在检查文件冲突...\n"
        
        # 检查每个受影响的文件
        for file in "${existing_files[@]}"; do
            if [[ -n "${file_to_patches_map[$file]}" ]]; then
                # 将空格分隔的补丁字符串转换为数组
                local patches_modifying_file
                IFS=' ' read -ra patches_modifying_file <<< "${file_to_patches_map[$file]}"
                
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
        printf "  🔍 检查模式: 完整检查 (已检查所有 ${#applied_patches[@]} 个补丁)\n"
        
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
    fi  # 结束 if [[ ${#applied_patches[@]} -eq 0 ]] 分支

    # 步骤 5.5: 符号/API 变更预警
    printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "🔬 步骤 5.5/6: 符号/API 变更预警..."
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    analyze_symbol_changes "$patch_file" "$commit_id" "${existing_files[@]}"

    # 步骤6: 尝试应用补丁 (dry-run)
    printf "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    log_info "🧪 步骤 6/6: 干运行补丁测试..."
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    # 保存应用测试结果
    local patch_test_output
    local patch_test_result=0
    
    # 使用 patch 命令进行 dry-run 测试 (非交互式，获取详细输出)
    printf "正在执行 patch 干运行测试...\n"
    patch_test_output=$(patch --dry-run -p1 --verbose --force --no-backup-if-mismatch < "$patch_file" 2>&1) || patch_test_result=$?
    
    # 如果初始尝试失败，启动智能模糊匹配重试
    if [[ $patch_test_result -ne 0 ]]; then
        printf "❌ ${RED}patch 干运行测试: 失败 (退出码: $patch_test_result)${NC}\n"
        log_info "💡 启动智能模糊匹配 (-F) 重试..."
        
        for fuzz_level in {1..3}; do
            printf "\n${CYAN}尝试模糊度 -F$fuzz_level...${NC}\n"
            local temp_output
            patch_test_output=$(patch --dry-run -p1 --verbose --force --no-backup-if-mismatch -F$fuzz_level < "$patch_file" 2>&1) || patch_test_result=$?
            
            if [[ $patch_test_result -eq 0 ]]; then
                printf "✅ ${GREEN}模糊匹配成功 (使用 -F$fuzz_level)!${NC}\n"
                # 在输出中添加一个明确的提示，告知用户这是通过模糊匹配成功的
                patch_test_output+=$'\n\n[INFO] Patch applied successfully with fuzz factor '"$fuzz_level"
                break # 成功，跳出循环
            else
                printf "❌ ${YELLOW}使用 -F$fuzz_level 仍然失败 (退出码: $patch_test_result)${NC}\n"
            fi
        done
    fi

    # 显示最终的patch测试结果
    if [[ $patch_test_result -eq 0 ]]; then
        printf "✅ ${GREEN}patch 干运行测试: 成功${NC}\n"
        log_debug "patch命令输出: $patch_test_output"
    else
        printf "❌ ${RED}patch 干运行测试: 最终失败 (退出码: $patch_test_result)${NC}\n"
        log_debug "patch命令详细输出: $patch_test_output"
    fi
    
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
            printf "\n${GREEN}✅ 补丁应用测试: 通过${NC}\n"
            printf "   • 所有文件都能成功应用补丁\n"
            printf "   • 没有代码级冲突\n"
            printf "\n${GREEN}💡 建议: 可以安全地应用此补丁${NC}\n"
            printf "   • 无文件冲突，可以安全应用\n"
            printf "   • 使用 auto-patch 命令自动创建 OpenWrt 补丁\n"
            printf "   • 或按照手动流程逐步创建补丁\n"
        else
            printf "⚠️ ${YELLOW}结果: 补丁技术兼容但有文件冲突${NC}\n"
            printf "\n${GREEN}✅ 补丁应用测试: 通过${NC}\n"
            printf "   • 补丁本身可以成功应用\n"
            printf "   • 但部分文件已被其他补丁修改\n"
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
        if [[ ${#conflicted_files[@]} -eq 0 ]]; then
            printf "⚠️ ${YELLOW}结果: 补丁代码级冲突 - 需要手动解决${NC}\n"
            printf "\n${CYAN}📋 冲突类型分析:${NC}\n"
            printf "  ✅ 文件级冲突: 无 (文件未被其他补丁修改)\n"
            printf "  ❌ 代码级冲突: 有 (补丁无法直接应用到当前代码)\n"
            printf "\n"
            analyze_conflict_locations "$patch_test_output" "$patch_file" "${affected_files[@]}"
        else
            printf "⚠️ ${YELLOW}结果: 补丁多重冲突 - 需要手动解决${NC}\n"
            printf "\n${CYAN}📋 冲突类型分析:${NC}\n"
            printf "  ❌ 文件级冲突: 有 (%d个文件被其他补丁修改)\n" "${#conflicted_files[@]}"
            printf "  ❌ 代码级冲突: 有 (补丁无法直接应用到当前代码)\n"
            printf "\n"
            analyze_conflict_locations "$patch_test_output" "$patch_file" "${affected_files[@]}"
        fi
        
        # 🆕 生成详细冲突报告文件
        local conflict_report_file="$ORIGINAL_PWD/conflict_report_${commit_id}_$(date +%Y%m%d_%H%M%S).md"
        log_info "📄 正在生成详细冲突报告..."
        generate_conflict_report "$commit_id" "$patch_file" "$patch_test_output" "$conflict_report_file" "${affected_files[@]}"
        
        if [[ ${#conflicted_files[@]} -eq 0 ]]; then
            printf "\n${YELLOW}💡 代码级冲突解决建议:${NC}\n"
            printf "   • 检查代码上下文是否发生变化 (行号、函数名等)\n"
            printf "   • 可能需要调整补丁的上下文行\n"
            printf "   • 考虑手动编辑补丁文件以适配当前代码\n"
            printf "   • 或者手动应用补丁中的修改逻辑\n"
            printf "   • 📄 查看详细冲突报告: ${PURPLE}$conflict_report_file${NC}\n"
        else
            printf "\n${YELLOW}💡 多重冲突解决建议:${NC}\n"
            printf "   • 首先解决文件级冲突 (检查其他补丁的修改)\n"
            printf "   • 然后处理代码级冲突 (调整补丁内容)\n"
            printf "   • 可能需要将补丁拆分或合并现有修改\n"
            printf "   • 建议在专门的分支中进行冲突解决\n"
            printf "   • 📄 查看详细冲突报告: ${PURPLE}$conflict_report_file${NC}\n"
        fi
        printf "\n${RED}🛑 警告: 不要直接应用此补丁，会导致代码损坏${NC}\n"
        printf "\n"
        return 1  # 有冲突退出码
    fi
}


# 🆕 为报告文件生成冲突分析 (增强版)
generate_conflict_analysis_for_report() {
    local patch_test_output="$1"
    local report_file="$2"
    shift 2
    local affected_files=("$@")
    
    # 解析所有冲突信息
    declare -a conflicts
    declare -A file_mapping
    declare -A conflicted_files_set
    local current_parsing_file=""
    
    # 建立文件映射
    for file in "${affected_files[@]}"; do
        local basename_file=$(basename "$file")
        file_mapping["$basename_file"]="$file"
        file_mapping["$file"]="$file"
    done
    
    while IFS= read -r line; do
        # 检测文件名
        if [[ "$line" =~ patching[[:space:]]+file[[:space:]]+(.+)$ ]] || [[ "$line" =~ patching[[:space:]]+(.+)$ ]]; then
            local file_from_output="${BASH_REMATCH[1]}"
            
            # 尝试映射到实际文件
            if [[ -n "${file_mapping[$file_from_output]}" ]]; then
                current_parsing_file="${file_mapping[$file_from_output]}"
            else
                # 尝试basename匹配
                local found_match=""
                for mapped_file in "${affected_files[@]}"; do
                    if [[ "$(basename "$mapped_file")" == "$(basename "$file_from_output")" ]]; then
                        found_match="$mapped_file"
                        break
                    fi
                done
                current_parsing_file="${found_match:-$file_from_output}"
            fi
            
        # 检测Hunk失败
        elif [[ "$line" =~ Hunk[[:space:]]*#?[0-9]*[[:space:]]*FAILED[[:space:]]+at[[:space:]]+([0-9]+) ]]; then
            local failed_line="${BASH_REMATCH[1]}"
            
            # 如果没有明确的文件，智能分配
            if [[ -z "$current_parsing_file" ]] && [[ ${#affected_files[@]} -gt 0 ]]; then
                current_parsing_file="${affected_files[$((file_index % ${#affected_files[@]}))]}"
                ((file_index++))
            fi
            
            # 记录冲突信息
            conflicts+=("$current_parsing_file:$failed_line")
            conflicted_files_set["$current_parsing_file"]=1
        fi
    done <<< "$patch_test_output"
    
    # 第二阶段：生成报告内容
    local conflicted_files_count=${#conflicted_files_set[@]}
    if [[ $conflicted_files_count -gt 0 ]]; then
        echo "### 📊 冲突统计" >> "$report_file"
        echo "" >> "$report_file"
        echo "- **冲突文件数量**: $conflicted_files_count 个" >> "$report_file"
        echo "- **总冲突位置**: ${#conflicts[@]} 处" >> "$report_file"
        echo "" >> "$report_file"
        echo "**涉及文件**:" >> "$report_file"
        for file in "${!conflicted_files_set[@]}"; do
            echo "- \`$(basename "$file")\`" >> "$report_file"
        done
        echo "" >> "$report_file"
    fi
    
    # 第三阶段：按文件分组显示冲突详情
    declare -A displayed_files
    local conflict_found=false
    
    for conflict_info in "${conflicts[@]}"; do
        IFS=':' read -r conflict_file conflict_line <<< "$conflict_info"
        
        # 每个文件只显示一次文件头
        if [[ -z "${displayed_files[$conflict_file]}" ]]; then
            echo "### 📄 文件: \`$conflict_file\`" >> "$report_file"
            echo "" >> "$report_file"
            displayed_files["$conflict_file"]=1
        fi
        
        echo "**❌ 冲突位置**: 第 $conflict_line 行附近" >> "$report_file"
        echo "" >> "$report_file"
        conflict_found=true
        
        # 显示代码内容
        if [[ -f "$conflict_file" ]]; then
            echo "**📖 现有代码内容**:" >> "$report_file"
            echo '```c' >> "$report_file"
            local start_line=$(( conflict_line - 3 ))
            local end_line=$(( conflict_line + 7 ))
            
            if [[ $start_line -lt 1 ]]; then
                start_line=1
            fi
            
            local line_counter=$start_line
            while IFS= read -r code_line; do
                if [[ $line_counter -eq $conflict_line ]]; then
                    echo "→ $line_counter: $code_line    ⟸ 冲突行" >> "$report_file"
                else
                    echo "  $line_counter: $code_line" >> "$report_file"
                fi
                ((line_counter++))
            done < <(sed -n "${start_line},${end_line}p" "$conflict_file" 2>/dev/null)
            echo '```' >> "$report_file"
        else
            echo "**❌ 文件不存在**: \`$conflict_file\`" >> "$report_file"
            
            # 尝试查找相似文件
            echo "" >> "$report_file"
            echo "**🔍 查找相似文件**:" >> "$report_file"
            local found_alternative=false
            for file in "${affected_files[@]}"; do
                if [[ "$(basename "$file")" == "$(basename "$conflict_file")" ]] && [[ -f "$file" ]]; then
                    echo "- 找到替代文件: \`$file\`" >> "$report_file"
                    echo "" >> "$report_file"
                    echo "**📖 替代文件代码内容**:" >> "$report_file"
                    echo '```c' >> "$report_file"
                    local start_line=$(( conflict_line - 3 ))
                    local end_line=$(( conflict_line + 7 ))
                    
                    if [[ $start_line -lt 1 ]]; then
                        start_line=1
                    fi
                    
                    local line_counter=$start_line
                    while IFS= read -r code_line; do
                        if [[ $line_counter -eq $conflict_line ]]; then
                            echo "→ $line_counter: $code_line    ⟸ 冲突行" >> "$report_file"
                        else
                            echo "  $line_counter: $code_line" >> "$report_file"
                        fi
                        ((line_counter++))
                    done < <(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null)
                    echo '```' >> "$report_file"
                    found_alternative=true
                    break
                fi
            done
            
            if [[ "$found_alternative" == "false" ]]; then
                echo "- **未找到对应的源文件**" >> "$report_file"
            fi
        fi
        echo "" >> "$report_file"
    done
    
    # 如果没有找到冲突，显示诊断信息
    if [[ "$conflict_found" == "false" ]] && [[ ${#conflicts[@]} -eq 0 ]]; then
        echo "### ❌ 解析失败" >> "$report_file"
        echo "" >> "$report_file"
        echo "未能解析出具体冲突位置，可能原因：" >> "$report_file"
        echo "- patch输出格式不符合预期" >> "$report_file"
        echo "- 文件路径映射失败" >> "$report_file"
        echo "- 内核版本差异过大" >> "$report_file"
        echo "" >> "$report_file"
        echo "**原始patch输出（前30行）**:" >> "$report_file"
        echo '```' >> "$report_file"
        echo "$patch_test_output" | head -30 >> "$report_file"
        echo '```' >> "$report_file"
    fi
    
    # 添加调试信息到报告
    echo "" >> "$report_file"
    echo "### 🔍 调试信息" >> "$report_file"
    echo "" >> "$report_file"
    echo "- **受影响文件数量**: ${#affected_files[@]}" >> "$report_file"
    echo "- **实际冲突文件数量**: $conflicted_files_count" >> "$report_file"
    echo "- **总冲突位置数量**: ${#conflicts[@]}" >> "$report_file"
    echo "" >> "$report_file"
    echo "**受影响文件列表**:" >> "$report_file"
    for file in "${affected_files[@]}"; do
        echo "- \`$file\`" >> "$report_file"
    done
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
    
    # 添加冲突位置分析
    cat >> "$report_file" << EOF

## 🔍 详细冲突分析

### 冲突位置和现有代码

EOF

    # 生成冲突位置信息（类似 analyze_conflict_locations 但输出到文件）
    generate_conflict_analysis_for_report "$patch_test_output" "$report_file" "${affected_files[@]}"
    
    cat >> "$report_file" << EOF

### 原始 patch 命令输出

\`\`\`
$patch_test_output
\`\`\`

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
        local file_list_content
        file_list_content=$(cat "$PATCH_LIST_FILE" | sed 's/^/  📄 /')
        echo "$file_list_content"

        # 写入缓存
        write_to_cache "$commit_id" "files" "$(cat $PATCH_LIST_FILE)"
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
    
    # 🔧 修复：一次性检查 quilt 环境，避免每次循环都检查
    if ! quilt series >/dev/null 2>&1; then
        log_error "请先创建 quilt 补丁，使用: quilt new <patch_name>"
        return 1
    fi
    
    log_info "添加文件到当前 quilt 补丁..."
    
    # 显示要处理的文件数量
    local total_files=$(wc -l < "$file_list")
    printf "📋 准备处理 $total_files 个文件...\n"
    
    debug_print "使用文件列表: $file_list"
    debug_print "文件总数: $total_files"
    
    local added_count=0
    local failed_count=0
    local skipped_count=0
    
    local file_count=0
    
    while IFS= read -r file; do
        # 跳过空行和注释
        if [[ -z "$file" ]] || [[ "$file" =~ ^[[:space:]]*# ]]; then
            debug_print "跳过空行或注释: '$file'"
            continue
        fi
        
        file_count=$((file_count + 1))
        printf "  [$file_count/$total_files] $file ... "
        
        debug_print "处理文件 $file_count/$total_files: $file"
        
        # 尝试添加文件到补丁
        if quilt add "$file" >/dev/null 2>&1; then
            printf "${GREEN}✅ 已添加${NC}\n"
            added_count=$((added_count + 1))
            debug_print "成功添加: $file"
        else
            printf "${YELLOW}⚠️  已存在${NC}\n"  
            skipped_count=$((skipped_count + 1))
            debug_print "文件已存在，跳过: $file"
        fi
    done < "$file_list"
    
    printf "\n"
    log_success "文件添加完成！"
    printf "📊 统计结果: ${GREEN}成功 $added_count 个${NC}, ${YELLOW}跳过 $skipped_count 个${NC}, ${RED}失败 $failed_count 个${NC}\n"
    return 0
}

# 提取补丁元数据
extract_metadata() {
    local source_input="$1"
    if [[ -z "$source_input" ]]; then
        log_error "请提供 commit ID, URL 或带前缀的源"
        return 1
    fi
    
    log_info "提取补丁源 $source_input 的元数据..."
    
    local patch_file
    local commit_id
    if patch_file=$(_fetch_patch_internal "$source_input" "commit_id"); then
        log_success "补丁已下载到: $patch_file"
    else
        log_error "无法下载补丁，请检查源: $source_input"
        return 1
    fi
    
    if [[ ! -f "$patch_file" ]]; then
        log_error "补丁文件不存在: $patch_file"
        return 1
    fi
    
    # ... (元数据提取逻辑保持不变)
    {
        grep "^From: " "$patch_file" | head -1
        grep "^Date: " "$patch_file" | head -1
        grep "^Subject: " "$patch_file" | head -1
        echo ""
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
                echo "$line"
            fi
        done < "$patch_file"
        echo ""
        grep -E "^(Signed-off-by|Cc|Fixes|Reported-by|Tested-by|Acked-by|Reviewed-by): " "$patch_file" 2>/dev/null
        
    } > "$PATCH_METADATA_FILE"

    log_success "元数据已保存到: $PATCH_METADATA_FILE"
    log_info "元数据文件已保存到当前目录，不会被自动删除"
    printf "\n"
    printf "元数据预览:\n"
    head -30 "$PATCH_METADATA_FILE" | sed 's/^/  /'
    
    # 写入缓存
    local metadata_content
    metadata_content=$(cat "$PATCH_METADATA_FILE")
    write_to_cache "$commit_id" "metadata" "$metadata_content"

    local fixes_content
    fixes_content=$(grep "^Fixes: " "$PATCH_METADATA_FILE")
    if [[ -n "$fixes_content" ]]; then
        write_to_cache "$commit_id" "fixes" "$fixes_content"
    fi

    # 智能依赖提醒
    if [[ -n "$fixes_content" ]]; then
        printf "\n"
        printf "${YELLOW}╔══════════════════════════════════════════════════════════════════════╗${NC}\n"
        printf "${YELLOW}║            ⚠️  智能依赖提醒 (SVN 环境)                             ║${NC}\n"
        printf "${YELLOW}╚══════════════════════════════════════════════════════════════════════╝${NC}\n"
        printf "${CYAN}检测到此补丁包含 'Fixes:' 标签，表明它依赖于另一个提交。${NC}\n"
        printf "${CYAN}在SVN管理的环境中，无法自动检查此依赖，请您手动关注：${NC}\n\n"
        
        # 提取并显示所有 Fixes 标签
        echo "$fixes_content" | while IFS= read -r line; do
            local fixes_commit
            fixes_commit=$(echo "$line" | awk '{print $2}')
            local fixes_summary
            fixes_summary=$(echo "$line" | cut -d' ' -f3-)
            printf "  - **依赖Commit**: ${PURPLE}%s${NC}\n" "$fixes_commit"
            printf "    **Commit主题**: %s\n" "$fixes_summary"
        done
        
        printf "\n"
        printf "${YELLOW}💡 建议操作:${NC}\n"
        printf "  1. 检查依赖的Commit对应的补丁是否已经在本分支中应用。\n"
        printf "  2. 如果没有，您可能需要先移植并应用依赖的补丁。\n"
        printf "  3. 使用 '${TOOL_NAME} save <commit_id>' 下载依赖的补丁进行分析。\n"
        printf "────────────────────────────────────────────────────────────────────────────\n"
    fi
    
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
        
        # 如果提供了 commit_id，提示用户使用 add-files 命令
        if [[ -n "$commit_id" ]]; then
            printf "${YELLOW}💡 提示: 如需添加 commit $commit_id 的相关文件，请执行:${NC}\n"
            printf "  ${CYAN}1. $0 extract-files $commit_id${NC}  # 先提取文件列表\n"
            printf "  ${CYAN}2. $0 add-files patch_files.txt${NC}  # 再添加文件到补丁\n"
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
        "patch_cache_*.patch"
        "conflict_report_*.md"
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
    
    # 单独处理缓存文件
    local cache_files=()
    while IFS= read -r -d '' file; do
        cache_files+=("$file")
    done < <(find . -maxdepth 1 -name "patch_cache_*.patch" -type f -print0 2>/dev/null)
    
    if [[ ${#cache_files[@]} -gt 0 ]]; then
        printf "\n"
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        log_info "💾 发现补丁缓存文件："
        printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        
        for file in "${cache_files[@]}"; do
            local file_size=$(wc -c < "$file" 2>/dev/null || echo "0")
            printf "  💾 $file ($(( file_size / 1024 )) KB)\n"
        done
        printf "\n"
        
        printf "${YELLOW}是否要清理补丁缓存? (y/N): ${NC}"
        printf "${CYAN}注意: 清理后下次下载同样的补丁会重新从网络获取${NC}\n"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            for file in "${cache_files[@]}"; do
                rm -f "$file"
                log_info "已删除缓存: $file"
            done
            log_success "✅ 已清理补丁缓存文件"
        else
            log_info "保留补丁缓存文件，下次下载相同补丁会更快"
        fi
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

# auto refresh - 生成补丁并自动集成元数据
auto_refresh() {
    local patch_name="$1"
    
    log_info "🔄 自动刷新补丁 (生成补丁并集成元数据)："
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
        
        # 执行refresh并捕获输出
        local refresh_output
        refresh_output=$(quilt refresh 2>&1)
        local refresh_status=$?
        
        if [[ $refresh_status -eq 0 ]]; then
            log_success "✅ 补丁刷新成功"
            
            # 显示refresh结果
            if echo "$refresh_output" | grep -q "unchanged"; then
                log_info "📋 补丁内容无变化"
            else
                log_info "📋 补丁内容已更新"
            fi
            
            # 🔧 检查并集成元数据（不管内容是否变化）
            local metadata_file="$ORIGINAL_PWD/$PATCH_METADATA_FILE"
            debug_print "检查元数据文件: $metadata_file"
            debug_print "ORIGINAL_PWD: $ORIGINAL_PWD"
            debug_print "PATCH_METADATA_FILE: $PATCH_METADATA_FILE"
            debug_print "当前工作目录: $(pwd)"
            
            if [[ -f "$metadata_file" ]] && [[ -f "$current_patch" ]]; then
                # 检查补丁是否已经包含元数据 (通过检查是否有 # From: 行)
                if grep -q "^# From: " "$current_patch" 2>/dev/null; then
                    log_info "📋 补丁已包含元数据，跳过集成"
                else
                    log_info "📋 发现元数据文件，正在集成到补丁中..."
                    debug_print "元数据文件路径: $metadata_file"
                    debug_print "补丁文件路径: $current_patch"
                    
                    # 备份原始补丁
                    cp "$current_patch" "${current_patch}.backup"
                    
                    # 创建带元数据的新补丁文件
                    {
                        # 添加元数据内容作为注释
                        while IFS= read -r line; do
                            if [[ -n "$line" ]]; then
                                echo "# $line"
                            else
                                echo "#"
                            fi
                        done < "$metadata_file"
                        
                        echo ""
                        
                        # 添加原始补丁内容
                        cat "${current_patch}.backup"
                        
                    } > "$current_patch"
                    
                    log_success "✅ 元数据已集成到补丁文件中"
                    rm -f "${current_patch}.backup"
                fi
            else
                log_warning "📋 未找到元数据文件 ($PATCH_METADATA_FILE)，跳过元数据集成"
                log_info "💡 提示: 可先运行 'extract-metadata <commit_id>' 提取元数据"
            fi
            
            # 显示补丁信息
            if [[ -f "$current_patch" ]]; then
                local patch_size=$(wc -c < "$current_patch" 2>/dev/null || echo "未知")
                local patch_lines=$(wc -l < "$current_patch" 2>/dev/null || echo "未知")
                log_info "📄 补丁文件: $current_patch"
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
        log_info "提示: 请先修改代码文件，然后再执行 auto-refresh"
    fi
    
    printf "\n"
}

# quilt delete - 删除补丁文件
delete_patch() {
    local patch_name="$1"
    
    if [[ -z "$patch_name" ]]; then
        log_error "请提供要删除的补丁名称"
        log_info "用法: $0 delete <patch_name>"
        return 1
    fi
    
    # 确保补丁名称以 .patch 结尾
    if [[ ! "$patch_name" =~ \.patch$ ]]; then
        patch_name="${patch_name}.patch"
    fi
    
    log_info "🗑️ 删除补丁: $patch_name"
    printf "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    
    # 检查补丁是否存在
    if [[ ! -f "patches/$patch_name" ]]; then
        log_error "补丁文件不存在: patches/$patch_name"
        return 1
    fi
    
    # 检查补丁是否已应用
    local current_patch=$(quilt top 2>/dev/null)
    if [[ "$current_patch" == "patches/$patch_name" ]]; then
        log_error "补丁 $patch_name 当前是顶部补丁（已应用状态）"
        log_info "请先使用 'pop' 命令移除该补丁，然后再删除"
        return 1
    fi
    
    # 检查补丁是否在已应用列表中
    if quilt applied 2>/dev/null | grep -q "^patches/$patch_name$"; then
        log_error "补丁 $patch_name 已被应用"
        log_info "请先使用 'pop' 命令移除该补丁及其上层补丁，然后再删除"
        return 1
    fi
    
    # 确认删除
    log_warning "⚠️ 警告：此操作将永久删除补丁文件，无法撤销！"
    printf "是否确认删除补丁 ${YELLOW}$patch_name${NC}？ (y/N): "
    read -r confirmation
    
    case "$confirmation" in
        [yY]|[yY][eE][sS])
            # 执行删除
            if quilt delete "$patch_name"; then
                log_success "✅ 补丁 $patch_name 已从 quilt 系列中移除"
                
                # 询问是否也删除物理文件
                printf "是否也删除物理文件 ${YELLOW}patches/$patch_name${NC}？ (y/N): "
                read -r delete_file_confirmation
                
                case "$delete_file_confirmation" in
                    [yY]|[yY][eE][sS])
                        if rm -f "patches/$patch_name"; then
                            log_success "✅ 补丁文件 patches/$patch_name 也已删除"
                        else
                            log_warning "⚠️ 补丁文件删除失败，但已从 quilt 系列中移除"
                        fi
                        ;;
                    *)
                        log_info "📄 补丁文件 patches/$patch_name 已保留"
                        ;;
                esac
                
                # 显示剩余补丁信息
                local total_patches=$(quilt series 2>/dev/null | wc -l)
                local applied_patches=$(quilt applied 2>/dev/null | wc -l)
                local unapplied_patches=$((total_patches - applied_patches))
                
                log_info "📊 补丁统计："
                log_info "  - 总补丁数: $total_patches"
                log_info "  - 已应用: $applied_patches"
                log_info "  - 未应用: $unapplied_patches"
            else
                log_error "❌ 补丁删除失败"
                return 1
            fi
            ;;
        *)
            log_info "取消删除操作"
            return 0
            ;;
    esac
    
    printf "\n"
}

# 集成元数据到补丁文件
integrate_metadata() {
    local patch_name="$1"
    local metadata_file="$ORIGINAL_PWD/$PATCH_METADATA_FILE"
    
    # 如果没有指定补丁名，使用当前顶部补丁
    if [[ -z "$patch_name" ]]; then
        patch_name=$(quilt top 2>/dev/null)
        if [[ -z "$patch_name" ]]; then
            log_error "没有顶部补丁，请指定补丁名称或先创建补丁"
            return 1
        fi
    fi
    
    # 检查补丁文件是否存在
    if [[ ! -f "patches/$patch_name" ]]; then
        log_error "补丁文件不存在: patches/$patch_name"
        return 1
    fi
    
    # 检查元数据文件是否存在
    if [[ ! -f "$metadata_file" ]]; then
        log_error "元数据文件不存在: $metadata_file"
        log_info "请先使用 'extract-metadata <commit_id>' 命令生成元数据"
        return 1
    fi
    
    log_info "🔗 正在将元数据集成到补丁: $patch_name"
    
    # 检查补丁是否已经包含元数据 (通过检查是否有 # From: 行)
    if grep -q "^# From: " "patches/$patch_name" 2>/dev/null; then
        log_warning "补丁已包含元数据，跳过集成"
        return 0
    fi
    
    # 备份原始补丁
    cp "patches/$patch_name" "patches/${patch_name}.backup"
    
    # 创建带元数据的新补丁文件
    {
        # 添加元数据内容作为注释
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                echo "# $line"
            else
                echo "#"
            fi
        done < "$metadata_file"
        
        echo ""
        
        # 添加原始补丁内容
        cat "patches/${patch_name}.backup"
        
    } > "patches/$patch_name"
    
    rm -f "patches/${patch_name}.backup"
    
    log_success "✅ 元数据已成功集成到补丁文件中"
    log_info "📄 补丁文件: patches/$patch_name"
    
    # 显示集成的元数据行数
    local metadata_lines=$(grep "^#" "patches/$patch_name" | wc -l)
    log_info "📊 集成了 $metadata_lines 行元数据信息"
    
    return 0
}

# 主函数
main() {
    # 初始化知识库缓存
    init_cache

    # 检查参数
    if [[ $# -eq 0 ]]; then
        print_help
        exit 0
    fi
    
    # 检查调试参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --debug)
                DEBUG_MODE=true
                debug_print "调试模式已启用"
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    
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
        "download-patch")
            download_patch_manual "$1"
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
        "integrate-metadata")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            integrate_metadata "$@"
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
        "test-network")
            test_network
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
        "delete")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            delete_patch "$@"
            ;;
        "refresh")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            quilt_refresh "$@"
            ;;
        "auto-refresh")
            check_dependencies "need_quilt"
            if ! find_kernel_source; then
                exit 1
            fi
            auto_refresh "$@"
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
