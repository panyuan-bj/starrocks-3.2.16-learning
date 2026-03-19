# WSL vs Docker for StarRocks development
_Exported on 3/8/2026 at 11:13:15 GMT+8 from Cursor (2.3.35)_

---

**User**

请阅读文档：/home/peter/my-project/starrocks/docs/zh/learning/starrocks编译启动源码debug总结.md

我是用docker环境来执行文档中的流程并同步记录下文档的，之前starrocks源码目录是在windows磁盘下，启动了一个docker，docker中的/worksapce目录改在到了windows磁盘下的starrocks目录，现在我觉得这样子不是我最预期的，我希望使用wsl环境，在wsl的home目录下，又放置了一个starrocks目录：/home/peter/my-project/starrocks，我准备重新开始编译、运行、源码debug这个过程

但就在我开始时，我发现一个问题，既然我都已经在wsl（linux）环境下了，我为什么还要弄一个docker呢？但是我仔细一想，wsl与docker还是有区别的

1、docker是一个方便植移的容器，我以后可能可以上传到docker云空间中，在其他地方使用（虽然这个需求可能性很小），用wsl无法做到这一点；

2、我在wsl上万一搞坏了什么，不太方便做恢复，但是在docker环境上如何搞坏了，可以再启动一个docker（但我肯定希望不要搞坏，也会注意）；

3、我可以给docker分配cpu和内存占比，能观察到使用情况，但wsl中也可以使用linu命令来查看cpu和内存占比情况，应该也可以分配cpu和占比吧（我理解wsl本质上也是一种虚环境，在windows上运行的linux虚环境，是吧？）

我后续长期肯定是在这台电脑上学习starrocks源码，暂时没有其他电脑的诉求，我会及时备份新产生的文件，还会传到我个人git仓库中，如果以后更换了电脑，我会在新电脑上（估计还是windows + wsl这种使用方式）重新编译部署starrocks，重新使用我备份的文件

在我上述的背景和思考下，我想请你帮我判断一下，我是不是用wsl环境就够了，我不需要再wsl基础上再弄docker来学习starrocks？请给出我详细的思考和优劣对别说明

---

**Cursor**

我已经完整阅读了你的文档。现在基于你的背景和需求来做一个详细分析。

---

## 结论：WSL 环境完全够用，不需要再套 Docker

基于你描述的场景，**直接在 WSL 上编译、运行、调试 StarRocks 即可，不需要再在 WSL 里面套一层 Docker**。下面是详细的分析：

---

### 一、逐一回应你提到的三个顾虑

#### 顾虑1：Docker 可以上传到云空间，方便迁移

**你自己也说了"这个可能性很小"**——的确如此。StarRocks 的开发环境（编译产出 + thirdparty + Debug 符号）体积非常大（轻松超过 10GB），上传到 Docker Hub 非常慢且不太实用。更关键的是，**你的核心资产不是"环境"，而是你写的笔记、配置、脚本等文件**——这些你会传到 Git 仓库里备份。

换了新电脑后，在新 WSL 上重新跑一次 `./build.sh --fe --be` 就能恢复编译环境，比拖一个巨大的 Docker 镜像要务实得多。

**结论：这个优势在你的场景下几乎不存在。**

#### 顾虑2：WSL 搞坏了不好恢复，Docker 可以随时新起一个

这是个合理的担心，但实际风险很低：

- StarRocks 的编译和运行，操作范围限定在项目目录下（`/home/peter/my-project/starrocks`），不会触碰系统文件。
- WSL 本身也支持**导出/导入**（`wsl --export` / `wsl --import`），如果真的很担心，可以在配好环境后做一次快照备份。
- 万一真搞坏了 WSL（极低概率），Windows 上可以直接 `wsl --unregister` 再重装，几分钟搞定。
- 反过来说，Docker 在 WSL 里跑也有可能出问题（Docker Desktop + WSL2 本身就是一层套一层，反而增加了复杂度和出问题的概率）。

**结论：WSL 的可恢复性并不比 Docker 差，且出问题的概率本身就很低。**

#### 顾虑3：资源分配和监控

你的理解是正确的——**WSL2 本质上就是一个轻量级的 Linux 虚拟机**（基于 Hyper-V），运行一个真正的 Linux 内核。

- **资源监控**：WSL 里可以直接用 `top`、`htop`、`free -h`、`df -h` 等标准 Linux 命令。
- **资源限制**：可以通过 Windows 用户目录下的 `.wslconfig` 文件来限制 WSL 的 CPU 和内存：
  ```ini
  # 文件位置：C:\Users\你的用户名\.wslconfig
  [wsl2]
  memory=16GB
  processors=8
  ```
- Docker 在 WSL2 上跑时，本质上也是在这同一个 WSL2 虚拟机里运行的，Docker 的资源限制也受限于 WSL2 分配的资源，**套了 Docker 并不会让资源管理更好，反而多了一层开销**。

**结论：WSL 完全具备资源监控和限制能力，Docker 在这方面没有额外优势。**

---

### 二、全面的优劣对比

| 维度 | 直接用 WSL | WSL + Docker |
|------|-----------|--------------|
| **性能** | ✅ **直接跑在 Linux 内核上，零额外开销**。编译速度最快 | ❌ 多一层容器抽象，I/O 有轻微开销 |
| **磁盘 I/O** | ✅ **WSL 的 ext4 文件系统，性能很好**（比你之前把代码放 Windows 磁盘上用 Docker 挂载进去要快得多） | ⚠️ Docker volume 挂载有性能损耗，尤其是跨文件系统时 |
| **IDE 调试体验** | ✅ **IDE 可以直接连 WSL**（VSCode Remote-WSL、IDEA 直接打开 WSL 路径、CLion 直接用 WSL toolchain）。**无需端口映射、无需 SSH、无需 gdbserver** | ❌ 需要配端口映射（9030/5005/2222 等），FE Debug 需要映射 5005，BE Debug 需要 SSH+远程开发或 gdbserver+path mapping，配置复杂 |
| **端口访问** | ✅ WSL 中启动的服务，Windows 上可以直接通过 `localhost:端口` 访问（WSL2 自动转发） | ❌ 需要手动 `-p` 映射每个端口 |
| **环境一致性** | ✅ WSL 是一个完整的 Ubuntu（或其他发行版），可以直接 `apt install` 安装编译依赖 | ✅ Docker 用 `starrocks/dev-env-ubuntu` 镜像，依赖已预装 |
| **编译依赖安装** | ⚠️ 需要自己安装编译依赖（GCC、JDK、Maven、CMake 等），StarRocks 有文档指导 | ✅ 官方镜像已预装 |
| **环境隔离** | ⚠️ 如果你在 WSL 里还跑其他项目，理论上有环境冲突风险（但实际上 StarRocks 的依赖不太会冲突） | ✅ 容器完全隔离 |
| **复杂度** | ✅ **少一层，少一类问题**。不用管 Docker 的端口映射、volume 挂载、`--cap-add=SYS_PTRACE`、SSH 服务等 | ❌ 你的文档里大量篇幅在处理 Docker 相关的配置问题（SSH、端口映射、容器 IP、镜像加速等） |
| **可迁移性** | ⚠️ 不能直接迁移到其他机器，需重新搭建 | ✅ Docker 镜像可导出/推送 |
| **多版本切换** | ⚠️ 同一 WSL 下切换不同 GCC/JDK 版本稍麻烦 | ✅ 不同镜像可以隔离不同版本 |

---

### 三、WSL 方案的关键优势（你的场景下特别突出）

1. **Debug 体验大幅简化**：
   - **FE Debug**：WSL 里启动 `start_fe.sh --debug`，Windows 上 IDEA 直接连 `localhost:5005`，无需任何端口映射配置。
   - **BE Debug**：CLion 可以直接用 WSL Toolchain（无需 Remote Development + SSH），也可以在 WSL 里直接 `gdb -p <PID>`。VSCode + C/C++ 扩展也可以直接 Attach。
   - **你文档里七.1~七.3 中大量关于 Docker 端口映射、SSH 配置、gdbserver 配置的内容，在 WSL 方案下全部不需要**。

2. **文件系统性能**：你现在代码已经在 WSL 的 home 目录下（`/home/peter/my-project/starrocks`），这是 WSL 原生的 ext4 文件系统，I/O 性能远好于从 Windows 磁盘挂载到 Docker（你之前的方案）。如果再套 Docker，要么用 volume 挂载（有性能损耗），要么把代码复制到容器内（浪费空间且不方便同步）。

3. **开发流程更直接**：编辑代码 → 编译 → 启动 → 调试，整个链路都在同一个 Linux 环境里，减少了心智负担。

---

### 四、WSL 方案唯一需要额外做的事

唯一的代价是：**你需要在 WSL 里自己安装 StarRocks 的编译依赖**（而不是用 `starrocks/dev-env-ubuntu` 镜像里预装的）。

但这并不困难，StarRocks 官方有明确的依赖列表。你的 WSL 如果是 Ubuntu，大致需要：

```bash
# 基础工具
sudo apt-get update
sudo apt-get install -y gcc g++ cmake make maven openjdk-17-jdk python3 python3-pip \
    autoconf automake binutils-dev bison byacc flex libiberty-dev libtool \
    zip unzip bzip2 ccache git patch lsof wget curl

# 或者更简单的方式：参考 StarRocks 的 thirdparty 构建脚本来安装
```

StarRocks 仓库中通常有 `build-support/` 或文档说明需要的依赖。你也可以参考 `starrocks/dev-env-ubuntu` 的 Dockerfile 来看它安装了什么。

---

### 五、最终建议

> **直接用 WSL，不再套 Docker。**

理由总结：
1. 你是**长期在这台电脑上学习源码**，不需要环境迁移。
2. 你会**备份文件到 Git**，核心资产不丢。
3. WSL 下 Debug 链路**大幅简化**（去掉所有端口映射和 SSH 配置）。
4. **性能最优**（原生 ext4，零容器开销）。
5. **复杂度最低**（少一层 Docker = 少一类问题）。

唯一建议：配好环境后，执行一次 `wsl --export` 做个快照，这样万一出问题可以快速恢复，功能上等价于 Docker 的"重建容器"。

