#!/usr/bin/make -f
# 页面保护内存监控驱动 Makefile - 简化版本
# 支持 ARM32, ARM64, x86, x64 架构

# 驱动名称和版本
DRIVER_NAME := page_monitor
DRIVER_VERSION := 1.0.0

# 内核模块对象
obj-m += page_monitor_mmu.o

# 编译标志
ccflags-y := -DDRIVER_VERSION=\"$(DRIVER_VERSION)\"
ccflags-y += -Wall
ccflags-y += -Wno-unused-parameter
ccflags-y += -Wno-declaration-after-statement  
ccflags-y += -Wno-sign-compare
ccflags-y += -Wno-unused-function
ccflags-y += -Wno-int-conversion
ccflags-y += -DDEBUG

# 架构检测和优化
ifeq ($(ARCH),arm)
    ccflags-y += -DARCH_ARM32
endif

ifeq ($(ARCH),arm64)
    ccflags-y += -DARCH_ARM64
endif

ifeq ($(ARCH),x86)
    ccflags-y += -DARCH_X86_32
endif

ifeq ($(ARCH),x86_64)
    ccflags-y += -DARCH_X86_64
endif

# 内核路径配置
KERNEL_VER ?= $(shell uname -r)
KERNEL_DIR ?= /lib/modules/$(KERNEL_VER)/build

# ARM 交叉编译配置 (请根据需要修改这些路径)
ifeq ($(ARCH),arm)
    # ARM32 交叉编译工具链前缀
    CROSS_COMPILE := arm-none-linux-gnueabi-
    # ARM32 内核源码路径 (修改为您的实际路径)
    KERNEL_DIR := /home/zhangbh/prolin/si/test/im20/prolin-2.7.172-Brazil/build_dir/linux-imx6ul_imx6_pax/linux-4.1.15
endif

ifeq ($(ARCH),arm64)
    # ARM64 交叉编译工具链前缀
    CROSS_COMPILE := aarch64-linux-gnu-
    # ARM64 内核源码路径 (修改为您的实际路径)
    KERNEL_DIR := /path/to/your/arm64-kernel-source
endif

# 默认目标
all: modules

# 编译模块
modules:
	@echo "========================================"
	@echo "编译页面保护内存监控驱动"
	@echo "架构: $(ARCH)"
	@echo "内核目录: $(KERNEL_DIR)"
	@echo "交叉编译: $(CROSS_COMPILE)"
	@echo "========================================"
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules
	@echo "✅ 编译完成: $(DRIVER_NAME).ko"

# 清理
clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) clean
	rm -f *.o *.ko *.mod.c *.mod *.order *.symvers
	rm -f .*.cmd .*.d
	rm -rf .tmp_versions/
	@echo "🧹 清理完成"

# 调试信息
debug:
	@echo "=== 调试信息 ==="
	@echo "PWD: $(PWD)"
	@echo "KERNEL_DIR: $(KERNEL_DIR)"
	@echo "ARCH: $(ARCH)"
	@echo "CROSS_COMPILE: $(CROSS_COMPILE)"
	@echo "ccflags-y: $(ccflags-y)"
	@file $(DRIVER_NAME).ko 2>/dev/null || echo "模块未编译"

# 帮助信息
help:
	@echo "页面保护内存监控驱动 Makefile - 简化版本"
	@echo ""
	@echo "主要目标:"
	@echo "  all/modules    - 编译驱动模块"
	@echo "  clean         - 清理编译文件"
	@echo "  debug         - 显示调试信息"
	@echo "  help          - 显示此帮助"
	@echo ""
	@echo "ARM 交叉编译:"
	@echo "  make ARCH=arm     - ARM32 交叉编译"
	@echo "  make ARCH=arm64   - ARM64 交叉编译"
	@echo ""
	@echo "配置修改:"
	@echo "  请编辑 Makefile 第36-46行修改交叉编译工具链和内核路径"

.PHONY: all modules clean debug help