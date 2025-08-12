===========================================================================
OpenWrt 内核补丁管理工具 - 快速入门指南
===========================================================================

:Author: OpenWrt 社区  
:Date: |today|
:Version: 8.3.0

前提条件
========

系统要求
--------

* OpenWrt 开发环境
* Linux 或 macOS 系统
* 必需软件包：``curl``、``awk``、``sed``、``grep``、``quilt``
* 内核源码树（通过 ``make target/linux/prepare`` 准备）

安装
====

1. **克隆工具**::

    git clone <repository-url>
    cd openwrt-patch-tools

2. **编译 kernel_snapshot_tool**::

    cd kernel_snapshot_tool  
    make clean && make
    cd ..

3. **配置全局设置**::

    # 编辑配置文件
    vim kernel_snapshot_tool/.kernel_snapshot.conf
    
    # 设置内核源码路径
    default_workspace_dir=/path/to/build_dir/linux-xxx/linux-x.x.x
    default_project_name=my-kernel-project

4. **使脚本可执行**::

    chmod +x quilt_patch_manager_final.sh

基本使用模式
============

模式一：已知文件变更（传统工作流）
----------------------------------

当您确切知道需要修改哪些文件时：

**步骤 1：测试补丁兼容性**::

    ./quilt_patch_manager_final.sh test-patch 654b33ada4ab5e926cd9c570196fefa7bec7c1df

**步骤 2：提取补丁信息**::

    # 提取受影响的文件
    ./quilt_patch_manager_final.sh extract-files 654b33ada4ab5e926cd9c570196fefa7bec7c1df
    
    # 提取 CVE 补丁的元数据
    ./quilt_patch_manager_final.sh extract-metadata 654b33ada4ab5e926cd9c570196fefa7bec7c1df

**步骤 3：创建和准备补丁**::

    # 创建新补丁
    ./quilt_patch_manager_final.sh create-patch my-security-fix.patch
    
    # 添加文件到跟踪
    ./quilt_patch_manager_final.sh add-files patch_manager_work/outputs/patch_files.txt

**步骤 4：修改代码**::

    # 根据需要编辑内核源文件
    vim /path/to/kernel/source/affected_file.c

**步骤 5：生成最终补丁**::

    # 用于内核补丁（纯 diff）
    ./quilt_patch_manager_final.sh refresh
    
    # 用于 CVE 补丁（带元数据） 
    ./quilt_patch_manager_final.sh refresh-with-header patch_manager_work/outputs/patch_metadata.txt

模式二：未知变更（基于快照的工作流）  
------------------------------------

当您需要发现哪些文件被更改时：

**步骤 1：创建基线快照**::

    ./quilt_patch_manager_final.sh snapshot-create

    # 验证干净状态
    ./quilt_patch_manager_final.sh snapshot-status

**步骤 2：进行代码更改**::

    # 编辑内核源文件
    vim /path/to/kernel/source/file1.c
    vim /path/to/kernel/source/file2.h
    # 添加新文件，修改现有文件...

**步骤 3：发现变更**::

    # 检查什么发生了变更
    ./quilt_patch_manager_final.sh snapshot-status
    
    # 列出所有变更文件
    ./quilt_patch_manager_final.sh snapshot-list-changes
    
    # 导出变更文件及目录结构
    ./quilt_patch_manager_final.sh export-changed-files

**步骤 4：从变更创建补丁**::

    # 创建补丁
    ./quilt_patch_manager_final.sh create-patch discovered-changes.patch
    
    # 自动添加所有变更文件  
    ./quilt_patch_manager_final.sh add-changed-files
    
    # 生成补丁
    ./quilt_patch_manager_final.sh refresh

模式三：完全自动化工作流
------------------------

对于希望最大自动化的有经验用户：

**一键补丁创建**::

    ./quilt_patch_manager_final.sh auto-patch 654b33ada4ab5e926cd9c570196fefa7bec7c1df security-fix.patch

这个单一命令将：
  1. 测试补丁兼容性
  2. 创建新的 quilt 补丁  
  3. 提取并添加受影响的文件
  4. 生成带元数据的最终补丁

常见场景
========

场景：CVE 漏洞修补
-------------------

**目标**：将上游安全修复应用到 OpenWrt 内核