```ini
  # 文件位置：C:\Users\你的用户名\.wslconfig
  [wsl2]
  memory=16GB
  processors=8
```

```shellscript
# 基础工具
sudo apt-get update
sudo apt-get install -y gcc g++ cmake make maven openjdk-17-jdk python3 python3-pip \
    autoconf automake binutils-dev bison byacc flex libiberty-dev libtool \
    zip unzip bzip2 ccache git patch lsof wget curl

# 或者更简单的方式：参考 StarRocks 的 thirdparty 构建脚本来安装
```

---

**User**

行，我决定选择wsl2

在你的说辞中，有一句话我很重视，即：BE Debug：CLion 可以直接用 WSL Toolchain（无需 Remote Development + SSH），也可以在 WSL 里直接 gdb -p <PID>。VSCode + C/C++ 扩展也可以直接 Attach

这一步对我来说需要做一下尝试和验证，我才能确信是没问题的。因为我必须要能debug，否则只阅读源码我觉得意义不大，我必须要能看到运行时的信息，我很注重这个

我重新建立了一份文档：/home/peter/my-project/starrocks/docs/zh/learning/在wsl2上进行starrocks编译启动源码debug总结.md

你可否基于你的理解，帮我先书写一些这篇新文档的内容，即不用docker了，而是用wsl2环境来完成同样的事情

对于新文档的内容我有些要求，我希望读者能够按照阅读顺序来完成操作，老文档我是改了好多次的结果，对“按阅读顺序操作”这个点不太友好，我自己能看懂，但分享给别人可能就有些阅读上的吃力了

因此请保证这个要求，文档中自然也要体现清晰的步骤：一、二、三...，做的事情范围与老文档一样，不要少，比如不能只有编译和启动，没有debug。关于debug要说明如何操作（用wsl toolchain）

文档请简洁一些，不要冗长。我会阅读文档，并在wsl2环境里验证操作，然后逐步修改或补充文档的内容细节。谢谢你

---

**Cursor**



让我先看一下新文档当前的内容，以及老文档的完整结构，确保不遗漏。

现在我来看一下 StarRocks 仓库里是否有编译依赖安装的参考脚本或文档，以便在新文档中给出准确的 WSL 依赖安装指引。

现在我已经充分了解了所有信息，可以编写新文档了。

```markdown
---
displayed_sidebar: docs
---

# WSL2 上编译、启动、Debug FE & BE

在 WSL2（Ubuntu）中完成 StarRocks 的编译、单机启动（1 FE + 1 BE）、以及 FE/BE 源码断点调试。所有命令在**项目根目录** `/home/peter/my-project/starrocks` 下执行，部署目录为 **`output/`**。

与 Docker 方案相比，WSL2 方案**不需要端口映射、不需要 SSH、不需要 gdbserver**，IDE 直接连接本地进程即可调试。

---

## 一、安装编译依赖

> 仅首次搭建环境时需要，后续不必重复。

```bash
sudo apt-get update

# 基础工具和编译器
sudo apt-get install -y automake binutils-dev bison byacc ccache flex libiberty-dev libtool \
    maven zip python3 python-is-python3 cmake gcc g++ default-jdk git patch lld bzip2 \
    wget unzip curl make build-essential ninja-build

# 设置 JAVA_HOME（加入 ~/.bashrc 或 ~/.zshrc 以持久化）
export JAVA_HOME=/usr/lib/jvm/default-java
```

验证关键版本：

```bash
gcc --version    # 需 >= 10.3
java --version   # 需 >= 8
cmake --version  # 需 >= 3.20.1
mvn --version
```

---

## 二、编译

```bash
cd /home/peter/my-project/starrocks

# 编译 FE + BE（首次会自动编译 thirdparty，耗时较长）
./build.sh --fe --be
```

> 可用 `-j N` 指定并行度，如 `./build.sh --fe --be -j 8`。
>
> 若只需 Debug BE，另做一次 Debug 构建（见「六、Debug BE」）。编译成功后产出在 `output/fe` 和 `output/be`。

---

## 三、启动 FE

```bash
# 1. 创建元数据目录
mkdir -p output/fe/meta

# 2. 配置 meta_dir
grep -q "^meta_dir " output/fe/conf/fe.conf || echo "meta_dir = \${STARROCKS_HOME}/meta" >> output/fe/conf/fe.conf

# 3. 单 BE 副本数设为 1
grep -q "default_replication_num" output/fe/conf/fe.conf || echo "default_replication_num = 1" >> output/fe/conf/fe.conf

# 4. 启动（若需 Debug FE，改用 --debug，见「五、Debug FE」）
cd output/fe && ./bin/start_fe.sh --daemon && cd ../..

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
cat output/be/log/be.INFO | grep heartbeat
```

### 4.2 把 BE 加入集群

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

FE 是 Java 进程，使用 JDWP 远程调试，**无需改代码**。

### 5.1 以 Debug 模式启动 FE

```bash
# 先停掉已运行的 FE（若有）
output/fe/bin/stop_fe.sh

# 加 --debug 启动
cd output/fe && ./bin/start_fe.sh --daemon --debug && cd ../..
```

日志中出现 `address=*:5005` 即表示调试端口已监听。

### 5.2 IDEA 连接

1. **Run → Edit Configurations → + → Remote JVM Debug**
2. Host `localhost`，Port `5005`，保存并点击 Debug。
3. WSL2 中的 5005 端口可直接从 Windows 访问（WSL2 自动转发），无需额外配置。

### 5.3 打断点验证

在 IDEA 中打开 FE 源码，推荐断点：

| 文件 | 说明 |
|------|------|
| `fe/fe-core/src/main/java/com/starrocks/qe/StmtExecutor.java` 的 `execute()` 方法 | SQL 执行入口，可看 `context`、`parsedStmt` |
| `fe/fe-core/src/main/java/com/starrocks/qe/ConnectProcessor.java` 的 `handleQuery` | 客户端发来的 SQL 字符串 |

用 MySQL 执行 `SELECT * FROM demo.t1;`，程序会在断点处暂停。

---

## 六、Debug BE（C++：CLion + WSL Toolchain）

BE 是 C++ 进程，需要 **Debug 构建**（带完整符号），再用 CLion 的 **Attach to Process** 调试。

### 6.1 Debug 构建 BE

```bash
cd /home/peter/my-project/starrocks

# Debug 构建（产出默认仍在 output/be，体积更大）
BUILD_TYPE=Debug ./build.sh --be
```

> 若想保留 Release 版 BE，可在构建前备份 `output/be`，或构建后将 Debug 版移到 `output/be-debug`。

### 6.2 启动 Debug 版 BE

```bash
mkdir -p output/be/storage
grep -q "^storage_root_path " output/be/conf/be.conf || echo "storage_root_path = \${STARROCKS_HOME}/storage" >> output/be/conf/be.conf

# 若遇 SIGABRT（DataCache 相关），加上这行：
# echo "datacache_enable = false" >> output/be/conf/be.conf

cd output/be && ./bin/start_be.sh --daemon && cd ../..
```

### 6.3 CLion 配置 WSL Toolchain

CLion 原生支持 WSL Toolchain，**IDE 运行在 Windows 上，编译/调试在 WSL 内执行，无需 SSH 配置**。

1. 打开 CLion（Windows 版） → **File → Open** → 打开 `\\wsl$\Ubuntu\home\peter\my-project\starrocks` 下的项目（或直接打开 WSL 路径）。

2. **Settings → Build, Execution, Deployment → Toolchains**：
   - 点 **+** → 选 **WSL**，CLion 会自动检测到你的 WSL 发行版。
   - 确认 CMake、C Compiler、C++ Compiler 均显示绿色勾（自动从 WSL 中检测）。

3. **Settings → Build, Execution, Deployment → CMake**：
   - **Build type**：`Debug`
   - **Toolchain**：选上一步添加的 WSL toolchain
   - **Environment**：添加 `STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr`
     - `STARROCKS_CLION_ONLY=1`：只生成代码导航用的 target，不真正编译，配置速度很快
     - `STARROCKS_GCC_HOME`：指定 GCC 路径（WSL 上通过 apt 安装的 GCC 在 `/usr`）
   - 取消勾选 **Include system environment variables**（避免 Windows 环境变量干扰）

4. 在项目树中找到 `be/CMakeLists.txt` → **右键 → Load CMake Project**，等待配置完成。

### 6.4 Attach 调试

1. 确认 BE 已在 WSL 中启动：`ps aux | grep starrocks_be`。
2. CLion 中：**Run → Attach to Process...**，在列表中选 `starrocks_be`。
3. 打开 BE 源码文件，设置断点（红色实心圆），用 MySQL 发 SQL 触发即可。

推荐断点：

| 文件 | 说明 |
|------|------|
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` 的 `_read_chunk_from_storage` | 每次从存储读 chunk 都会经过 |

### 6.5 备选：gdb 命令行调试

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
| 启动 FE | `cd output/fe && ./bin/start_fe.sh --daemon` |
| 启动 FE（Debug） | `cd output/fe && ./bin/start_fe.sh --daemon --debug` |
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

---

## 九、推荐 Debug 组合

| 组件 | 启动方式 | 调试方式 |
|------|----------|----------|
| FE | `start_fe.sh --daemon --debug` | Windows IDEA → Remote JVM Debug → `localhost:5005` |
| BE | `start_be.sh --daemon`（Debug 构建） | Windows CLion（WSL Toolchain）→ Attach to Process |

**完整链路**：MySQL 连 `localhost:9030` 执行 SQL → FE 在 Java 断点停住看解析/规划 → BE 在 C++ 断点停住看执行/存储，完整跟踪一条 SQL 从头到尾的源码路径。

