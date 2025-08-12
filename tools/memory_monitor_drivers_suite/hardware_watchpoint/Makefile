# 硬件 Watchpoint 内存监控驱动 Makefile
# 支持 ARM32 Cortex-A5, ARM64, 和 x86/x64 架构
# 使用硬件断点寄存器进行精确监控

# 驱动模块名称
MODULE_NAME := hw_watchpoint
obj-m := memory_monitor.o

# 版本信息
VERSION := 1.1.0

# 检测当前架构
UNAME_M := $(shell uname -m)
UNAME_S := $(shell uname -s)

# 默认内核源码路径
KERNEL_DIR ?= /lib/modules/$(shell uname -r)/build

# 交叉编译配置
# ARM32 交叉编译器前缀
ARM32_CROSS_COMPILE ?= arm-linux-gnueabihf-
ARM32_KERNEL_DIR ?= /opt/kernel/arm32

# ARM64 交叉编译器前缀
ARM64_CROSS_COMPILE ?= aarch64-linux-gnu-
ARM64_KERNEL_DIR ?= /opt/kernel/arm64

# 工作目录
PWD := $(shell pwd)

# 编译器标志
EXTRA_CFLAGS += -DMODULE_VERSION=\"$(VERSION)\"
EXTRA_CFLAGS += -Wall -Wextra
EXTRA_CFLAGS += -DDEBUG

# 根据架构设置特定标志
ifeq ($(ARCH),arm)
    EXTRA_CFLAGS += -DCONFIG_ARM=1
    EXTRA_CFLAGS += -march=armv7-a
    # Cortex-A5 特定优化
    EXTRA_CFLAGS += -mtune=cortex-a5
else ifeq ($(ARCH),arm64)
    EXTRA_CFLAGS += -DCONFIG_ARM64=1
    # ARM64 通用优化
    EXTRA_CFLAGS += -march=armv8-a
else ifeq ($(ARCH),x86_64)
    EXTRA_CFLAGS += -DCONFIG_X86_64=1
else ifeq ($(ARCH),i386)
    EXTRA_CFLAGS += -DCONFIG_X86=1
endif

# 主要编译目标
.PHONY: all clean help info test install uninstall
.PHONY: arm32 arm64 x86_64 native
.PHONY: test-arm32 test-arm64 test-x86_64 test-native

# 默认目标 - 本地架构编译
all: native

# 显示编译信息
info:
	@echo "=== 硬件 Watchpoint 监控驱动编译系统 ==="
	@echo "版本: $(VERSION)"
	@echo "监控方案: 硬件断点寄存器"
	@echo "当前主机: $(UNAME_S) $(UNAME_M)"
	@echo "内核目录: $(KERNEL_DIR)"
	@echo "工作目录: $(PWD)"
	@echo ""
	@echo "可用目标:"
	@echo "  native     - 本地架构编译 ($(UNAME_M))"
	@echo "  arm32      - ARM32 交叉编译 (Cortex-A5)"
	@echo "  arm64      - ARM64 交叉编译 (Cortex-A53/A72)"
	@echo "  x86_64     - x86_64 交叉编译"
	@echo "  test       - 编译并运行测试"
	@echo "  clean      - 清理编译文件"
	@echo "  install    - 安装驱动模块"
	@echo "  uninstall  - 卸载驱动模块"
	@echo ""
	@echo "硬件支持:"
	@echo "  ARM32: 协处理器p14调试寄存器 (2-6个watchpoint)"
	@echo "  ARM64: AArch64调试架构 (2-16个watchpoint)"  
	@echo "  x86/x64: DR0-DR7调试寄存器 (4个watchpoint)"
	@echo ""

# 本地架构编译
native:
	@echo "🔨 编译本地架构 ($(UNAME_M))..."
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules
	@echo "✅ 本地编译完成: $(MODULE_NAME).ko"
	@file $(MODULE_NAME).ko

# ARM32 交叉编译
arm32:
	@echo "🔨 ARM32 交叉编译 (Cortex-A5)..."
	@if [ ! -d "$(ARM32_KERNEL_DIR)" ]; then \
		echo "❌ 错误: ARM32内核源码目录不存在: $(ARM32_KERNEL_DIR)"; \
		echo "请设置 ARM32_KERNEL_DIR 环境变量或安装ARM32内核源码"; \
		exit 1; \
	fi
	$(MAKE) -C $(ARM32_KERNEL_DIR) M=$(PWD) \
		ARCH=arm \
		CROSS_COMPILE=$(ARM32_CROSS_COMPILE) \
		modules
	@echo "✅ ARM32编译完成: $(MODULE_NAME).ko"
	@file $(MODULE_NAME).ko

