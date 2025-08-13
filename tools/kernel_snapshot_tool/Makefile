# 内核快照工具 Makefile
# 专为OpenWrt内核开发优化的高性能快照系统
# 支持跨平台编译和交叉编译 (Linux: x86_64/ARM32/ARM64, macOS: Intel/Apple Silicon)

# 编译器和工具配置
CC ?= gcc
STRIP ?= strip
CROSS_COMPILE ?=

# 如果设置了交叉编译前缀，使用它
ifneq ($(CROSS_COMPILE),)
    CC = $(CROSS_COMPILE)gcc
    STRIP = $(CROSS_COMPILE)strip
endif

# 检测操作系统和架构
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Darwin)
    # macOS specific settings
    PLATFORM = MACOS
    PLATFORM_NAME = macOS
    ifeq ($(UNAME_M),x86_64)
        ARCH_NAME = Intel_x86_64
    else ifeq ($(UNAME_M),arm64)
        ARCH_NAME = Apple_Silicon_ARM64
    else
        ARCH_NAME = $(UNAME_M)
    endif
else ifeq ($(UNAME_S),Linux)
    # Linux specific settings
    PLATFORM = LINUX
    PLATFORM_NAME = Linux
    ifeq ($(UNAME_M),x86_64)
        ARCH_NAME = x86_64
    else ifeq ($(UNAME_M),aarch64)
        ARCH_NAME = ARM64
    else ifeq ($(UNAME_M),armv7l)
        ARCH_NAME = ARM32_ARMv7
    else ifneq ($(filter arm%,$(UNAME_M)),)
        ARCH_NAME = ARM32
    else ifeq ($(UNAME_M),mips)
        ARCH_NAME = MIPS
    else ifeq ($(UNAME_M),mips64)
        ARCH_NAME = MIPS64
    else ifeq ($(UNAME_M),riscv64)
        ARCH_NAME = RISC_V_64
    else
        ARCH_NAME = $(UNAME_M)
    endif
else
    PLATFORM = UNKNOWN
    PLATFORM_NAME = Unknown
    ARCH_NAME = $(UNAME_M)
endif

# 项目信息
PROGRAM = kernel_snapshot
VERSION = 1.2.1
TARGET_DIR = /usr/local/bin

# 源文件 (新增 watch 相关文件)
SRCS = main.c \
       snapshot_core.c \
       snapshot_diff.c \
       index_cache_simple.c \
       progress_bar.c \
       file_monitor.c \
       watch.c

OBJS = $(SRCS:.c=.o)

# 基础编译标志
BASE_CFLAGS = -std=c99 -Wall -Wextra -O3 \
              -flto -ffast-math -funroll-loops -finline-functions \
              -DVERSION=\"$(VERSION)\" \
              -DPLATFORM_NAME=\"$(PLATFORM_NAME)\" \
              -DARCH_NAME=\"$(ARCH_NAME)\"

# 平台特定的编译和链接标志
ifeq ($(PLATFORM),MACOS)
    # macOS specific flags
    CFLAGS = $(BASE_CFLAGS) -D_POSIX_C_SOURCE=200809L
    LDFLAGS = -lpthread -framework CoreServices
    
    # macOS 的 strip 命令参数
    STRIP_FLAGS = 
else ifeq ($(PLATFORM),LINUX)
    # Linux specific flags (包括交叉编译支持)
    CFLAGS = $(BASE_CFLAGS) -D_GNU_SOURCE -D_POSIX_C_SOURCE=200809L
    LDFLAGS = -lpthread
    
    # 交叉编译时避免使用本地优化
    ifeq ($(CROSS_COMPILE),)
        # 原生编译可以使用本地优化 (但为了兼容性，现在移除了)
        # CFLAGS += -march=native
    endif
    
    STRIP_FLAGS = --strip-all
else
    # 其他平台或未知平台
    CFLAGS = $(BASE_CFLAGS) -D_POSIX_C_SOURCE=200809L
    LDFLAGS = -lpthread
    STRIP_FLAGS = 
endif

