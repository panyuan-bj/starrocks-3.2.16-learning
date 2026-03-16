---
displayed_sidebar: docs
---

# WSL2 上编译、启动、Debug StarRocks（3.2 版本）

在 WSL2（Windows 系统上的 Linux 子系统，Ubuntu）中完成 StarRocks 的编译、单机启动（1 FE + 1 BE）、以及 FE/BE 源码断点调试。所有命令在**项目根目录** `/home/peter/my-project/starrocks` 下执行，部署目录为 **`output/`**。

与 Docker 方案相比，WSL2 方案**不需要端口映射、不需要 SSH、不需要 gdbserver**，IDE 直接连接本地进程即可调试。

---

## 零、基础准备

### 0.1 安装 WSL2

在 Windows PowerShell（管理员）中执行：

```powershell
wsl --install -d Ubuntu
```

安装完成后重启电脑，打开 Ubuntu 终端设置用户名和密码。

**WSL2 内存配置建议**（避免编译时 OOM 崩溃）：

在 Windows 用户目录创建或编辑 `C:\Users\<你的用户名>\.wslconfig`：

```ini
[wsl2]
memory=24GB
swap=16GB
processors=24
```

修改后在 PowerShell 执行 `wsl --shutdown`，再重新进入 WSL 使配置生效。可在 WSL 中用 `free -h` 验证。

### 0.2 下载源码

```bash
git clone https://github.com/StarRocks/starrocks.git
cd starrocks
git checkout branch-3.2.16   # 切换到版本分支
git branch branch-3.2.16-learning # 新建分支
git checkout branch-3.2.16-learning # 切换分支
```

### 0.3 使用 Cursor 或 Claude Code

可以在 WSL 命令行中执行 `cursor .` 启动 Cursor 打开项目。

> **注意**：编译（特别是 Debug 模式）非常吃内存。建议编译时**关闭 Cursor**，在纯命令行下编译，编完后再打开 Cursor 进行代码浏览和调试。

### 0.4 安装 CLion（可选，用于 BE 调试）

在 Windows 上安装 CLion，通过 WSL Toolchain 连接 WSL 内的编译器和调试器，详见「六、Debug BE」。

---

## 一、安装编译依赖

> 仅首次搭建环境时需要，后续不必重复。

### 1.1 基础工具

```bash
sudo apt-get update

sudo apt-get install -y automake binutils-dev bison byacc ccache flex libiberty-dev libtool \
    maven zip python3 python-is-python3 cmake git patch lld bzip2 \
    wget unzip curl make build-essential ninja-build
```

### 1.2 安装 GCC 10（⚠️ 重要）

> **强烈建议使用 GCC 10（如 10.3 或 10.5）。不建议使用 Ubuntu 24.04 默认的 GCC 13/14。**
>
> 原因：StarRocks 3.2 分支依赖的多个第三方库（RocksDB 6.22.1、Breakpad、AWS SDK CPP 等）在 GCC 13+ 下会出现大量编译错误（`-Wredundant-move`、`-Wnonnull`、缺少 `<cstdint>` 隐式引入等），需要逐个打补丁才能编译通过。使用 GCC 10 可以避免这些问题。

Ubuntu 24.04（noble）默认源中没有 GCC 10，需要添加 Ubuntu 22.04（jammy）的源：

```bash
# 添加 jammy 源
echo "deb http://archive.ubuntu.com/ubuntu jammy main universe" | sudo tee /etc/apt/sources.list.d/jammy.list
sudo apt-get update

# 安装 GCC 10
sudo apt-get install -y gcc-10 g++-10

# 设置为默认版本
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 100

# 如果系统中有多个 GCC 版本，选择 gcc-10
sudo update-alternatives --config gcc
sudo update-alternatives --config g++
```

### 1.3 安装 JDK 17

```bash
# StarRocks 3.2.x 推荐 JDK 17，不建议用 default-jdk 装到 21，可能有兼容问题
sudo apt-get install -y openjdk-17-jdk

# 若系统中有多个 JDK 版本，切换到 17
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac

# 设置 JAVA_HOME（加入 ~/.bashrc 或 ~/.zshrc 以持久化）
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

### 1.4 验证

```bash
gcc --version    # 应显示 10.x（如 10.5.0）✓
g++ --version    # 应显示 10.x ✓
java --version   # 需 >= 8，推荐 17（当前 17.x ✓）
cmake --version  # 需 >= 3.20.1
mvn --version
```

---

## 二、编译

```bash
cd /home/peter/my-project/starrocks

# 由于编译耗时很长，建议分开fe、be编译，二者编译顺序没有前后关系

# 编译 FE
./build.sh --fe

