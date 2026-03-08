---
displayed_sidebar: docs
---

# Docker内 编译、启动、debug starrocks

适用于在 Docker 中完成 `./build.sh --fe --be` 后，在**单机**上快速启动一个 FE + 一个 BE。所有命令在**项目根目录**执行（Docker 里为 `/workspace`），部署目录为 **`output/`**。后续章节支持debug starrocks。

---

## 一、启动 FE

> **若你打算以 Debug 方式启动 FE/BE**（用 IDE 断点调试源码），请先阅读完 **「七、打通 Debug 能力」** 再操作，再按该节的 Docker 端口映射、启动方式执行，不要直接按本节命令启动。

```bash
# 1. 创建元数据目录（start_fe.sh 会把 STARROCKS_HOME 设为 output/fe，故用 output/fe/meta）
mkdir -p output/fe/meta

# 2. 设置 meta_dir（在 fe.conf 中取消注释 meta_dir，或追加一行）
#    手动编辑 output/fe/conf/fe.conf，将 “# meta_dir = ...” 改为：meta_dir = ${STARROCKS_HOME}/meta
#    或执行（若文件中尚无有效 meta_dir）：
grep -q "^meta_dir " output/fe/conf/fe.conf || echo "meta_dir = \${STARROCKS_HOME}/meta" >> output/fe/conf/fe.conf

# 3. 单 BE 时副本数设为 1
grep -q "default_replication_num" output/fe/conf/fe.conf || echo "default_replication_num = 1" >> output/fe/conf/fe.conf

# 4. 启动 FE
cd output/fe && ./bin/start_fe.sh --daemon && cd ../..

# 5. 检查（看到 thrift server started with port 9020 即成功）
cat output/fe/log/fe.log | grep thrift
```

---

## 二、启动 BE

> **若你打算以 Debug 方式启动**（例如用 gdb/gdbserver 调 BE），请先阅读完 **「七、打通 Debug 能力」**（含 BE 的 Debug 构建与端口映射），再按该节步骤操作。

```bash
# 1. 创建数据目录（start_be.sh 会把 STARROCKS_HOME 设为 output/be）
mkdir -p output/be/storage

# 2. 设置 storage_root_path（在 be.conf 中取消注释 storage_root_path，或追加一行）
#    手动编辑 output/be/conf/be.conf，将 “# storage_root_path = ...” 改为：storage_root_path = ${STARROCKS_HOME}/storage
#    或执行（若文件中尚无有效 storage_root_path）：
grep -q "^storage_root_path " output/be/conf/be.conf || echo "storage_root_path = \${STARROCKS_HOME}/storage" >> output/be/conf/be.conf

# 3. 启动 BE
cd output/be && ./bin/start_be.sh --daemon && cd ../..

# 4. 检查（看到 heartbeat has started listening port on 9050 即成功）
cat output/be/log/be.INFO | grep heartbeat
```

---

## 三、把 BE 加入集群

用 MySQL 客户端连接 FE（默认端口 9030），并添加 BE。

**Docker 内若没有 `mysql` 命令**，可任选其一：

- **在容器内安装**（需以 root 进入，例如 `docker exec -u root -it <容器名> bash` 后再执行）：
  ```bash
  apt-get update && apt-get install -y default-mysql-client
  ```
- **在宿主机执行**：若 9030 已映射到宿主机，可在本机用 `mysql -h 127.0.0.1 -P 9030 -uroot`（本机需已装 MySQL 客户端）。

```bash
# 连接 FE（Docker 内用 127.0.0.1 或本机 IP；宿主机用实际 FE 地址）
mysql -h 127.0.0.1 -P 9030 -uroot

# 在 MySQL 里执行（单机时 be_address 一般为 127.0.0.1 或本机 IP，heartbeat 端口默认 9050）：
# ALTER SYSTEM ADD BACKEND "127.0.0.1:9050";
```

```sql
-- Docker 内建议用容器网卡 IP（与 FE 日志中一致，如 172.17.0.2），否则可能 Alive: false
ALTER SYSTEM ADD BACKEND "172.17.0.2:9050";
-- 若之前误加了 127.0.0.1 且一直 CONNECTING，可先删除再加正确 IP：
-- ALTER SYSTEM DROP BACKEND "127.0.0.1:9050";
-- ALTER SYSTEM ADD BACKEND "172.17.0.2:9050";

SHOW PROC '/backends'\G
```