# ARM64 交叉编译
arm64:
	@echo "🔨 ARM64 交叉编译 (Cortex-A53/A72)..."
	@if [ ! -d "$(ARM64_KERNEL_DIR)" ]; then \
		echo "❌ 错误: ARM64内核源码目录不存在: $(ARM64_KERNEL_DIR)"; \
		echo "请设置 ARM64_KERNEL_DIR 环境变量或安装ARM64内核源码"; \
		exit 1; \
	fi
	$(MAKE) -C $(ARM64_KERNEL_DIR) M=$(PWD) \
		ARCH=arm64 \
		CROSS_COMPILE=$(ARM64_CROSS_COMPILE) \
		modules
	@echo "✅ ARM64编译完成: $(MODULE_NAME).ko"
	@file $(MODULE_NAME).ko

# x86_64 编译 (用于Ubuntu等)
x86_64:
	@echo "🔨 x86_64 编译..."
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) \
		ARCH=x86_64 \
		modules
	@echo "✅ x86_64编译完成: $(MODULE_NAME).ko"
	@file $(MODULE_NAME).ko

# 清理编译文件
clean:
	@echo "🧹 清理编译文件..."
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean
	rm -f *.o *.ko *.mod.c *.mod *.symvers *.order
	rm -rf .tmp_versions
	@echo "✅ 清理完成"

# 安装模块
install: $(MODULE_NAME).ko
	@echo "📦 安装硬件Watchpoint驱动模块..."
	sudo insmod $(MODULE_NAME).ko
	@echo "✅ 驱动已加载"
	@echo "使用方法: cat /proc/$(MODULE_NAME)"

# 卸载模块
uninstall:
	@echo "🗑️  卸载硬件Watchpoint驱动模块..."
	@if lsmod | grep -q $(MODULE_NAME); then \
		sudo rmmod $(MODULE_NAME); \
		echo "✅ 驱动已卸载"; \
	else \
		echo "ℹ️  驱动未加载"; \
	fi

# 测试驱动功能
test: $(MODULE_NAME).ko
	@echo "🧪 测试硬件Watchpoint功能..."
	@echo "1. 加载驱动..."
	sudo insmod $(MODULE_NAME).ko || true
	@echo ""
	@echo "2. 查看驱动状态:"
	cat /proc/$(MODULE_NAME)
	@echo ""
	@echo "3. 测试写入操作:"
	echo "test_write 12345" | sudo tee /proc/$(MODULE_NAME)
	@echo ""
	@echo "4. 测试读取操作:"
	echo "test_read" | sudo tee /proc/$(MODULE_NAME)
	@echo ""
	@echo "5. 查看内核日志 (最后10行):"
	dmesg | tail -10
	@echo ""
	@echo "6. 卸载驱动..."
	sudo rmmod $(MODULE_NAME) || true
	@echo "✅ 测试完成"

# ARM32 特定测试
test-arm32: arm32
	@echo "🧪 ARM32 测试 (需要在ARM32设备上运行)..."
	@echo "请将 $(MODULE_NAME).ko 复制到ARM32设备并运行:"
	@echo "  scp $(MODULE_NAME).ko user@arm32-device:~/"
	@echo "  ssh user@arm32-device 'sudo insmod $(MODULE_NAME).ko'"
	@echo "  ssh user@arm32-device 'cat /proc/$(MODULE_NAME)'"

# ARM64 特定测试
test-arm64: arm64
	@echo "🧪 ARM64 测试 (需要在ARM64设备上运行)..."
	@echo "请将 $(MODULE_NAME).ko 复制到ARM64设备并运行:"
	@echo "  scp $(MODULE_NAME).ko user@arm64-device:~/"
	@echo "  ssh user@arm64-device 'sudo insmod $(MODULE_NAME).ko'"
	@echo "  ssh user@arm64-device 'cat /proc/$(MODULE_NAME)'"