```

文档已写好。下面是整体说明：

---

新文档已写入 `/home/peter/my-project/starrocks/docs/zh/learning/在wsl2上进行starrocks编译启动源码debug总结.md`，内容严格按照**阅读顺序即操作顺序**来组织：

| 章节 | 内容 |
|------|------|
| **一** | 安装编译依赖（仅首次） |
| **二** | 编译 FE + BE |
| **三** | 启动 FE |
| **四** | 启动 BE → 加入集群 → SQL 验证 |
| **五** | Debug FE（IDEA Remote JVM Debug） |
| **六** | Debug BE（CLion WSL Toolchain + Attach to Process） |
| **七** | 常用命令速查 |
| **八** | 报错排查 |
| **九** | 推荐 Debug 组合总览 |

相比老文档的关键变化：

1. **去掉了所有 Docker 相关内容**——没有端口映射、SSH、gdbserver、容器 IP 等配置
2. **BE Debug 用 CLion WSL Toolchain**——CLion 运行在 Windows，通过 WSL Toolchain 原生支持直接 Attach 到 WSL 里的 `starrocks_be` 进程，无需 Remote Development + SSH
3. **FE Debug 更简单**——WSL2 自动转发端口，Windows 上 IDEA 直接连 `localhost:5005`
4. **严格按阅读顺序操作**——从安装依赖到编译到启动到 Debug，一步接一步，没有"先跳到第七节再回来"的情况

你可以按文档顺序在 WSL2 里逐步验证，遇到问题随时告诉我，我们一起修正文档细节。

---

**User**

请帮我确认一下当前starrocks项目中是否有要求gcc和java的版本，我觉得这2个比较重要
我看了一下之前部署的docker中

root@74ea0cd8b588:/workspace# gcc --version
gcc (GCC) 14.3.0

root@74ea0cd8b588:/workspace# java --version
openjdk 17.0.16 2025-07-15
OpenJDK Runtime Environment (build 17.0.16+8-Ubuntu-0ubuntu122.04.1)
OpenJDK 64-Bit Server VM (build 17.0.16+8-Ubuntu-0ubuntu122.04.1, mixed mode, sharing)

看起来gcc是14，java是17，但是我执行了文档中的apt-get install...命令后

@zsh (878-887) 
看起来gcc是13，java是21

gcc我感觉似乎还好，但java会不会太高了一些
所以我希望你帮我确认一下，是否要修改

---

**Cursor**



好的，让我帮你确认 StarRocks 3.2.16 分支对 GCC 和 Java 版本的具体要求。

现在已经很清楚了。让我总结一下确认结果：

---

## 确认结果

### GCC：你的 13.3.0 ✅ 完全没问题

从 `be/CMakeLists.txt` 中可以看到：

```101:112:/home/peter/my-project/starrocks/be/CMakeLists.txt
# Check gcc
if (CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    if (CMAKE_CXX_COMPILER_VERSION VERSION_LESS "4.8.2")
        message(FATAL_ERROR "Need GCC version at least 4.8.2")
    endif()

    if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER "10.3.0")
        message(STATUS "GCC version ${CMAKE_CXX_COMPILER_VERSION} is greater than 10.3.0, disable -Werror. Be careful with compile warnings.")
    else()
        #   -Werror: compile warnings should be errors when using the toolchain compiler.
        set(CXX_GCC_FLAGS "${CXX_GCC_FLAGS} -Werror")
    endif()
```

- **最低要求**：GCC ≥ 4.8.2
- GCC > 10.3.0 时只是关闭 `-Werror`（不把 warning 当 error），这是正常行为
- Docker 里的 14.3.0 和你 WSL 里的 **13.3.0 都没问题**，差异不影响编译

### Java：你的 JDK 21 ⚠️ 可以编译，但运行 FE 时**可能有问题**

**编译层面**：`fe/pom.xml` 中指定了：

```44:45:/home/peter/my-project/starrocks/fe/pom.xml
        <maven.compiler.source>1.8</maven.compiler.source>
        <maven.compiler.target>1.8</maven.compiler.target>
```

即 Maven 编译 FE 时 source/target 是 Java 8，JDK 21 是**向下兼容**的，可以用高版本 JDK 编译出 Java 8 目标的字节码，**编译没问题**。

**运行层面**：`JdkUtils.checkJavaVersion()` 的逻辑是：

```60:64:/home/peter/my-project/starrocks/fe/fe-core/src/main/java/com/starrocks/common/util/JdkUtils.java
        if (runtimeVersion < compileVersion) {
            System.out.println("The runtime java version " + javaRuntimeVersionStr + " is less than "
                    + "compile version " + javaCompileVersionStr);
            return false;
        }
```

要求**运行时 Java 版本 ≥ 编译时 Java 版本**。如果你用 JDK 21 编译，那运行时也必须是 JDK 21+。这本身不矛盾（你编译和运行都在 WSL 里用同一个 JDK 21）。

**但实际风险在于**：StarRocks 3.2.x 分支主要在 **JDK 8 ~ 17** 上测试和验证的，JDK 21 引入了一些 breaking changes（比如 removal of SecurityManager 相关 API、一些反射限制增强等），**有小概率在运行时遇到兼容性问题**。

### 建议：安装 JDK 17，与 Docker 环境保持一致

```bash
# 安装 JDK 17
sudo apt-get install -y openjdk-17-jdk

# 切换为 JDK 17
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac

# 设置 JAVA_HOME（加入 ~/.zshrc 持久化）
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# 验证
java --version   # 应显示 17.x
javac --version
```

这样和你 Docker 里的环境完全一致（JDK 17），是 StarRocks 3.2.x 最稳妥的选择。

**总结**：
| 工具 | WSL 当前版本 | Docker 中版本 | 是否需要改 |
|------|-------------|--------------|-----------|
| GCC | 13.3.0 | 14.3.0 | ❌ 不需要，都满足要求 |
| Java | 21 | 17 | ⚠️ **建议降到 17**，避免潜在兼容问题 |

要不要我帮你把文档中的依赖安装部分也更新一下，加上安装 JDK 17 的说明？

```plaintext
# Check gcc
if (CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    if (CMAKE_CXX_COMPILER_VERSION VERSION_LESS "4.8.2")
        message(FATAL_ERROR "Need GCC version at least 4.8.2")
    endif()

    if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER "10.3.0")
        message(STATUS "GCC version ${CMAKE_CXX_COMPILER_VERSION} is greater than 10.3.0, disable -Werror. Be careful with compile warnings.")
    else()
        #   -Werror: compile warnings should be errors when using the toolchain compiler.
        set(CXX_GCC_FLAGS "${CXX_GCC_FLAGS} -Werror")
    endif()
```

```xml
        <maven.compiler.source>1.8</maven.compiler.source>
        <maven.compiler.target>1.8</maven.compiler.target>
```

```java
        if (runtimeVersion < compileVersion) {
            System.out.println("The runtime java version " + javaRuntimeVersionStr + " is less than "
                    + "compile version " + javaCompileVersionStr);
            return false;
        }
```

```shellscript
# 安装 JDK 17
sudo apt-get install -y openjdk-17-jdk

# 切换为 JDK 17
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac

# 设置 JAVA_HOME（加入 ~/.zshrc 持久化）
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# 验证
java --version   # 应显示 17.x
javac --version
```

---

**User**

OK了，我已安装好openjdk 17，请帮我也优化一下文档说明

---

**Cursor**

```markdown
---
displayed_sidebar: docs
---

# WSL2 上编译、启动、Debug FE & BE

在 WSL2（Ubuntu）中完成 StarRocks 的编译、单机启动（1 FE + 1 BE）、以及 FE/BE 源码断点调试。所有命令在**项目根目录** `/home/peter/my-project/starrocks` 下执行，部署目录为 **`output/`**。

与 Docker 方案相比，WSL2 方案**不需要端口映射、不需要 SSH、不需要 gdbserver**，IDE 直接连接本地进程即可调试。

---

## 一、安装编译依赖

> 仅首次搭建环境时需要，后续不必重复。

```bash
sudo apt-get update

# 基础工具和编译器（不含 JDK，JDK 单独安装以控制版本）
sudo apt-get install -y automake binutils-dev bison byacc ccache flex libiberty-dev libtool \
    maven zip python3 python-is-python3 cmake gcc g++ git patch lld bzip2 \
    wget unzip curl make build-essential ninja-build

# 安装 JDK 17（StarRocks 3.2.x 推荐，不建议用 default-jdk 装到 21，可能有兼容问题）
sudo apt-get install -y openjdk-17-jdk

# 若系统中有多个 JDK 版本，切换到 17
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac

# 设置 JAVA_HOME（加入 ~/.bashrc 或 ~/.zshrc 以持久化）
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

验证关键版本：

```bash
gcc --version    # 需 >= 10.3（当前 13.3.0 ✓）
java --version   # 需 >= 8，推荐 17（当前 17.x ✓）
cmake --version  # 需 >= 3.20.1
mvn --version
```

---

## 二、编译

```bash
cd /home/peter/my-project/starrocks

# 编译 FE + BE（首次会自动编译 thirdparty，耗时较长）
./build.sh --fe --be
```

> 可用 `-j N` 指定并行度，如 `./build.sh --fe --be -j 8`。
>
> 若只需 Debug BE，另做一次 Debug 构建（见「六、Debug BE」）。编译成功后产出在 `output/fe` 和 `output/be`。

---

## 三、启动 FE

```bash
# 1. 创建元数据目录
mkdir -p output/fe/meta

# 2. 配置 meta_dir
grep -q "^meta_dir " output/fe/conf/fe.conf || echo "meta_dir = \${STARROCKS_HOME}/meta" >> output/fe/conf/fe.conf

# 3. 单 BE 副本数设为 1
grep -q "default_replication_num" output/fe/conf/fe.conf || echo "default_replication_num = 1" >> output/fe/conf/fe.conf

# 4. 启动（若需 Debug FE，改用 --debug，见「五、Debug FE」）
cd output/fe && ./bin/start_fe.sh --daemon && cd ../..

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
cat output/be/log/be.INFO | grep heartbeat
```

### 4.2 把 BE 加入集群

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

FE 是 Java 进程，使用 JDWP 远程调试，**无需改代码**。

### 5.1 以 Debug 模式启动 FE

```bash
# 先停掉已运行的 FE（若有）
output/fe/bin/stop_fe.sh