若 `Alive` 为 `true`，说明 BE 已加入集群。若一直 `Alive: false`、`StatusCode: CONNECTING`，见下方「六、若启动报错」中的说明。

---

## 四、试用 StarRocks（MySQL 命令行）

### 4.1 简单 SQL 试用

在 mysql 命令行里直接执行以下 SQL 即可体验建库、建表、插入和查询：

```sql
-- 建库
CREATE DATABASE IF NOT EXISTS demo;
USE demo;

-- 建表（主键模型，适合有主键的明细/更新场景）
CREATE TABLE IF NOT EXISTS t1 (
    id      BIGINT NOT NULL,
    name    VARCHAR(100),
    ts      DATETIME DEFAULT CURRENT_TIMESTAMP
)
PRIMARY KEY (id)
DISTRIBUTED BY HASH(id) BUCKETS 1
PROPERTIES ("replication_num" = "1");

-- 插入
INSERT INTO t1 (id, name) VALUES (1, 'a'), (2, 'b'), (3, 'c');

-- 查询
SELECT * FROM t1 ORDER BY id;
```

如需更多表类型和语法，可参考官方文档 [StarRocks SQL 参考](https://docs.starrocks.io/docs/sql-reference/sql-statements/)。

---

## 五、常用命令小结

| 操作       | 命令 |
|------------|------|
| 启动 docker | `docker start starrocks-dev` |
| 进入已启动的docker | `docker exec -it starrocks-dev bash` |
| 启动 docker ssh服务 | `docker exec starrocks-dev service ssh start` |
| 启动 FE    | `cd output/fe && ./bin/start_fe.sh --daemon` |
| 启动 BE    | `cd output/be && ./bin/start_be.sh --daemon` |
| 停 FE      | `output/fe/bin/stop_fe.sh` |
| 停 BE      | `output/be/bin/stop_be.sh` |
| 连库       | `mysql -h 127.0.0.1 -P 9030 -uroot` |

---

## 六、若启动报错

- **FE**：看 `output/fe/log/fe.warn.log`。
- **BE**：看 `output/be/log/be.WARNING`。
- **Docker 内报错 `id: cannot find name for user ID 501`**：因容器用 host 的 UID 运行，没有对应用户名。已在 `conf/hadoop_env.sh` 中做兼容（`id -u -n` 失败时用 `starrocks`）。FE 和 BE 都会 source 该脚本：若你用的是旧产出，可手动改 **`output/fe/conf/hadoop_env.sh`** 与 **`output/be/conf/hadoop_env.sh`**，把 `$(id -u -n)` 改为 `$(id -u -n 2>/dev/null) || echo "starrocks"`，或先执行 `export HADOOP_USER_NAME=starrocks` 再启动 FE/BE。
- 若提示需配置 **priority_networks**：在 `fe.conf` 或 `be.conf` 中加上本机网段，例如：  
  `priority_networks = 127.0.0.1/24` 或本机实际 IP 的 CIDR（如 `192.168.1.0/24`）。
- **BE 已添加但 `Alive: false`、`StatusCode: CONNECTING`**：  
  1) **地址不一致**：Docker 内 BE 未配 `priority_networks` 时，会用容器 IP（如 172.17.0.2）。若用 `127.0.0.1:9050` 添加，FE 与 BE 对不上，会一直 CONNECTING。解决：在 MySQL 里执行 `ALTER SYSTEM DROP BACKEND "127.0.0.1:9050";`，再 `ALTER SYSTEM ADD BACKEND "172.17.0.2:9050";`（IP 以 FE 日志中出现的为准）。  
  2) **BE 未真正起来**：若曾因 `id: cannot find name for user ID 501` 导致脚本报错，有可能脚本在 fork 出 BE 进程后才报错，BE 已在跑但状态异常。解决：先执行 `output/be/bin/stop_be.sh`，确认已停（`ps aux | grep starrocks_be` 无残留），再执行 `./output/be/bin/start_be.sh --daemon`，等几秒后用 `172.17.0.2:9050` 添加并查看 `SHOW PROC '/backends'\G`。

更完整的配置与多节点部署见 [手动部署 StarRocks](./deploy_manually.md)。

---

## 七、打通 Debug 能力（便于阅读源码）

目标：用 IDE 断点调试 FE（Java）和 BE（C++），配合 MySQL 执行 SQL，在断点处查看调用栈、变量，从而理解 SQL 执行路径与源码。

