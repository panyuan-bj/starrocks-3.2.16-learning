# Git status performance issue
_Exported on 3/7/2026 at 21:05:59 GMT+8 from Cursor (2.3.35)_

---

**User**

我当前项目文件太多了，执行git status都特别慢，要将近10分钟才能执行出结果，有什么解决办法吗？主要是卡在refresh index这一步
@wsl (98-99)

---

**Cursor**

# Git Status 慢的解决方案

你的问题是 `git status` 在 **Refresh index** 阶段非常慢（18809个文件），这在大型仓库（如 StarRocks）中很常见。以下是几个有效的解决方案：

## 1. 启用 `core.fsmonitor`（推荐，效果最显著）

使用文件系统监控守护进程，让 Git 只检查实际发生变化的文件，而不是扫描所有文件：

PowerShell 不支持 `&&`，我改用分号：

好的，已成功配置。但是你看起来是在 **WSL** 中操作的，也需要在 WSL 里配置：

确认是在 WSL 中操作的，路径是 `/mnt/d/my-project/starrocks`。这里有一个 **关键问题**：你是在 WSL 中通过 `/mnt/d/` 访问 Windows 文件系统上的仓库！这是导致 `git status` 极慢的**根本原因**。

## 核心问题分析

你的仓库位于 **Windows 文件系统**（`D:\my-project\starrocks`），但你通过 **WSL** 的 `/mnt/d/` 路径来操作它。WSL 跨文件系统（通过 `9P` 协议桥接）访问 Windows 磁盘的 I/O 性能非常差，**比原生慢 5-10 倍**。对于 18000+ 文件的仓库，`git status` 需要逐个文件做 `stat` 调用，这会被放大到不可接受的程度。

---

## 解决方案（按效果排序）

### 方案一（最佳）：把仓库移到 WSL 原生文件系统

这是**最有效**的解决方案。把代码放到 WSL 的 `~/` 目录下而不是 `/mnt/d/`：

```bash
# 在 WSL 中执行
cp -r /mnt/d/my-project/starrocks ~/starrocks
cd ~/starrocks
git status   # 会快几十倍
```

或者重新 clone：

```bash
cd ~
git clone <your-repo-url> starrocks
```

> ⚠️ 注意：Cursor/VS Code 可以通过 WSL Remote 扩展直接打开 WSL 内的项目，所以不影响开发体验。

---

### 方案二：如果必须留在 Windows 磁盘，在 WSL 中启用优化

```bash
# 在 WSL 终端中执行
cd /mnt/d/my-project/starrocks
git config core.fsmonitor true
git config core.untrackedcache true
git config core.preloadindex true
```

> 第一次执行 `git status` 仍然会慢（因为要初始化 fsmonitor daemon），但后续执行会显著加快。

---

### 方案三：直接在 Windows (PowerShell/Git Bash) 中运行 Git 命令

