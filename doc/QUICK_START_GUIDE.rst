===========================================================================
OpenWrt Kernel Patch Management Tools - Quick Start Guide
===========================================================================

:Author: OpenWrt Community  
:Date: |today|
:Version: 8.3.0

Prerequisites
=============

System Requirements
-------------------

* OpenWrt development environment
* Linux or macOS system
* Required packages: ``curl``, ``awk``, ``sed``, ``grep``, ``quilt``
* Kernel source tree (prepared via ``make target/linux/prepare``)

Installation
============

1. **Clone the tools**::

    git clone <repository-url>
    cd openwrt-patch-tools

2. **Build kernel_snapshot_tool**::

    cd kernel_snapshot_tool  
    make clean && make
    cd ..

3. **Configure global settings**::

    # Edit configuration file
    vim kernel_snapshot_tool/.kernel_snapshot.conf
    
    # Set your kernel source path
    default_workspace_dir=/path/to/build_dir/linux-xxx/linux-x.x.x
    default_project_name=my-kernel-project

4. **Make script executable**::

    chmod +x quilt_patch_manager_final.sh

Basic Usage Patterns
====================

Pattern 1: Known File Changes (Traditional Workflow)
-----------------------------------------------------

When you know exactly which files need modification:

**Step 1: Test Patch Compatibility**::

    ./quilt_patch_manager_final.sh test-patch 654b33ada4ab5e926cd9c570196fefa7bec7c1df

**Step 2: Extract Patch Information**::

    # Extract affected files
    ./quilt_patch_manager_final.sh extract-files 654b33ada4ab5e926cd9c570196fefa7bec7c1df
    
    # Extract metadata for CVE patches
    ./quilt_patch_manager_final.sh extract-metadata 654b33ada4ab5e926cd9c570196fefa7bec7c1df

**Step 3: Create and Prepare Patch**::

    # Create new patch
    ./quilt_patch_manager_final.sh create-patch my-security-fix.patch
    
    # Add files to tracking
    ./quilt_patch_manager_final.sh add-files patch_manager_work/outputs/patch_files.txt

**Step 4: Modify Code**::

    # Edit kernel source files as needed
    vim /path/to/kernel/source/affected_file.c

**Step 5: Generate Final Patch**::

    # For kernel patches (clean diff)
    ./quilt_patch_manager_final.sh refresh
    
    # For CVE patches (with metadata) 
    ./quilt_patch_manager_final.sh refresh-with-header patch_manager_work/outputs/patch_metadata.txt

Pattern 2: Unknown Changes (Snapshot-Based Workflow)  
-----------------------------------------------------

When you need to discover which files were changed:

**Step 1: Create Baseline Snapshot**::

    ./quilt_patch_manager_final.sh snapshot-create

    # Verify clean state
    ./quilt_patch_manager_final.sh snapshot-status

**Step 2: Make Code Changes**::

    # Edit kernel source files
    vim /path/to/kernel/source/file1.c
    vim /path/to/kernel/source/file2.h
    # Add new files, modify existing ones...

**Step 3: Discover Changes**::

    # Check what changed
    ./quilt_patch_manager_final.sh snapshot-status
    
    # List all changed files
    ./quilt_patch_manager_final.sh snapshot-list-changes
    
    # Export changed files with directory structure
    ./quilt_patch_manager_final.sh export-changed-files

**Step 4: Create Patch from Changes**::

    # Create patch
    ./quilt_patch_manager_final.sh create-patch discovered-changes.patch
    
    # Auto-add all changed files  
    ./quilt_patch_manager_final.sh add-changed-files
    
    # Generate patch
    ./quilt_patch_manager_final.sh refresh

Pattern 3: Fully Automated Workflow
------------------------------------

For experienced users who want maximum automation:

**One-Command Patch Creation**::

    ./quilt_patch_manager_final.sh auto-patch 654b33ada4ab5e926cd9c570196fefa7bec7c1df security-fix.patch

This single command will:
  1. Test patch compatibility
  2. Create new quilt patch  
  3. Extract and add affected files
  4. Generate final patch with metadata

Common Scenarios
================

Scenario: CVE Vulnerability Patching
-------------------------------------

**Objective**: Apply upstream security fix to OpenWrt kernel