# 编译 FE + BE（Debug 模式，首次会自动编译 thirdparty，耗时较长）
BUILD_TYPE=Debug ./build.sh --be
```

编译过程中，很可能会多次遇到error，要有耐心，建议找AI分析解决，非常好用。

> 可用 `-j N` 指定并行度，如 `BUILD_TYPE=Debug ./build.sh --fe --be -j 8`。

`BUILD_TYPE=Debug` 的作用：BE 以 `-O0 -ggdb` 编译（不优化、带完整调试符号），且不会 strip 二进制。这样用 GDB/CLion Attach 时变量可查看、断点精准、单步与源码一致。不加此参数默认为 Release（`-O3` 优化 + strip 符号），调试时变量大量显示 `<optimized out>`，断点乱跳，基本不可用。FE 是 Java 不受此参数影响。

> 若不需要 Debug、只想快速跑起来，可用 `./build.sh --fe --be`（Release 模式，编译更快、二进制更小）。

编译成功后产出在 `output/fe` 和 `output/be`。

---

## 三、启动 FE

```bash
# 1. 创建元数据目录
mkdir -p output/fe/meta

# 2. 配置 meta_dir
grep -q "^meta_dir " output/fe/conf/fe.conf || echo "meta_dir = \${STARROCKS_HOME}/meta" >> output/fe/conf/fe.conf

# 3. 单 BE 副本数设为 1
grep -q "default_replication_num" output/fe/conf/fe.conf || echo "default_replication_num = 1" >> output/fe/conf/fe.conf

# 4. 以 Debug 模式启动（--debug 会监听 5005 端口用于 IDEA 断点调试，见「五、Debug FE」）
cd output/fe && ./bin/start_fe.sh --daemon --debug && cd ../..

# 5. 检查（看到 thrift server started with port 9020 即成功）
cat output/fe/log/fe.log | grep thrift
```

---

## 四、启动 BE 并加入集群

### 4.1 启动 BE

```bash
# 1. 创建数据目录
mkdir -p output/be/storage

# 2. 配置 storage_root_path
grep -q "^storage_root_path " output/be/conf/be.conf || echo "storage_root_path = \${STARROCKS_HOME}/storage" >> output/be/conf/be.conf

# 3. 启动
cd output/be && ./bin/start_be.sh --daemon && cd ../..

# 4. 检查（看到 heartbeat has started listening port on 9050 即成功）
cat output/be/log/be.INFO | grep "heartbeat has started listening port"
```

### 4.2 把 BE 加入集群

修改output/be/conf/be.conf，添加内容`priority_networks = 127.0.0.1/32`，强制BE使用IP

```bash
# 安装 MySQL 客户端（若未安装）
sudo apt-get install -y default-mysql-client

# 连接 FE
mysql -h 127.0.0.1 -P 9030 -uroot
```

```sql
-- WSL2 中 FE 和 BE 在同一个系统，直接用 127.0.0.1
ALTER SYSTEM ADD BACKEND "127.0.0.1:9050";

SHOW PROC '/backends'\G
```

`Alive` 为 `true` 即成功。

### 4.3 简单验证

```sql
CREATE DATABASE IF NOT EXISTS demo;
USE demo;

