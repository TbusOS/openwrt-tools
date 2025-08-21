#!/bin/bash

# Linux内核CVE补丁批量下载工具
# 基于Git提交时间搜索CVE补丁（不限CVE编号年份）
# 支持单月下载和批量月份范围下载

set -e

# 显示使用帮助
show_help() {
    cat << EOF
Linux内核CVE补丁批量下载工具

说明:
    按Git提交时间搜索CVE补丁，不限制CVE编号年份
    例如：下载2025年4月可能包含CVE-2016、CVE-2020等各年份的漏洞补丁

用法:
    $0 [选项] [年份] [开始月份] [结束月份]
    $0 [年份] [单个月份]
    $0 --list-available [年份]
    $0 --help

选项:
    --no-git              跳过Linux内核仓库下载，只从CVE数据库获取信息
    --debug               显示详细的调试信息和CVE筛选过程
    --list-available      查看指定年份各月份提交的CVE补丁分布情况
    --help, -h            显示此帮助信息

参数说明:
    年份        : 4位数年份 - 表示补丁提交时间，非CVE编号年份
    开始月份    : 1-12 (默认: 当前月份)
    结束月份    : 1-12 (可选，如果指定则下载范围内所有月份)

重要概念:
    - CVE-2016-1234 可能在2025年才发布补丁
    - 脚本按补丁提交时间搜索，不按CVE编号年份
    - 2025年4月的下载可能包含各个年份的CVE编号

示例:
    # 查看2025年各月份提交的CVE补丁分布
    $0 --list-available 2025
    
    # 下载2025年4月提交的所有CVE补丁（包含各年份CVE编号）
    $0 2025 04
    
    # 下载2024年1月到6月提交的CVE补丁
    $0 2024 01 06
    
    # 下载2023年全年提交的CVE补丁（跳过Git仓库）
    $0 --no-git 2023 01 12

注意:
    - 建议先使用 --list-available 查看可用的补丁分布
    - 所有文件保存在当前目录的 cve_downloads/ 中
    - 每个月份会创建独立的会话目录
    - 批量下载时会询问是否继续下一个月份
    - 使用 --no-git 可以避免网络问题，但会错过Git仓库中的补丁
    - 使用 --debug 可以查看详细的CVE筛选和搜索过程
EOF
}

# 检查帮助参数
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# 解析选项参数
SKIP_GIT=false
DEBUG_MODE=false
LIST_AVAILABLE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-git)
            SKIP_GIT=true
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --list-available)
            LIST_AVAILABLE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            break  # 遇到非选项参数，停止解析
            ;;
    esac
done

# 配置参数
YEAR=${1:-$(date +%Y)}
START_MONTH=${2:-$(date +%m)}
END_MONTH=${3:-$START_MONTH}