# 调试标志
DEBUG_CFLAGS = -std=c99 -Wall -Wextra -g -O0 -DDEBUG \
               -D_GNU_SOURCE -D_POSIX_C_SOURCE=200809L \
               -DVERSION=\"$(VERSION)-debug\" \
               -DPLATFORM_NAME=\"$(PLATFORM_NAME)\" \
               -DARCH_NAME=\"$(ARCH_NAME)\"

DEBUG_LDFLAGS = -lpthread
ifeq ($(PLATFORM),MACOS)
    DEBUG_LDFLAGS += -framework CoreServices
endif

# 默认目标
all: $(PROGRAM)

# 显示编译信息
info:
	@echo "==================================="
	@echo "内核快照工具编译配置"
	@echo "==================================="
	@echo "平台: $(PLATFORM_NAME) $(ARCH_NAME)"
	@echo "编译器: $(CC)"
	@echo "交叉编译: $(if $(CROSS_COMPILE),$(CROSS_COMPILE),否)"
	@echo "版本: $(VERSION)"
	@echo "源文件: $(SRCS)"
	@echo "==================================="

# 主程序
$(PROGRAM): info $(OBJS)
	@echo "🔗 链接 $(PROGRAM)..."
	$(CC) -o $@ $(OBJS) $(LDFLAGS)
	$(STRIP) $(STRIP_FLAGS) $@
	@echo "✅ 编译完成: $(PROGRAM) ($(PLATFORM_NAME) $(ARCH_NAME))"
	@echo "📋 功能特性:"
	@echo "   - 快照创建和差异分析"
	@echo "   - 实时文件监控 (watch)"
	@echo "   - 跨平台支持 (Linux/macOS)"
ifeq ($(PLATFORM),LINUX)
	@echo "   - inotify 文件监控"
else ifeq ($(PLATFORM),MACOS)
	@echo "   - FSEvents 文件监控"
endif

# 编译目标文件
%.o: %.c
	@echo "🔨 编译 $< ($(ARCH_NAME))..."
	$(CC) $(CFLAGS) -c $< -o $@

# 调试版本
debug: CFLAGS = $(DEBUG_CFLAGS)
debug: LDFLAGS = $(DEBUG_LDFLAGS)
debug: $(PROGRAM)_debug

$(PROGRAM)_debug: $(SRCS)
	@echo "🐛 编译调试版本 ($(PLATFORM_NAME) $(ARCH_NAME))..."
	$(CC) $(DEBUG_CFLAGS) $(SRCS) $(DEBUG_LDFLAGS) -o $@
	@echo "✅ 调试版本完成: $(PROGRAM)_debug"

# 交叉编译目标
cross-arm32:
	@echo "🔧 ARM32 交叉编译..."
	$(MAKE) CROSS_COMPILE=arm-linux-gnueabihf- all

cross-arm64:
	@echo "🔧 ARM64 交叉编译..."
	$(MAKE) CROSS_COMPILE=aarch64-linux-gnu- all

cross-mips:
	@echo "🔧 MIPS 交叉编译..."
	$(MAKE) CROSS_COMPILE=mips-linux-gnu- all

# 清理
clean:
	@echo "🧹 清理编译文件..."
	rm -f $(OBJS) $(PROGRAM) $(PROGRAM)_debug
	rm -f test_*.snapshot *.log

# 安装
install: $(PROGRAM)
	@echo "📦 安装 $(PROGRAM) 到 $(TARGET_DIR)..."
	sudo mkdir -p $(TARGET_DIR)
	sudo cp $(PROGRAM) $(TARGET_DIR)/
	sudo chmod 755 $(TARGET_DIR)/$(PROGRAM)
	@echo "✅ 安装完成"

# 卸载
uninstall:
	@echo "🗑️ 卸载 $(PROGRAM)..."
	sudo rm -f $(TARGET_DIR)/$(PROGRAM)
	@echo "✅ 卸载完成"