CREATE TABLE IF NOT EXISTS t1 (
    id      BIGINT NOT NULL,
    name    VARCHAR(100),
    ts      DATETIME DEFAULT CURRENT_TIMESTAMP
)
PRIMARY KEY (id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ("replication_num" = "1");

INSERT INTO t1 (id, name) VALUES (1, 'a'), (2, 'b'), (3, 'c');

SELECT * FROM t1 ORDER BY id;
```

---

## 五、Debug FE（Java：IntelliJ IDEA）

FE 是 Java 进程，第三节已用 `--debug` 启动（监听 5005 端口），日志中可见 `address=*:5005`。下面用 IDEA 连接即可断点调试，**无需改代码**。

### 5.1 IDEA 连接

1. **Run → Edit Configurations → + → Remote JVM Debug**
2. Host `localhost`，Port `5005`，保存并点击 Debug。
3. WSL2 中的 5005 端口可直接从 Windows 访问（WSL2 自动转发），无需额外配置。

### 5.2 打断点验证

在 IDEA 中打开 FE 源码，推荐断点：

| 文件 | 说明 |
|------|------|
| `fe/fe-core/src/main/java/com/starrocks/qe/StmtExecutor.java` 的 `execute()` 方法 | SQL 执行入口，可看 `context`、`parsedStmt` |
| `fe/fe-core/src/main/java/com/starrocks/qe/ConnectProcessor.java` 的 `handleQuery` | 客户端发来的 SQL 字符串 |

用 MySQL 执行 `SELECT * FROM demo.t1;`，程序会在断点处暂停。

---

## 六、Debug BE（C++：CLion + WSL Toolchain）

BE 是 C++ 进程，第二节已用 `BUILD_TYPE=Debug` 编译（带完整符号），第四节已启动。下面配置 CLion 来 Attach 调试。

### 6.1 CLion 配置 WSL Toolchain

CLion 原生支持 WSL Toolchain，**IDE 运行在 Windows 上，编译/调试在 WSL 内执行，无需 SSH 配置**。

1. 打开 CLion（Windows 版） → **File → Open** → 打开 `\\wsl$\Ubuntu\home\peter\my-project\starrocks` 下的项目（或直接打开 WSL 路径）。

2. **Settings → Build, Execution, Deployment → Toolchains**：
   - 点 **+** → 选 **WSL**，CLion 会自动检测到你的 WSL 发行版。
   - 确认 CMake、C Compiler、C++ Compiler 均显示绿色勾（自动从 WSL 中检测）。

3. **Settings → Build, Execution, Deployment → CMake**：
   - 如果点击`Build, Execution, Deployment`后找不到`CMake`，可以在项目中找到文件`be/CMakeLists.txt`，点击右键：加载CMake项目
   - **Build type**：`Debug`
   - **Toolchain**：选上一步添加的 WSL toolchain
   - **Environment**：添加 `STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr;JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64;STARROCKS_THIRDPARTY=/home/peter/my-project/starrocks/thirdparty`
     - `STARROCKS_CLION_ONLY=1`：只生成代码导航用的 target，不真正编译，配置速度很快
     - `STARROCKS_GCC_HOME`：指定 GCC 路径（WSL 上通过 apt 安装的 GCC 在 `/usr`）
     - `JAVA_HOME`：CMake 配置过程中 `gen_build_version.py` 需要调用 `java` 来获取版本信息，必须设置此变量
     - `STARROCKS_THIRDPARTY`：指向第三方依赖目录，CMake 通过此变量定位 Boost、gflags、protobuf 等所有预编译的第三方库
   - 取消勾选 **Include system environment variables**（避免 Windows 环境变量干扰）

4. 在项目树中找到 `be/CMakeLists.txt` → **右键 → Load CMake Project**，等待配置完成。

### 6.2 Attach 调试

1. **放开 ptrace 权限**（每次 WSL 重启后需重新执行）：
   ```bash
   echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope
   ```
   > 默认值为 `1`（只允许父进程调试子进程），改为 `0` 后 CLion/GDB 才能 attach 到 `starrocks_be`。否则会报 `ptrace: Operation not permitted`。

2. 确认 BE 已在 WSL 中启动：`ps aux | grep starrocks_be`。
3. CLion 中：**Run → Attach to Process...**，在 **SSH/WSL** 标签下找到 `starrocks_be`，点击「使用 WSL GDB 附加」。
4. 打开 BE 源码文件，设置断点（红色实心圆），用 MySQL 发 SQL 触发即可。

推荐断点：

| 文件 | 行号 | 说明 |
|------|------|------|
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` | **398** | `_prj_iter->get_next(chunk)`，实际从底层存储读取数据 |

### 6.3 备选：gdb 命令行调试

不依赖 IDE，适合快速排查：

```bash
# 安装 gdb（若未安装）
sudo apt-get install -y gdb

# 查找 BE 进程 PID 并附加
ps aux | grep starrocks_be
gdb -p <PID>

# 在 gdb 中
(gdb) break starrocks::SomeClass::some_method
(gdb) continue
```

用 MySQL 发 SQL 触发后，gdb 会在断点处停住。`bt` 查看调用栈，`n`/`s` 单步，`detach` + `quit` 退出。

---

## 七、常用命令小结

| 操作 | 命令 |
|------|------|
| 编译（Debug） | `BUILD_TYPE=Debug ./build.sh --fe --be` |
| 编译（Release） | `./build.sh --fe --be` |
| 启动 FE（带调试） | `cd output/fe && ./bin/start_fe.sh --daemon --debug` |
| 启动 FE（不调试） | `cd output/fe && ./bin/start_fe.sh --daemon` |
| 停 FE | `output/fe/bin/stop_fe.sh` |
| 启动 BE | `cd output/be && ./bin/start_be.sh --daemon` |
| 停 BE | `output/be/bin/stop_be.sh` |
| 连库 | `mysql -h 127.0.0.1 -P 9030 -uroot` |

---

## 八、若启动报错

- **FE 日志**：`output/fe/log/fe.warn.log`
- **BE 日志**：`output/be/log/be.WARNING`
- **priority_networks**：若提示需配置，在 `fe.conf` 或 `be.conf` 中加 `priority_networks = 127.0.0.1/24`。
- **BE Alive: false**：确认用 `127.0.0.1:9050` 添加 Backend（WSL2 中 FE/BE 同机，应一致）。若仍失败，检查 BE 是否真正启动：`ps aux | grep starrocks_be`。
- **BE 启动时 SIGABRT（DataCache 相关）**：在 `output/be/conf/be.conf` 中加一行 `datacache_enable = false`。

---

## 九、推荐 Debug 组合

| 组件 | 启动方式 | 调试方式 |
|------|----------|----------|
| FE | `start_fe.sh --daemon --debug` | Windows IDEA → Remote JVM Debug → `localhost:5005` |
| BE | `start_be.sh --daemon`（Debug 构建） | Windows CLion（WSL Toolchain）→ Attach to Process |

**完整链路**：MySQL 连 `localhost:9030` 执行 SQL → FE 在 Java 断点停住看解析/规划 → BE 在 C++ 断点停住看执行/存储，完整跟踪一条 SQL 从头到尾的源码路径。
