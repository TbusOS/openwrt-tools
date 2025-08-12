#!/usr/bin/make -f
# 页面保护内存监控驱动 Makefile
# 支持 ARM32, ARM64, x86, x64 架构
# 作者: OpenWrt Tools Project

# 驱动名称和版本
DRIVER_NAME := page_monitor
DRIVER_VERSION := 1.0.0

# 内核模块对象
obj-m += $(DRIVER_NAME).o

# 编译标志
ccflags-y := -DDRIVER_VERSION=\"$(DRIVER_VERSION)\"
ccflags-y += -Wall -Wextra
ccflags-y += -DDEBUG

# 架构检测和优化
ifeq ($(ARCH),arm)
    ccflags-y += -DARCH_ARM32
    ccflags-y += -march=armv7-a
endif

ifeq ($(ARCH),arm64)
    ccflags-y += -DARCH_ARM64
    ccflags-y += -march=armv8-a
endif

ifeq ($(ARCH),x86)
    ccflags-y += -DARCH_X86_32
endif

ifeq ($(ARCH),x86_64)
    ccflags-y += -DARCH_X86_64
endif

# 内核路径自动检测
KERNEL_VER ?= $(shell uname -r)
KERNEL_DIR ?= /lib/modules/$(KERNEL_VER)/build

# 交叉编译支持
ifdef CROSS_COMPILE
    KERNEL_DIR := $(KERNEL_BUILD_PATH)
    ARCH := $(ARCH)
endif

# OpenWrt 编译支持
ifdef STAGING_DIR
    KERNEL_DIR := $(LINUX_DIR)
endif

# 默认目标
all: modules

# 编译模块
modules:
	@echo "========================================"
	@echo "编译页面保护内存监控驱动"
	@echo "架构: $(ARCH)"
	@echo "内核: $(KERNEL_VER)"
	@echo "内核目录: $(KERNEL_DIR)"
	@echo "交叉编译: $(CROSS_COMPILE)"
	@echo "========================================"
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules
	@echo "✅ 编译完成: $(DRIVER_NAME).ko"

# 清理
clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean
	rm -f *.o *.ko *.mod.c *.mod *.order *.symvers
	rm -f .*.cmd .*.d
	rm -rf .tmp_versions/
	@echo "🧹 清理完成"

# 安装模块
install: modules
	@echo "安装页面保护监控驱动..."
	sudo insmod $(DRIVER_NAME).ko
	@echo "✅ 驱动已加载"
	@echo "📋 使用以下命令查看状态:"
	@echo "   cat /proc/$(DRIVER_NAME)"
	@echo "   dmesg | tail"

# 卸载模块
uninstall:
	@echo "卸载页面保护监控驱动..."
	-sudo rmmod $(DRIVER_NAME)
	@echo "🛑 驱动已卸载"

# 重新加载
reload: uninstall install

# 查看状态
status:
	@echo "=== 驱动状态 ==="
	@lsmod | grep $(DRIVER_NAME) || echo "驱动未加载"
	@echo ""
	@echo "=== proc 信息 ==="
	@if [ -f /proc/$(DRIVER_NAME) ]; then \
		cat /proc/$(DRIVER_NAME); \
	else \
		echo "/proc/$(DRIVER_NAME) 不存在"; \
	fi

# 测试功能
test: status
	@echo ""
	@echo "=== 功能测试 ==="
	@if [ -f /proc/$(DRIVER_NAME) ]; then \
		echo "1. 测试读取..."; \
		echo "test_read 0" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
		echo "2. 测试写入..."; \
		echo "test_write 100 Hello_Page_Monitor" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
		echo "3. 再次读取..."; \
		echo "test_read 100" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
		echo "4. 查看内核日志..."; \
		dmesg | tail -10 | grep $(DRIVER_NAME); \
	else \
		echo "驱动未加载，请先运行: make install"; \
	fi

# 架构特定测试
test-arm32:
	$(MAKE) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- test

test-arm64:
	$(MAKE) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- test

test-x86:
	$(MAKE) ARCH=x86 test

test-x86_64:
	$(MAKE) ARCH=x86_64 test

# OpenWrt 编译
openwrt: modules
	@echo "✅ OpenWrt 编译完成"
	@echo "请将 $(DRIVER_NAME).ko 复制到目标设备"

# 创建安装包
package:
	@echo "创建安装包..."
	mkdir -p package/$(DRIVER_NAME)-$(DRIVER_VERSION)
	cp $(DRIVER_NAME).ko package/$(DRIVER_NAME)-$(DRIVER_VERSION)/
	cp README.md package/$(DRIVER_NAME)-$(DRIVER_VERSION)/
	cp test_driver.sh package/$(DRIVER_NAME)-$(DRIVER_VERSION)/
	cd package && tar czf $(DRIVER_NAME)-$(DRIVER_VERSION).tar.gz $(DRIVER_NAME)-$(DRIVER_VERSION)/
	@echo "✅ 安装包已创建: package/$(DRIVER_NAME)-$(DRIVER_VERSION).tar.gz"

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
	@echo "页面保护内存监控驱动 Makefile"
	@echo ""
	@echo "可用目标:"
	@echo "  all/modules    - 编译驱动模块"
	@echo "  clean         - 清理编译文件"
	@echo "  install       - 编译并安装驱动"
	@echo "  uninstall     - 卸载驱动"
	@echo "  reload        - 重新加载驱动"
	@echo "  status        - 查看驱动状态"
	@echo "  test          - 运行功能测试"
	@echo "  package       - 创建安装包"
	@echo "  openwrt       - OpenWrt 编译"
	@echo "  debug         - 显示调试信息"
	@echo "  help          - 显示此帮助"
	@echo ""
	@echo "架构特定测试:"
	@echo "  test-arm32    - ARM32 测试"
	@echo "  test-arm64    - ARM64 测试" 
	@echo "  test-x86      - x86 测试"
	@echo "  test-x86_64   - x86_64 测试"
	@echo ""
	@echo "变量:"
	@echo "  ARCH          - 目标架构 (arm, arm64, x86, x86_64)"
	@echo "  CROSS_COMPILE - 交叉编译前缀"
	@echo "  KERNEL_DIR    - 内核源码路径"

.PHONY: all modules clean install uninstall reload status test package openwrt debug help
.PHONY: test-arm32 test-arm64 test-x86 test-x86_64 