### 7.1 前置：Docker 启动

若你是在 **Docker 容器内** 启动 FE/BE，宿主机要连 MySQL 或做远程调试，需要把对应端口映射出来。FE/BE 常用端口如下（与 `SHOW PROC '/frontends'`、`SHOW PROC '/backends'` 一致）：

| 端口 | 用途 | 宿主机是否需要映射 |
|------|------|--------------------|
| **9030** | FE QueryPort，MySQL 客户端连接用 | **必须**（否则宿主机无法 `mysql -h 127.0.0.1 -P 9030`） |
| **5005** | FE 远程调试 JDWP（仅 `start_fe.sh --debug` 时监听） | **要调试 FE 时必须** |
| **2222→22** | SSH（CLion Remote Development 连接容器用） | 用 CLion Remote Development 调 BE 时需要 |
| **1234** | BE 远程调试 gdbserver（仅手动起 gdbserver 时用） | 仅用 gdbserver 调 BE 时需要 |
| 9020 | FE RpcPort（FE 内部/Thrift） | 一般不需要 |
| 9010 | FE EditLogPort（元数据同步） | 一般不需要 |
| 8030 | FE HttpPort（HTTP 管理/监控） | 需要从宿主机访问 FE Web 时再映射 |
| 9050 | BE HeartbeatPort（FE 心跳） | 容器内 FE↔BE 用，宿主机不需 |
| 9060 | BE BePort | 容器内用，宿主机不需 |
| 8040 | BE HttpPort | 需要从宿主机访问 BE HTTP 时再映射 |
| 8060 | BE BrpcPort | 容器内用，宿主机不需 |

**推荐做法：**

- **只跑 MySQL + FE 断点调试**：映射 **9030**（MySQL）和 **5005**（JDWP）即可。
- **用 CLion Remote Development 调 BE**（推荐）：再加 **2222→22**（SSH）和 `--cap-add=SYS_PTRACE`。
- **用 gdbserver 调 BE**（备选）：再加 **1234**。
- 若需从宿主机打开 FE/BE 的 Web 页面，再按需加 **8030**、**8040**。

**最小映射（MySQL + FE Debug）：**

```bash
docker run -it \
  -v "$(pwd):/workspace" -w /workspace \
  -p 9030:9030 \
  -p 5005:5005 \
  --name starrocks-dev \
  starrocks/dev-env-ubuntu:latest \
  /bin/bash
```

**含 CLion Remote Development 的完整示例（推荐）：**

```bash
docker run -it \
  -v "$(pwd):/workspace" -w /workspace \
  -p 9030:9030 -p 5005:5005 \
  -p 2222:22 \
  -p 8030:8030 -p 8040:8040 \
  --cap-add=SYS_PTRACE \
  --name starrocks-dev \
  starrocks/dev-env-ubuntu:latest \
  /bin/bash
```

> `--cap-add=SYS_PTRACE` 允许 GDB 附加到进程（Attach to Process 需要此权限）。`-p 2222:22` 将容器的 SSH 端口映射到宿主机 2222，供 CLion Remote Development 连接。

**含 gdbserver 的示例（备选）：**

```bash
docker run -it \
  -v "$(pwd):/workspace" -w /workspace \
  -p 9030:9030 -p 5005:5005 -p 1234:1234 \
  -p 8030:8030 -p 8040:8040 \
  --cap-add=SYS_PTRACE \
  --name starrocks-dev \
  starrocks/dev-env-ubuntu:latest \
  /bin/bash
```

**在windows的Git Bash (MINGW64)环境上执行**

```bash
MSYS_NO_PATHCONV=1 docker run -it \
  -v "$(pwd):/workspace" -w /workspace \
  -p 9030:9030 -p 5005:5005 \
  -p 2222:22 \
  -p 8030:8030 -p 8040:8040 \
  --cap-add=SYS_PTRACE \
  --name starrocks-dev \
  starrocks/dev-env-ubuntu:latest \
  /bin/bash
```

之后在容器内按下面步骤启动带 Debug 的 FE/BE，在宿主机用 MySQL 连 9030、IDE 连 5005 即可。

**docker安装starrocks/dev-env-ubuntu:latest镜像很慢**

可以考虑使用镜像源，在docker desktop的配置类似如下。镜像源不稳定，这里不做推荐，网上搜，试着用
```
{
  "builder": {
    "gc": {
      "defaultKeepStorage": "20GB",
      "enabled": true
    }
  },
  "experimental": false,
  "registry-mirrors": [
    "https://docker.1ms.run"
  ]
}
```