**工作流**::

    # 1. 测试与当前内核的兼容性
    ./quilt_patch_manager_final.sh test-patch https://git.kernel.org/...commit.patch
    
    # 2. 本地保存补丁以供参考
    ./quilt_patch_manager_final.sh save https://git.kernel.org/...commit.patch cve-2024-xxxx
    
    # 3. 提取补丁信息
    ./quilt_patch_manager_final.sh extract-files cve-2024-xxxx.patch
    ./quilt_patch_manager_final.sh extract-metadata cve-2024-xxxx.patch  
    
    # 4. 创建 OpenWrt 补丁
    ./quilt_patch_manager_final.sh create-patch 999-cve-2024-xxxx.patch
    ./quilt_patch_manager_final.sh add-files patch_files.txt
    
    # 5. 应用手动更改（如需要解决冲突）
    # 根据 test-patch 报告编辑文件
    
    # 6. 生成带有原始作者信息的最终补丁
    ./quilt_patch_manager_final.sh refresh-with-header patch_metadata.txt

**输出**：``patch_manager_work/outputs/999-cve-2024-xxxx.patch``

场景：自定义功能开发
--------------------

**目标**：开发新的内核功能并进行变更跟踪

**工作流**::

    # 1. 创建开发快照
    ./quilt_patch_manager_final.sh snapshot-create
    
    # 2. 开发功能（多个文件）
    # 添加新文件，修改现有文件...
    
    # 3. 开发过程中跟踪变更
    ./quilt_patch_manager_final.sh snapshot-status  # 检查进度
    ./quilt_patch_manager_final.sh export-changed-files  # 备份变更
    
    # 4. 准备就绪时创建补丁
    ./quilt_patch_manager_final.sh create-patch feature-xyz.patch
    ./quilt_patch_manager_final.sh add-changed-files
    ./quilt_patch_manager_final.sh refresh

**输出**：包含所有修改的干净功能补丁

场景：移植上游补丁
------------------

**目标**：将较新的内核补丁适配到较旧的 OpenWrt 内核

**工作流**::

    # 1. 测试原始补丁（预期有冲突）
    ./quilt_patch_manager_final.sh test-patch upstream-commit-id
    # 查看冲突分析报告
    
    # 2. 创建开发快照
    ./quilt_patch_manager_final.sh snapshot-create
    
    # 3. 基于冲突报告进行手动移植
    # 编辑文件以将补丁适配到当前内核版本
    
    # 4. 生成移植后的补丁  
    ./quilt_patch_manager_final.sh create-patch backport-feature.patch
    ./quilt_patch_manager_final.sh add-changed-files
    ./quilt_patch_manager_final.sh refresh-with-header upstream-commit-id

**输出**：保持原始作者信息的移植补丁

命令快速参考
============

基本命令
--------

**测试与分析**::

    test-patch <source>              # 测试补丁兼容性
    extract-files <source>          # 获取受影响的文件列表
    extract-metadata <source>       # 获取补丁作者信息

**快照管理**::

    snapshot-create [dir]           # 创建基线快照
    snapshot-status [dir]           # 检查当前状态  
    snapshot-list-changes          # 列出变更文件
    export-changed-files           # 导出并保持目录结构

**补丁操作**::

    create-patch <name>             # 创建新的 quilt 补丁
    add-files <list>                # 从列表添加文件
    add-changed-files              # 自动添加变更文件
    refresh                        # 生成干净补丁
    refresh-with-header <meta>     # 生成带元数据补丁

**Quilt 状态**::

    status                         # 显示补丁统计
    top                           # 显示活动补丁
    files                         # 显示跟踪文件
    series                        # 列出所有补丁

**维护**::

    clean                         # 交互式清理
    distclean                     # 完全重置
    snapshot-clean               # 移除快照

配置文件
========

全局配置
--------

文件：``kernel_snapshot_tool/.kernel_snapshot.conf``

**基本设置**::

    # 内核源码目录（绝对路径）
    default_workspace_dir=/home/user/openwrt/build_dir/linux-imx6ul_pax/linux-4.1.15
    
    # 项目标识符  
    default_project_name=openwrt-kernel
    
    # 扫描时忽略的文件
    ignore_patterns=.git,.svn,*.tmp,*.log,*.bak,*.o,*.ko,Documentation

**模式语法**：
  - ``*.ext`` - 所有具有该扩展名的文件
  - ``prefix*`` - 以前缀开头的文件  
  - ``dirname`` - 整个目录
  - ``path/to/file`` - 特定路径

目录结构
========

工作目录
--------