# 如果是查询模式，执行查询功能
if [ "$LIST_AVAILABLE" = true ]; then
    echo "=========================================="
    echo "查询 ${YEAR} 年提交的Linux内核CVE补丁分布"
    echo "=========================================="
    echo "正在搜索 ${YEAR} 年提交的所有CVE补丁（不限CVE编号年份）..."
    echo ""
    
    # 搜索该年份提交的所有CVE补丁（使用Git日志方式，更准确）
    # 先检查是否能访问GitHub API
    test_url="https://api.github.com/repos/torvalds/linux"
    if ! curl -s --head "$test_url" > /dev/null 2>&1; then
        echo "❌ 无法访问GitHub API，请检查网络连接"
        echo ""
        echo "你可以直接尝试常见的月份:"
        echo "./download_monthly_cve.sh --no-git $YEAR 01  # 1月"
        echo "./download_monthly_cve.sh --no-git $YEAR 06  # 6月"  
        echo "./download_monthly_cve.sh --no-git $YEAR 12  # 12月"
        exit 1
    fi
    
    # 使用更广泛的搜索：搜索所有包含"CVE-"的提交
    search_url="https://api.github.com/search/commits?q=repo:torvalds/linux+CVE-+committer-date:${YEAR}-01-01..${YEAR}-12-31&sort=committer-date&per_page=100"
    echo "搜索URL: $search_url"
    echo ""
    
    search_result=$(curl -s "$search_url" 2>/dev/null || echo '{"items":[]}')
    
    if echo "$search_result" | grep -q '"total_count"'; then
        total_commits=$(echo "$search_result" | grep -o '"total_count":[[:space:]]*[0-9]*' | grep -o '[0-9]*')
        
        # 确保total_commits是有效数字
        if [ -z "$total_commits" ]; then
            total_commits=0
        fi
        
        if [ "$total_commits" -gt 0 ]; then
            echo "✅ 找到 $total_commits 个 ${YEAR} 年提交的Linux内核CVE补丁！"
            echo ""
            echo "📊 建议的下载策略:"
            echo ""
            
            # 提供不同的下载建议
            if [ "$total_commits" -le 10 ]; then
                echo "💡 补丁数量较少，建议下载全年："
                echo "./download_monthly_cve.sh --no-git $YEAR 01 12"
                echo ""
                echo "💡 或者逐月尝试（推荐从下半年开始）："
                for month in 12 11 10 09 08 07 06 05 04 03 02 01; do
                    echo "./download_monthly_cve.sh --no-git $YEAR $month"
                done
            elif [ "$total_commits" -le 50 ]; then
                echo "💡 补丁数量适中，建议分季度下载："
                echo "./download_monthly_cve.sh --no-git $YEAR 01 03  # Q1"
                echo "./download_monthly_cve.sh --no-git $YEAR 04 06  # Q2"
                echo "./download_monthly_cve.sh --no-git $YEAR 07 09  # Q3"
                echo "./download_monthly_cve.sh --no-git $YEAR 10 12  # Q4"
                echo ""
                echo "💡 或者下载全年："
                echo "./download_monthly_cve.sh --no-git $YEAR 01 12"
            else
                echo "💡 补丁数量较多，建议分月下载："
                echo ""
                echo "# 下半年（通常CVE更多）："
                for month in 12 11 10 09 08 07; do
                    echo "./download_monthly_cve.sh --no-git $YEAR $month"
                done
                echo ""
                echo "# 上半年："
                for month in 06 05 04 03 02 01; do
                    echo "./download_monthly_cve.sh --no-git $YEAR $month"
                done
                echo ""
                echo "# 或者分季度下载："
                echo "./download_monthly_cve.sh --no-git $YEAR 01 03  # Q1"
                echo "./download_monthly_cve.sh --no-git $YEAR 04 06  # Q2"
                echo "./download_monthly_cve.sh --no-git $YEAR 07 09  # Q3"
                echo "./download_monthly_cve.sh --no-git $YEAR 10 12  # Q4"
            fi
            
            echo ""
            echo "🔍 如果想了解具体哪些月份有补丁，可以尝试："
            echo ""
            echo "# 测试单个月份（快速）："
            echo "./download_monthly_cve.sh --no-git $YEAR 03  # 测试3月"
            echo "./download_monthly_cve.sh --no-git $YEAR 06  # 测试6月"
            echo "./download_monthly_cve.sh --no-git $YEAR 09  # 测试9月"
            echo "./download_monthly_cve.sh --no-git $YEAR 12  # 测试12月"
            
            echo ""
            echo "📋 说明："
            echo "- 每次下载会显示实际找到的补丁数量和CVE编号"
            echo "- ${YEAR}年的提交可能包含CVE-2016、CVE-2020等各年份的漏洞"
            echo "- 没有补丁的月份会快速完成"
            echo "- 建议先测试1-2个月份，再决定批量下载策略"
            
            # 移除复杂的API分析部分，因为会触发API限制
            # 直接提供实用的建议即可
        else
            echo "⚠️  ${YEAR} 年暂无Linux内核CVE补丁提交"
            echo ""
            echo "建议尝试其他年份:"
            echo "./download_monthly_cve.sh --list-available $((YEAR - 1))"
            echo "./download_monthly_cve.sh --list-available $((YEAR + 1))"
        fi
    else
        echo "❌ GitHub API搜索失败，请检查网络连接"
        echo ""
        echo "你也可以直接尝试常见的月份:"
        echo "./download_monthly_cve.sh --no-git $YEAR 01  # 1月"
        echo "./download_monthly_cve.sh --no-git $YEAR 06  # 6月"
        echo "./download_monthly_cve.sh --no-git $YEAR 12  # 12月"
    fi
    
    exit 0
fi

# 参数验证
if ! [[ "$YEAR" =~ ^[0-9]{4}$ ]]; then
    echo "错误: 年份必须是4位数字"
    exit 1
fi

if ! [[ "$START_MONTH" =~ ^[0-9]{1,2}$ ]] || [ "$START_MONTH" -lt 1 ] || [ "$START_MONTH" -gt 12 ]; then
    echo "错误: 开始月份必须是1-12之间的数字"
    exit 1
fi

if ! [[ "$END_MONTH" =~ ^[0-9]{1,2}$ ]] || [ "$END_MONTH" -lt 1 ] || [ "$END_MONTH" -gt 12 ]; then
    echo "错误: 结束月份必须是1-12之间的数字"
    exit 1
fi

