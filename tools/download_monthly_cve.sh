#!/bin/bash

# Linux内核CVE补丁批量下载工具
# 基于Ubuntu CVE Tracker和官方Git仓库

set -e

# 配置参数
YEAR=${1:-$(date +%Y)}
MONTH=${2:-$(date +%m)}
DOWNLOAD_DIR="linux_cve_patches_${YEAR}_${MONTH}"
TEMP_DIR="/tmp/cve_download_$$"
CVE_TRACKER_URL="https://git.launchpad.net/ubuntu-cve-tracker"
LINUX_GIT_URL="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"

echo "=========================================="
echo "Linux内核CVE补丁批量下载工具"
echo "=========================================="
echo "目标年月: ${YEAR}-${MONTH}"
echo "下载目录: ${DOWNLOAD_DIR}"
echo ""

# 创建工作目录
mkdir -p "${DOWNLOAD_DIR}"
mkdir -p "${TEMP_DIR}"

# 下载Ubuntu CVE跟踪数据库
echo "[1/5] 获取Ubuntu CVE跟踪数据库..."
if [ ! -d "${TEMP_DIR}/ubuntu-cve-tracker" ]; then
    git clone --depth=1 "${CVE_TRACKER_URL}" "${TEMP_DIR}/ubuntu-cve-tracker"
else
    cd "${TEMP_DIR}/ubuntu-cve-tracker" && git pull && cd -
fi

# 查找指定月份的Linux内核CVE
echo "[2/5] 查找${YEAR}-${MONTH}的Linux内核CVE..."

# 从CVE数据库中提取Linux内核相关的CVE
find "${TEMP_DIR}/ubuntu-cve-tracker/active" -name "CVE-${YEAR}-*" | while read cve_file; do
    cve_id=$(basename "$cve_file")
    
    # 检查是否是指定月份
    if [[ "$cve_id" =~ CVE-${YEAR}-([0-9]{4}) ]]; then
        cve_num=${BASH_REMATCH[1]}
        # 粗略按CVE编号判断月份 (这个方法不够精确，但是实用)
        if [ "$cve_num" -ge "$((MONTH * 800))" ] && [ "$cve_num" -lt "$(((MONTH + 1) * 800))" ]; then
            # 检查是否与Linux内核相关
            if grep -q "linux" "$cve_file" && grep -q "kernel" "$cve_file"; then
                echo "发现CVE: $cve_id"
                echo "$cve_id" >> "${DOWNLOAD_DIR}/cve_list.txt"
            fi
        fi
    fi
done

# 方法2：通过Git日志查找CVE提交
echo "[3/5] 从Git日志查找CVE相关提交..."

# 克隆或更新Linux内核仓库 (shallow clone以节省空间)
if [ ! -d "${TEMP_DIR}/linux" ]; then
    echo "克隆Linux内核仓库..."
    git clone --depth=100 "${LINUX_GIT_URL}" "${TEMP_DIR}/linux"
else
    echo "更新Linux内核仓库..."
    cd "${TEMP_DIR}/linux" && git pull && cd -
fi

cd "${TEMP_DIR}/linux"

# 查找指定月份的CVE相关提交
git log --since="${YEAR}-${MONTH}-01" --until="${YEAR}-$((MONTH + 1))-01" \
    --grep="CVE-${YEAR}" --oneline --no-merges > "${DOWNLOAD_DIR}/git_cve_commits.txt"

echo "[4/5] 下载CVE补丁文件..."

# 从Git提交下载补丁
cat "${DOWNLOAD_DIR}/git_cve_commits.txt" | while read line; do
    commit_id=$(echo "$line" | awk '{print $1}')
    commit_msg=$(echo "$line" | cut -d' ' -f2-)
    
    # 提取CVE编号
    cve_id=$(echo "$commit_msg" | grep -o "CVE-${YEAR}-[0-9]\{4,5\}" | head -1)
    
    if [ -n "$cve_id" ]; then
        echo "下载 $cve_id ($commit_id)..."
        
        # 下载补丁文件
        patch_file="${DOWNLOAD_DIR}/${cve_id}_${commit_id}.patch"
        git format-patch -1 --stdout "$commit_id" > "$patch_file"
        
        # 下载GitHub格式的补丁 (备用)
        curl -s -L "https://github.com/torvalds/linux/commit/${commit_id}.patch" \
            > "${DOWNLOAD_DIR}/${cve_id}_${commit_id}_github.patch"
        
        echo "$cve_id,$commit_id,$commit_msg" >> "${DOWNLOAD_DIR}/download_log.csv"
    fi
done

cd -

# 从其他来源获取CVE信息
echo "[5/5] 从其他数据源获取补充信息..."

# 下载当月的CVE公告
mkdir -p "${DOWNLOAD_DIR}/advisories"

# Red Hat安全公告
echo "获取Red Hat安全公告..."
curl -s "https://access.redhat.com/security/updates/classification/important" \
    > "${DOWNLOAD_DIR}/advisories/redhat_${YEAR}_${MONTH}.html"

# Ubuntu安全公告  
echo "获取Ubuntu安全公告..."
curl -s "https://ubuntu.com/security/cves?package=linux" \
    > "${DOWNLOAD_DIR}/advisories/ubuntu_${YEAR}_${MONTH}.html"

# 生成下载报告
echo ""
echo "=========================================="
echo "下载完成报告"
echo "=========================================="

total_patches=$(ls "${DOWNLOAD_DIR}"/*.patch 2>/dev/null | wc -l)
echo "下载补丁数量: $total_patches"

if [ -f "${DOWNLOAD_DIR}/download_log.csv" ]; then
    echo "CVE列表:"
    echo "CVE编号,Git提交ID,提交信息" > "${DOWNLOAD_DIR}/summary.csv"
    cat "${DOWNLOAD_DIR}/download_log.csv" >> "${DOWNLOAD_DIR}/summary.csv"
    cat "${DOWNLOAD_DIR}/download_log.csv" | cut -d',' -f1 | sort | uniq
fi

echo ""
echo "文件保存在: ${DOWNLOAD_DIR}/"
echo "- *.patch: 补丁文件"
echo "- summary.csv: CVE汇总"
echo "- advisories/: 安全公告"

# 清理临时文件
echo ""
echo "清理临时文件..."
rm -rf "${TEMP_DIR}"

echo "完成!" 