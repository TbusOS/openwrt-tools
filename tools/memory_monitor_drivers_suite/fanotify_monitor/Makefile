# fanotify 文件访问监控工具 Makefile
# Linux 高级文件监控解决方案

# 编译器配置
CC ?= gcc
STRIP ?= strip

# 项目信息
PROGRAM = fanotify_demo
VERSION = 1.0.0
INSTALL_DIR = /usr/local/bin

# 源文件
SRCS = fanotify_demo.c
OBJS = $(SRCS:.c=.o)

# 编译标志
CFLAGS = -std=c99 -Wall -Wextra -O3 \
         -D_GNU_SOURCE \
         -DVERSION=\"$(VERSION)\"

# 链接标志
LDFLAGS = 

# 调试标志
DEBUG_CFLAGS = -std=c99 -Wall -Wextra -g -O0 -DDEBUG \
               -D_GNU_SOURCE \
               -DVERSION=\"$(VERSION)-debug\"

# 检查系统支持
KERNEL_VERSION := $(shell uname -r)
FANOTIFY_SUPPORT := $(shell grep -q "CONFIG_FANOTIFY=y" /boot/config-$(KERNEL_VERSION) 2>/dev/null && echo "yes" || echo "unknown")

# 默认目标
all: check-support $(PROGRAM)

# 检查系统支持
check-support:
	@echo "======================================"
	@echo "fanotify 文件监控工具编译检查"
	@echo "======================================"
	@echo "内核版本: $(KERNEL_VERSION)"
	@echo "fanotify支持: $(FANOTIFY_SUPPORT)"
	@echo "编译器: $(CC)"
	@echo "版本: $(VERSION)"
	@echo "======================================"
ifeq ($(FANOTIFY_SUPPORT),unknown)
	@echo "⚠️  警告: 无法确认内核fanotify支持状态"
	@echo "   如果编译失败，请检查内核配置"
endif

# 主程序
$(PROGRAM): $(OBJS)
	@echo "🔗 链接 $(PROGRAM)..."
	$(CC) -o $@ $(OBJS) $(LDFLAGS)
	$(STRIP) --strip-all $@
	@echo "✅ 编译完成: $(PROGRAM)"
	@echo ""
	@echo "📋 使用说明:"
	@echo "   sudo ./$(PROGRAM) <监控路径>"
	@echo "   例如: sudo ./$(PROGRAM) /home/user/test"
	@echo ""
	@echo "⚠️  注意: 需要root权限运行"

# 编译目标文件
%.o: %.c
	@echo "🔨 编译 $<..."
	$(CC) $(CFLAGS) -c $< -o $@

# 调试版本
debug: CFLAGS = $(DEBUG_CFLAGS)
debug: $(PROGRAM)_debug

$(PROGRAM)_debug: $(SRCS)
	@echo "🐛 编译调试版本..."
	$(CC) $(DEBUG_CFLAGS) $(SRCS) $(LDFLAGS) -o $@
	@echo "✅ 调试版本完成: $(PROGRAM)_debug"

# 测试系统兼容性
test-system:
	@echo "🧪 测试系统兼容性..."
	@echo "1. 检查内核版本..."
	@uname -r
	@echo "2. 检查权限..."
	@if [ "$$(id -u)" -eq 0 ]; then \
		echo "✅ 当前是root用户"; \
	else \
		echo "❌ 当前不是root用户，需要使用sudo"; \
	fi
	@echo "3. 检查fanotify头文件..."
	@if [ -f "/usr/include/sys/fanotify.h" ]; then \
		echo "✅ fanotify头文件存在"; \
	else \
		echo "❌ fanotify头文件不存在，可能需要安装开发包"; \
	fi
	@echo "4. 尝试编译测试..."
	@$(CC) $(CFLAGS) -c $(SRCS) -o test.o && echo "✅ 编译测试通过" || echo "❌ 编译测试失败"
	@rm -f test.o

# 功能测试（需要root权限）
test: $(PROGRAM)
	@echo "🧪 功能测试 (需要root权限)..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "❌ 测试需要root权限，请使用: sudo make test"; \
		exit 1; \
	fi
	@echo "1. 创建测试目录..."
	@mkdir -p test_dir
	@echo "测试文件" > test_dir/test.txt
	@echo "2. 启动监控测试 (5秒)..."
	@timeout 5s ./$(PROGRAM) test_dir || true
	@echo "3. 清理测试文件..."
	@rm -rf test_dir
	@echo "✅ 功能测试完成"

# 性能基准测试
benchmark: $(PROGRAM)
	@echo "⚡ 性能基准测试..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "❌ 基准测试需要root权限，请使用: sudo make benchmark"; \
		exit 1; \
	fi
	@echo "创建大量测试文件..."
	@mkdir -p benchmark_dir
	@for i in $$(seq 1 100); do echo "test $$i" > benchmark_dir/file$$i.txt; done
	@echo "开始基准测试 (10秒)..."
	@timeout 10s ./$(PROGRAM) benchmark_dir || true
	@echo "清理测试文件..."
	@rm -rf benchmark_dir
	@echo "✅ 基准测试完成"

# 安装
install: $(PROGRAM)
	@echo "📦 安装 $(PROGRAM) 到 $(INSTALL_DIR)..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "❌ 安装需要root权限，请使用: sudo make install"; \
		exit 1; \
	fi
	mkdir -p $(INSTALL_DIR)
	cp $(PROGRAM) $(INSTALL_DIR)/
	chmod 755 $(INSTALL_DIR)/$(PROGRAM)
	@echo "✅ 安装完成"
	@echo "使用方法: sudo $(INSTALL_DIR)/$(PROGRAM) <路径>"

# 卸载
uninstall:
	@echo "🗑️ 卸载 $(PROGRAM)..."
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo "❌ 卸载需要root权限，请使用: sudo make uninstall"; \
		exit 1; \
	fi
	rm -f $(INSTALL_DIR)/$(PROGRAM)
	@echo "✅ 卸载完成"

# 清理
clean:
	@echo "🧹 清理编译文件..."
	rm -f $(OBJS) $(PROGRAM) $(PROGRAM)_debug
	rm -rf test_dir benchmark_dir
	@echo "✅ 清理完成"

# 显示帮助
help:
	@echo "fanotify 文件监控工具编译选项:"
	@echo "================================="
	@echo "基本编译:"
	@echo "  make              - 编译发布版本"
	@echo "  make debug        - 编译调试版本"
	@echo "  make clean        - 清理编译文件"
	@echo ""
	@echo "系统检查:"
	@echo "  make test-system  - 测试系统兼容性"
	@echo "  make check-support - 检查fanotify支持"
	@echo ""
	@echo "测试运行:"
	@echo "  sudo make test      - 功能测试"
	@echo "  sudo make benchmark - 性能基准测试"
	@echo ""
	@echo "安装管理:"
	@echo "  sudo make install   - 安装到系统"
	@echo "  sudo make uninstall - 从系统卸载"
	@echo ""
	@echo "使用方法:"
	@echo "  sudo ./$(PROGRAM) <监控路径>"
	@echo ""
	@echo "⚠️  重要提醒:"
	@echo "  - 需要root权限或CAP_SYS_ADMIN"
	@echo "  - 需要内核支持fanotify (Linux 2.6.37+)"
	@echo "  - 监控大目录可能影响系统性能"

# 显示版本信息
version:
	@echo "fanotify 文件监控工具 v$(VERSION)"
	@echo "Linux 高级文件访问监控解决方案"
	@echo "需要: Linux 2.6.37+, root权限"

.PHONY: all debug clean install uninstall test test-system benchmark help version check-support