# 加 --debug 启动
cd output/fe && ./bin/start_fe.sh --daemon --debug && cd ../..
```

日志中出现 `address=*:5005` 即表示调试端口已监听。

### 5.2 IDEA 连接

1. **Run → Edit Configurations → + → Remote JVM Debug**
2. Host `localhost`，Port `5005`，保存并点击 Debug。
3. WSL2 中的 5005 端口可直接从 Windows 访问（WSL2 自动转发），无需额外配置。

### 5.3 打断点验证

在 IDEA 中打开 FE 源码，推荐断点：

| 文件 | 说明 |
|------|------|
| `fe/fe-core/src/main/java/com/starrocks/qe/StmtExecutor.java` 的 `execute()` 方法 | SQL 执行入口，可看 `context`、`parsedStmt` |
| `fe/fe-core/src/main/java/com/starrocks/qe/ConnectProcessor.java` 的 `handleQuery` | 客户端发来的 SQL 字符串 |

用 MySQL 执行 `SELECT * FROM demo.t1;`，程序会在断点处暂停。

---

## 六、Debug BE（C++：CLion + WSL Toolchain）

BE 是 C++ 进程，需要 **Debug 构建**（带完整符号），再用 CLion 的 **Attach to Process** 调试。

### 6.1 Debug 构建 BE

```bash
cd /home/peter/my-project/starrocks

# Debug 构建（产出默认仍在 output/be，体积更大）
BUILD_TYPE=Debug ./build.sh --be
```

> 若想保留 Release 版 BE，可在构建前备份 `output/be`，或构建后将 Debug 版移到 `output/be-debug`。

### 6.2 启动 Debug 版 BE

```bash
mkdir -p output/be/storage
grep -q "^storage_root_path " output/be/conf/be.conf || echo "storage_root_path = \${STARROCKS_HOME}/storage" >> output/be/conf/be.conf

# 若遇 SIGABRT（DataCache 相关），加上这行：
# echo "datacache_enable = false" >> output/be/conf/be.conf

cd output/be && ./bin/start_be.sh --daemon && cd ../..
```

### 6.3 CLion 配置 WSL Toolchain

CLion 原生支持 WSL Toolchain，**IDE 运行在 Windows 上，编译/调试在 WSL 内执行，无需 SSH 配置**。

1. 打开 CLion（Windows 版） → **File → Open** → 打开 `\\wsl$\Ubuntu\home\peter\my-project\starrocks` 下的项目（或直接打开 WSL 路径）。

2. **Settings → Build, Execution, Deployment → Toolchains**：
   - 点 **+** → 选 **WSL**，CLion 会自动检测到你的 WSL 发行版。
   - 确认 CMake、C Compiler、C++ Compiler 均显示绿色勾（自动从 WSL 中检测）。

3. **Settings → Build, Execution, Deployment → CMake**：
   - **Build type**：`Debug`
   - **Toolchain**：选上一步添加的 WSL toolchain
   - **Environment**：添加 `STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr`
     - `STARROCKS_CLION_ONLY=1`：只生成代码导航用的 target，不真正编译，配置速度很快
     - `STARROCKS_GCC_HOME`：指定 GCC 路径（WSL 上通过 apt 安装的 GCC 在 `/usr`）
   - 取消勾选 **Include system environment variables**（避免 Windows 环境变量干扰）

4. 在项目树中找到 `be/CMakeLists.txt` → **右键 → Load CMake Project**，等待配置完成。

### 6.4 Attach 调试

1. 确认 BE 已在 WSL 中启动：`ps aux | grep starrocks_be`。
2. CLion 中：**Run → Attach to Process...**，在列表中选 `starrocks_be`。
3. 打开 BE 源码文件，设置断点（红色实心圆），用 MySQL 发 SQL 触发即可。

推荐断点：

| 文件 | 说明 |
|------|------|
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` 的 `_read_chunk_from_storage` | 每次从存储读 chunk 都会经过 |

### 6.5 备选：gdb 命令行调试

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
| 启动 FE | `cd output/fe && ./bin/start_fe.sh --daemon` |
| 启动 FE（Debug） | `cd output/fe && ./bin/start_fe.sh --daemon --debug` |
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

---

## 九、推荐 Debug 组合

| 组件 | 启动方式 | 调试方式 |
|------|----------|----------|
| FE | `start_fe.sh --daemon --debug` | Windows IDEA → Remote JVM Debug → `localhost:5005` |
| BE | `start_be.sh --daemon`（Debug 构建） | Windows CLion（WSL Toolchain）→ Attach to Process |

**完整链路**：MySQL 连 `localhost:9030` 执行 SQL → FE 在 Java 断点停住看解析/规划 → BE 在 C++ 断点停住看执行/存储，完整跟踪一条 SQL 从头到尾的源码路径。

```

已更新。主要改动：

1. **去掉了 `default-jdk`**——避免装到 JDK 21
2. **单独用 `openjdk-17-jdk` 安装 JDK 17**，并加了注释说明原因
3. **加了 `update-alternatives` 切换命令**——应对系统中可能存在多个 JDK 版本的情况
4. **`JAVA_HOME` 改为明确的 `/usr/lib/jvm/java-17-openjdk-amd64`**
5. **版本验证注释里补充了当前实际版本**，方便对照

---

**User**

我把文档看完了：/home/peter/my-project/starrocks/docs/zh/learning/在wsl2上进行starrocks编译启动源码debug总结.md

我有一些疑问，也是之前遗留下来的，请问be普通构建和debug方式构建，核心差异是什么？看起来debug构建的命令是：BUILD_TYPE=Debug ./build.sh --be，普通构建的命令是：./build.sh --be。都有 ./build.sh --be，前面的 BUILD_TYPE=Debug 起到的作用是什么呢？如果我就是只以./build.sh --be方式编译，那启动后，还能用clion + wsl toolchain来debug吗？

---

**Cursor**



好问题，这是理解 C++ 调试的关键。让我从源码层面帮你确认具体差异。

现在信息足够清楚了，给你完整解答：

---

## `BUILD_TYPE=Debug` 与默认（Release）的核心差异

从 `build.sh` 和 `be/CMakeLists.txt` 可以看到，差异有**两层**：

### 第一层：编译器标志不同

```719:719:/home/peter/my-project/starrocks/be/CMakeLists.txt
set(CXX_FLAGS_DEBUG "${CXX_GCC_FLAGS} -ggdb -O0 -gdwarf-4 -DDEBUG")
```

```725:725:/home/peter/my-project/starrocks/be/CMakeLists.txt
set(CXX_FLAGS_RELEASE "${CXX_GCC_FLAGS} -O3 -gdwarf-4 -DNDEBUG")
```

| 标志 | Debug | Release | 影响 |
|------|-------|---------|------|
| **优化级别** | `-O0`（不优化） | `-O3`（最高优化） | Release 下变量会被优化掉、代码会被内联/重排，调试时变量显示 `<optimized out>`、断点跳来跳去 |
| **调试符号** | `-ggdb`（完整 gdb 符号） | `-gdwarf-4`（也有符号） | 两者都有调试符号，但 Debug 更丰富 |
| **宏定义** | `-DDEBUG` | `-DNDEBUG` | Release 会关闭 `assert()`、关闭 debug 专用代码 |

### 第二层：Release 会 strip 掉调试符号

```518:528:/home/peter/my-project/starrocks/build.sh
    if [ "${ibuildtype}" == "release" ] ; then
        pushd ${STARROCKS_OUTPUT}/be/lib/ &>/dev/null
        BE_BIN=starrocks_be
        BE_BIN_DEBUGINFO=starrocks_be.debuginfo
        echo "Split $BE_BIN debug symbol to $BE_BIN_DEBUGINFO ..."
        # strip be binary
        objcopy --only-keep-debug $BE_BIN $BE_BIN_DEBUGINFO
        strip --strip-debug $BE_BIN
        objcopy --add-gnu-debuglink=$BE_BIN_DEBUGINFO $BE_BIN
        popd &>/dev/null
    fi
```

Release 构建完后，脚本会把 `starrocks_be` 的调试符号**剥离**到单独的 `starrocks_be.debuginfo` 文件，最终的 `starrocks_be` 二进制体积小了很多，但**本体不再包含调试符号**。

---

## 回答你的核心问题：Release 构建能不能用 CLion debug？

**能 attach 上去，但调试体验会很差**，具体表现为：

1. **很多变量显示 `<optimized out>`**——因为 `-O3` 优化后，编译器把变量放在寄存器里或直接消除了，GDB 读不到。
2. **断点位置不准**——代码被重排/内联后，你在源码第 100 行打的断点可能跳到第 105 行，或者根本停不住（函数被内联展开了）。
3. **单步执行时会"跳来跳去"**——因为优化后的执行顺序和源码顺序不同。
4. **还需要额外加载 `.debuginfo` 文件**——因为符号被 strip 了，如果不加载 `starrocks_be.debuginfo`，连函数名和行号都看不到。

**一句话总结**：

> **Debug 构建 = 所见即所得**（变量能看、断点精准、单步顺序和源码一致）
> **Release 构建 = 能 attach 但基本不可用**（变量被优化掉、断点乱跳、像在看乱码）

对于你"阅读源码、理解运行时逻辑"的需求，**Debug 构建是必须的**。Release 构建的 debug 体验差到几乎没有实用价值。

```plaintext
set(CXX_FLAGS_DEBUG "${CXX_GCC_FLAGS} -ggdb -O0 -gdwarf-4 -DDEBUG")
```

```plaintext
set(CXX_FLAGS_RELEASE "${CXX_GCC_FLAGS} -O3 -gdwarf-4 -DNDEBUG")
```

```shellscript
    if [ "${ibuildtype}" == "release" ] ; then
        pushd ${STARROCKS_OUTPUT}/be/lib/ &>/dev/null
        BE_BIN=starrocks_be
        BE_BIN_DEBUGINFO=starrocks_be.debuginfo
        echo "Split $BE_BIN debug symbol to $BE_BIN_DEBUGINFO ..."
        # strip be binary
        objcopy --only-keep-debug $BE_BIN $BE_BIN_DEBUGINFO
        strip --strip-debug $BE_BIN
        objcopy --add-gnu-debuglink=$BE_BIN_DEBUGINFO $BE_BIN
        popd &>/dev/null
    fi
