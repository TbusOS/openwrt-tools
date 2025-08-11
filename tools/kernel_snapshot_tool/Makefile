# 内核快照工具 Makefile
# 专为OpenWrt内核开发优化的高性能快照系统

# 编译器和工具
CC = gcc
STRIP = strip

# 项目信息
PROGRAM = kernel_snapshot
VERSION = 1.1.1
TARGET_DIR = /usr/local/bin

# 源文件
SRCS = main.c \
       snapshot_core.c \
       snapshot_diff.c \
       index_cache_simple.c \
       progress_bar.c

OBJS = $(SRCS:.c=.o)

# 编译标志
CFLAGS = -std=c99 -Wall -Wextra -O3 -march=native \
         -flto -ffast-math -funroll-loops -finline-functions \
         -D_GNU_SOURCE -D_POSIX_C_SOURCE=200809L \
         -DVERSION=\"$(VERSION)\"

LDFLAGS = -lpthread

# 调试标志
DEBUG_CFLAGS = -std=c99 -Wall -Wextra -g -O0 -DDEBUG \
               -fsanitize=address -fno-omit-frame-pointer \
               -D_GNU_SOURCE -D_POSIX_C_SOURCE=200809L \
               -DVERSION=\"$(VERSION)-debug\"

DEBUG_LDFLAGS = -lpthread -fsanitize=address

# 默认目标
all: $(PROGRAM)

# 主程序
$(PROGRAM): $(OBJS)
	@echo "🔗 链接 $(PROGRAM)..."
	$(CC) -o $@ $(OBJS) $(LDFLAGS)
	$(STRIP) $@
	@echo "✅ 编译完成: $(PROGRAM)"

# 编译目标文件
%.o: %.c
	@echo "🔨 编译 $<..."
	$(CC) $(CFLAGS) -c $< -o $@

# 调试版本
debug: CFLAGS = $(DEBUG_CFLAGS)
debug: LDFLAGS = $(DEBUG_LDFLAGS)
debug: $(PROGRAM)_debug

$(PROGRAM)_debug: $(SRCS)
	@echo "🐛 编译调试版本..."
	$(CC) $(DEBUG_CFLAGS) $(SRCS) $(DEBUG_LDFLAGS) -o $@
	@echo "✅ 调试版本完成: $(PROGRAM)_debug"

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

# 测试
test: $(PROGRAM)
	@echo "🧪 运行基本测试..."
	@echo "1. 创建测试目录..."
	@mkdir -p test_data
	@echo "test file 1" > test_data/file1.txt
	@echo "test file 2" > test_data/file2.txt
	@echo "2. 创建快照..."
	@./$(PROGRAM) create test_data test1.snapshot
	@echo "3. 修改文件..."
	@echo "modified" >> test_data/file1.txt
	@echo "new file" > test_data/file3.txt
	@echo "4. 创建第二个快照..."
	@./$(PROGRAM) create test_data test2.snapshot
	@echo "5. 对比快照..."
	@./$(PROGRAM) diff test1.snapshot test2.snapshot
	@echo "6. 清理测试文件..."
	@rm -rf test_data test1.snapshot test2.snapshot
	@echo "✅ 测试完成"

# 性能测试
benchmark: $(PROGRAM)
	@echo "⚡ 性能基准测试..."
	@echo "正在测试大型目录..."
	@time ./$(PROGRAM) create /usr/include benchmark.snapshot || echo "请选择其他目录进行测试"
	@rm -f benchmark.snapshot
	@echo "✅ 基准测试完成"

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
	@echo "  make        - 编译发布版本"
	@echo "  make debug  - 编译调试版本"
	@echo "  make test   - 运行测试"
	@echo "  make benchmark - 性能基准测试"
	@echo "  make install   - 安装到系统"
	@echo "  make uninstall - 从系统卸载"
	@echo "  make clean     - 清理编译文件"
	@echo "  make format    - 格式化代码"
	@echo "  make analyze   - 静态代码分析"
	@echo "  make help      - 显示此帮助"

# 显示版本信息
version:
	@echo "内核快照工具 v$(VERSION)"
	@echo "为OpenWrt内核开发优化的高性能快照系统"

.PHONY: all debug clean install uninstall test benchmark format analyze help version