# 检查依赖
check-deps:
	@echo "🔍 检查编译依赖..."
	@echo "内核头文件:"
	@if [ -d "$(KERNEL_DIR)" ]; then \
		echo "  ✅ $(KERNEL_DIR)"; \
	else \
		echo "  ❌ $(KERNEL_DIR) (不存在)"; \
	fi
	@echo "内核配置:"
	@if [ -f "$(KERNEL_DIR)/.config" ]; then \
		echo "  ✅ 内核配置文件存在"; \
		@if grep -q "CONFIG_HAVE_HW_BREAKPOINT=y" "$(KERNEL_DIR)/.config" 2>/dev/null; then \
			echo "  ✅ 硬件断点支持: 已启用"; \
		else \
			echo "  ⚠️  硬件断点支持: 未知状态"; \
		fi \
	else \
		echo "  ⚠️  内核配置文件不存在"; \
	fi
	@echo "交叉编译工具:"
	@if command -v $(ARM32_CROSS_COMPILE)gcc >/dev/null 2>&1; then \
		echo "  ✅ ARM32交叉编译器: $(ARM32_CROSS_COMPILE)gcc"; \
	else \
		echo "  ❌ ARM32交叉编译器: $(ARM32_CROSS_COMPILE)gcc (未找到)"; \
		echo "    安装: sudo apt-get install gcc-arm-linux-gnueabihf"; \
	fi
	@if command -v $(ARM64_CROSS_COMPILE)gcc >/dev/null 2>&1; then \
		echo "  ✅ ARM64交叉编译器: $(ARM64_CROSS_COMPILE)gcc"; \
	else \
		echo "  ❌ ARM64交叉编译器: $(ARM64_CROSS_COMPILE)gcc (未找到)"; \
		echo "    安装: sudo apt-get install gcc-aarch64-linux-gnu"; \
	fi

# 生成部署包
package: clean
	@echo "📦 生成部署包..."
	@mkdir -p build/$(MODULE_NAME)-$(VERSION)
	@cp -r * build/$(MODULE_NAME)-$(VERSION)/ 2>/dev/null || true
	@cd build && tar -czf $(MODULE_NAME)-$(VERSION).tar.gz $(MODULE_NAME)-$(VERSION)
	@echo "✅ 部署包已生成: build/$(MODULE_NAME)-$(VERSION).tar.gz"

# 帮助信息
help: info
	@echo "详细使用方法:"
	@echo ""
	@echo "1. 本地开发 (Ubuntu/Debian):"
	@echo "   make native && make test"
	@echo ""
	@echo "2. ARM32开发板交叉编译:"
	@echo "   # 设置交叉编译环境"
	@echo "   export ARM32_CROSS_COMPILE=arm-linux-gnueabihf-"
	@echo "   export ARM32_KERNEL_DIR=/path/to/arm32/kernel"
	@echo "   make arm32"
	@echo ""
	@echo "3. ARM64开发板交叉编译:"
	@echo "   # 设置交叉编译环境"
	@echo "   export ARM64_CROSS_COMPILE=aarch64-linux-gnu-"
	@echo "   export ARM64_KERNEL_DIR=/path/to/arm64/kernel"
	@echo "   make arm64"
	@echo ""
	@echo "4. 内核模块参数:"
	@echo "   sudo insmod $(MODULE_NAME).ko monitor_addr=0xc0800000 monitor_size=4"
	@echo ""
	@echo "5. 运行时控制:"
	@echo "   cat /proc/$(MODULE_NAME)                    # 查看状态"
	@echo "   echo 'add test1 0xc0800000 4 3' > /proc/$(MODULE_NAME) # 添加监控"
	@echo "   echo 'test_write 123' > /proc/$(MODULE_NAME) # 测试写入"
	@echo "   echo 'test_read' > /proc/$(MODULE_NAME)      # 测试读取"
	@echo "   dmesg | tail                                # 查看日志"
	@echo ""

# 显示内核模块信息
modinfo: $(MODULE_NAME).ko
	@echo "📋 模块信息:"
	@modinfo $(MODULE_NAME).ko

# 快速测试编译
quick-test:
	@echo "⚡ 快速编译测试..."
	@$(MAKE) clean >/dev/null 2>&1
	@$(MAKE) native >/dev/null 2>&1 && echo "✅ 本地编译: 成功" || echo "❌ 本地编译: 失败"
	@if command -v $(ARM32_CROSS_COMPILE)gcc >/dev/null 2>&1 && [ -d "$(ARM32_KERNEL_DIR)" ]; then \
		$(MAKE) clean >/dev/null 2>&1; \
		$(MAKE) arm32 >/dev/null 2>&1 && echo "✅ ARM32编译: 成功" || echo "❌ ARM32编译: 失败"; \
	else \
		echo "⚠️  ARM32编译: 跳过 (缺少工具链或内核源码)"; \
	fi
	@if command -v $(ARM64_CROSS_COMPILE)gcc >/dev/null 2>&1 && [ -d "$(ARM64_KERNEL_DIR)" ]; then \
		$(MAKE) clean >/dev/null 2>&1; \
		$(MAKE) arm64 >/dev/null 2>&1 && echo "✅ ARM64编译: 成功" || echo "❌ ARM64编译: 失败"; \
	else \
		echo "⚠️  ARM64编译: 跳过 (缺少工具链或内核源码)"; \
	fi

# 默认显示帮助
.DEFAULT_GOAL := info 