```

---

**User**

明白了，那看来debug构建是必须的。

我以后也会主要以debug方式编译，因此我希望你帮我改一下文档。文档中二、编译章节，还是在以普通编译方式阐述，我希望这里就以debug编译方式来阐述，但同时保留说明一下如果不想debug该如何编译

请注意下上下文的内容关联改动，我觉得章节不需要新增、修改、删除，只需要把debug作为重点来写就行，麻烦改一改，谢谢

---

**Cursor**

现在来做改动：第二节以 Debug 编译为主线，第三节启动 FE 默认用 `--debug`，第六节去掉重复的 Debug 构建步骤（已在第二节完成），其他章节做相应的关联调整。

```markdown
---
displayed_sidebar: docs
---

# WSL2 上编译、启动、Debug FE & BE

在 WSL2（Ubuntu）中完成 StarRocks 的编译、单机启动（1 FE + 1 BE）、以及 FE/BE 源码断点调试。所有命令在**项目根目录** `/home/peter/my-project/starrocks` 下执行，部署目录为 **`output/`**。

与 Docker 方案相比，WSL2 方案**不需要端口映射、不需要 SSH、不需要 gdbserver**，IDE 直接连接本地进程即可调试。

---

## 一、安装编译依赖

> 仅首次搭建环境时需要，后续不必重复。

```bash
sudo apt-get update

# 基础工具和编译器（不含 JDK，JDK 单独安装以控制版本）
sudo apt-get install -y automake binutils-dev bison byacc ccache flex libiberty-dev libtool \
    maven zip python3 python-is-python3 cmake gcc g++ git patch lld bzip2 \
    wget unzip curl make build-essential ninja-build

# 安装 JDK 17（StarRocks 3.2.x 推荐，不建议用 default-jdk 装到 21，可能有兼容问题）
sudo apt-get install -y openjdk-17-jdk

# 若系统中有多个 JDK 版本，切换到 17
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac

# 设置 JAVA_HOME（加入 ~/.bashrc 或 ~/.zshrc 以持久化）
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

验证关键版本：

```bash
gcc --version    # 需 >= 10.3（当前 13.3.0 ✓）
java --version   # 需 >= 8，推荐 17（当前 17.x ✓）
cmake --version  # 需 >= 3.20.1
mvn --version
```

---

## 二、编译

```bash
cd /home/peter/my-project/starrocks

# 编译 FE + BE（Debug 模式，首次会自动编译 thirdparty，耗时较长）
BUILD_TYPE=Debug ./build.sh --fe --be
```

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

# 4. 启动（若需 Debug FE，改用 --debug，见「五、Debug FE」）
cd output/fe && ./bin/start_fe.sh --daemon && cd ../..

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
cat output/be/log/be.INFO | grep heartbeat
```

### 4.2 把 BE 加入集群

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

FE 是 Java 进程，使用 JDWP 远程调试，**无需改代码**。

### 5.1 以 Debug 模式启动 FE

```bash
# 先停掉已运行的 FE（若有）
output/fe/bin/stop_fe.sh

# 加 --debug 启动
cd output/fe && ./bin/start_fe.sh --daemon --debug && cd ../..
```

日志中出现 `address=*:5005` 即表示调试端口已监听。

### 5.2 IDEA 连接

1. **Run → Edit Configurations → + → Remote JVM Debug**
2. Host `localhost`，Port `5005`，保存并点击 Debug。
3. WSL2 中的 5005 端口可直接从 Windows 访问（WSL2 自动转发），无需额外配置。

### 5.3 打断点验证

在 IDEA 中打开 FE 源码，推荐断点：

| 文件 | 说明 |
|------|------|
| `fe/fe-core/src/main/java/com/starrocks/qe/StmtExecutor.java` 的 `execute()` 方法 | SQL 执行入口，可看 `context`、`parsedStmt` |
| `fe/fe-core/src/main/java/com/starrocks/qe/ConnectProcessor.java` 的 `handleQuery` | 客户端发来的 SQL 字符串 |

用 MySQL 执行 `SELECT * FROM demo.t1;`，程序会在断点处暂停。

---

## 六、Debug BE（C++：CLion + WSL Toolchain）

BE 是 C++ 进程，需要 **Debug 构建**（带完整符号），再用 CLion 的 **Attach to Process** 调试。

### 6.1 Debug 构建 BE

```bash
cd /home/peter/my-project/starrocks

# Debug 构建（产出默认仍在 output/be，体积更大）
BUILD_TYPE=Debug ./build.sh --be
```

> 若想保留 Release 版 BE，可在构建前备份 `output/be`，或构建后将 Debug 版移到 `output/be-debug`。

### 6.2 启动 Debug 版 BE

```bash
mkdir -p output/be/storage
grep -q "^storage_root_path " output/be/conf/be.conf || echo "storage_root_path = \${STARROCKS_HOME}/storage" >> output/be/conf/be.conf

# 若遇 SIGABRT（DataCache 相关），加上这行：
# echo "datacache_enable = false" >> output/be/conf/be.conf

cd output/be && ./bin/start_be.sh --daemon && cd ../..
```

### 6.3 CLion 配置 WSL Toolchain

CLion 原生支持 WSL Toolchain，**IDE 运行在 Windows 上，编译/调试在 WSL 内执行，无需 SSH 配置**。

1. 打开 CLion（Windows 版） → **File → Open** → 打开 `\\wsl$\Ubuntu\home\peter\my-project\starrocks` 下的项目（或直接打开 WSL 路径）。

2. **Settings → Build, Execution, Deployment → Toolchains**：
   - 点 **+** → 选 **WSL**，CLion 会自动检测到你的 WSL 发行版。
   - 确认 CMake、C Compiler、C++ Compiler 均显示绿色勾（自动从 WSL 中检测）。

3. **Settings → Build, Execution, Deployment → CMake**：
   - **Build type**：`Debug`
   - **Toolchain**：选上一步添加的 WSL toolchain
   - **Environment**：添加 `STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr`
     - `STARROCKS_CLION_ONLY=1`：只生成代码导航用的 target，不真正编译，配置速度很快
     - `STARROCKS_GCC_HOME`：指定 GCC 路径（WSL 上通过 apt 安装的 GCC 在 `/usr`）
   - 取消勾选 **Include system environment variables**（避免 Windows 环境变量干扰）

4. 在项目树中找到 `be/CMakeLists.txt` → **右键 → Load CMake Project**，等待配置完成。

### 6.4 Attach 调试

1. 确认 BE 已在 WSL 中启动：`ps aux | grep starrocks_be`。
2. CLion 中：**Run → Attach to Process...**，在列表中选 `starrocks_be`。
3. 打开 BE 源码文件，设置断点（红色实心圆），用 MySQL 发 SQL 触发即可。

推荐断点：

| 文件 | 说明 |
|------|------|
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` 的 `_read_chunk_from_storage` | 每次从存储读 chunk 都会经过 |

### 6.5 备选：gdb 命令行调试

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
| 启动 FE | `cd output/fe && ./bin/start_fe.sh --daemon` |
| 启动 FE（Debug） | `cd output/fe && ./bin/start_fe.sh --daemon --debug` |
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

---

## 九、推荐 Debug 组合

| 组件 | 启动方式 | 调试方式 |
|------|----------|----------|
| FE | `start_fe.sh --daemon --debug` | Windows IDEA → Remote JVM Debug → `localhost:5005` |
| BE | `start_be.sh --daemon`（Debug 构建） | Windows CLion（WSL Toolchain）→ Attach to Process |

**完整链路**：MySQL 连 `localhost:9030` 执行 SQL → FE 在 Java 断点停住看解析/规划 → BE 在 C++ 断点停住看执行/存储，完整跟踪一条 SQL 从头到尾的源码路径。

```

```markdown
---
displayed_sidebar: docs
---

# WSL2 上编译、启动、Debug FE & BE

在 WSL2（Ubuntu）中完成 StarRocks 的编译、单机启动（1 FE + 1 BE）、以及 FE/BE 源码断点调试。所有命令在**项目根目录** `/home/peter/my-project/starrocks` 下执行，部署目录为 **`output/`**。

与 Docker 方案相比，WSL2 方案**不需要端口映射、不需要 SSH、不需要 gdbserver**，IDE 直接连接本地进程即可调试。

---

## 一、安装编译依赖

> 仅首次搭建环境时需要，后续不必重复。

```bash
sudo apt-get update

# 基础工具和编译器（不含 JDK，JDK 单独安装以控制版本）
sudo apt-get install -y automake binutils-dev bison byacc ccache flex libiberty-dev libtool \
    maven zip python3 python-is-python3 cmake gcc g++ git patch lld bzip2 \
    wget unzip curl make build-essential ninja-build

# 安装 JDK 17（StarRocks 3.2.x 推荐，不建议用 default-jdk 装到 21，可能有兼容问题）
sudo apt-get install -y openjdk-17-jdk

# 若系统中有多个 JDK 版本，切换到 17
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac

# 设置 JAVA_HOME（加入 ~/.bashrc 或 ~/.zshrc 以持久化）
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

验证关键版本：

```bash
gcc --version    # 需 >= 10.3（当前 13.3.0 ✓）
java --version   # 需 >= 8，推荐 17（当前 17.x ✓）
cmake --version  # 需 >= 3.20.1
mvn --version
```

---

## 二、编译

```bash
cd /home/peter/my-project/starrocks

# 编译 FE + BE（Debug 模式，首次会自动编译 thirdparty，耗时较长）
BUILD_TYPE=Debug ./build.sh --fe --be
```

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
cat output/be/log/be.INFO | grep heartbeat
```

### 4.2 把 BE 加入集群

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

FE 是 Java 进程，使用 JDWP 远程调试，**无需改代码**。

### 5.1 以 Debug 模式启动 FE

```bash
# 先停掉已运行的 FE（若有）
output/fe/bin/stop_fe.sh