# 将月份转换为十进制数字（去除前导零）
start_month_decimal=$((10#${START_MONTH}))
end_month_decimal=$((10#${END_MONTH}))

if [ "$end_month_decimal" -lt "$start_month_decimal" ]; then
    echo "错误: 结束月份不能小于开始月份"
    exit 1
fi

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 创建主下载目录结构
MAIN_DOWNLOAD_DIR="$SCRIPT_DIR/cve_downloads"

CVE_TRACKER_URL="https://git.launchpad.net/ubuntu-cve-tracker"

# Linux内核仓库备用URL列表
LINUX_GIT_URLS=(
    "https://github.com/torvalds/linux.git"                                    # GitHub镜像
    "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"      # 官方仓库
    "https://kernel.googlesource.com/pub/scm/linux/kernel/git/torvalds/linux" # Google镜像
    "https://mirrors.tuna.tsinghua.edu.cn/git/linux.git"                      # 清华镜像
)

# 尝试克隆Linux内核仓库的函数
clone_linux_repo() {
    local target_dir=$1
    local success=false
    
    echo "尝试从多个镜像克隆Linux内核仓库..."
    
    for url in "${LINUX_GIT_URLS[@]}"; do
        echo "正在尝试: $url"
        if git clone --depth=100 "$url" "$target_dir" 2>/dev/null; then
            echo "成功从 $url 克隆仓库"
            success=true
            break
        else
            echo "从 $url 克隆失败，尝试下一个镜像..."
            rm -rf "$target_dir" 2>/dev/null
        fi
    done
    
    if [ "$success" = false ]; then
        echo "错误: 所有镜像都无法连接，请检查网络设置"
        echo "你可以尝试以下解决方案："
        echo "1. 检查网络连接"
        echo "2. 配置Git代理: git config --global http.proxy http://proxy:port"
        echo "3. 手动下载内核仓库到 $target_dir"
        return 1
    fi
    
    return 0
}

echo "=========================================="
echo "Linux内核CVE补丁批量下载工具"
echo "=========================================="
echo "目标年份: ${YEAR}"
if [ "$start_month_decimal" -eq "$end_month_decimal" ]; then
    echo "目标月份: ${START_MONTH}"
else
    echo "目标月份范围: ${START_MONTH} 到 ${END_MONTH} (共 $((end_month_decimal - start_month_decimal + 1)) 个月)"
fi
echo "脚本目录: ${SCRIPT_DIR}"
echo "主下载目录: ${MAIN_DOWNLOAD_DIR}"
echo ""

# 创建主目录
mkdir -p "${MAIN_DOWNLOAD_DIR}"

# 创建批次汇总目录
if [ "$start_month_decimal" -ne "$end_month_decimal" ]; then
    BATCH_SUMMARY_DIR="$MAIN_DOWNLOAD_DIR/batch_${YEAR}_${START_MONTH}_to_${END_MONTH}_$(date +%H%M%S)"
    mkdir -p "${BATCH_SUMMARY_DIR}"
    echo "批次汇总目录: ${BATCH_SUMMARY_DIR}"
    echo ""
fi

# 下载单个月份的函数
download_month() {
    local year=$1
    local month=$2
    
    # 格式化月份为两位数
    local month_formatted=$(printf "%02d" $((10#${month})))
    
    echo ""
    echo "==========================================  "
    echo "开始下载 ${year}-${month_formatted} 的CVE补丁"
    echo "=========================================="
    
    # 创建会话目录
    local SESSION_DIR="$MAIN_DOWNLOAD_DIR/${year}_${month_formatted}_$(date +%H%M%S)"
    local DOWNLOAD_DIR="$SESSION_DIR/patches"
    local TEMP_DIR="$SESSION_DIR/temp"
    local WORK_DIR="$SESSION_DIR/work"
    
    echo "本次会话目录: ${SESSION_DIR}"
    echo "补丁输出目录: ${DOWNLOAD_DIR}"
    
    # 创建完整的目录结构
    mkdir -p "${DOWNLOAD_DIR}"
    mkdir -p "${TEMP_DIR}"
    mkdir -p "${WORK_DIR}"
    
    # 创建会话信息文件
    cat > "${SESSION_DIR}/session_info.txt" << EOF
# CVE下载会话信息
会话时间: $(date)
目标年月: ${year}-${month_formatted}
脚本位置: ${SCRIPT_DIR}
会话目录: ${SESSION_DIR}
运行用户: $(whoami)
工作目录: $(pwd)
EOF

    # 检查是否已有CVE tracker数据库，如果没有就下载
    local SHARED_CVE_TRACKER="$MAIN_DOWNLOAD_DIR/.shared/ubuntu-cve-tracker"
    if [ ! -d "$SHARED_CVE_TRACKER" ]; then
        echo "[1/5] 获取Ubuntu CVE跟踪数据库（首次下载）..."
        mkdir -p "$MAIN_DOWNLOAD_DIR/.shared"
        git clone --depth=1 "${CVE_TRACKER_URL}" "$SHARED_CVE_TRACKER"
    else
        echo "[1/5] 更新Ubuntu CVE跟踪数据库..."
        cd "$SHARED_CVE_TRACKER" && git pull && cd - > /dev/null
    fi
    
    # 软链接到当前会话
    ln -sf "$SHARED_CVE_TRACKER" "${TEMP_DIR}/ubuntu-cve-tracker"
    
    # 查找指定月份的Linux内核CVE
    echo "[2/5] 查找${year}-${month_formatted}的Linux内核CVE..."
    
    # 创建结果文件
    touch "${WORK_DIR}/cve_list.txt"
    
    # 从CVE数据库中提取Linux内核相关的CVE
    find "${TEMP_DIR}/ubuntu-cve-tracker/active" -name "CVE-${year}-*" | while read cve_file; do
        cve_id=$(basename "$cve_file")
        
        if [ "$DEBUG_MODE" = true ]; then
            echo "调试: 检查文件 $cve_id"
        fi
        
        # 检查是否是指定月份
        if [[ "$cve_id" =~ CVE-${year}-([0-9]{4}) ]]; then
            cve_num=${BASH_REMATCH[1]}
            # 将月份转换为十进制数字（去除前导零）
            month_decimal=$((10#${month}))
            
            if [ "$DEBUG_MODE" = true ]; then
                echo "调试: CVE编号 $cve_num, 目标月份范围: $((month_decimal * 800)) - $(((month_decimal + 1) * 800))"
            fi
            
            # 粗略按CVE编号判断月份 (这个方法不够精确，但是实用)
            if [ "$cve_num" -ge "$((month_decimal * 800))" ] && [ "$cve_num" -lt "$(((month_decimal + 1) * 800))" ]; then
                if [ "$DEBUG_MODE" = true ]; then
                    echo "调试: $cve_id 在目标范围内，检查是否为Linux内核相关..."
                fi
                
                # 检查是否与Linux内核相关
                if grep -q "linux" "$cve_file" && grep -q "kernel" "$cve_file"; then
                    echo "发现CVE: $cve_id"
                    echo "$cve_id" >> "${WORK_DIR}/cve_list.txt"
                    
                    if [ "$DEBUG_MODE" = true ]; then
                        echo "调试: $cve_id 确认为Linux内核CVE"
                        echo "调试: 文件内容预览:"
                        head -10 "$cve_file" | sed 's/^/  /'
                        echo ""
                    fi
                else
                    if [ "$DEBUG_MODE" = true ]; then
                        echo "调试: $cve_id 不是Linux内核相关"
                    fi
                fi
            else
                if [ "$DEBUG_MODE" = true ]; then
                    echo "调试: $cve_id 不在目标月份范围内"
                fi
            fi
        else
            if [ "$DEBUG_MODE" = true ]; then
                echo "调试: $cve_id 格式不匹配预期模式"
            fi
        fi
    done
    
    # 方法2：通过Git日志查找CVE提交（可选）
    if [ "$SKIP_GIT" = false ]; then
        # 检查是否已有Linux内核仓库，如果没有就下载
        local SHARED_LINUX_REPO="$MAIN_DOWNLOAD_DIR/.shared/linux"
        if [ ! -d "$SHARED_LINUX_REPO" ]; then
            echo "[3/5] 克隆Linux内核仓库（首次下载，可能需要较长时间）..."
            mkdir -p "$MAIN_DOWNLOAD_DIR/.shared"
            if ! clone_linux_repo "$SHARED_LINUX_REPO"; then
                echo "无法下载Linux内核仓库，将跳过Git日志搜索，但仍可通过其他方式获取补丁..."
                SKIP_GIT=true
            fi
        else
            echo "[3/5] 更新Linux内核仓库..."
            cd "$SHARED_LINUX_REPO" && git pull && cd - > /dev/null
        fi
    fi
    
    if [ "$SKIP_GIT" = false ]; then
        # 软链接到当前会话
        ln -sf "$SHARED_LINUX_REPO" "${TEMP_DIR}/linux"
        
        cd "${TEMP_DIR}/linux"
        
        # 查找指定月份的CVE相关提交
        # 将月份转换为十进制数字（去除前导零）以正确处理日期
        month_decimal=$((10#${month}))
        next_month=$((month_decimal + 1))
        next_year=${year}
        
        # 处理12月的情况
        if [ "$next_month" -gt 12 ]; then
            next_month=1
            next_year=$((year + 1))
        fi
        
        # 格式化月份为两位数
        month_formatted=$(printf "%02d" $month_decimal)
        next_month_formatted=$(printf "%02d" $next_month)
        
        # 搜索指定月份提交的所有CVE补丁（不限CVE编号年份）
        echo "搜索 ${year}-${month_formatted} 提交的CVE补丁（包含各年份CVE编号）..."
        git log --since="${year}-${month_formatted}-01" --until="${next_year}-${next_month_formatted}-01" \
            --grep="CVE-" --oneline --no-merges > "${WORK_DIR}/git_cve_commits.txt"
        
        echo "[4/5] 下载CVE补丁文件（从Git仓库）..."
        
        # 创建下载日志
        touch "${WORK_DIR}/download_log.csv"
        
        # 从Git提交下载补丁
        local patch_count=0
        cat "${WORK_DIR}/git_cve_commits.txt" | while read line; do
            commit_id=$(echo "$line" | awk '{print $1}')
            commit_msg=$(echo "$line" | cut -d' ' -f2-)
            
            # 提取CVE编号
            cve_id=$(echo "$commit_msg" | grep -o "CVE-[0-9]\{4\}-[0-9]\{4,5\}" | head -1)
            
            if [ -n "$cve_id" ]; then
                echo "下载 $cve_id ($commit_id)..."
                
                # 下载补丁文件
                patch_file="${DOWNLOAD_DIR}/${cve_id}_${commit_id}.patch"
                git format-patch -1 --stdout "$commit_id" > "$patch_file"
                
                # 下载GitHub格式的补丁 (备用)
                curl -s -L "https://github.com/torvalds/linux/commit/${commit_id}.patch" \
                    > "${DOWNLOAD_DIR}/${cve_id}_${commit_id}_github.patch"
                
                echo "$cve_id,$commit_id,$commit_msg" >> "${WORK_DIR}/download_log.csv"
                patch_count=$((patch_count + 1))
            fi
        done
        
        cd "${SCRIPT_DIR}"
    else
        echo "[3/5] 跳过Git仓库下载，使用替代方法获取补丁..."
        
        # 创建空的Git提交文件，避免后续错误
        touch "${WORK_DIR}/git_cve_commits.txt"
        touch "${WORK_DIR}/download_log.csv"
        
        echo "[4/5] 下载CVE补丁文件（从在线源）..."
        
        # 新方法：直接从GitHub搜索该年份已有的CVE提交
        local patch_count=0
        local total_cve_count=0
        local found_count=0
        
        echo "正在搜索 ${year} 年 ${month_formatted} 月已有的Linux内核CVE补丁..."
        
        # 使用GitHub API搜索该年份的CVE相关提交
        # 这样确保我们只获取已经有补丁的CVE
        search_url="https://api.github.com/search/commits?q=repo:torvalds/linux+CVE-${year}&sort=committer-date&per_page=100"
        
        echo "正在从GitHub搜索 ${year} 年的CVE提交..."
        search_result=$(curl -s "$search_url" 2>/dev/null || echo '{"items":[]}')
        
        if echo "$search_result" | grep -q '"total_count"'; then
            total_commits=$(echo "$search_result" | grep -o '"total_count":[[:space:]]*[0-9]*' | grep -o '[0-9]*')
            
            # 确保total_commits是有效数字
            if [ -z "$total_commits" ]; then
                total_commits=0
            fi
            
            echo "GitHub搜索到 $total_commits 个 ${year} 年的CVE相关提交"
            
            if [ "$total_commits" -gt 0 ]; then
                # 解析所有找到的提交
                echo "$search_result" | grep -o '"sha":"[^"]*"' | cut -d'"' -f4 | while read commit_sha; do
                    if [ -n "$commit_sha" ]; then
                        echo "正在处理提交: $commit_sha"
                        
                        # 获取提交信息
                        commit_url="https://api.github.com/repos/torvalds/linux/commits/$commit_sha"
                        commit_info=$(curl -s "$commit_url" 2>/dev/null || echo '{}')
                        
                        # 提取提交日期和消息
                        commit_date=$(echo "$commit_info" | grep -o '"date":"[^"]*"' | head -1 | cut -d'"' -f4)
                        commit_message=$(echo "$commit_info" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
                        
                        if [ -n "$commit_date" ] && [ -n "$commit_message" ]; then
                            # 检查提交日期是否在目标月份范围内
                            commit_year_month=$(echo "$commit_date" | cut -c1-7)  # YYYY-MM
                            target_year_month="${year}-${month_formatted}"
                            
                            if [[ "$commit_year_month" == "$target_year_month" ]]; then
                                # 从提交消息中提取CVE编号
                                cve_id=$(echo "$commit_message" | grep -o "CVE-[0-9]\{4\}-[0-9]\{4,5\}" | head -1)
                                
                                if [ -n "$cve_id" ]; then
                                    echo "✓ 找到匹配的CVE: $cve_id (提交: $commit_sha)"
                                    found_count=$((found_count + 1))
                                    
                                    # 下载补丁文件
                                    patch_file="${DOWNLOAD_DIR}/${cve_id}_${commit_sha}_github.patch"
                                    if curl -s -L "https://github.com/torvalds/linux/commit/${commit_sha}.patch" > "$patch_file"; then
                                        # 检查下载的文件是否有效
                                        if [ -s "$patch_file" ] && ! grep -q "404" "$patch_file"; then
                                            echo "  ✓ 成功下载 $cve_id 补丁"
                                            echo "$cve_id,$commit_sha,$commit_message" >> "${WORK_DIR}/download_log.csv"
                                            patch_count=$((patch_count + 1))
                                        else
                                            echo "  ✗ 下载的补丁文件无效"
                                            rm -f "$patch_file"
                                        fi
                                    else
                                        echo "  ✗ 下载 $cve_id 补丁失败"
                                    fi
                                else
                                    if [ "$DEBUG_MODE" = true ]; then
                                        echo "  调试: 提交消息中未找到CVE编号: $commit_message"
                                    fi
                                fi
                            else
                                if [ "$DEBUG_MODE" = true ]; then
                                    echo "  调试: 提交日期 $commit_year_month 不在目标月份 $target_year_month"
                                fi
                            fi
                        fi
                        
                        # 避免API限制
                        sleep 1
                    fi
                done
                
                # 等待子进程完成并获取实际的补丁数量
                wait
                patch_count=$(wc -l < "${WORK_DIR}/download_log.csv" 2>/dev/null || echo 0)
                
            else
                echo "未找到 ${year} 年的CVE相关提交"
            fi
        else
            echo "GitHub API搜索失败"
            
            # 备用方法：使用CVE数据库的方法（原来的逻辑）
            echo "使用备用方法：从CVE数据库搜索..."
            
            if [ -f "${WORK_DIR}/cve_list.txt" ] && [ -s "${WORK_DIR}/cve_list.txt" ]; then
                total_cve_count=$(wc -l < "${WORK_DIR}/cve_list.txt")
                echo "发现 $total_cve_count 个潜在的Linux内核CVE"
                
                while read cve_id; do
                    if [ -n "$cve_id" ]; then
                        echo "正在搜索 $cve_id 的补丁..."
                        
                        # 直接搜索单个CVE
                        cve_search_url="https://api.github.com/search/commits?q=repo:torvalds/linux+${cve_id}"
                        cve_search_result=$(curl -s "$cve_search_url" 2>/dev/null || echo '{"items":[]}')
                        
                        if echo "$cve_search_result" | grep -q '"total_count"'; then
                            cve_total_commits=$(echo "$cve_search_result" | grep -o '"total_count":[[:space:]]*[0-9]*' | grep -o '[0-9]*')
                            
                            if [ "$cve_total_commits" -gt 0 ]; then
                                commit_sha=$(echo "$cve_search_result" | grep -o '"sha":"[^"]*"' | head -1 | cut -d'"' -f4)
                                
                                if [ -n "$commit_sha" ]; then
                                    echo "  ✓ 找到提交: $commit_sha"
                                    found_count=$((found_count + 1))
                                    
                                    # 下载GitHub格式的补丁
                                    patch_file="${DOWNLOAD_DIR}/${cve_id}_${commit_sha}_github.patch"
                                    if curl -s -L "https://github.com/torvalds/linux/commit/${commit_sha}.patch" > "$patch_file"; then
                                        if [ -s "$patch_file" ] && ! grep -q "404" "$patch_file"; then
                                            echo "  ✓ 成功下载 $cve_id 补丁"
                                            echo "$cve_id,$commit_sha,Downloaded from GitHub API" >> "${WORK_DIR}/download_log.csv"
                                            patch_count=$((patch_count + 1))
                                        else
                                            echo "  ✗ 下载的补丁文件无效"
                                            rm -f "$patch_file"
                                        fi
                                    else
                                        echo "  ✗ 下载 $cve_id 补丁失败"
                                        rm -f "$patch_file"
                                    fi
                                fi
                            else
                                echo "  ⚠ 未找到 $cve_id 的对应提交（该CVE可能还未修复或未公开）"
                            fi
                        fi
                        
                        # 避免API限制
                        sleep 2
                    fi
                done < "${WORK_DIR}/cve_list.txt"
            else
                echo "没有找到CVE列表文件，无法使用备用方法"
            fi
        fi
        
        echo ""
        echo "搜索结果统计:"
        echo "  找到CVE提交: $found_count"
        echo "  成功下载补丁: $patch_count"
        
        if [ "$patch_count" -eq 0 ]; then
            echo ""
            echo "⚠ 警告: 没有成功下载任何补丁，可能的原因："
            echo "  1. 该月份确实没有Linux内核CVE修复提交"
            echo "  2. CVE修复可能在其他月份提交"
            echo "  3. GitHub API限制或网络问题"
            echo ""
            echo "建议："
            echo "  - 尝试其他月份: ./download_monthly_cve.sh --no-git 2024 03"
            echo "  - 尝试更早的年份: ./download_monthly_cve.sh --no-git 2023 06"
            echo "  - 使用完整Git模式: ./download_monthly_cve.sh 2024 08"
        else
            echo ""
            echo "✓ 成功下载了 $patch_count 个已有补丁的CVE！"
        fi
        
        echo "通过在线源下载了 $patch_count 个补丁"
    fi
    
    # 从其他来源获取CVE信息
    echo "[5/5] 从其他数据源获取补充信息..."
    
    # 下载当月的CVE公告
    mkdir -p "${DOWNLOAD_DIR}/advisories"
    
    # Red Hat安全公告
    echo "获取Red Hat安全公告..."
    curl -s "https://access.redhat.com/security/updates/classification/important" \
        > "${DOWNLOAD_DIR}/advisories/redhat_${year}_${month_formatted}.html"
    
    # Ubuntu安全公告  
    echo "获取Ubuntu安全公告..."
    curl -s "https://ubuntu.com/security/cves?package=linux" \
        > "${DOWNLOAD_DIR}/advisories/ubuntu_${year}_${month_formatted}.html"
    
    # 生成下载报告
    echo ""
    echo "=========================================="
    echo "${year}-${month_formatted} 下载完成报告"
    echo "=========================================="
    
    total_patches=$(ls "${DOWNLOAD_DIR}"/*.patch 2>/dev/null | wc -l)
    echo "下载补丁数量: $total_patches"
    
    if [ -f "${WORK_DIR}/download_log.csv" ]; then
        echo "CVE列表:"
        echo "CVE编号,Git提交ID,提交信息" > "${DOWNLOAD_DIR}/summary.csv"
        cat "${WORK_DIR}/download_log.csv" >> "${DOWNLOAD_DIR}/summary.csv"
        cat "${WORK_DIR}/download_log.csv" | cut -d',' -f1 | sort | uniq
    fi
    
    # 创建README文件
    cat > "${SESSION_DIR}/README.md" << EOF
# CVE 下载会话 ${year}-${month_formatted}

## 会话信息
- 下载时间: $(date)
- 目标年月: ${year}-${month_formatted}
- 下载补丁数量: $total_patches

## 目录结构
\`\`\`
${SESSION_DIR}/
├── README.md              # 本文件
├── session_info.txt       # 会话详细信息
├── patches/               # 下载的补丁文件
│   ├── *.patch           # Git格式补丁
│   ├── *_github.patch    # GitHub格式补丁
│   ├── summary.csv       # CVE汇总信息
│   └── advisories/       # 安全公告
├── work/                  # 工作文件
│   ├── cve_list.txt      # 发现的CVE列表
│   ├── git_cve_commits.txt # Git提交记录
│   └── download_log.csv  # 下载日志
└── temp/                  # 临时文件（软链接到共享仓库）
    ├── ubuntu-cve-tracker/ -> 共享CVE数据库
    └── linux/ -> 共享Linux仓库
\`\`\`

## 使用补丁
可以使用 quilt_patch_manager_final.sh 脚本来测试和应用这些补丁：

\`\`\`bash
# 测试补丁兼容性
./quilt_patch_manager_final.sh test-patch ${DOWNLOAD_DIR}/CVE-xxxx-xxxx_commit.patch

# 快速应用补丁
./quilt_patch_manager_final.sh quick-apply ${DOWNLOAD_DIR}/CVE-xxxx-xxxx_commit.patch
\`\`\`
EOF
    
    echo ""
    echo "文件保存在: ${SESSION_DIR}/"
    echo "- patches/: 补丁文件目录"
    echo "  - *.patch: Git格式补丁文件 ($total_patches 个)"
    echo "  - summary.csv: CVE汇总信息"
    echo "  - advisories/: 安全公告"
    echo "- work/: 工作文件和日志"
    echo "- temp/: 临时文件（软链接到共享仓库）"
    echo "- README.md: 详细说明文档"
    
    # 创建最新会话的软链接
    LATEST_LINK="$MAIN_DOWNLOAD_DIR/latest_${year}_${month_formatted}"
    rm -f "$LATEST_LINK" 2>/dev/null || true
    ln -sf "$(basename "$SESSION_DIR")" "$LATEST_LINK"
    
    # 如果是批量下载，添加到批次汇总
    if [ "$start_month_decimal" -ne "$end_month_decimal" ] && [ -n "$BATCH_SUMMARY_DIR" ]; then
        echo "${year}-${month_formatted}: $total_patches 个补丁, 会话目录: $SESSION_DIR" >> "$BATCH_SUMMARY_DIR/batch_summary.txt"
        ln -sf "$SESSION_DIR" "$BATCH_SUMMARY_DIR/${year}_${month_formatted}"
    fi
    
    echo ""
    echo "${year}-${month_formatted} 下载完成!"
    
    return $total_patches
}

# 主执行逻辑
total_downloaded=0
successful_months=0

# 询问是否继续批量下载
if [ "$start_month_decimal" -ne "$end_month_decimal" ]; then
    echo "准备下载 $((end_month_decimal - start_month_decimal + 1)) 个月份的CVE补丁"
    read -p "是否继续？[Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "下载已取消。"
        exit 0
    fi
fi

# 循环下载每个月份
for month in $(seq $start_month_decimal $end_month_decimal); do
    month_formatted=$(printf "%02d" $month)
    
    # 下载该月份
    download_month "$YEAR" "$month_formatted"
    month_patches=$?
    total_downloaded=$((total_downloaded + month_patches))
    successful_months=$((successful_months + 1))
    
    # 如果不是最后一个月份，询问是否继续
    if [ "$month" -lt "$end_month_decimal" ]; then
        echo ""
        read -p "是否继续下载下一个月份 ($(printf "%02d" $((month + 1))))？[Y/n]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo "下载已停止。"
            break
        fi
    fi
done

# 询问是否清理共享临时文件
echo ""
read -p "是否删除共享的临时文件以节省空间？(位于 ${MAIN_DOWNLOAD_DIR}/.shared) [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "清理共享临时文件..."
    rm -rf "${MAIN_DOWNLOAD_DIR}/.shared"
    echo "共享临时文件已清理。"
else
    echo "共享临时文件保留在: ${MAIN_DOWNLOAD_DIR}/.shared"
    echo "这些文件可以在下次下载时重复使用，建议保留。"
fi

# 创建最新批次的软链接
if [ "$start_month_decimal" -ne "$end_month_decimal" ] && [ -n "$BATCH_SUMMARY_DIR" ]; then
    LATEST_BATCH_LINK="$MAIN_DOWNLOAD_DIR/latest_batch"
    rm -f "$LATEST_BATCH_LINK" 2>/dev/null || true
    ln -sf "$(basename "$BATCH_SUMMARY_DIR")" "$LATEST_BATCH_LINK"
    
    # 生成批次汇总报告
    cat > "$BATCH_SUMMARY_DIR/README.md" << EOF
# CVE 批量下载汇总 ${YEAR}-${START_MONTH} 到 ${END_MONTH}

## 批次信息
- 下载时间: $(date)
- 目标年份: ${YEAR}
- 月份范围: ${START_MONTH} 到 ${END_MONTH}
- 成功下载月份: $successful_months 个
- 总补丁数量: $total_downloaded 个

## 各月份详情
\`\`\`
$(cat "$BATCH_SUMMARY_DIR/batch_summary.txt" 2>/dev/null || echo "无详情记录")
\`\`\`

## 目录结构
\`\`\`
${BATCH_SUMMARY_DIR}/
├── README.md              # 本文件
├── batch_summary.txt      # 批次汇总信息
└── ${YEAR}_XX/            # 各月份会话目录的软链接
\`\`\`
EOF
    
    echo ""
    echo "批次汇总报告: $BATCH_SUMMARY_DIR/README.md"
    echo "最新批次链接: $LATEST_BATCH_LINK -> $BATCH_SUMMARY_DIR"
fi

echo ""
echo "========================================"
echo "所有下载任务完成!"
echo "========================================"
echo "成功下载月份: $successful_months"
echo "总补丁数量: $total_downloaded"
echo "所有文件保存在: $MAIN_DOWNLOAD_DIR/"

if [ "$start_month_decimal" -eq "$end_month_decimal" ]; then
    echo ""
    echo "单月下载完成，查看结果:"
    echo "  ls $MAIN_DOWNLOAD_DIR/latest_${YEAR}_$(printf "%02d" $start_month_decimal)/"
else
    echo ""
    echo "批量下载完成，查看结果:"
    echo "  ls $MAIN_DOWNLOAD_DIR/latest_batch/"
    echo "  cat $MAIN_DOWNLOAD_DIR/latest_batch/README.md"
fi