如果你不需要 WSL 环境，直接在 Windows 上操作 `D:\` 盘的仓库会快得多：

```powershell
# 在 PowerShell 中
cd D:\my-project\starrocks
git status
```

Windows 原生 Git 操作 Windows 文件系统不存在跨文件系统的性能损失。

---

## 总结

| 方案 | 预期提速 | 推荐程度 |
|------|----------|----------|
| **移到 WSL 原生文件系统** (`~/`) | **10-50倍** | ⭐⭐⭐⭐⭐ |
| 启用 `fsmonitor` + `untrackedcache` | 3-5倍 | ⭐⭐⭐ |
| 在 Windows 上直接操作 | 5-10倍 | ⭐⭐⭐⭐ |

**最推荐的方案**是把仓库移到 WSL 原生文件系统（`~/starrocks`），这样 `git status` 应该可以在 **1-2 秒**内完成。跨文件系统访问是 WSL 最大的性能瓶颈之一。

```shellscript
# 在 WSL 中执行
cp -r /mnt/d/my-project/starrocks ~/starrocks
cd ~/starrocks
git status   # 会快几十倍
```

```shellscript
cd ~
git clone <your-repo-url> starrocks
```

```shellscript
# 在 WSL 终端中执行
cd /mnt/d/my-project/starrocks
git config core.fsmonitor true
git config core.untrackedcache true
git config core.preloadindex true
```

```powershell
# 在 PowerShell 中
cd D:\my-project\starrocks
git status
```

---

**User**

我这有个疑问，我执行方案一的话，把项目文件夹移动到了 ~/starrocks，是相当于windows里、wsl里各有一份starrocks文件夹了吗？而我的cursor是要打开starrocks文件夹的，我似乎只能从windows里引入文件夹，那我在cursor里改文件内容，~/starrocks中的文件内容岂不是无法被同步修改？因为这是两份文件

---

**Cursor**

你的疑问非常合理，我来解释清楚：

## 不用担心，Cursor 可以直接打开 WSL 里的文件夹

你**不需要**在 Windows 里打开文件夹。Cursor（基于 VS Code）原生支持 **WSL Remote** 模式，可以直接打开 WSL 文件系统中的项目。

### 具体做法

1. **把仓库移到 WSL 原生文件系统**（`~/starrocks`）
2. **从 WSL 终端启动 Cursor**：

```bash
# 在 WSL 终端中
cd ~/starrocks
cursor .
```

或者在 Cursor 中：
- 按 `Ctrl+Shift+P` → 输入 `WSL: Open Folder in WSL...` → 选择 `~/starrocks`

这样 Cursor 会以 **WSL Remote** 模式运行，直接操作的就是 `~/starrocks` 里的文件，**不存在两份文件的问题**。你在 Cursor 里的编辑、终端里的 `git status`，操作的都是同一份文件。

### 你可能在 Cursor 左下角看到类似这样的标识

```
WSL: Ubuntu
```

这说明 Cursor 已经连接到 WSL 了，所有文件操作都发生在 WSL 文件系统中。

---

## 总结

| 你的担心 | 实际情况 |
|---------|---------|
| Windows 和 WSL 各一份文件？ | ✅ 移动后只保留 WSL 里那一份就行，Windows 的可以删掉 |
| Cursor 只能打开 Windows 文件夹？ | ❌ Cursor 支持直接打开 WSL 里的文件夹 |
| 两份文件无法同步？ | 不存在这个问题，只有一份文件 |

所以流程就是：

```bash
# 1. 移动仓库到 WSL 原生文件系统
mv /mnt/d/my-project/starrocks ~/starrocks

# 2. 用 Cursor 打开（WSL 终端中）
cd ~/starrocks
cursor .
```

之后你的 Cursor 和终端操作的就是同一个目录，`git status` 也会飞快。

```shellscript
# 在 WSL 终端中
cd ~/starrocks
cursor .
```

```plaintext
WSL: Ubuntu
```

```shellscript
# 1. 移动仓库到 WSL 原生文件系统
mv /mnt/d/my-project/starrocks ~/starrocks

# 2. 用 Cursor 打开（WSL 终端中）
cd ~/starrocks
cursor .
```

---

**User**

OK，我明白了，一会就去试，我还想问个问题，wsl系统里存的文件，在我windows下的哪个盘呢？我现在有两块ssd，一块ssd里有C盘（系统盘）和D盘，一块ssd只有E盘，D、E是文件盘

---

**Cursor**

好问题！WSL 文件系统默认存储在 **C 盘（系统盘）** 中。

## 具体位置

WSL 的文件存储在：

```
C:\Users\<你的用户名>\AppData\Local\Packages\<WSL发行版名称>\LocalState\ext4.vhdx
```

它本质上是一个 **虚拟磁盘文件**（`ext4.vhdx`），你 WSL 里 `~/` 下的所有文件都在这个 vhdx 文件里。

你可以验证一下：

```plaintext
C:\Users\<你的用户名>\AppData\Local\Packages\<WSL发行版名称>\LocalState\ext4.vhdx
```

没找到，可能你的 WSL 是通过其他方式安装的。让我换个方式查：

找到了！让我看看虚拟磁盘文件的具体位置和大小：

这个包目录下没有 vhdx 文件，说明你的 Ubuntu 发行版是另外安装的。让我直接在 WSL 里查：

找到了！结果非常清晰。

## 结论

你的 **WSL Ubuntu 文件系统**存储在：

```
C:\Users\peter\AppData\Local\wsl\{41e2bf22-4268-47f6-8828-053057f86158}\ext4.vhdx
```

- **位置：C 盘（系统盘）**
- **当前大小：10.42 GB**
- 它是一个虚拟磁盘文件（vhdx），WSL 里 `~/` 下的所有内容都在这个文件里

另外那个 `Docker\wsl\main\ext4.vhdx`（0.1 GB）是 Docker Desktop 的 WSL 数据，不用管。

---

## 需要注意的事

### ⚠️ C 盘空间

StarRocks 源码比较大，如果你把仓库移到 `~/starrocks`，加上编译产物，可能还需要 **额外 5-15 GB** 的 C 盘空间。请确认你的 C 盘空间够用。

### 🔄 如果 C 盘空间不够，可以把 WSL 迁移到 D 盘或 E 盘

```powershell
# 1. 导出 WSL
wsl --export Ubuntu D:\wsl-backup\ubuntu.tar