# 加 --debug 启动
cd output/fe && ./bin/start_fe.sh --daemon --debug && cd ../..
```

日志中出现 `address=*:5005` 即表示调试端口已监听。

### 5.2 IDEA 连接

1. **Run → Edit Configurations → + → Remote JVM Debug**
2. Host `localhost`，Port `5005`，保存并点击 Debug。
3. WSL2 中的 5005 端口可直接从 Windows 访问（WSL2 自动转发），无需额外配置。

### 5.3 打断点验证

在 IDEA 中打开 FE 源码，推荐断点：

| 文件 | 说明 |
|------|------|
| `fe/fe-core/src/main/java/com/starrocks/qe/StmtExecutor.java` 的 `execute()` 方法 | SQL 执行入口，可看 `context`、`parsedStmt` |
| `fe/fe-core/src/main/java/com/starrocks/qe/ConnectProcessor.java` 的 `handleQuery` | 客户端发来的 SQL 字符串 |

用 MySQL 执行 `SELECT * FROM demo.t1;`，程序会在断点处暂停。

---

## 六、Debug BE（C++：CLion + WSL Toolchain）

BE 是 C++ 进程，需要 **Debug 构建**（带完整符号），再用 CLion 的 **Attach to Process** 调试。

### 6.1 Debug 构建 BE

```bash
cd /home/peter/my-project/starrocks

# Debug 构建（产出默认仍在 output/be，体积更大）
BUILD_TYPE=Debug ./build.sh --be
```

> 若想保留 Release 版 BE，可在构建前备份 `output/be`，或构建后将 Debug 版移到 `output/be-debug`。

### 6.2 启动 Debug 版 BE

```bash
mkdir -p output/be/storage
grep -q "^storage_root_path " output/be/conf/be.conf || echo "storage_root_path = \${STARROCKS_HOME}/storage" >> output/be/conf/be.conf

# 若遇 SIGABRT（DataCache 相关），加上这行：
# echo "datacache_enable = false" >> output/be/conf/be.conf

cd output/be && ./bin/start_be.sh --daemon && cd ../..
```

### 6.3 CLion 配置 WSL Toolchain

CLion 原生支持 WSL Toolchain，**IDE 运行在 Windows 上，编译/调试在 WSL 内执行，无需 SSH 配置**。

1. 打开 CLion（Windows 版） → **File → Open** → 打开 `\\wsl$\Ubuntu\home\peter\my-project\starrocks` 下的项目（或直接打开 WSL 路径）。

2. **Settings → Build, Execution, Deployment → Toolchains**：
   - 点 **+** → 选 **WSL**，CLion 会自动检测到你的 WSL 发行版。
   - 确认 CMake、C Compiler、C++ Compiler 均显示绿色勾（自动从 WSL 中检测）。

3. **Settings → Build, Execution, Deployment → CMake**：
   - **Build type**：`Debug`
   - **Toolchain**：选上一步添加的 WSL toolchain
   - **Environment**：添加 `STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr`
     - `STARROCKS_CLION_ONLY=1`：只生成代码导航用的 target，不真正编译，配置速度很快
     - `STARROCKS_GCC_HOME`：指定 GCC 路径（WSL 上通过 apt 安装的 GCC 在 `/usr`）
   - 取消勾选 **Include system environment variables**（避免 Windows 环境变量干扰）

4. 在项目树中找到 `be/CMakeLists.txt` → **右键 → Load CMake Project**，等待配置完成。

### 6.4 Attach 调试

1. 确认 BE 已在 WSL 中启动：`ps aux | grep starrocks_be`。
2. CLion 中：**Run → Attach to Process...**，在列表中选 `starrocks_be`。
3. 打开 BE 源码文件，设置断点（红色实心圆），用 MySQL 发 SQL 触发即可。

推荐断点：

| 文件 | 说明 |
|------|------|
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` 的 `_read_chunk_from_storage` | 每次从存储读 chunk 都会经过 |

### 6.5 备选：gdb 命令行调试

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
| 启动 FE | `cd output/fe && ./bin/start_fe.sh --daemon` |
| 启动 FE（Debug） | `cd output/fe && ./bin/start_fe.sh --daemon --debug` |
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

---

## 九、推荐 Debug 组合

| 组件 | 启动方式 | 调试方式 |
|------|----------|----------|
| FE | `start_fe.sh --daemon --debug` | Windows IDEA → Remote JVM Debug → `localhost:5005` |
| BE | `start_be.sh --daemon`（Debug 构建） | Windows CLion（WSL Toolchain）→ Attach to Process |

**完整链路**：MySQL 连 `localhost:9030` 执行 SQL → FE 在 Java 断点停住看解析/规划 → BE 在 C++ 断点停住看执行/存储，完整跟踪一条 SQL 从头到尾的源码路径。

```

```markdown
---
displayed_sidebar: docs
---

# WSL2 上编译、启动、Debug FE & BE

在 WSL2（Ubuntu）中完成 StarRocks 的编译、单机启动（1 FE + 1 BE）、以及 FE/BE 源码断点调试。所有命令在**项目根目录** `/home/peter/my-project/starrocks` 下执行，部署目录为 **`output/`**。

与 Docker 方案相比，WSL2 方案**不需要端口映射、不需要 SSH、不需要 gdbserver**，IDE 直接连接本地进程即可调试。

---

## 一、安装编译依赖

> 仅首次搭建环境时需要，后续不必重复。

```bash
sudo apt-get update

# 基础工具和编译器（不含 JDK，JDK 单独安装以控制版本）
sudo apt-get install -y automake binutils-dev bison byacc ccache flex libiberty-dev libtool \
    maven zip python3 python-is-python3 cmake gcc g++ git patch lld bzip2 \
    wget unzip curl make build-essential ninja-build

# 安装 JDK 17（StarRocks 3.2.x 推荐，不建议用 default-jdk 装到 21，可能有兼容问题）
sudo apt-get install -y openjdk-17-jdk

# 若系统中有多个 JDK 版本，切换到 17
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac

# 设置 JAVA_HOME（加入 ~/.bashrc 或 ~/.zshrc 以持久化）
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

验证关键版本：

```bash
gcc --version    # 需 >= 10.3（当前 13.3.0 ✓）
java --version   # 需 >= 8，推荐 17（当前 17.x ✓）
cmake --version  # 需 >= 3.20.1
mvn --version
```

---

## 二、编译

```bash
cd /home/peter/my-project/starrocks

# 编译 FE + BE（Debug 模式，首次会自动编译 thirdparty，耗时较长）
BUILD_TYPE=Debug ./build.sh --fe --be
```

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
cat output/be/log/be.INFO | grep heartbeat
```

### 4.2 把 BE 加入集群

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

FE 是 Java 进程，使用 JDWP 远程调试，**无需改代码**。

### 5.1 以 Debug 模式启动 FE

```bash
# 先停掉已运行的 FE（若有）
output/fe/bin/stop_fe.sh

# 加 --debug 启动
cd output/fe && ./bin/start_fe.sh --daemon --debug && cd ../..
```

日志中出现 `address=*:5005` 即表示调试端口已监听。

### 5.2 IDEA 连接

1. **Run → Edit Configurations → + → Remote JVM Debug**
2. Host `localhost`，Port `5005`，保存并点击 Debug。
3. WSL2 中的 5005 端口可直接从 Windows 访问（WSL2 自动转发），无需额外配置。

### 5.3 打断点验证

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
   - **Build type**：`Debug`
   - **Toolchain**：选上一步添加的 WSL toolchain
   - **Environment**：添加 `STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr`
     - `STARROCKS_CLION_ONLY=1`：只生成代码导航用的 target，不真正编译，配置速度很快
     - `STARROCKS_GCC_HOME`：指定 GCC 路径（WSL 上通过 apt 安装的 GCC 在 `/usr`）
   - 取消勾选 **Include system environment variables**（避免 Windows 环境变量干扰）

4. 在项目树中找到 `be/CMakeLists.txt` → **右键 → Load CMake Project**，等待配置完成。

### 6.4 Attach 调试

1. 确认 BE 已在 WSL 中启动：`ps aux | grep starrocks_be`。
2. CLion 中：**Run → Attach to Process...**，在列表中选 `starrocks_be`。
3. 打开 BE 源码文件，设置断点（红色实心圆），用 MySQL 发 SQL 触发即可。

推荐断点：

| 文件 | 说明 |
|------|------|
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` 的 `_read_chunk_from_storage` | 每次从存储读 chunk 都会经过 |

### 6.5 备选：gdb 命令行调试

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
| 启动 FE | `cd output/fe && ./bin/start_fe.sh --daemon` |
| 启动 FE（Debug） | `cd output/fe && ./bin/start_fe.sh --daemon --debug` |
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

---

## 九、推荐 Debug 组合

| 组件 | 启动方式 | 调试方式 |
|------|----------|----------|
| FE | `start_fe.sh --daemon --debug` | Windows IDEA → Remote JVM Debug → `localhost:5005` |
| BE | `start_be.sh --daemon`（Debug 构建） | Windows CLion（WSL Toolchain）→ Attach to Process |

**完整链路**：MySQL 连 `localhost:9030` 执行 SQL → FE 在 Java 断点停住看解析/规划 → BE 在 C++ 断点停住看执行/存储，完整跟踪一条 SQL 从头到尾的源码路径。

```

```markdown
---
displayed_sidebar: docs
---

# WSL2 上编译、启动、Debug FE & BE

在 WSL2（Ubuntu）中完成 StarRocks 的编译、单机启动（1 FE + 1 BE）、以及 FE/BE 源码断点调试。所有命令在**项目根目录** `/home/peter/my-project/starrocks` 下执行，部署目录为 **`output/`**。

与 Docker 方案相比，WSL2 方案**不需要端口映射、不需要 SSH、不需要 gdbserver**，IDE 直接连接本地进程即可调试。

---

## 一、安装编译依赖

> 仅首次搭建环境时需要，后续不必重复。

```bash
sudo apt-get update

# 基础工具和编译器（不含 JDK，JDK 单独安装以控制版本）
sudo apt-get install -y automake binutils-dev bison byacc ccache flex libiberty-dev libtool \
    maven zip python3 python-is-python3 cmake gcc g++ git patch lld bzip2 \
    wget unzip curl make build-essential ninja-build

# 安装 JDK 17（StarRocks 3.2.x 推荐，不建议用 default-jdk 装到 21，可能有兼容问题）
sudo apt-get install -y openjdk-17-jdk

# 若系统中有多个 JDK 版本，切换到 17
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac

# 设置 JAVA_HOME（加入 ~/.bashrc 或 ~/.zshrc 以持久化）
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

验证关键版本：

```bash
gcc --version    # 需 >= 10.3（当前 13.3.0 ✓）
java --version   # 需 >= 8，推荐 17（当前 17.x ✓）
cmake --version  # 需 >= 3.20.1
mvn --version
```

---

## 二、编译

```bash
cd /home/peter/my-project/starrocks

# 编译 FE + BE（Debug 模式，首次会自动编译 thirdparty，耗时较长）
BUILD_TYPE=Debug ./build.sh --fe --be
```

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
cat output/be/log/be.INFO | grep heartbeat
```

### 4.2 把 BE 加入集群

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

FE 是 Java 进程，使用 JDWP 远程调试，**无需改代码**。

### 5.1 以 Debug 模式启动 FE

```bash
# 先停掉已运行的 FE（若有）
output/fe/bin/stop_fe.sh

# 加 --debug 启动
cd output/fe && ./bin/start_fe.sh --daemon --debug && cd ../..
```

日志中出现 `address=*:5005` 即表示调试端口已监听。

### 5.2 IDEA 连接

1. **Run → Edit Configurations → + → Remote JVM Debug**
2. Host `localhost`，Port `5005`，保存并点击 Debug。
3. WSL2 中的 5005 端口可直接从 Windows 访问（WSL2 自动转发），无需额外配置。

### 5.3 打断点验证

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
   - **Build type**：`Debug`
   - **Toolchain**：选上一步添加的 WSL toolchain
   - **Environment**：添加 `STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr`
     - `STARROCKS_CLION_ONLY=1`：只生成代码导航用的 target，不真正编译，配置速度很快
     - `STARROCKS_GCC_HOME`：指定 GCC 路径（WSL 上通过 apt 安装的 GCC 在 `/usr`）
   - 取消勾选 **Include system environment variables**（避免 Windows 环境变量干扰）

4. 在项目树中找到 `be/CMakeLists.txt` → **右键 → Load CMake Project**，等待配置完成。

### 6.2 Attach 调试

1. 确认 BE 已在 WSL 中启动：`ps aux | grep starrocks_be`。
2. CLion 中：**Run → Attach to Process...**，在列表中选 `starrocks_be`。
3. 打开 BE 源码文件，设置断点（红色实心圆），用 MySQL 发 SQL 触发即可。

推荐断点：

| 文件 | 说明 |
|------|------|
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` 的 `_read_chunk_from_storage` | 每次从存储读 chunk 都会经过 |

### 6.5 备选：gdb 命令行调试

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
| 启动 FE | `cd output/fe && ./bin/start_fe.sh --daemon` |
| 启动 FE（Debug） | `cd output/fe && ./bin/start_fe.sh --daemon --debug` |
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

---

## 九、推荐 Debug 组合

| 组件 | 启动方式 | 调试方式 |
|------|----------|----------|
| FE | `start_fe.sh --daemon --debug` | Windows IDEA → Remote JVM Debug → `localhost:5005` |
| BE | `start_be.sh --daemon`（Debug 构建） | Windows CLion（WSL Toolchain）→ Attach to Process |

**完整链路**：MySQL 连 `localhost:9030` 执行 SQL → FE 在 Java 断点停住看解析/规划 → BE 在 C++ 断点停住看执行/存储，完整跟踪一条 SQL 从头到尾的源码路径。

```

```markdown
---
displayed_sidebar: docs
---

# WSL2 上编译、启动、Debug FE & BE

在 WSL2（Ubuntu）中完成 StarRocks 的编译、单机启动（1 FE + 1 BE）、以及 FE/BE 源码断点调试。所有命令在**项目根目录** `/home/peter/my-project/starrocks` 下执行，部署目录为 **`output/`**。

与 Docker 方案相比，WSL2 方案**不需要端口映射、不需要 SSH、不需要 gdbserver**，IDE 直接连接本地进程即可调试。

---

## 一、安装编译依赖

> 仅首次搭建环境时需要，后续不必重复。

```bash
sudo apt-get update

# 基础工具和编译器（不含 JDK，JDK 单独安装以控制版本）
sudo apt-get install -y automake binutils-dev bison byacc ccache flex libiberty-dev libtool \
    maven zip python3 python-is-python3 cmake gcc g++ git patch lld bzip2 \
    wget unzip curl make build-essential ninja-build

# 安装 JDK 17（StarRocks 3.2.x 推荐，不建议用 default-jdk 装到 21，可能有兼容问题）
sudo apt-get install -y openjdk-17-jdk

# 若系统中有多个 JDK 版本，切换到 17
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac

# 设置 JAVA_HOME（加入 ~/.bashrc 或 ~/.zshrc 以持久化）
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

验证关键版本：

```bash
gcc --version    # 需 >= 10.3（当前 13.3.0 ✓）
java --version   # 需 >= 8，推荐 17（当前 17.x ✓）
cmake --version  # 需 >= 3.20.1
mvn --version
```

---

## 二、编译

```bash
cd /home/peter/my-project/starrocks

# 编译 FE + BE（Debug 模式，首次会自动编译 thirdparty，耗时较长）
BUILD_TYPE=Debug ./build.sh --fe --be
```

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
cat output/be/log/be.INFO | grep heartbeat
```

### 4.2 把 BE 加入集群

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

FE 是 Java 进程，使用 JDWP 远程调试，**无需改代码**。

### 5.1 以 Debug 模式启动 FE

```bash
# 先停掉已运行的 FE（若有）
output/fe/bin/stop_fe.sh

# 加 --debug 启动
cd output/fe && ./bin/start_fe.sh --daemon --debug && cd ../..
```

日志中出现 `address=*:5005` 即表示调试端口已监听。

### 5.2 IDEA 连接

1. **Run → Edit Configurations → + → Remote JVM Debug**
2. Host `localhost`，Port `5005`，保存并点击 Debug。
3. WSL2 中的 5005 端口可直接从 Windows 访问（WSL2 自动转发），无需额外配置。

### 5.3 打断点验证

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
   - **Build type**：`Debug`
   - **Toolchain**：选上一步添加的 WSL toolchain
   - **Environment**：添加 `STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr`
     - `STARROCKS_CLION_ONLY=1`：只生成代码导航用的 target，不真正编译，配置速度很快
     - `STARROCKS_GCC_HOME`：指定 GCC 路径（WSL 上通过 apt 安装的 GCC 在 `/usr`）
   - 取消勾选 **Include system environment variables**（避免 Windows 环境变量干扰）

4. 在项目树中找到 `be/CMakeLists.txt` → **右键 → Load CMake Project**，等待配置完成。

### 6.2 Attach 调试

1. 确认 BE 已在 WSL 中启动：`ps aux | grep starrocks_be`。
2. CLion 中：**Run → Attach to Process...**，在列表中选 `starrocks_be`。
3. 打开 BE 源码文件，设置断点（红色实心圆），用 MySQL 发 SQL 触发即可。

推荐断点：

| 文件 | 说明 |
|------|------|
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` 的 `_read_chunk_from_storage` | 每次从存储读 chunk 都会经过 |

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
| 启动 FE | `cd output/fe && ./bin/start_fe.sh --daemon` |
| 启动 FE（Debug） | `cd output/fe && ./bin/start_fe.sh --daemon --debug` |
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

---

## 九、推荐 Debug 组合

| 组件 | 启动方式 | 调试方式 |
|------|----------|----------|
| FE | `start_fe.sh --daemon --debug` | Windows IDEA → Remote JVM Debug → `localhost:5005` |
| BE | `start_be.sh --daemon`（Debug 构建） | Windows CLion（WSL Toolchain）→ Attach to Process |

**完整链路**：MySQL 连 `localhost:9030` 执行 SQL → FE 在 Java 断点停住看解析/规划 → BE 在 C++ 断点停住看执行/存储，完整跟踪一条 SQL 从头到尾的源码路径。

```

现在更新第五节开头，因为 FE 已经在第三节就以 `--debug` 方式启动了：

```markdown
---
displayed_sidebar: docs
---

# WSL2 上编译、启动、Debug FE & BE

在 WSL2（Ubuntu）中完成 StarRocks 的编译、单机启动（1 FE + 1 BE）、以及 FE/BE 源码断点调试。所有命令在**项目根目录** `/home/peter/my-project/starrocks` 下执行，部署目录为 **`output/`**。

与 Docker 方案相比，WSL2 方案**不需要端口映射、不需要 SSH、不需要 gdbserver**，IDE 直接连接本地进程即可调试。

---

## 一、安装编译依赖

> 仅首次搭建环境时需要，后续不必重复。

```bash
sudo apt-get update

# 基础工具和编译器（不含 JDK，JDK 单独安装以控制版本）
sudo apt-get install -y automake binutils-dev bison byacc ccache flex libiberty-dev libtool \
    maven zip python3 python-is-python3 cmake gcc g++ git patch lld bzip2 \
    wget unzip curl make build-essential ninja-build

# 安装 JDK 17（StarRocks 3.2.x 推荐，不建议用 default-jdk 装到 21，可能有兼容问题）
sudo apt-get install -y openjdk-17-jdk

# 若系统中有多个 JDK 版本，切换到 17
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac

# 设置 JAVA_HOME（加入 ~/.bashrc 或 ~/.zshrc 以持久化）
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

验证关键版本：

```bash
gcc --version    # 需 >= 10.3（当前 13.3.0 ✓）
java --version   # 需 >= 8，推荐 17（当前 17.x ✓）
cmake --version  # 需 >= 3.20.1
mvn --version
```

---

## 二、编译