**Workflow**::

    # 1. Test compatibility with current kernel
    ./quilt_patch_manager_final.sh test-patch https://git.kernel.org/...commit.patch
    
    # 2. Save patch locally for reference
    ./quilt_patch_manager_final.sh save https://git.kernel.org/...commit.patch cve-2024-xxxx
    
    # 3. Extract patch information
    ./quilt_patch_manager_final.sh extract-files cve-2024-xxxx.patch
    ./quilt_patch_manager_final.sh extract-metadata cve-2024-xxxx.patch  
    
    # 4. Create OpenWrt patch
    ./quilt_patch_manager_final.sh create-patch 999-cve-2024-xxxx.patch
    ./quilt_patch_manager_final.sh add-files patch_files.txt
    
    # 5. Apply manual changes (resolve conflicts if needed)
    # Edit files according to test-patch report
    
    # 6. Generate final patch with original authorship
    ./quilt_patch_manager_final.sh refresh-with-header patch_metadata.txt

**Output**: ``patch_manager_work/outputs/999-cve-2024-xxxx.patch``

Scenario: Custom Feature Development
-------------------------------------

**Objective**: Develop new kernel feature with change tracking

**Workflow**::

    # 1. Create development snapshot
    ./quilt_patch_manager_final.sh snapshot-create
    
    # 2. Develop feature (multiple files)
    # Add new files, modify existing ones...
    
    # 3. Track changes during development
    ./quilt_patch_manager_final.sh snapshot-status  # Check progress
    ./quilt_patch_manager_final.sh export-changed-files  # Backup changes
    
    # 4. Create patch when ready
    ./quilt_patch_manager_final.sh create-patch feature-xyz.patch
    ./quilt_patch_manager_final.sh add-changed-files
    ./quilt_patch_manager_final.sh refresh

**Output**: Clean feature patch with all modifications

Scenario: Backporting Upstream Patches
---------------------------------------

**Objective**: Adapt newer kernel patch to older OpenWrt kernel

**Workflow**::

    # 1. Test original patch (expect conflicts)
    ./quilt_patch_manager_final.sh test-patch upstream-commit-id
    # Review conflict analysis report
    
    # 2. Create development snapshot
    ./quilt_patch_manager_final.sh snapshot-create
    
    # 3. Manual porting based on conflict report
    # Edit files to adapt patch to current kernel version
    
    # 4. Generate backported patch  
    ./quilt_patch_manager_final.sh create-patch backport-feature.patch
    ./quilt_patch_manager_final.sh add-changed-files
    ./quilt_patch_manager_final.sh refresh-with-header upstream-commit-id

**Output**: Backported patch maintaining original authorship

Command Quick Reference
=======================

Essential Commands
------------------

**Testing & Analysis**::

    test-patch <source>              # Test patch compatibility
    extract-files <source>          # Get affected file list
    extract-metadata <source>       # Get patch authorship info

**Snapshot Management**::

    snapshot-create [dir]           # Create baseline snapshot
    snapshot-status [dir]           # Check current status  
    snapshot-list-changes          # List changed files
    export-changed-files           # Export with directory structure

**Patch Operations**::

    create-patch <name>             # Create new quilt patch
    add-files <list>                # Add files from list
    add-changed-files              # Auto-add changed files
    refresh                        # Generate clean patch
    refresh-with-header <meta>     # Generate with metadata

**Quilt Status**::

    status                         # Show patch statistics
    top                           # Show active patch
    files                         # Show tracked files
    series                        # List all patches

**Maintenance**::

    clean                         # Interactive cleanup
    distclean                     # Complete reset
    snapshot-clean               # Remove snapshots

Configuration Files
===================

Global Configuration
--------------------

File: ``kernel_snapshot_tool/.kernel_snapshot.conf``

**Essential Settings**::

    # Kernel source directory (absolute path)
    default_workspace_dir=/home/user/openwrt/build_dir/linux-imx6ul_pax/linux-4.1.15
    
    # Project identifier  
    default_project_name=openwrt-kernel
    
    # Files to ignore during scanning
    ignore_patterns=.git,.svn,*.tmp,*.log,*.bak,*.o,*.ko,Documentation

**Pattern Syntax**:
  - ``*.ext`` - All files with extension
  - ``prefix*`` - Files starting with prefix  
  - ``dirname`` - Entire directories
  - ``path/to/file`` - Specific paths

Directory Structure
===================

Working Directories
-------------------