# 2. 注销原来的
wsl --unregister Ubuntu

# 3. 导入到 D 盘或 E 盘
wsl --import Ubuntu D:\WSL\Ubuntu D:\wsl-backup\ubuntu.tar

# 4. 设为默认
wsl -s Ubuntu
```

这样整个 WSL 文件系统就搬到 D 盘了，既有 WSL 原生文件系统的性能优势，又不占 C 盘空间。**两全其美！**

```plaintext
C:\Users\peter\AppData\Local\wsl\{41e2bf22-4268-47f6-8828-053057f86158}\ext4.vhdx
```

```powershell
# 1. 导出 WSL
wsl --export Ubuntu D:\wsl-backup\ubuntu.tar

# 2. 注销原来的
wsl --unregister Ubuntu

# 3. 导入到 D 盘或 E 盘
wsl --import Ubuntu D:\WSL\Ubuntu D:\wsl-backup\ubuntu.tar

# 4. 设为默认
wsl -s Ubuntu
```

---

**User**

我C盘空间足够用。听完你的说明后，我对wsl有了新的认知，我决定以后都把需要在wsl环境运行的文件，从windows磁盘迁移过来

我现在有两个ssd，分别都是1TB的，第一个ssd是C盘、D盘，已经存储了很多文件，还有一个ssd是E盘，我打算把D盘里面的游戏大文件等都逐步迁移到D盘中，然后用分区助手这个软件，把D盘的空间逐步挪给C盘用，这样我wsl环境下的空间就肯定够用了

我还有一些疑问
1、我本地还有一个docker，名字叫：starrocks-dev。我想知道这个docker里的文件是存储在windows上的哪里？
2、我在docker中已经配好了starrocks的许多环境，我通过 docker exec -it starrocks-dev bash 这个命令行可以登录到docker上，在/workspace这个目录下，全是starrocks文件，我想知道docker中的/workspace的starrocks文件，是单独的一套文件，还是引用了D盘下my-project\starrocks的文件？如果是后者，那我按照之前说的，把D盘下的starrocks复制到wsl的~/starrocks后，我肯定希望删除掉D盘的starrocks，这样能省空间，但是就会导致我docker中的starrocks无法被使用了，配置starrocks环境需要编译fe、be，安装很多东西，非常麻烦、繁琐，我不太希望再重新来一遍

---

**Cursor**

非常好的问题！让我先帮你查清楚这两个问题的实际情况。

关键信息已经拿到了！再看一下这个容器的完整配置：

好了，所有信息都搞清楚了。下面给你完整解答：

---

## 回答你的问题

### 问题 1：Docker 的文件存储在哪里？

Docker Desktop 在 Windows 上是通过 WSL 运行的，它的数据存储在：

```
C:\Users\peter\AppData\Local\Docker\wsl\main\ext4.vhdx  (目前仅 0.1 GB)
```

但 Docker 容器自身的分层文件系统也在 C 盘的 Docker 数据目录中。你的容器内 **非挂载** 的文件（编译环境、工具链、缓存等）都在这里面。

### 问题 2：Docker 中 `/workspace` 是独立文件还是引用？

**答案是：引用（挂载），不是独立的一份！**

```
/mnt/d/my-project/starrocks  →  挂载到容器内  /workspace
```

也就是说，Docker 容器里的 `/workspace` 和你 Windows 上 `D:\my-project\starrocks` 是 **同一份文件**。你在容器里改文件，D 盘上也会变；删了 D 盘的，容器里也没了。

### 你的容器内数据分布

| 位置 | 大小 | 性质 | 删除 D 盘后是否受影响 |
|------|------|------|---------------------|
| `/workspace/`（D盘挂载） | 30 GB | 挂载的 D 盘文件 | ❌ **会丢失** |
| `/root/.m2/`（Maven 缓存） | 1.6 GB | 容器内独立存储 | ✅ 不受影响 |
| `/root/.cache/ccache/`（C++编译缓存） | 2.9 GB | 容器内独立存储 | ✅ 不受影响 |
| `/root/.cache/JetBrains/` | 6.7 GB | 容器内独立存储 | ✅ 不受影响 |
| `/opt/`（工具链等） | 437 MB | 容器内独立存储 | ✅ 不受影响 |

---

## 你真正担心的问题

你担心的是：**删了 D 盘的 starrocks 后，Docker 里配好的编译环境就白费了。**

好消息是：**你配的环境不会丢！** 你的编译环境（Maven 缓存 `.m2`、C++ 编译缓存 `ccache`、各种工具链 `/opt`）都存储在**容器内部**，不在 D 盘上。丢失的只是源码和编译产物（output），而源码你会移到 WSL 的 `~/starrocks`，编译产物重新编译就行。

### 推荐的迁移方案

你只需要 **把挂载路径改一下**，让 Docker 容器的 `/workspace` 指向 WSL 的 `~/starrocks` 即可：

```bash
# 步骤 1：把源码复制到 WSL（你之前已经计划做的）
# 在 WSL 终端中
cp -r /mnt/d/my-project/starrocks ~/starrocks