**docker pull中途主动退出后再次pull卡在Pulling fs layer的问题**

```
# 删掉之前创建的容器
docker rm starrocks-dev 2>/dev/null

# 清理未完成的下载缓存
docker system prune -f

# 测试能否连接 Docker Hub
docker pull hello-world

# 重新拉取
docker pull starrocks/dev-env-ubuntu:latest
```

### 7.2 FE Debug（Java：IntelliJ IDEA 远程断点）

推荐使用 **IntelliJ IDEA** 做 FE 远程调试：FE 已支持 **JDWP**，无需改代码。

1. **以 Debug 模式启动 FE**

   - 若当前 FE 在运行，先停止：`output/fe/bin/stop_fe.sh`
   - 启动时加上 `--debug`（保留 `--daemon` 亦可）：

   ```bash
   cd output/fe && ./bin/start_fe.sh --daemon --debug && cd ../..
   ```

   - 日志里会出现类似：`Start debugger with: ... -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005`，表示已在 **5005** 端口监听调试连接。

2. **IDEA 附加到 FE（Remote JVM Debug）**

   - **Run → Edit Configurations → + → Remote JVM Debug**
   - Host 填 `127.0.0.1`，Port 填 `5005`，保存。
   - 点击 Debug 连接。若 FE 在 Docker 内且已映射 `-p 5005:5005`，即可从宿主机连上。

3. **使用方式**

   - 用 MySQL 客户端连接 StarRocks（`mysql -h 127.0.0.1 -P 9030 -uroot`），执行任意 SQL。
   - 在 IDEA 里打开 FE 源码（如 `fe/fe-core` 下的 Java 文件），在需要的位置打断点。
   - 当请求命中断点时会暂停，可查看调用栈、变量、单步执行。

4. **首次 Debug 推荐断点位置**

   任意一条 SELECT 都会经过以下位置（例如执行 `select * from t1` 时会停住）：

   | 文件 | 行号 | 说明 |
   |------|------|------|
   | `fe/fe-core/src/main/java/com/starrocks/qe/StmtExecutor.java` | **807** | `execute()` 入口，可看调用栈（`ConnectProcessor.handleQuery` → `StmtExecutor.execute`）及变量 `context`、`parsedStmt`。 |
   | `fe/fe-core/src/main/java/com/starrocks/qe/ConnectProcessor.java` | **366** | 客户端发来的 SQL 转成字符串处，可查看 `originStmt`。 |

   **操作步骤**：IDEA 中打开上述文件并在对应行设断点 → 用 Remote JVM Debug 连上 5005 → MySQL 执行 `use demo;` 再 `select * from t1;` → 程序会在断点处暂停。

**小结**：FE 用 `--debug` 启动 → 暴露 5005（Docker 需映射）→ IDEA Remote JVM Debug 连接 → MySQL 发 SQL → 在断点处看栈与变量。

### 7.3 BE Debug（C++：CLion / gdb）

BE 是 C++ 进程，需要**带符号的 Debug 构建**，再用 IDE 或 gdb 调试。

#### 7.3.1 Debug 构建 BE

Release 构建会 strip 符号，断点与变量查看效果差。建议单独做一次 Debug 构建：

```bash
# 在项目根目录（Docker 内即 /workspace）
BUILD_TYPE=Debug ./build.sh --be
```

构建完成后，`output/be/lib/starrocks_be` 会变为 Debug 版（体积更大、带完整符号）。若你平时用 Release 跑，可备份后再替换，或单独用一份 output 目录做调试。

#### 7.3.2 方式一：CLion Remote Development（推荐）

使用 JetBrains 的 **Remote Development** 功能，让 CLion 后端（包括 GDB）直接运行在 Docker 容器内，宿主机只跑轻量客户端 UI。优点：

- GDB 在容器内直接附加进程，**无需 gdbserver**，无需传输 2GB+ 的调试符号
- 源码和调试符号在同一文件系统，**无需 Path mapping**
- 代码导航、断点、变量查看都在容器内完成，macOS/Linux 宿主机均可用

**前提**：Docker 启动时需加 `--cap-add=SYS_PTRACE`（允许 GDB 附加进程）和 `-p 2222:22`（SSH 端口映射），见 7.1 节的 Docker 启动示例。