```bash
cd /home/peter/my-project/starrocks

# 编译 FE + BE（Debug 模式，首次会自动编译 thirdparty，耗时较长）
BUILD_TYPE=Debug ./build.sh --fe --be
```

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
cat output/be/log/be.INFO | grep heartbeat
```

### 4.2 把 BE 加入集群

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

### 5.3 打断点验证

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
   - **Build type**：`Debug`
   - **Toolchain**：选上一步添加的 WSL toolchain
   - **Environment**：添加 `STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr`
     - `STARROCKS_CLION_ONLY=1`：只生成代码导航用的 target，不真正编译，配置速度很快
     - `STARROCKS_GCC_HOME`：指定 GCC 路径（WSL 上通过 apt 安装的 GCC 在 `/usr`）
   - 取消勾选 **Include system environment variables**（避免 Windows 环境变量干扰）

4. 在项目树中找到 `be/CMakeLists.txt` → **右键 → Load CMake Project**，等待配置完成。

### 6.2 Attach 调试

1. 确认 BE 已在 WSL 中启动：`ps aux | grep starrocks_be`。
2. CLion 中：**Run → Attach to Process...**，在列表中选 `starrocks_be`。
3. 打开 BE 源码文件，设置断点（红色实心圆），用 MySQL 发 SQL 触发即可。

推荐断点：

| 文件 | 说明 |
|------|------|
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` 的 `_read_chunk_from_storage` | 每次从存储读 chunk 都会经过 |

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
| 启动 FE | `cd output/fe && ./bin/start_fe.sh --daemon` |
| 启动 FE（Debug） | `cd output/fe && ./bin/start_fe.sh --daemon --debug` |
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

---

## 九、推荐 Debug 组合

| 组件 | 启动方式 | 调试方式 |
|------|----------|----------|
| FE | `start_fe.sh --daemon --debug` | Windows IDEA → Remote JVM Debug → `localhost:5005` |
| BE | `start_be.sh --daemon`（Debug 构建） | Windows CLion（WSL Toolchain）→ Attach to Process |

**完整链路**：MySQL 连 `localhost:9030` 执行 SQL → FE 在 Java 断点停住看解析/规划 → BE 在 C++ 断点停住看执行/存储，完整跟踪一条 SQL 从头到尾的源码路径。

```

```markdown
---
displayed_sidebar: docs
---

# WSL2 上编译、启动、Debug FE & BE

在 WSL2（Ubuntu）中完成 StarRocks 的编译、单机启动（1 FE + 1 BE）、以及 FE/BE 源码断点调试。所有命令在**项目根目录** `/home/peter/my-project/starrocks` 下执行，部署目录为 **`output/`**。

与 Docker 方案相比，WSL2 方案**不需要端口映射、不需要 SSH、不需要 gdbserver**，IDE 直接连接本地进程即可调试。

---

## 一、安装编译依赖

> 仅首次搭建环境时需要，后续不必重复。

```bash
sudo apt-get update

# 基础工具和编译器（不含 JDK，JDK 单独安装以控制版本）
sudo apt-get install -y automake binutils-dev bison byacc ccache flex libiberty-dev libtool \
    maven zip python3 python-is-python3 cmake gcc g++ git patch lld bzip2 \
    wget unzip curl make build-essential ninja-build

# 安装 JDK 17（StarRocks 3.2.x 推荐，不建议用 default-jdk 装到 21，可能有兼容问题）
sudo apt-get install -y openjdk-17-jdk

# 若系统中有多个 JDK 版本，切换到 17
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac

# 设置 JAVA_HOME（加入 ~/.bashrc 或 ~/.zshrc 以持久化）
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

验证关键版本：

```bash
gcc --version    # 需 >= 10.3（当前 13.3.0 ✓）
java --version   # 需 >= 8，推荐 17（当前 17.x ✓）
cmake --version  # 需 >= 3.20.1
mvn --version
```

---

## 二、编译

```bash
cd /home/peter/my-project/starrocks

# 编译 FE + BE（Debug 模式，首次会自动编译 thirdparty，耗时较长）
BUILD_TYPE=Debug ./build.sh --fe --be
```

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
cat output/be/log/be.INFO | grep heartbeat
```

### 4.2 把 BE 加入集群

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
   - **Build type**：`Debug`
   - **Toolchain**：选上一步添加的 WSL toolchain
   - **Environment**：添加 `STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr`
     - `STARROCKS_CLION_ONLY=1`：只生成代码导航用的 target，不真正编译，配置速度很快
     - `STARROCKS_GCC_HOME`：指定 GCC 路径（WSL 上通过 apt 安装的 GCC 在 `/usr`）
   - 取消勾选 **Include system environment variables**（避免 Windows 环境变量干扰）

4. 在项目树中找到 `be/CMakeLists.txt` → **右键 → Load CMake Project**，等待配置完成。

### 6.2 Attach 调试

1. 确认 BE 已在 WSL 中启动：`ps aux | grep starrocks_be`。
2. CLion 中：**Run → Attach to Process...**，在列表中选 `starrocks_be`。
3. 打开 BE 源码文件，设置断点（红色实心圆），用 MySQL 发 SQL 触发即可。

推荐断点：

| 文件 | 说明 |
|------|------|
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` 的 `_read_chunk_from_storage` | 每次从存储读 chunk 都会经过 |

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
| 启动 FE | `cd output/fe && ./bin/start_fe.sh --daemon` |
| 启动 FE（Debug） | `cd output/fe && ./bin/start_fe.sh --daemon --debug` |
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

---

## 九、推荐 Debug 组合

| 组件 | 启动方式 | 调试方式 |
|------|----------|----------|
| FE | `start_fe.sh --daemon --debug` | Windows IDEA → Remote JVM Debug → `localhost:5005` |
| BE | `start_be.sh --daemon`（Debug 构建） | Windows CLion（WSL Toolchain）→ Attach to Process |

**完整链路**：MySQL 连 `localhost:9030` 执行 SQL → FE 在 Java 断点停住看解析/规划 → BE 在 C++ 断点停住看执行/存储，完整跟踪一条 SQL 从头到尾的源码路径。

```

最后更新常用命令小结，把 Debug 作为默认：

```markdown
---
displayed_sidebar: docs
---

# WSL2 上编译、启动、Debug FE & BE

在 WSL2（Ubuntu）中完成 StarRocks 的编译、单机启动（1 FE + 1 BE）、以及 FE/BE 源码断点调试。所有命令在**项目根目录** `/home/peter/my-project/starrocks` 下执行，部署目录为 **`output/`**。

与 Docker 方案相比，WSL2 方案**不需要端口映射、不需要 SSH、不需要 gdbserver**，IDE 直接连接本地进程即可调试。

---

## 一、安装编译依赖

> 仅首次搭建环境时需要，后续不必重复。

```bash
sudo apt-get update

# 基础工具和编译器（不含 JDK，JDK 单独安装以控制版本）
sudo apt-get install -y automake binutils-dev bison byacc ccache flex libiberty-dev libtool \
    maven zip python3 python-is-python3 cmake gcc g++ git patch lld bzip2 \
    wget unzip curl make build-essential ninja-build

# 安装 JDK 17（StarRocks 3.2.x 推荐，不建议用 default-jdk 装到 21，可能有兼容问题）
sudo apt-get install -y openjdk-17-jdk

# 若系统中有多个 JDK 版本，切换到 17
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac

# 设置 JAVA_HOME（加入 ~/.bashrc 或 ~/.zshrc 以持久化）
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

验证关键版本：

```bash
gcc --version    # 需 >= 10.3（当前 13.3.0 ✓）
java --version   # 需 >= 8，推荐 17（当前 17.x ✓）
cmake --version  # 需 >= 3.20.1
mvn --version
```

---

## 二、编译

```bash
cd /home/peter/my-project/starrocks

# 编译 FE + BE（Debug 模式，首次会自动编译 thirdparty，耗时较长）
BUILD_TYPE=Debug ./build.sh --fe --be
```

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
cat output/be/log/be.INFO | grep heartbeat
```

### 4.2 把 BE 加入集群

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
   - **Build type**：`Debug`
   - **Toolchain**：选上一步添加的 WSL toolchain
   - **Environment**：添加 `STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr`
     - `STARROCKS_CLION_ONLY=1`：只生成代码导航用的 target，不真正编译，配置速度很快
     - `STARROCKS_GCC_HOME`：指定 GCC 路径（WSL 上通过 apt 安装的 GCC 在 `/usr`）
   - 取消勾选 **Include system environment variables**（避免 Windows 环境变量干扰）

4. 在项目树中找到 `be/CMakeLists.txt` → **右键 → Load CMake Project**，等待配置完成。

### 6.2 Attach 调试

1. 确认 BE 已在 WSL 中启动：`ps aux | grep starrocks_be`。
2. CLion 中：**Run → Attach to Process...**，在列表中选 `starrocks_be`。
3. 打开 BE 源码文件，设置断点（红色实心圆），用 MySQL 发 SQL 触发即可。

推荐断点：

| 文件 | 说明 |
|------|------|
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` 的 `_read_chunk_from_storage` | 每次从存储读 chunk 都会经过 |

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

---

## 九、推荐 Debug 组合

| 组件 | 启动方式 | 调试方式 |
|------|----------|----------|
| FE | `start_fe.sh --daemon --debug` | Windows IDEA → Remote JVM Debug → `localhost:5005` |
| BE | `start_be.sh --daemon`（Debug 构建） | Windows CLion（WSL Toolchain）→ Attach to Process |

**完整链路**：MySQL 连 `localhost:9030` 执行 SQL → FE 在 Java 断点停住看解析/规划 → BE 在 C++ 断点停住看执行/存储，完整跟踪一条 SQL 从头到尾的源码路径。

```

改动完成，改了以下几处：

1. **第二节「编译」**——默认用 `BUILD_TYPE=Debug ./build.sh --fe --be`，并解释了 Debug 与 Release 的区别，末尾补了"不需要 Debug 时可用 Release"的说明
2. **第三节「启动 FE」**——直接用 `--debug` 启动，注释里说明 5005 端口用于 IDEA 调试
3. **第五节「Debug FE」**——去掉重复的"停 FE → 重新 `--debug` 启动"步骤（因为第三节已经是 `--debug` 启动的），直接从 IDEA 连接开始
4. **第六节「Debug BE」**——去掉重复的 Debug 构建和启动步骤（已在第二、四节完成），直接从 CLion 配置开始，子节编号从 6.1 重排
5. **第七节「常用命令」**——新增编译命令（Debug/Release），FE 启动默认列带调试的版本

整个文档现在的主线就是：**Debug 编译 → Debug 启动 → IDE 调试**，一气呵成。