# 步骤 2：停掉旧容器
docker stop starrocks-dev

# 步骤 3：用同样的镜像创建新容器，只改挂载路径
docker run -it -d \
  --name starrocks-dev-new \
  -v ~/starrocks:/workspace \
  starrocks/dev-env-ubuntu:latest

# 步骤 4：把旧容器里的环境缓存复制到新容器
docker cp starrocks-dev:/root/.m2 /tmp/.m2
docker cp starrocks-dev:/root/.cache /tmp/.cache
docker cp /tmp/.m2 starrocks-dev-new:/root/.m2
docker cp /tmp/.cache starrocks-dev-new:/root/.cache

# 步骤 5：验证新容器一切正常后，再删除旧容器和 D 盘文件
docker rm starrocks-dev
# 然后删除 D:\my-project\starrocks
```

> **注意**：由于新容器挂载的 `~/starrocks` 在 WSL 原生文件系统上，Docker 容器内的编译速度也会更快（同样受益于避免跨文件系统 I/O）。

### 更简单的替代方案

如果你不想折腾新容器，也可以直接修改旧容器的挂载点。但 Docker 不支持直接改正在运行的容器的挂载，所以最稳妥的还是上面创建新容器 + 迁移缓存的方案。整个过程**不需要重新编译环境**，只需要重新 `build.sh` 编译一次源码即可。

```plaintext
C:\Users\peter\AppData\Local\Docker\wsl\main\ext4.vhdx  (目前仅 0.1 GB)
```

```plaintext
/mnt/d/my-project/starrocks  →  挂载到容器内  /workspace
```

```shellscript
# 步骤 1：把源码复制到 WSL（你之前已经计划做的）
# 在 WSL 终端中
cp -r /mnt/d/my-project/starrocks ~/starrocks

# 步骤 2：停掉旧容器
docker stop starrocks-dev

# 步骤 3：用同样的镜像创建新容器，只改挂载路径
docker run -it -d \
  --name starrocks-dev-new \
  -v ~/starrocks:/workspace \
  starrocks/dev-env-ubuntu:latest

# 步骤 4：把旧容器里的环境缓存复制到新容器
docker cp starrocks-dev:/root/.m2 /tmp/.m2
docker cp starrocks-dev:/root/.cache /tmp/.cache
docker cp /tmp/.m2 starrocks-dev-new:/root/.m2
docker cp /tmp/.cache starrocks-dev-new:/root/.cache