首次运行后，工具会创建::

    patch_manager_work/
    ├── cache/                    # 下载的补丁缓存
    │   └── original_*.patch     # 缓存的上游补丁
    ├── outputs/                 # 生成的文件
    │   ├── *.patch             # 最终补丁文件
    │   ├── patch_files.txt     # 提取的文件列表
    │   ├── patch_metadata.txt  # 提取的元数据
    │   ├── changed_files.txt   # 快照变更列表
    │   └── changed_files/      # 导出的文件树
    └── session_tmp/            # 临时文件（自动清理）

内核工作区::

    /path/to/kernel/source/
    ├── .snapshot/              # 快照数据（隐藏）
    │   ├── baseline.snapshot   # 文件状态基线
    │   ├── index.cache        # 快速查找索引
    │   └── workspace.conf     # 工作区设置
    └── patches/               # Quilt 补丁目录
        └── your-patch.patch   # 生成的补丁

故障排除
========

常见问题
--------

**"未找到内核源码目录"**::

    问题：无法定位内核源码树
    解决方案： 
      1. 在 OpenWrt 根目录运行 'make target/linux/prepare'
      2. 检查全局配置文件路径
      3. 确保内核 Makefile 存在

**"补丁存在冲突"**::

    问题：补丁无法干净地应用  
    解决方案：
      1. 仔细查看 test-patch 报告
      2. 使用快照工作流进行手动适配
      3. 检查内核版本兼容性

**"索引缓存不可用"**::

    问题：快照索引损坏或丢失
    解决方案：
      1. 重新运行 snapshot-create 以重建
      2. 检查磁盘空间和权限
      3. 如持续存在，清理并重新创建

**"找不到配置文件"**::

    问题：找不到全局配置
    解决方案：
      1. 在工具目录中创建 .kernel_snapshot.conf  
      2. 将 default_workspace_dir 设置为您的内核路径
      3. 确保文件可读

性能提示
--------

**大型内核树**::

    # 优化忽略模式
    ignore_patterns=.git,Documentation,scripts/kconfig,*.o,*.ko
    
    # 如内存受限，减少线程数
    kernel_snapshot_tool create -t 2

**网络操作**::

    # 缓存补丁以避免重复下载
    ./quilt_patch_manager_final.sh save <url> local-name
    
    # 尽可能使用本地文件
    ./quilt_patch_manager_final.sh test-patch ./local-patch.patch

**磁盘空间**::

    # 定期清理
    ./quilt_patch_manager_final.sh clean
    
    # 移除旧快照
    ./quilt_patch_manager_final.sh snapshot-clean

最佳实践
========

开发工作流
----------

1. **始终先测试补丁**::

    ./quilt_patch_manager_final.sh test-patch <source>

2. **在重大变更前创建快照**::

    ./quilt_patch_manager_final.sh snapshot-create

3. **使用描述性的补丁名称**::

    # 好的
    ./quilt_patch_manager_final.sh create-patch 999-cve-2024-1234-buffer-overflow.patch
    
    # 避免  
    ./quilt_patch_manager_final.sh create-patch fix.patch

4. **为 CVE 补丁保留原始作者信息**::

    ./quilt_patch_manager_final.sh refresh-with-header <metadata-source>

5. **定期清理**::

    ./quilt_patch_manager_final.sh clean  # 每周
    ./quilt_patch_manager_final.sh export-changed-files  # 重大变更前

质量保证
--------

**验证变更**::

    # 检查补丁内容
    ./quilt_patch_manager_final.sh diff
    
    # 验证文件跟踪
    ./quilt_patch_manager_final.sh files

**测试集成**::

    # 应用补丁
    ./quilt_patch_manager_final.sh push
    
    # 测试内核编译
    make target/linux/compile
    
    # 如有问题则移除
    ./quilt_patch_manager_final.sh pop

**备份策略**::

    # 提交前导出
    ./quilt_patch_manager_final.sh export-changed-files
    
    # 归档输出目录
    tar -czf my-patches-$(date +%Y%m%d).tar.gz patch_manager_work/outputs/

下一步
======

高级用法
--------

掌握基本工作流后，可以探索：

* **自动化 CI 集成**：在构建流水线中使用
* **多补丁管理**：高效处理补丁系列  
* **自定义忽略模式**：针对特定项目优化
* **性能调优**：为大型内核树配置

其他资源
--------

* **技术手册**：完整命令参考和内部机制
* **项目仓库**：最新更新和社区支持
* **OpenWrt 文档**：与现有工作流的集成
* **社区论坛**：分享经验和获取帮助

祝您补丁制作愉快！ 🚀

.. |today| date::
