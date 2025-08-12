#!/usr/bin/make -f
# Kprobe 内存监控驱动 Makefile
# 支持 ARM32, ARM64, x86, x64 架构
# 作者: OpenWrt Tools Project

# 驱动名称和版本
DRIVER_NAME := kprobe_monitor
DRIVER_VERSION := 1.2.0

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
	@echo "编译 Kprobe 内存监控驱动"
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
	@echo "安装 Kprobe 监控驱动..."
	sudo insmod $(DRIVER_NAME).ko
	@echo "✅ 驱动已加载"
	@echo "📋 使用以下命令查看状态:"
	@echo "   cat /proc/$(DRIVER_NAME)"
	@echo "   dmesg | tail"

# 卸载模块
uninstall:
	@echo "卸载 Kprobe 监控驱动..."
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
		echo "1. 添加 mmap 监控..."; \
		echo "add test_mmap sys_mmap 0" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
		echo "2. 添加 munmap 监控..."; \
		echo "add test_munmap sys_munmap 0" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
		echo "3. 列出可用符号..."; \
		echo "list_symbols" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
		echo "4. 触发一些内存操作以测试探针..."; \
		dd if=/dev/zero of=/tmp/test_mmap bs=1M count=1 2>/dev/null; \
		sleep 2; \
		rm -f /tmp/test_mmap; \
		echo "5. 查看内核日志..."; \
		dmesg | tail -15 | grep $(DRIVER_NAME); \
		echo "6. 清理测试监控..."; \
		echo "del test_mmap" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
		echo "del test_munmap" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
	else \
		echo "驱动未加载，请先运行: make install"; \
	fi

# 高级测试 - 监控特定进程
test-process:
	@echo "=== 进程特定监控测试 ==="
	@if [ -f /proc/$(DRIVER_NAME) ]; then \
		echo "添加针对 bash 进程的 mmap 监控..."; \
		echo "add bash_mmap sys_mmap 0 0 0 bash" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
		echo "在新的 bash 中执行一些命令来触发监控..."; \
		bash -c "echo 'test' > /tmp/kprobe_test; cat /tmp/kprobe_test; rm -f /tmp/kprobe_test"; \
		sleep 1; \
		echo "查看监控结果..."; \
		dmesg | tail -10 | grep $(DRIVER_NAME); \
		echo "清理监控..."; \
		echo "del bash_mmap" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
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

# 检查内核配置
check-config:
	@echo "=== 检查内核配置 ==="
	@echo "检查 Kprobe 支持..."
	@if [ -f /proc/config.gz ]; then \
		gunzip -c /proc/config.gz | grep -E "CONFIG_KPROBES|CONFIG_KRETPROBES|CONFIG_STACKTRACE" || echo "配置文件中未找到相关选项"; \
	elif [ -f /boot/config-$(shell uname -r) ]; then \
		grep -E "CONFIG_KPROBES|CONFIG_KRETPROBES|CONFIG_STACKTRACE" /boot/config-$(shell uname -r) || echo "配置文件中未找到相关选项"; \
	else \
		echo "无法找到内核配置文件"; \
	fi
	@echo ""
	@echo "检查符号表支持..."
	@if [ -f /proc/kallsyms ]; then \
		echo "✅ kallsyms 可用"; \
		echo "可用的内存相关符号数量: $$(grep -E 'sys_mmap|sys_munmap|sys_brk|do_mmap|vmalloc' /proc/kallsyms | wc -l)"; \
	else \
		echo "❌ kallsyms 不可用"; \
	fi

# 符号查找
find-symbols:
	@echo "=== 查找内存相关符号 ==="
	@if [ -f /proc/kallsyms ]; then \
		echo "mmap 相关符号:"; \
		grep -i mmap /proc/kallsyms | head -10; \
		echo ""; \
		echo "内存管理相关符号:"; \
		grep -E 'alloc|free' /proc/kallsyms | grep -v __free | head -10; \
	else \
		echo "kallsyms 不可用"; \
	fi

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
	@echo ""
	@echo "内核版本信息:"
	@uname -a
	@echo ""
	@echo "内核模块信息:"
	@if [ -f $(DRIVER_NAME).ko ]; then \
		modinfo $(DRIVER_NAME).ko; \
	fi

# 性能测试
benchmark:
	@echo "=== 性能基准测试 ==="
	@if [ -f /proc/$(DRIVER_NAME) ]; then \
		echo "测试前记录时间..."; \
		time_start=$$(date +%s.%N); \
		echo "添加多个监控点..."; \
		echo "add perf_mmap sys_mmap 0" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
		echo "add perf_munmap sys_munmap 0" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
		echo "add perf_brk sys_brk 0" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
		echo "执行内存密集型操作..."; \
		for i in $$(seq 1 10); do \
			dd if=/dev/zero of=/tmp/benchmark_$$$$i bs=1M count=1 2>/dev/null; \
			rm -f /tmp/benchmark_$$$$i; \
		done; \
		time_end=$$(date +%s.%N); \
		echo "测试完成，耗时: $$(echo "$$time_end - $$time_start" | bc -l 2>/dev/null || echo "N/A")秒"; \
		echo "清理监控点..."; \
		echo "del perf_mmap" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
		echo "del perf_munmap" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
		echo "del perf_brk" | sudo tee /proc/$(DRIVER_NAME) > /dev/null; \
	else \
		echo "驱动未加载，请先运行: make install"; \
	fi

# 帮助信息
help:
	@echo "Kprobe 内存监控驱动 Makefile"
	@echo ""
	@echo "可用目标:"
	@echo "  all/modules       - 编译驱动模块"
	@echo "  clean            - 清理编译文件"
	@echo "  install          - 编译并安装驱动"
	@echo "  uninstall        - 卸载驱动"
	@echo "  reload           - 重新加载驱动"
	@echo "  status           - 查看驱动状态"
	@echo "  test             - 运行基本功能测试"
	@echo "  test-process     - 测试进程特定监控"
	@echo "  check-config     - 检查内核配置"
	@echo "  find-symbols     - 查找内存相关符号"
	@echo "  benchmark        - 性能基准测试"
	@echo "  package          - 创建安装包"
	@echo "  openwrt          - OpenWrt 编译"
	@echo "  debug            - 显示调试信息"
	@echo "  help             - 显示此帮助"
	@echo ""
	@echo "架构特定测试:"
	@echo "  test-arm32       - ARM32 测试"
	@echo "  test-arm64       - ARM64 测试" 
	@echo "  test-x86         - x86 测试"
	@echo "  test-x86_64      - x86_64 测试"
	@echo ""
	@echo "变量:"
	@echo "  ARCH             - 目标架构 (arm, arm64, x86, x86_64)"
	@echo "  CROSS_COMPILE    - 交叉编译前缀"
	@echo "  KERNEL_DIR       - 内核源码路径"
	@echo ""
	@echo "示例:"
	@echo "  make install                    # 编译并安装"
	@echo "  make test                       # 基本功能测试"
	@echo "  make test-process              # 进程监控测试"
	@echo "  make check-config              # 检查内核支持"
	@echo "  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- # 交叉编译"

.PHONY: all modules clean install uninstall reload status test test-process package openwrt debug help
.PHONY: test-arm32 test-arm64 test-x86 test-x86_64 check-config find-symbols benchmark 