# 步骤 5：验证新容器一切正常后，再删除旧容器和 D 盘文件
docker rm starrocks-dev
# 然后删除 D:\my-project\starrocks
```

---

**User**

好，我还没操作。我发现一个新问题，就是假设我把starrocks迁移到wsl的~/starrocks中之后，我需要打开cursor，导入wsl的starrocks

根据你之前给我的提示，我在wsl中执行 cursor . 就行
但是我执行后得到如下报错
➜  ~ cursor .
/mnt/c/Users/peter/.cursor/extensions/anysphere.remote-wsl-1.0.13/dist/scripts/wslCursor.sh: 52: /home/peter/.cursor-server/bin/cf8353edc265f5e46b798bfb276861d0bf3bf120/bin/remote-cli/cursor: not found

还有一个办法就是按 Ctrl+Shift+P → 输入 WSL: Open Folder in WSL... → 选择 ~/starrocks
但是我在选择文件夹的弹窗中，无法选择到wsl主目录下的~/starrocks，只有windows的文件系统，没有wsl的

所以我犯难了，整体我是希望把starrocks迁移到wsl上，以后我所有源码编译、运行、debug的操作，我都放在wsl上进行，甚至重新来一遍编译我也愿意

---

**Cursor**

这个问题是因为 Cursor 的 WSL Remote 组件没有正确安装。让我帮你一步步排查和解决。

问题清楚了。目录 `cf8353edc265f5e46b798bfb276861d0bf3bf120` 是空的，Cursor Server 没有成功下载到 WSL 中。让我来帮你修复：

好的，已经清理掉了损坏的 cursor-server 目录。现在请按以下步骤操作：

## 修复方案

### 第一步：从 Cursor 内部连接 WSL

不要从 WSL 终端执行 `cursor .`，而是：

1. **打开 Cursor**（正常在 Windows 上打开）
2. 按 **`Ctrl+Shift+P`**
3. 输入 **`WSL: Connect to WSL`**（不是 Open Folder），先回车连接

这一步会触发 Cursor 自动将 Server 组件下载并安装到 WSL 中。等左下角出现 `WSL: Ubuntu` 标识后，说明连接成功。

4. 然后再按 **`Ctrl+Shift+P`** → 输入 **`File: Open Folder`**
5. 此时弹出的路径选择框**就是 WSL 文件系统**了，在顶部输入框中直接输入：

```
/home/peter/starrocks
```

（如果你还没复制 starrocks 过去，可以先输入 `/home/peter` 看看是否能打开，验证 WSL 连接是 OK 的）

---

### 如果 `WSL: Connect to WSL` 找不到

说明你的 Cursor 缺少 WSL 扩展，在 Cursor 的扩展商店中搜索并安装 **`WSL`**（发布者为 anysphere 或 Microsoft），安装后重试。

从你的报错路径来看，你已经有 `anysphere.remote-wsl-1.0.13` 这个扩展了，所以大概率直接 `Connect to WSL` 就行。

---

### 操作流程总结

```
在 Cursor 中操作（不是在终端里）：

Ctrl+Shift+P → WSL: Connect to WSL → 等待连接成功
                                        ↓
                            左下角显示 "WSL: Ubuntu"
                                        ↓
Ctrl+Shift+P → File: Open Folder → 输入 /home/peter/starrocks → 确认
```

你先试试这个方案，如果 Cursor 连接 WSL 成功，之后在 WSL 终端中执行 `cursor .` 也会正常工作了（因为 Server 组件已经被正确安装到 WSL 中）。

```plaintext
/home/peter/starrocks
```

```plaintext
在 Cursor 中操作（不是在终端里）：

Ctrl+Shift+P → WSL: Connect to WSL → 等待连接成功
                                        ↓
                            左下角显示 "WSL: Ubuntu"
                                        ↓
