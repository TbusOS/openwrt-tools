# 📋 页面保护内存监控驱动测试指南

本指南提供了详细的测试步骤，确保驱动在不同内核版本和架构下正常工作。

## 🎯 测试环境支持

### 内核版本兼容性
- ✅ Linux 4.1.x (OpenWrt)
- ✅ Linux 5.x (Ubuntu 20.04+)
- ✅ Linux 6.x (最新发行版)

### 架构支持
- ✅ ARM32 (imx6ul等)
- ✅ ARM64 (aarch64)
- ✅ x86_64 (开发机)

## 🔧 编译步骤

### 1. 本地编译 (x86_64)
```bash
cd /path/to/page_protection
make clean
make
```

### 2. ARM交叉编译
```bash
# ARM32 编译
make ARCH=arm clean
make ARCH=arm

# ARM64 编译
make ARCH=arm64 clean
make ARCH=arm64
```

### 3. 验证编译结果
```bash
file page_monitor.ko
modinfo page_monitor.ko
```

## 🚀 测试步骤

### 第一步：准备工作

#### 在开发机上：
1. **确保有sudo权限**
2. **关闭SELinux（如果启用）**：
   ```bash
   sudo setenforce 0  # 临时关闭
   ```
3. **检查内核版本**：
   ```bash
   uname -r
   cat /proc/version
   ```

#### 在开发板上：
1. **传输驱动文件**：
   ```bash
   scp page_monitor.ko root@your_board_ip:/tmp/
   ```

### 第二步：安全加载测试

⚠️ **重要安全提示**：
- 在生产环境加载前，务必在测试环境验证
- 准备好重启设备的方案
- 建议先在虚拟机或不重要的设备上测试

#### 基础加载测试：
```bash
# 1. 加载模块
sudo insmod page_monitor.ko

# 2. 检查加载状态
lsmod | grep page_monitor
dmesg | tail -20

# 3. 检查proc接口
ls -la /proc/page_monitor
cat /proc/page_monitor
```

预期输出示例：
```
[12345.678] [page_monitor] 页面保护内存监控驱动加载中...
[12345.679] [page_monitor] 内核兼容性信息:
[12345.680] [page_monitor]   内核版本: 4.x (4.1.15)
[12345.681] [page_monitor]   架构: ARM32
[12345.682] [page_monitor]   指针格式: 0x%08lx
[12345.683] [page_monitor]   proc_ops: 不可用 (使用 file_operations)
[12345.684] [page_monitor]   vm_fault_t: 不可用 (使用 int)
[12345.685] [page_monitor] 📄 驱动加载成功!
```

### 第三步：功能测试

#### 1. 基本状态查看
```bash
cat /proc/page_monitor
```

预期显示驱动信息、系统架构、内核版本等。

#### 2. 监控测试内存
```bash
# 启动测试内存监控
echo "monitor test_memory" > /proc/page_monitor

# 查看监控状态
cat /proc/page_monitor
```

#### 3. 读取测试
```bash
# 读取测试内存内容
echo "read 0" > /proc/page_monitor

# 检查dmesg看是否触发监控
dmesg | tail -10
```

#### 4. 写入测试
```bash
# 写入测试数据
echo "write 0 Hello_World_Test" > /proc/page_monitor

# 再次检查监控日志
dmesg | tail -10
```

预期监控输出：
```
[12346.123] 📄 [page_monitor] 页面访问检测!
[12346.124] 监控点: test_memory
[12346.125] 故障地址: 0x12345678
[12346.126] 页面号: 12345
[12346.127] 命中次数: 1
[12346.128] 访问类型: 写入
```

#### 5. 停止监控测试
```bash
echo "stop test_memory" > /proc/page_monitor
cat /proc/page_monitor
```

### 第四步：高级测试

#### 1. 压力测试
```bash
# 快速连续访问
for i in {1..10}; do
    echo "write 0 test_$i" > /proc/page_monitor
    sleep 0.1
done

# 检查命中次数
dmesg | grep "命中次数" | tail -5
```

#### 2. 多监控点测试
```bash
# 如果支持多个监控点
echo "monitor custom_area 4096" > /proc/page_monitor
cat /proc/page_monitor
```

#### 3. 错误处理测试
```bash
# 测试无效命令
echo "invalid_command" > /proc/page_monitor
dmesg | tail -5

# 测试无效参数
echo "monitor" > /proc/page_monitor
dmesg | tail -5
```

### 第五步：性能测试

