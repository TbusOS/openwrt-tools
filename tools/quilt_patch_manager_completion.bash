#!/bin/bash
# Bash completion script for quilt_patch_manager_final.sh
# 使用方法：source quilt_patch_manager_completion.bash

_quilt_patch_manager_complete() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    # 定义所有可用的命令
    local commands="
        fetch save test-patch extract-files extract-metadata
        add-files create-patch refresh refresh-with-header auto-patch
        quick-apply
        snapshot-create snapshot-diff snapshot-status 
        snapshot-list-changes snapshot-list-new snapshot-list-modified snapshot-clean
        export-changed-files export-from-file
        distclean clean reset-env
        status series applied unapplied top files push pop diff
        fold header
        graph graph-pdf
        help version
    "
    
    # 定义选项
    local graph_pdf_options="--color --all"
    local snapshot_clean_options="force"
    
    # 如果是第一个参数（命令），提供命令补全
    if [[ ${COMP_CWORD} == 1 ]]; then
        COMPREPLY=($(compgen -W "${commands}" -- ${cur}))
        return 0
    fi
    
    # 根据前一个命令提供相应的补全
    case "${COMP_WORDS[1]}" in
        graph-pdf)
            # 为 graph-pdf 命令提供选项补全
            if [[ ${cur} == -* ]]; then
                COMPREPLY=($(compgen -W "${graph_pdf_options}" -- ${cur}))
            else
                # 如果不是选项，尝试补全补丁文件名
                _complete_patch_files
            fi
            return 0
            ;;
        snapshot-clean)
            COMPREPLY=($(compgen -W "${snapshot_clean_options}" -- ${cur}))
            return 0
            ;;
        fetch|save|test-patch|extract-files|extract-metadata|refresh-with-header|auto-patch)
            # 这些命令可能需要补丁文件或commit ID
            _complete_patch_files
            return 0
            ;;
        add-files|export-from-file)
            # 这些命令需要文件路径补全
            COMPREPLY=($(compgen -f -- ${cur}))
            return 0
            ;;
        quick-apply)
            # quick-apply 需要补丁文件路径
            COMPREPLY=($(compgen -f -X '!*.patch' -- ${cur}))
            return 0
            ;;
        create-patch)
            # create-patch 需要补丁名称，不提供补全
            return 0
            ;;
        graph)
            # graph 命令可以补全补丁名称
            _complete_patch_files
            return 0
            ;;
        fold)
            # fold 命令需要补全补丁文件
            _complete_patch_files
            return 0
            ;;
        header)
            # header 命令可以补全补丁名称和选项
            if [[ ${cur} == -* ]]; then
                COMPREPLY=($(compgen -W "-a -r -e" -- ${cur}))
            else
                _complete_patch_files
            fi
            return 0
            ;;
        *)
            # 默认情况下不提供补全
            return 0
            ;;
    esac
}

# 辅助函数：补全补丁文件名
_complete_patch_files() {
    local patch_files=""
    
    # 尝试从当前目录及其子目录查找 .patch 文件
    if [[ -d "patch_manager_work/outputs" ]]; then
        patch_files+=" $(find patch_manager_work/outputs -name "*.patch" -type f 2>/dev/null | sed 's|patch_manager_work/outputs/||')"
    fi
    
    # 尝试从 OpenWrt 补丁目录查找补丁
    local openwrt_patches_dir
    if openwrt_patches_dir=$(find . -path "*/target/linux/*/patches*" -type d 2>/dev/null | head -1); then
        if [[ -n "$openwrt_patches_dir" && -d "$openwrt_patches_dir" ]]; then
            patch_files+=" $(find "$openwrt_patches_dir" -name "*.patch" -type f 2>/dev/null | sed "s|$openwrt_patches_dir/||")"
        fi
    fi
    
    # 也包括普通文件补全
    COMPREPLY=($(compgen -f -X '!*.patch' -- ${cur}))
    
    # 如果找到了补丁文件，添加到补全列表
    if [[ -n "$patch_files" ]]; then
        COMPREPLY+=($(compgen -W "${patch_files}" -- ${cur}))
    fi
}

# 注册补全函数
complete -F _quilt_patch_manager_complete ./quilt_patch_manager_final.sh
complete -F _quilt_patch_manager_complete quilt_patch_manager_final.sh

# 如果脚本被直接执行，显示使用说明
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Bash 自动补全脚本已加载！"
    echo ""
    echo "使用方法："
    echo "  source quilt_patch_manager_completion.bash"
    echo ""
    echo "或者将以下行添加到您的 ~/.bashrc 文件中："
    echo "  source $(pwd)/quilt_patch_manager_completion.bash"
    echo ""
    echo "然后重新启动终端或执行 'source ~/.bashrc'"
    echo ""
    echo "之后您就可以使用 Tab 键自动补全命令了："
    echo "  ./quilt_patch_manager_final.sh <Tab><Tab>"
    echo "  ./quilt_patch_manager_final.sh graph-pdf --<Tab><Tab>"
fi 