Ctrl+Shift+P → File: Open Folder → 输入 /home/peter/starrocks → 确认
```

---

**User**

OK，这下OK了，在wsl中执行cursor .，已经能出cursor了

请你把我上述沟通的所有内容，尤其是我提的问题和你的方案和建议，精简的罗列总结一下，我这边会保存为一份文档，以便以后复习使用

---

**Cursor**



很高兴问题解决了！以下是完整的总结：

---

## 总结文档

### 一、问题：Git Status 在 WSL 中极慢（卡在 Refresh Index）

**根本原因**：仓库在 Windows 文件系统（`D:\`），通过 WSL 的 `/mnt/d/` 跨文件系统访问，I/O 性能比 WSL 原生文件系统慢 5-10 倍。18000+ 文件逐个 `stat`，耗时被严重放大。

**最佳方案**：将仓库迁移到 WSL 原生文件系统（`~/starrocks`），`git status` 可从近 10 分钟缩短到 1-2 秒。

**备选优化**（如不迁移）：
```bash
git config core.fsmonitor true
git config core.untrackedcache true
git config core.preloadindex true
```

---

### 二、WSL 文件存储位置

WSL 文件系统存储在 Windows 的 **C 盘**，以虚拟磁盘（vhdx）形式存在：

```
C:\Users\peter\AppData\Local\wsl\{41e2bf22-...}\ext4.vhdx
```

如果 C 盘空间不够，可以将整个 WSL 迁移到其他盘：
```powershell
wsl --export Ubuntu D:\wsl-backup\ubuntu.tar
wsl --unregister Ubuntu
wsl --import Ubuntu D:\WSL\Ubuntu D:\wsl-backup\ubuntu.tar
wsl -s Ubuntu
```

---

### 三、Docker 容器 starrocks-dev 的文件存储

**容器 `/workspace` 是挂载，不是独立文件：**

```
D:\my-project\starrocks  ←→  容器 /workspace（同一份文件）
```

**容器内独立存储的环境数据（不受 D 盘影响）：**

| 目录 | 大小 | 内容 |
|------|------|------|
| `/root/.m2/` | 1.6 GB | Maven 缓存 |
| `/root/.cache/ccache/` | 2.9 GB | C++ 编译缓存 |
| `/root/.cache/JetBrains/` | 6.7 GB | IDE 缓存 |
| `/opt/` | 437 MB | 工具链 |

**迁移后如需保留 Docker 环境**：创建新容器挂载 WSL 路径，用 `docker cp` 迁移缓存：
```bash
docker run -it -d --name starrocks-dev-new \
  -v ~/starrocks:/workspace \
  starrocks/dev-env-ubuntu:latest

docker cp starrocks-dev:/root/.m2 /tmp/.m2
docker cp starrocks-dev:/root/.cache /tmp/.cache
docker cp /tmp/.m2 starrocks-dev-new:/root/.m2
docker cp /tmp/.cache starrocks-dev-new:/root/.cache
```

---

### 四、Cursor 连接 WSL 的方法

**从 WSL 终端启动**：
```bash
cd ~/starrocks
cursor .
```

**从 Cursor 内连接**：
```
Ctrl+Shift+P → WSL: Connect to WSL → 等左下角显示 "WSL: Ubuntu"
Ctrl+Shift+P → File: Open Folder → 输入 /home/peter/starrocks
```

**如果 `cursor .` 报错 `cursor: not found`**：
1. 清理损坏的 server 目录：`rm -rf ~/.cursor-server`
2. 先在 Cursor 中通过 `Ctrl+Shift+P → WSL: Connect to WSL` 连接一次（触发 Server 自动安装）
3. 之后 `cursor .` 即可正常使用

---

### 五、核心原则

> **在 WSL 中操作的项目，源码应放在 WSL 原生文件系统（`~/`）下，而不是 `/mnt/` 挂载的 Windows 磁盘。** 这对 Git、编译、文件读写的性能都有数量级的提升。

```shellscript
git config core.fsmonitor true
git config core.untrackedcache true
git config core.preloadindex true
```

```plaintext
C:\Users\peter\AppData\Local\wsl\{41e2bf22-...}\ext4.vhdx
```

```powershell
wsl --export Ubuntu D:\wsl-backup\ubuntu.tar
wsl --unregister Ubuntu
wsl --import Ubuntu D:\WSL\Ubuntu D:\wsl-backup\ubuntu.tar
wsl -s Ubuntu
```

```plaintext
D:\my-project\starrocks  ←→  容器 /workspace（同一份文件）
```

```shellscript
docker run -it -d --name starrocks-dev-new \
  -v ~/starrocks:/workspace \
  starrocks/dev-env-ubuntu:latest

docker cp starrocks-dev:/root/.m2 /tmp/.m2
docker cp starrocks-dev:/root/.cache /tmp/.cache
docker cp /tmp/.m2 starrocks-dev-new:/root/.m2
docker cp /tmp/.cache starrocks-dev-new:/root/.cache
```

```shellscript
cd ~/starrocks
cursor .
```

```plaintext
Ctrl+Shift+P → WSL: Connect to WSL → 等左下角显示 "WSL: Ubuntu"
Ctrl+Shift+P → File: Open Folder → 输入 /home/peter/starrocks
```