**Step 1：容器内安装并启动 SSH 服务**

```bash
# 在容器内执行
apt-get update && apt-get install -y openssh-server
echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
echo 'root:your_password' | chpasswd
service ssh start
```

> 建议完成后用 `docker commit` 保存镜像，避免每次重装：
> ```bash
> # 宿主机执行
> docker commit starrocks-dev starrocks-dev-with-ssh
> ```
> 后续用 `starrocks-dev-with-ssh` 镜像创建容器即可。每次启动容器后仍需执行 `service ssh start`。

**Step 2：宿主机通过 CLion 连接容器**

1. 打开 CLion → **File → Remote Development → SSH**（或通过 JetBrains Gateway）。
2. 新建 SSH 连接：Host `127.0.0.1`，Port `2222`，Username `root`，Password 为上一步设置的密码。
3. 连接成功后，**IDE version** 选择 CLion。若容器无法访问外网导致下拉列表为空，点击 **Installation options... → Upload installer file**，从 [JetBrains 官网](https://www.jetbrains.com/clion/download/#section=linux) 下载 Linux x86_64 的 `.tar.gz` 安装包，上传到容器。
4. **Project directory** 填 `/workspace`。
5. 点击连接，等待 CLion 后端启动（首次需 1-2 分钟）。

**Step 3：配置 CMake（让 CLion 识别 BE 源码）**

在远程 CLion 窗口中：

1. **Settings → Build, Execution, Deployment → CMake**。
2. 编辑 Default profile（或新建）：
   - **Build type**：`Debug`
   - **Environment**：添加 `STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/opt/gcc-toolset-14`
     - `STARROCKS_CLION_ONLY=1`：让 CMake 只生成代码导航用的 target，跳过 thirdparty 和 gensrc 构建
     - `STARROCKS_GCC_HOME`：指定 GCC 安装路径，CMake 会使用 `$STARROCKS_GCC_HOME/bin/gcc`。在 `starrocks/dev-env-ubuntu` 镜像中为 `/opt/gcc-toolset-14`（可通过 `readlink -f $(which gcc)` 确认）
3. 点 Apply/OK。
4. 在项目树中找到 `be/CMakeLists.txt`，**右键 → Load CMake Project**。
5. 等待 CMake 配置完成（CLION_ONLY 模式下很快，十几秒内完成）。

> `STARROCKS_CLION_ONLY=1` 会让 CMake 只生成一个包含全部 BE 源码的 `starrocks_be` target，不依赖 thirdparty，仅用于代码导航和断点。CLion 不会真正编译 BE。

**Step 4：启动 BE 并 Attach 调试**

1. 在 CLion 底部的 **Terminal** 中启动 Debug 版 BE：

   ```bash
   cd /workspace/output/be-debug && ./bin/start_be.sh --daemon
   ```

2. 确认 BE 已启动：`ps aux | grep starrocks_be`。
3. **Run → 附加到进程...**（Attach to Process），在列表中选择 `starrocks_be`，点击「使用 捆绑的 GDB 附加」。
4. 打开 BE 源码文件，设置断点（应显示为红色实心圆），用 MySQL 发 SQL 即可触发。

**执行 `SELECT * FROM t1` 时 BE 必经过的推荐断点：**

| 文件 | 行号 | 说明 |
|------|------|------|
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` | **797** | `_read_chunk_from_storage` 入口，每次从存储读 chunk 都会经过 |
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` | **803** | `_prj_iter->get_next(chunk)`，实际读取数据 |

**常见问题：**

- **BE 启动时 SIGABRT（DataCache 相关）**：在 `output/be-debug/conf/be.conf` 中加一行 `datacache_enable = false`，调试结束后可删除。
- **CLion 很卡（CPU/内存占用高）**：首次打开项目时 CLion 会索引全部源码，等索引完成后会明显好转。可在 **Settings → Build, Execution, Deployment → Clangd** 中降低并发线程数。建议机器配置不低于 8 核 16GB。
- **下次如何重新打开**：启动容器 → `docker exec starrocks-dev service ssh start` → 打开 CLion/Gateway → 点击历史记录中的 `/workspace` 即可重连，无需重新安装。

#### 7.3.3 方式二：gdbserver + 宿主机 CLion（GDB Remote Debug）

若机器资源不足以跑 CLion Remote Development，或需要在宿主机本地使用 CLion，可用 gdbserver 方案。此方式下 GDB 客户端运行在宿主机，通过网络连接容器内的 gdbserver。

**前提**：Docker 启动时需映射 `-p 1234:1234`（gdbserver 端口）。

**1. 容器内启动 gdbserver**

项目内提供了 `run_gdbserver.sh`，会设置与 `start_be.sh` 一致的环境（JAVA_HOME、LD_LIBRARY_PATH、be.conf 等），避免直接 `gdbserver ... starrocks_be` 时出现 libjvm 找不到或 `basic_string: construction from null`。

```bash
# Debug 构建的 BE
/workspace/output/be-debug/bin/run_gdbserver.sh
```

若启动后出现 **SIGABRT**（栈里有 DataCache/StarCache），在 `output/be-debug/conf/be.conf` 中加 `datacache_enable = false` 后重试。

若需后台跑：`nohup /workspace/output/be-debug/bin/run_gdbserver.sh > /tmp/gdbserver.log 2>&1 &`

**2. 宿主机 CLion 配置**

在 CLion 里：**Run → Edit Configurations → + → GDB Remote Debug**，设置：
- **Remote host**: `127.0.0.1`，**Port**: `1234`
- **Symbol file**: 指向宿主机上的 `output/be-debug/lib/starrocks_be`（约 2GB，大文件加载较慢）

**3. CMake 配置（解决「This file does not belong to any project target」）**

在宿主机 CLion 中打开 BE 源码文件可能提示文件不属于任何 target。解决方式：

在 **Settings → Build, Execution, Deployment → CMake** 的 **Environment** 里添加：
- `STARROCKS_CLION_ONLY=1`
- macOS：`CC=/usr/bin/clang`、`CXX=/usr/bin/clang++`
- Linux：`STARROCKS_GCC_HOME=/usr`

然后右键 `be/CMakeLists.txt` → Load CMake Project。配置成功后断点即可正常使用。

**4. 断点变灰（Path mapping）**

若断点先红后灰，是源码路径不一致：二进制在容器内编译，调试信息中记录的是容器路径；宿主机 CLion 用的是本地路径。

在 GDB Remote Debug 配置的 **Path mappings** 中添加：
- **Local path**：宿主机 BE 源码目录，例如 `/Users/你的用户名/my-project/starrocks/be`
- **Remote path**：`/workspace/be/build_Debug/be`（由 CMake 的 `-ffile-prefix-map` 决定，该目录不需要在容器中真实存在）

保存后重新连接即可。

#### 7.3.4 方式三：容器内 gdb 命令行调试

不依赖 IDE，适合快速排查或无图形界面的场景。

**Attach 模式（推荐）**：先启动 BE，再用 gdb 附加：

```bash
# 安装 gdb（若镜像没有）
apt-get update && apt-get install -y gdb

# 启动 BE
cd /workspace/output/be-debug && ./bin/start_be.sh --daemon && cd /workspace

# 查 PID 并附加
ps aux | grep starrocks_be
gdb -p <PID>

# 在 gdb 中
(gdb) break starrocks::SomeClass::some_method
(gdb) continue
```

用 MySQL 发 SQL 触发逻辑后，gdb 会在断点处停住。查看调用栈：`bt`，单步：`n`/`s`，退出：`detach` 再 `quit`。

**前台模式**：适合从启动就单步的场景。修改 `start_backend.sh` 中非 daemon 分支，将 `exec ${START_BE_CMD}` 改为 `exec gdb -tui --args ${START_BE_CMD}`，然后 `./bin/start_be.sh`（不加 `--daemon`）。

> 若调试湖仓相关代码时 SIGSEGV 被 gdb 误拦，可在 `~/.gdbinit` 里加：`handle SIGSEGV nostop noprint pass`。

### 7.4 推荐组合（Docker 内 FE + BE）

| 组件 | 启动方式 | 调试方式 |
|------|----------|----------|
| FE   | `./bin/start_fe.sh --daemon --debug` | 宿主机 IDEA Remote JVM Debug → 5005，在 Java 源码打断点 |
| BE   | `./bin/start_be.sh --daemon`（Debug 构建） | CLion Remote Development → Attach to Process（推荐），或 gdbserver + 宿主机 CLion |

这样你可以：MySQL 连 9030 执行 SQL → FE 侧在 Java 断点停住看解析/规划 → BE 侧在 C++ 断点停住看执行/存储，从而完整跟踪一句 SQL 的源码路径。