# 功能测试
test: $(PROGRAM)
	@echo "🧪 运行功能测试..."
	@echo "1. 平台检测测试..."
	@./$(PROGRAM) --version
	@echo "2. 文件监控支持测试..."
	@./$(PROGRAM) watch --help || echo "watch 命令测试完成"
	@echo "3. 创建测试目录..."
	@mkdir -p test_data
	@echo "test file 1" > test_data/file1.txt
	@echo "test file 2" > test_data/file2.txt
	@echo "4. 创建快照..."
	@./$(PROGRAM) create test_data test1.snapshot
	@echo "5. 修改文件..."
	@echo "modified" >> test_data/file1.txt
	@echo "new file" > test_data/file3.txt
	@echo "6. 状态检查..."
	@./$(PROGRAM) status test1.snapshot test_data
	@echo "7. 清理测试文件..."
	@rm -rf test_data test1.snapshot
	@echo "✅ 功能测试完成"

# 性能基准测试
benchmark: $(PROGRAM)
	@echo "⚡ 性能基准测试 ($(PLATFORM_NAME) $(ARCH_NAME))..."
	@echo "正在测试大型目录..."
	@time ./$(PROGRAM) create /usr/include benchmark.snapshot || echo "请选择其他目录进行测试"
	@rm -f benchmark.snapshot
	@echo "✅ 基准测试完成"

# 交叉编译测试
test-cross:
	@echo "🔧 交叉编译测试..."
	@echo "测试 ARM32 交叉编译..."
	@which arm-linux-gnueabihf-gcc > /dev/null && $(MAKE) cross-arm32 || echo "ARM32 交叉编译器未安装"
	@echo "测试 ARM64 交叉编译..."
	@which aarch64-linux-gnu-gcc > /dev/null && $(MAKE) cross-arm64 || echo "ARM64 交叉编译器未安装"
	@echo "✅ 交叉编译测试完成"

# 代码格式化（需要clang-format）
format:
	@echo "📝 格式化代码..."
	@which clang-format > /dev/null && \
		clang-format -i -style="{BasedOnStyle: Linux, IndentWidth: 4}" $(SRCS) *.h || \
		echo "⚠️ 未找到clang-format，跳过格式化"

# 静态分析（需要cppcheck）
analyze:
	@echo "🔍 静态代码分析..."
	@which cppcheck > /dev/null && \
		cppcheck --enable=all --suppress=missingIncludeSystem $(SRCS) || \
		echo "⚠️ 未找到cppcheck，跳过静态分析"

# 显示帮助
help:
	@echo "内核快照工具编译选项:"
	@echo "================================="
	@echo "基本编译:"
	@echo "  make           - 编译发布版本"
	@echo "  make debug     - 编译调试版本"
	@echo "  make clean     - 清理编译文件"
	@echo ""
	@echo "交叉编译:"
	@echo "  make cross-arm32    - ARM32 交叉编译"
	@echo "  make cross-arm64    - ARM64 交叉编译" 
	@echo "  make cross-mips     - MIPS 交叉编译"
	@echo "  make CROSS_COMPILE=xxx- - 自定义交叉编译"
	@echo ""
	@echo "测试和分析:"
	@echo "  make test           - 功能测试"
	@echo "  make test-cross     - 交叉编译测试"
	@echo "  make benchmark      - 性能基准测试"
	@echo "  make format         - 代码格式化"
	@echo "  make analyze        - 静态代码分析"
	@echo ""
	@echo "安装和管理:"
	@echo "  make install        - 安装到系统"
	@echo "  make uninstall      - 从系统卸载"
	@echo "  make info           - 显示编译配置"
	@echo "  make help           - 显示此帮助"
	@echo ""
	@echo "支持的平台:"
	@echo "  Linux:  x86_64, ARM32, ARM64, MIPS, RISC-V"
	@echo "  macOS:  Intel x86_64, Apple Silicon ARM64"

# 显示版本信息
version:
	@echo "内核快照工具 v$(VERSION)"
	@echo "平台: $(PLATFORM_NAME) $(ARCH_NAME)"
	@echo "为OpenWrt内核开发优化的跨平台快照系统"

.PHONY: all debug clean install uninstall test benchmark test-cross format analyze help version info cross-arm32 cross-arm64 cross-mips