After first run, the tool creates::

    patch_manager_work/
    ├── cache/                    # Downloaded patch cache
    │   └── original_*.patch     # Cached upstream patches
    ├── outputs/                 # Generated files
    │   ├── *.patch             # Final patch files
    │   ├── patch_files.txt     # Extracted file lists
    │   ├── patch_metadata.txt  # Extracted metadata
    │   ├── changed_files.txt   # Snapshot change lists
    │   └── changed_files/      # Exported file trees
    └── session_tmp/            # Temporary files (auto-cleaned)

Kernel Workspace::

    /path/to/kernel/source/
    ├── .snapshot/              # Snapshot data (hidden)
    │   ├── baseline.snapshot   # File state baseline
    │   ├── index.cache        # Fast lookup index
    │   └── workspace.conf     # Workspace settings
    └── patches/               # Quilt patch directory
        └── your-patch.patch   # Generated patches

Troubleshooting
===============

Common Issues
-------------

**"未找到内核源码目录"**::

    Problem: Cannot locate kernel source tree
    Solution: 
      1. Run 'make target/linux/prepare' in OpenWrt root
      2. Check global config file path
      3. Ensure kernel Makefile exists

**"补丁存在冲突"**::

    Problem: Patch cannot be applied cleanly  
    Solution:
      1. Review test-patch report carefully
      2. Use snapshot workflow for manual adaptation
      3. Check kernel version compatibility

**"索引缓存不可用"**::

    Problem: Snapshot index corrupted or missing
    Solution:
      1. Re-run snapshot-create to rebuild
      2. Check disk space and permissions
      3. Clean and recreate if persistent

**"找不到配置文件"**::

    Problem: Global configuration not found
    Solution:
      1. Create .kernel_snapshot.conf in tool directory  
      2. Set default_workspace_dir to your kernel path
      3. Ensure file is readable

Performance Tips
----------------

**Large Kernel Trees**::

    # Optimize ignore patterns
    ignore_patterns=.git,Documentation,scripts/kconfig,*.o,*.ko
    
    # Reduce thread count if memory limited
    kernel_snapshot_tool create -t 2

**Network Operations**::

    # Cache patches to avoid re-downloads
    ./quilt_patch_manager_final.sh save <url> local-name
    
    # Use local files when possible
    ./quilt_patch_manager_final.sh test-patch ./local-patch.patch

**Disk Space**::

    # Regular cleanup
    ./quilt_patch_manager_final.sh clean
    
    # Remove old snapshots
    ./quilt_patch_manager_final.sh snapshot-clean

Best Practices
==============

Development Workflow
--------------------

1. **Always test patches first**::

    ./quilt_patch_manager_final.sh test-patch <source>

2. **Create snapshots before major changes**::

    ./quilt_patch_manager_final.sh snapshot-create

3. **Use descriptive patch names**::

    # Good
    ./quilt_patch_manager_final.sh create-patch 999-cve-2024-1234-buffer-overflow.patch
    
    # Avoid  
    ./quilt_patch_manager_final.sh create-patch fix.patch

4. **Preserve original authorship for CVE patches**::

    ./quilt_patch_manager_final.sh refresh-with-header <metadata-source>

5. **Regular cleanup**::

    ./quilt_patch_manager_final.sh clean  # Weekly
    ./quilt_patch_manager_final.sh export-changed-files  # Before major changes

Quality Assurance
-----------------

**Verify Changes**::

    # Check patch content
    ./quilt_patch_manager_final.sh diff
    
    # Verify file tracking
    ./quilt_patch_manager_final.sh files

**Test Integration**::

    # Apply patch
    ./quilt_patch_manager_final.sh push
    
    # Test kernel build
    make target/linux/compile
    
    # Remove if issues
    ./quilt_patch_manager_final.sh pop

**Backup Strategy**::

    # Export before submission
    ./quilt_patch_manager_final.sh export-changed-files
    
    # Archive outputs directory
    tar -czf my-patches-$(date +%Y%m%d).tar.gz patch_manager_work/outputs/

Next Steps
==========

Advanced Usage
--------------

After mastering basic workflows, explore:

* **Automated CI Integration**: Use in build pipelines
* **Multi-patch Management**: Handle patch series efficiently  
* **Custom Ignore Patterns**: Optimize for specific projects
* **Performance Tuning**: Configure for large kernel trees

Additional Resources
--------------------

* **Technical Manual**: Complete command reference and internals
* **Project Repository**: Latest updates and community support
* **OpenWrt Documentation**: Integration with existing workflows
* **Community Forums**: Share experiences and get help

Happy patching! 🚀

.. |today| date::