#### 1. 监控开销测试
```bash
# 不启用监控的性能基准
time for i in {1..1000}; do echo "test" > /dev/null; done

# 启用监控后的性能
echo "monitor test_memory" > /proc/page_monitor
time for i in {1..1000}; do echo "read 0" > /proc/page_monitor; done

# 停止监控
echo "stop test_memory" > /proc/page_monitor
```

#### 2. 内存使用测试
```bash
# 检查模块内存使用
cat /proc/meminfo | grep -E "(MemFree|MemAvailable)"
cat /proc/slabinfo | grep page_monitor  # 如果使用了slab分配器
```

### 第六步：卸载测试

#### 正常卸载
```bash
# 停止所有监控
echo "stop test_memory" > /proc/page_monitor

# 卸载模块
sudo rmmod page_monitor

# 验证卸载
lsmod | grep page_monitor
ls /proc/page_monitor  # 应该显示"No such file or directory"
dmesg | tail -5
```

预期卸载输出：
```
[12347.456] [page_monitor] 页面保护内存监控驱动卸载完成
```

#### 强制卸载（如果需要）
```bash
sudo rmmod -f page_monitor
```

## 🐛 故障排除

### 常见问题

#### 1. 加载失败
```bash
# 检查详细错误
dmesg | tail -20
modinfo page_monitor.ko

# 可能的原因：
# - 内核版本不匹配
# - 缺少依赖符号
# - 架构不匹配
```

#### 2. 监控不工作
```bash
# 检查是否启用了页面保护
cat /proc/page_monitor | grep "页面保护"

# 检查架构支持
cat /proc/page_monitor | grep "支持"
```

#### 3. proc接口无响应
```bash
# 检查proc文件权限
ls -la /proc/page_monitor

# 检查是否可写
echo "test" > /proc/page_monitor
echo $?  # 应该返回0表示成功
```

#### 4. 系统卡死或异常
```bash
# 如果系统响应但驱动异常，立即卸载
sudo rmmod page_monitor

# 如果系统卡死，需要硬重启
# 这就是为什么要在测试环境先验证的原因
```

### 调试技巧

#### 1. 启用详细日志
```bash
# 如果驱动支持debug模式
echo "debug on" > /proc/page_monitor
```

#### 2. 监控系统日志
```bash
# 实时监控dmesg
dmesg -w | grep page_monitor

# 查看系统日志
tail -f /var/log/kern.log  # Ubuntu/Debian
tail -f /var/log/messages  # CentOS/RHEL
```

#### 3. 检查内核符号
```bash
# 检查导出的符号
cat /proc/kallsyms | grep page_monitor
```

## 📊 测试验收标准

### 功能测试通过标准
- ✅ 模块加载成功，无错误输出
- ✅ proc接口创建成功 (`/proc/page_monitor`)
- ✅ 基本读写操作正常响应
- ✅ 监控功能能检测到内存访问
- ✅ 监控日志格式正确，包含地址、类型、次数
- ✅ 模块卸载干净，无残留

### 兼容性测试通过标准
- ✅ 在目标内核版本编译成功
- ✅ 在目标架构运行正常
- ✅ 兼容性信息显示正确
- ✅ 不同内核API调用正确

### 稳定性测试通过标准
- ✅ 连续运行24小时无崩溃
- ✅ 压力测试无内存泄漏
- ✅ 多次加载/卸载无问题
- ✅ 系统重启后可重复使用

## 🎯 生产环境部署建议

### 1. 部署前检查
- 在相同内核版本的测试环境充分验证
- 确保有回滚方案
- 准备监控和日志收集

### 2. 安全部署
```bash
# 创建systemd服务（可选）
sudo cp page_monitor.ko /lib/modules/$(uname -r)/
sudo depmod -a

# 开机自动加载（可选）
echo "page_monitor" >> /etc/modules
```

### 3. 监控部署
```bash
# 设置日志轮转
# 创建 /etc/logrotate.d/page_monitor 配置文件
```

## 📝 测试报告模板

### 测试环境
- 内核版本：
- 架构：
- 设备型号：
- 测试时间：

### 测试结果
- [ ] 编译测试
- [ ] 加载测试  
- [ ] 功能测试
- [ ] 性能测试
- [ ] 稳定性测试
- [ ] 卸载测试

### 发现的问题
1. 问题描述
2. 复现步骤
3. 影响程度
4. 建议解决方案

---

⚠️ **重要提醒**：
- 内核模块开发有风险，测试时务必小心
- 建议先在虚拟机或专用测试设备验证
- 生产环境部署前务必充分测试
- 保持测试记录和回滚方案
