# WSL上启动及debug FE和BE遇到的问题
_Exported on 3/9/2026 at 00:39:54 GMT+8 from Cursor (2.3.35)_

---

**User**

启动fe，命令行日志如下：
@zsh (17-20) 

没有生成output/fe/log/fe.log文件
@zsh (14-15)

 但是有output/fe/log/fe.out文件
内容如下
@fe.out (1-7) 

请问是启动的参数中，PrintGCDateStamps在jdk-17里不适配吗？

---

**Cursor**

是的，你的判断完全正确！问题就出在 JVM 参数上。

## 原因分析

在 **JDK 9+** 中，以下 GC 日志相关的参数已经被**移除**了：

- `-XX:+PrintGCDetails` ❌
- `-XX:+PrintGCDateStamps` ❌
- `-Xloggc:<file>` ❌
- `-XX:+PrintConcurrentLocks`（这个还在）

JDK 9 引入了**统一的 GC 日志框架 (Unified GC Logging)**，用 `-Xlog:gc*` 来替代上述所有旧参数。所以在 JDK 17 中使用 `PrintGCDateStamps` 会直接报错：

> `Unrecognized VM option 'PrintGCDateStamps'`

这导致 JVM 根本启动不了，所以 `fe.log` 文件也不会生成。

让我看一下 FE 的启动脚本，帮你修复这个问题。

现在让我看一下 `fe.conf` 中 `JAVA_OPTS` 的配置：

找到问题了！让我来看看启动脚本中的 JDK 版本判断逻辑：

**问题完全定位了！** 来看看根因：

## 根因分析

在 `fe.conf` 中，配置了两组 `JAVA_OPTS`：

- **第 27 行 `JAVA_OPTS`**（JDK 8 用的）：包含 `-XX:+PrintGCDetails -XX:+PrintGCDateStamps -Xloggc:...` 这些**旧版 GC 日志参数**
- **第 30 行 `JAVA_OPTS_FOR_JDK_11`**（JDK 11+ 用的）：已经用了新的 `-Xlog:gc*:...` 格式 ✅

但是 `start_fe.sh` 的第 132-141 行，`case` 语句只匹配了 `11`，JDK 17 会走到 `*` 通配分支，使用的是**旧版的 `JAVA_OPTS`**，而不是 `JAVA_OPTS_FOR_JDK_11`！

所以你的 JDK 17 用了 JDK 8 的 GC 参数，自然报 `Unrecognized VM option 'PrintGCDateStamps'`。

## 修复方案

需要修改 `start_fe.sh`，让 JDK 17（以及其他 11+ 的版本）也使用 `JAVA_OPTS_FOR_JDK_11`：

```shellscript
#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

curdir=`dirname "$0"`
curdir=`cd "$curdir"; pwd`

OPTS=$(getopt \
  -n $0 \
  -o '' \
  -l 'daemon' \
  -l 'helper:' \
  -l 'host_type:' \
  -l 'debug' \
  -l 'logconsole' \
  -- "$@")

eval set -- "$OPTS"

RUN_DAEMON=0
HELPER=
HOST_TYPE=
ENABLE_DEBUGGER=0
RUN_LOG_CONSOLE=${SYS_LOG_TO_CONSOLE:-0}
while true; do
    case "$1" in
        --daemon) RUN_DAEMON=1 ; shift ;;
        --helper) HELPER=$2 ; shift 2 ;;
        --host_type) HOST_TYPE=$2 ; shift 2 ;;
        --debug) ENABLE_DEBUGGER=1 ; shift ;;
        --logconsole) RUN_LOG_CONSOLE=1 ; shift ;;
        --) shift ;  break ;;
        *) echo "Internal error" ; exit 1 ;;
    esac
done

export STARROCKS_HOME=`cd "$curdir/.."; pwd`

# compatible with DORIS_HOME: DORIS_HOME still be using in config on the user side, so set DORIS_HOME to the meaningful value in case of wrong envs.
export DORIS_HOME="$STARROCKS_HOME"

source $STARROCKS_HOME/bin/common.sh

check_and_update_max_processes

# export env variables from fe.conf
#
# JAVA_OPTS
# LOG_DIR
# PID_DIR
export LOG_DIR="$STARROCKS_HOME/log"
export PID_DIR=`cd "$curdir"; pwd`
export_env_from_conf $STARROCKS_HOME/conf/fe.conf

if [ -e $STARROCKS_HOME/conf/hadoop_env.sh ]; then
    source $STARROCKS_HOME/conf/hadoop_env.sh
fi

# java
if [[ -z ${JAVA_HOME} ]]; then
    if command -v javac &> /dev/null; then
        export JAVA_HOME="$(dirname $(dirname $(readlink -f $(which javac))))"
        echo "Infered JAVA_HOME=$JAVA_HOME"
    else
      cat << EOF
Error: The environment variable JAVA_HOME is not set. The FE program requires JDK version 8 or higher in order to run.
Please take the following steps to resolve this issue:
1. Install OpenJDK 8 or higher using your Linux distribution's package manager.
For example:
sudo apt install openjdk-8-jdk  (on Ubuntu/Debian)
sudo yum install java-1.8.0-openjdk-devel (on CentOS/RHEL)
2. Set the JAVA_HOME environment variable to point to your installed OpenJDK directory.
For example:
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
3. Try running this script again.
EOF
      exit 1
    fi
fi

# cannot be jre
if [ ! -f "$JAVA_HOME/bin/javac" ]; then
  cat << EOF
Error: It appears that your JAVA_HOME environment variable is pointing to a non-JDK path: $JAVA_HOME
The FE program requires the full JDK to be installed and configured properly. Please check that JAVA_HOME
is set to the installation directory of JDK 8 or higher, rather than the JRE installation directory.
EOF
  exit 1
fi

JAVA=$JAVA_HOME/bin/java

# check java version and choose correct JAVA_OPTS
JAVA_VERSION=$(jdk_version)
# JDK8 is still OK for v3.2.x, so this line will just block jdk9 and jdk10
if [[ "$JAVA_VERSION" -gt 8 && "$JAVA_VERSION" -lt 11 ]]; then
    echo "JDK $JAVA_VERSION is not supported, please use JDK 8, 11 or 17"
    exit -1
fi

# ### Things to know about environment variables of JAVA_OPTS, JAVA_OPTS_FOR_JDK_9 and JAVA_OPTS_FOR_JDK_11
# * It is historic reason and backwards compatibility consideration to have separate JAVA_OPTS
#   for diffferent versions of JDK, so that when the user upgrades or downgrades the JDK version,
#   the JAVA_OPTS won't be suddenly broken.
# * Ideally, the user will only care about the `JAVA_OPTS`, don't set any JAVA_OPTS_FOR_JDK_*
# * JAVA_OPTS/JAVA_OPTS_FOR_JDK_9/JAVA_OPTS_FOR_JDK_11 can be either set in the shell before invoking
#   this script, or can be set in `fe.conf` which will be loaded automatically by `export_env_from_conf`
#
# ### Precedence of environment variables
# For JDK11, it takes the following precedences:
#    JAVA_OPTS_FOR_JDK_11 > JAVA_OPTS_FOR_JDK_9 > JAVA_OPTS
# (The `JAVA_OPTS_FOR_JDK_9` here is just for historic reason)
# For all remain jdk versions, only JAVA_OPTS takes effect.
#
# NOTE: try not adding new JAVA_OPTS_FOR_JDK_## for a new JDK version.
#
final_java_opt=
if [[ "$JAVA_VERSION" -ge 11 ]]; then
    # For JDK 11+, take JAVA_OPTS_FOR_JDK_11 or JAVA_OPTS_FOR_JDK_9 if the former is empty
    final_java_opt=${JAVA_OPTS_FOR_JDK_11:-$JAVA_OPTS_FOR_JDK_9}
    final_java_opt=${final_java_opt:-$JAVA_OPTS}
else
    final_java_opt=$JAVA_OPTS
fi

if [ -z "$final_java_opt" ] ; then
    # lookup fails, provide a fixed opts with best guess that may or may not work
    if [ -z "$DATE" ] ; then
        DATE=`date +%Y%m%d-%H%M%S`
    fi
    final_java_opt="-Dlog4j2.formatMsgNoLookups=true -Xmx8192m -XX:+UseG1GC -Xlog:gc*:${LOG_DIR}/fe.gc.log.$DATE:time"
    echo "JAVA_OPTS is not set in fe.conf, use default java options to start fe process: $final_java_opt"
fi

# Auto detect jvm -Xmx parameter in case $FE_ENABLE_AUTO_JVM_XMX_DETECT = true
#  default to 70% of total available mem and can be tuned by env var: FE_JVM_XMX_PERCENTAGE
# NOTE: the feature is only supported in container env
xmx=$(detect_jvm_xmx)
final_java_opt="${final_java_opt} ${xmx}"

if [[ "$JAVA_VERSION" -lt 11 ]]; then
    echo "Tips: current JDK version is $JAVA_VERSION, JDK 11 or 17 is highly recommended for better GC performance(lower version JDK may not be supported in the future)"
    if [[ "$JAVA_VERSION" == 8 ]]; then
        export JAVA=${JAVA_HOME}/bin/java
        JAVA_UPDATE_VER=$(${JAVA} -version 2>&1 | sed -n 's/.* version "1\.8\.0_\([0-9]*\)".*/\1/p')
        if [[ $JAVA_UPDATE_VER -lt 192 ]]; then
            echo "Tips: JAVA_UPDATE_VER is $JAVA_UPDATE_VER, Please upgrade the JAVA version to at least 1.8.0_192 to avoid potential issues of G1 gc on jdk8."
        fi
    fi
fi

if [ ${ENABLE_DEBUGGER} -eq 1 ]; then
    # Allow attaching debuggers to the FE process:
    # https://www.jetbrains.com/help/idea/attaching-to-local-process.html
    if [[ "$JAVA_VERSION" -gt 8 ]]; then
        final_java_opt="${final_java_opt} -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005"
    else
        final_java_opt="${final_java_opt} -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005"
    fi
    echo "Start debugger with: $final_java_opt"
fi

# add datadog profile settings when enabled
if [ "${ENABLE_DATADOG_PROFILE}" == "true" ] && [ -f "${STARROCKS_HOME}/datadog/dd-java-agent.jar" ]; then
    final_java_opt="-javaagent:${STARROCKS_HOME}/datadog/dd-java-agent.jar ${final_java_opt}"
fi

if [ ! -d $LOG_DIR ]; then
    mkdir -p $LOG_DIR
fi

read_var_from_conf meta_dir $STARROCKS_HOME/conf/fe.conf
mkdir -p ${meta_dir:-"$STARROCKS_HOME/meta"}

# add libs to CLASSPATH
for f in $STARROCKS_HOME/lib/*.jar; do
  CLASSPATH=$f:${CLASSPATH};
done
export CLASSPATH=${STARROCKS_HOME}/lib/starrocks-hadoop-ext.jar:${CLASSPATH}:${STARROCKS_HOME}/lib:${STARROCKS_HOME}/conf

pidfile=$PID_DIR/fe.pid

if [ -f $pidfile ]; then
  oldpid=$(cat $pidfile)
  # get the full command
  pscmd=$(ps -q $oldpid -o cmd=)
  if echo "$pscmd" | grep -q -w StarRocksFE &>/dev/null ; then
    echo Frontend running as process $oldpid. Stop it first.
    exit 1
  fi
fi

if [ ! -f /bin/limit ]; then
    LIMIT=
else
    LIMIT=/bin/limit
fi

if [ x"$HELPER" != x"" ]; then
    # change it to '-helper' to be compatible with code in Frontend
    HELPER="-helper $HELPER"
fi

if [ x"$HOST_TYPE" != x"" ]; then
    # change it to '-host_type' to be compatible with code in Frontend
    HOST_TYPE="-host_type $HOST_TYPE"
fi

LOG_FILE=$LOG_DIR/fe.out

if [ ${RUN_LOG_CONSOLE} -eq 1 ] ; then
    if [ ! -w $STARROCKS_HOME/conf/fe.conf ] ; then
        # workaround configmap readonly, can't change its content
        mv $STARROCKS_HOME/conf/fe.conf $STARROCKS_HOME/conf/fe.conf.readonly
        cp $STARROCKS_HOME/conf/fe.conf.readonly $STARROCKS_HOME/conf/fe.conf
    fi
else
    # redirect all subsequent commands' stdout/stderr into $LOG_FILE
    exec >> $LOG_FILE 2>&1
fi
export SYS_LOG_TO_CONSOLE=${RUN_LOG_CONSOLE}

echo "using java version $JAVA_VERSION"
echo $final_java_opt
echo "start time: $(date), server uptime: $(uptime)"

# StarRocksFE java process will write its process id into $pidfile
if [ ${RUN_DAEMON} -eq 1 ]; then
    nohup $LIMIT $JAVA $final_java_opt com.starrocks.StarRocksFE ${HELPER} ${HOST_TYPE} "$@" </dev/null &
else
    exec $LIMIT $JAVA $final_java_opt com.starrocks.StarRocksFE ${HELPER} ${HOST_TYPE} "$@" </dev/null
fi

```

现在也把源码里的脚本一起改了，这样下次编译后也不会有这个问题：

```shellscript
#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

curdir=`dirname "$0"`
curdir=`cd "$curdir"; pwd`

OPTS=$(getopt \
  -n $0 \
  -o '' \
  -l 'daemon' \
  -l 'helper:' \
  -l 'host_type:' \
  -l 'debug' \
  -l 'logconsole' \
  -- "$@")

eval set -- "$OPTS"

RUN_DAEMON=0
HELPER=
HOST_TYPE=
ENABLE_DEBUGGER=0
RUN_LOG_CONSOLE=${SYS_LOG_TO_CONSOLE:-0}
while true; do
    case "$1" in
        --daemon) RUN_DAEMON=1 ; shift ;;
        --helper) HELPER=$2 ; shift 2 ;;
        --host_type) HOST_TYPE=$2 ; shift 2 ;;
        --debug) ENABLE_DEBUGGER=1 ; shift ;;
        --logconsole) RUN_LOG_CONSOLE=1 ; shift ;;
        --) shift ;  break ;;
        *) echo "Internal error" ; exit 1 ;;
    esac
done

export STARROCKS_HOME=`cd "$curdir/.."; pwd`

# compatible with DORIS_HOME: DORIS_HOME still be using in config on the user side, so set DORIS_HOME to the meaningful value in case of wrong envs.
export DORIS_HOME="$STARROCKS_HOME"

source $STARROCKS_HOME/bin/common.sh

check_and_update_max_processes

# export env variables from fe.conf
#
# JAVA_OPTS
# LOG_DIR
# PID_DIR
export LOG_DIR="$STARROCKS_HOME/log"
export PID_DIR=`cd "$curdir"; pwd`
export_env_from_conf $STARROCKS_HOME/conf/fe.conf

if [ -e $STARROCKS_HOME/conf/hadoop_env.sh ]; then
    source $STARROCKS_HOME/conf/hadoop_env.sh
fi

# java
if [[ -z ${JAVA_HOME} ]]; then
    if command -v javac &> /dev/null; then
        export JAVA_HOME="$(dirname $(dirname $(readlink -f $(which javac))))"
        echo "Infered JAVA_HOME=$JAVA_HOME"
    else
      cat << EOF
Error: The environment variable JAVA_HOME is not set. The FE program requires JDK version 8 or higher in order to run.
Please take the following steps to resolve this issue:
1. Install OpenJDK 8 or higher using your Linux distribution's package manager.
For example:
sudo apt install openjdk-8-jdk  (on Ubuntu/Debian)
sudo yum install java-1.8.0-openjdk-devel (on CentOS/RHEL)
2. Set the JAVA_HOME environment variable to point to your installed OpenJDK directory.
For example:
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
3. Try running this script again.
EOF
      exit 1
    fi
fi

# cannot be jre
if [ ! -f "$JAVA_HOME/bin/javac" ]; then
  cat << EOF
Error: It appears that your JAVA_HOME environment variable is pointing to a non-JDK path: $JAVA_HOME
The FE program requires the full JDK to be installed and configured properly. Please check that JAVA_HOME
is set to the installation directory of JDK 8 or higher, rather than the JRE installation directory.
EOF
  exit 1
fi

JAVA=$JAVA_HOME/bin/java

# check java version and choose correct JAVA_OPTS
JAVA_VERSION=$(jdk_version)
# JDK8 is still OK for v3.2.x, so this line will just block jdk9 and jdk10
if [[ "$JAVA_VERSION" -gt 8 && "$JAVA_VERSION" -lt 11 ]]; then
    echo "JDK $JAVA_VERSION is not supported, please use JDK 8, 11 or 17"
    exit -1
fi

# ### Things to know about environment variables of JAVA_OPTS, JAVA_OPTS_FOR_JDK_9 and JAVA_OPTS_FOR_JDK_11
# * It is historic reason and backwards compatibility consideration to have separate JAVA_OPTS
#   for diffferent versions of JDK, so that when the user upgrades or downgrades the JDK version,
#   the JAVA_OPTS won't be suddenly broken.
# * Ideally, the user will only care about the `JAVA_OPTS`, don't set any JAVA_OPTS_FOR_JDK_*
# * JAVA_OPTS/JAVA_OPTS_FOR_JDK_9/JAVA_OPTS_FOR_JDK_11 can be either set in the shell before invoking
#   this script, or can be set in `fe.conf` which will be loaded automatically by `export_env_from_conf`
#
# ### Precedence of environment variables
# For JDK11, it takes the following precedences:
#    JAVA_OPTS_FOR_JDK_11 > JAVA_OPTS_FOR_JDK_9 > JAVA_OPTS
# (The `JAVA_OPTS_FOR_JDK_9` here is just for historic reason)
# For all remain jdk versions, only JAVA_OPTS takes effect.
#
# NOTE: try not adding new JAVA_OPTS_FOR_JDK_## for a new JDK version.
#
final_java_opt=
if [[ "$JAVA_VERSION" -ge 11 ]]; then
    # For JDK 11+, take JAVA_OPTS_FOR_JDK_11 or JAVA_OPTS_FOR_JDK_9 if the former is empty
    final_java_opt=${JAVA_OPTS_FOR_JDK_11:-$JAVA_OPTS_FOR_JDK_9}
    final_java_opt=${final_java_opt:-$JAVA_OPTS}
else
    final_java_opt=$JAVA_OPTS
fi

if [ -z "$final_java_opt" ] ; then
    # lookup fails, provide a fixed opts with best guess that may or may not work
    if [ -z "$DATE" ] ; then
        DATE=`date +%Y%m%d-%H%M%S`
    fi
    final_java_opt="-Dlog4j2.formatMsgNoLookups=true -Xmx8192m -XX:+UseG1GC -Xlog:gc*:${LOG_DIR}/fe.gc.log.$DATE:time"
    echo "JAVA_OPTS is not set in fe.conf, use default java options to start fe process: $final_java_opt"
fi

# Auto detect jvm -Xmx parameter in case $FE_ENABLE_AUTO_JVM_XMX_DETECT = true
#  default to 70% of total available mem and can be tuned by env var: FE_JVM_XMX_PERCENTAGE
# NOTE: the feature is only supported in container env
xmx=$(detect_jvm_xmx)
final_java_opt="${final_java_opt} ${xmx}"

if [[ "$JAVA_VERSION" -lt 11 ]]; then
    echo "Tips: current JDK version is $JAVA_VERSION, JDK 11 or 17 is highly recommended for better GC performance(lower version JDK may not be supported in the future)"
    if [[ "$JAVA_VERSION" == 8 ]]; then
        export JAVA=${JAVA_HOME}/bin/java
        JAVA_UPDATE_VER=$(${JAVA} -version 2>&1 | sed -n 's/.* version "1\.8\.0_\([0-9]*\)".*/\1/p')
        if [[ $JAVA_UPDATE_VER -lt 192 ]]; then
            echo "Tips: JAVA_UPDATE_VER is $JAVA_UPDATE_VER, Please upgrade the JAVA version to at least 1.8.0_192 to avoid potential issues of G1 gc on jdk8."
        fi
    fi
fi

if [ ${ENABLE_DEBUGGER} -eq 1 ]; then
    # Allow attaching debuggers to the FE process:
    # https://www.jetbrains.com/help/idea/attaching-to-local-process.html
    if [[ "$JAVA_VERSION" -gt 8 ]]; then
        final_java_opt="${final_java_opt} -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005"
    else
        final_java_opt="${final_java_opt} -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=5005"
    fi
    echo "Start debugger with: $final_java_opt"
fi

# add datadog profile settings when enabled
if [ "${ENABLE_DATADOG_PROFILE}" == "true" ] && [ -f "${STARROCKS_HOME}/datadog/dd-java-agent.jar" ]; then
    final_java_opt="-javaagent:${STARROCKS_HOME}/datadog/dd-java-agent.jar ${final_java_opt}"
fi

if [ ! -d $LOG_DIR ]; then
    mkdir -p $LOG_DIR
fi

read_var_from_conf meta_dir $STARROCKS_HOME/conf/fe.conf
mkdir -p ${meta_dir:-"$STARROCKS_HOME/meta"}

# add libs to CLASSPATH
for f in $STARROCKS_HOME/lib/*.jar; do
  CLASSPATH=$f:${CLASSPATH};
done
export CLASSPATH=${STARROCKS_HOME}/lib/starrocks-hadoop-ext.jar:${CLASSPATH}:${STARROCKS_HOME}/lib:${STARROCKS_HOME}/conf

pidfile=$PID_DIR/fe.pid

if [ -f $pidfile ]; then
  oldpid=$(cat $pidfile)
  # get the full command
  pscmd=$(ps -q $oldpid -o cmd=)
  if echo "$pscmd" | grep -q -w StarRocksFE &>/dev/null ; then
    echo Frontend running as process $oldpid. Stop it first.
    exit 1
  fi
fi

if [ ! -f /bin/limit ]; then
    LIMIT=
else
    LIMIT=/bin/limit
fi

if [ x"$HELPER" != x"" ]; then
    # change it to '-helper' to be compatible with code in Frontend
    HELPER="-helper $HELPER"
fi

if [ x"$HOST_TYPE" != x"" ]; then
    # change it to '-host_type' to be compatible with code in Frontend
    HOST_TYPE="-host_type $HOST_TYPE"
fi

LOG_FILE=$LOG_DIR/fe.out

if [ ${RUN_LOG_CONSOLE} -eq 1 ] ; then
    if [ ! -w $STARROCKS_HOME/conf/fe.conf ] ; then
        # workaround configmap readonly, can't change its content
        mv $STARROCKS_HOME/conf/fe.conf $STARROCKS_HOME/conf/fe.conf.readonly
        cp $STARROCKS_HOME/conf/fe.conf.readonly $STARROCKS_HOME/conf/fe.conf
    fi
else
    # redirect all subsequent commands' stdout/stderr into $LOG_FILE
    exec >> $LOG_FILE 2>&1
fi
export SYS_LOG_TO_CONSOLE=${RUN_LOG_CONSOLE}

echo "using java version $JAVA_VERSION"
echo $final_java_opt
echo "start time: $(date), server uptime: $(uptime)"

# StarRocksFE java process will write its process id into $pidfile
if [ ${RUN_DAEMON} -eq 1 ]; then
    nohup $LIMIT $JAVA $final_java_opt com.starrocks.StarRocksFE ${HELPER} ${HOST_TYPE} "$@" </dev/null &
else
    exec $LIMIT $JAVA $final_java_opt com.starrocks.StarRocksFE ${HELPER} ${HOST_TYPE} "$@" </dev/null
fi

```

修复完成！现在你可以重新启动 FE 试试。先停掉之前的进程（如果还在的话），再启动：

```bash
cd /home/peter/my-project/starrocks/output/fe && ./bin/stop_fe.sh && ./bin/start_fe.sh --daemon --debug && cd ../..
```

## 总结

| 项目 | 说明 |
|------|------|
| **问题** | JDK 17 使用了 JDK 8 的 GC 日志参数 (`PrintGCDateStamps` 等) |
| **根因** | `start_fe.sh` 中 `case $JAVA_VERSION` 只匹配了 `11`，JDK 17 走到了 `*` 默认分支，用了旧版 `JAVA_OPTS` |
| **修复** | 将 `case` 改为 `if [[ "$JAVA_VERSION" -ge 11 ]]`，让所有 JDK 11+ 版本都使用 `JAVA_OPTS_FOR_JDK_11` 中的新式 GC 日志参数 (`-Xlog:gc*:...`) |

已经同时修改了 `output/fe/bin/start_fe.sh`（运行时）和 `bin/start_fe.sh`（源码），两处都已修复。

```shellscript
cd /home/peter/my-project/starrocks/output/fe && ./bin/stop_fe.sh && ./bin/start_fe.sh --daemon --debug && cd ../..
```

---

**User**

OK，我接下来启动BE，也遇到了问题

如下命令，是添加成功了ALTER SYSTEM ADD BACKEND "127.0.0.1:9050";
@mysql (100-101) 

但是如下，看起来Alive: false
@mysql (219-248)

请问是IP不对吗，我感觉检查output/be/log/be.INFO文件应该能发现原因

---

**Cursor**



让我先看看 BE 的日志文件：

问题很清楚了！让我看一下 BE 的配置和相关源码：

现在完全清楚了！来看看关键的日志信息：

## 问题分析

`be.INFO` 日志中有两行关键信息：

**第 142 行** — BE 自动检测到的本地 IP 地址：

```142:142:/home/peter/my-project/starrocks/output/be/log/be.INFO
I0308 23:51:02.117089 17736 backend_options.cpp:84] localhost 10.255.255.254
```

**第 196 行** — 心跳失败的原因：

```196:196:/home/peter/my-project/starrocks/output/be/log/be.INFO
W0308 23:53:24.270012 21365 heartbeat_server.cpp:196] 127.0.0.1 not equal to to backend localhost 10.255.255.254
```

### 问题本质

这是一个 **IP 地址不匹配**的问题：

| 角色 | IP 地址 | 来源 |
|------|---------|------|
| 你在 FE 注册 BE 时用的 | `127.0.0.1` | `ALTER SYSTEM ADD BACKEND "127.0.0.1:9050"` |
| BE 自动检测到的本机 IP | `10.255.255.254` | WSL2 的虚拟网卡地址 |

FE 发心跳给 BE 时，携带的是 `backend_ip=127.0.0.1`，但 BE 自己认为本机地址是 `10.255.255.254`，两者不匹配，所以 BE 拒绝了心跳，报 `FE saved address not match backend address`。

这是 WSL2 的典型问题 — WSL2 有一个虚拟网络，`10.255.255.254` 是 WSL2 分配的 IP，而不是 `127.0.0.1`。

## 解决方案

在 `be.conf` 中配置 `priority_networks`，强制 BE 使用 `127.0.0.1`：

```plaintext
I0308 23:51:02.117089 17736 backend_options.cpp:84] localhost 10.255.255.254
```

```plaintext
W0308 23:53:24.270012 21365 heartbeat_server.cpp:196] 127.0.0.1 not equal to to backend localhost 10.255.255.254
```

```properties
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

# INFO, WARNING, ERROR, FATAL
sys_log_level = INFO

# ports for admin, web, heartbeat service 
be_port = 9060
be_http_port = 8040
heartbeat_service_port = 9050
brpc_port = 8060
starlet_port = 9070

# Enable jaeger tracing by setting jaeger_endpoint
# jaeger_endpoint = localhost:6831

# Choose one if there are more than one ip except loopback address. 
# Note that there should at most one ip match this list.
# If no ip match this rule, will choose one randomly.
# use CIDR format, e.g. 10.10.10.0/24
# Default value is empty.
# priority_networks = 10.10.10.0/24;192.168.0.0/16
priority_networks = 127.0.0.1/32

# data root path, separate by ';'
# you can specify the storage medium of each root path, HDD or SSD, seperate by ','
# eg:
# storage_root_path = /data1,medium:HDD;/data2,medium:SSD;/data3
# /data1, HDD;
# /data2, SSD;
# /data3, HDD(default);
#
# Default value is ${STARROCKS_HOME}/storage, you should create it by hand.
# storage_root_path = ${STARROCKS_HOME}/storage

# Advanced configurations
# sys_log_dir = ${STARROCKS_HOME}/log
# sys_log_roll_mode = SIZE-MB-1024
# sys_log_roll_num = 10
# sys_log_verbose_modules = *
# log_buffer_level = -1

# JVM options for be
# eg:
# JAVA_OPTS="-Djava.security.krb5.conf=/etc/krb5.conf"
# For jdk 9+, this JAVA_OPTS will be used as default JVM options
# JAVA_OPTS_FOR_JDK_9_AND_LATER="-Djava.security.krb5.conf=/etc/krb5.conf"
storage_root_path = ${STARROCKS_HOME}/storage

```

修复完成！接下来你需要：

1. **先删掉已注册的错误 BE 节点**，在 MySQL 客户端执行：
   ```sql
   ALTER SYSTEM DROP BACKEND "127.0.0.1:9050";
   ```
   > 如果报错说要加 FORCE，就用：`ALTER SYSTEM DROP BACKEND "127.0.0.1:9050" FORCE;`

2. **重启 BE**：
   ```bash
   cd /home/peter/my-project/starrocks/output/be && ./bin/stop_be.sh && ./bin/start_be.sh --daemon && cd ../..
   ```

3. **重新添加 BE**（等 BE 启动后）：
   ```sql
   ALTER SYSTEM ADD BACKEND "127.0.0.1:9050";
   ```

4. **验证**：
   ```sql
   SHOW PROC '/backends'\G
   ```
   这次 `Alive` 应该变成 `true` 了。

### 总结

| 项目 | 说明 |
|------|------|
| **问题** | BE 心跳失败，`Alive: false` |
| **根因** | WSL2 环境下 BE 自动检测 IP 为 `10.255.255.254`，与 FE 注册时的 `127.0.0.1` 不匹配 |
| **修复** | 在 `be.conf` 中添加 `priority_networks = 127.0.0.1/32`，强制 BE 绑定到 `127.0.0.1` |

```sql
   ALTER SYSTEM DROP BACKEND "127.0.0.1:9050";
```

```shellscript
   cd /home/peter/my-project/starrocks/output/be && ./bin/stop_be.sh && ./bin/start_be.sh --daemon && cd ../..
```

```sql
   ALTER SYSTEM ADD BACKEND "127.0.0.1:9050";
```

```sql
   SHOW PROC '/backends'\G
```

---

**User**

启动起来了，在尝试debug BE

根据/home/peter/my-project/starrocks/docs/zh/learning/在wsl2上进行starrocks编译启动源码debug总结.md中的内容
6.1 CLion 配置 WSL Toolchain这一步骤
Settings → Build, Execution, Deployment → CMake：这一子步骤
遇到下述问题

/usr/bin/cmake -DCMAKE_BUILD_TYPE=Debug -G "Unix Makefiles" -S /home/peter/my-project/starrocks/be -B /home/peter/my-project/starrocks/be/cmake-build-debug-wsl
-- The CXX compiler identification is GNU 10.5.0
-- The C compiler identification is GNU 10.5.0
-- Detecting CXX compiler ABI info
-- Detecting CXX compiler ABI info - done
-- Check for working CXX compiler: /usr/bin/g++ - skipped
-- Detecting CXX compile features
-- Detecting CXX compile features - done
-- Detecting C compiler ABI info
-- Detecting C compiler ABI info - done
-- Check for working C compiler: /usr/bin/gcc - skipped
-- Detecting C compile features
-- Detecting C compile features - done
-- Build type is DEBUG
-- Build target arch is x86_64
-- make test: OFF
-- GCC version 10.5.0 is greater than 10.3.0, disable -Werror. Be careful with compile warnings.
-- defined PIC_LIB_PATH
-- build gensrc if necessary
make: Entering directory '/home/peter/my-project/starrocks/gensrc'
make -C script
make[1]: Entering directory '/home/peter/my-project/starrocks/gensrc/script'
/home/peter/my-project/starrocks/gensrc/script/../../build-support/gen_build_version.py --cpp /home/peter/my-project/starrocks/gensrc/script/../build//gen_cpp --java /home/peter/my-project/starrocks/gensrc/script/../../fe/fe-core/target/generated-sources/build
Traceback (most recent call last):
  File "/home/peter/my-project/starrocks/gensrc/script/../../build-support/gen_build_version.py", line 224, in <module>
    main()
  File "/home/peter/my-project/starrocks/gensrc/script/../../build-support/gen_build_version.py", line 218, in main
    java_version = get_java_version()
                   ^^^^^^^^^^^^^^^^^^
  File "/home/peter/my-project/starrocks/gensrc/script/../../build-support/gen_build_version.py", line 88, in get_java_version
    java_res = subprocess.Popen([java_home + "/bin/java", "-fullversion"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                                 ~~~~~~~~~~^~~~~~~~~~~~~
TypeError: unsupported operand type(s) for +: 'NoneType' and 'str'
make[1]: Leaving directory '/home/peter/my-project/starrocks/gensrc/script'
make[1]: *** [Makefile:39: gen_version] Error 1
make: Leaving directory '/home/peter/my-project/starrocks/gensrc'
make: *** [Makefile:30: script] Error 2
CMake Error at CMakeLists.txt:142 (message):
  Failed to build /home/peter/my-project/starrocks/be/../gensrc/


-- Configuring incomplete, errors occurred!

---

**Cursor**

这个错误很明显，是 CMake 在 CLion 中运行时，**`JAVA_HOME` 环境变量没有设置**。

来看关键报错：

```
java_res = subprocess.Popen([java_home + "/bin/java", "-fullversion"], ...)
TypeError: unsupported operand type(s) for +: 'NoneType' and 'str'
```

`java_home` 是 `None`，说明 Python 脚本从环境变量中读取 `JAVA_HOME` 时拿到了空值。

让我确认一下这个脚本的逻辑：

```plaintext
java_res = subprocess.Popen([java_home + "/bin/java", "-fullversion"], ...)
TypeError: unsupported operand type(s) for +: 'NoneType' and 'str'
```

问题很清楚了！CLion 通过 WSL Toolchain 执行 CMake 配置时，**缺少 `JAVA_HOME` 环境变量**。

你文档第 274 行的 **Environment** 只设置了：
```
STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr
```

但是没有加 `JAVA_HOME`，导致 `gen_build_version.py` 脚本获取不到 `JAVA_HOME` 而报错。

## 解决方案

在 CLion 的 **Settings → Build, Execution, Deployment → CMake → Environment** 中，加上 `JAVA_HOME`，完整设置应为：

```
STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr;JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

然后重新 **Reload CMake Project** 即可。

同时，我帮你把文档也更新一下，避免以后忘记：

```plaintext
STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr
```

```plaintext
STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr;JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

```markdown
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
   - **Environment**：添加 `STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr;JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64`
     - `STARROCKS_CLION_ONLY=1`：只生成代码导航用的 target，不真正编译，配置速度很快
     - `STARROCKS_GCC_HOME`：指定 GCC 路径（WSL 上通过 apt 安装的 GCC 在 `/usr`）
     - `JAVA_HOME`：CMake 配置过程中 `gen_build_version.py` 需要调用 `java` 来获取版本信息，必须设置此变量
   - 取消勾选 **Include system environment variables**（避免 Windows 环境变量干扰）

4. 在项目树中找到 `be/CMakeLists.txt` → **右键 → Load CMake Project**，等待配置完成。

### 6.2 Attach 调试

1. 确认 BE 已在 WSL 中启动：`ps aux | grep starrocks_be`。
2. CLion 中：**Run → Attach to Process...**，在列表中选 `starrocks_be`。
3. 打开 BE 源码文件，设置断点（红色实心圆），用 MySQL 发 SQL 触发即可。

推荐断点：

| 文件 | 行号 | 说明 |
|------|------|------|
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` | **797** | `_read_chunk_from_storage` 入口，每次从存储读 chunk 都会经过 |
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` | **803** | `_prj_iter->get_next(chunk)`，实际读取数据 |

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

```

## 总结

| 项目 | 说明 |
|------|------|
| **问题** | CLion CMake 配置时 `gen_build_version.py` 报 `TypeError: NoneType + str` |
| **根因** | CLion 勾选了「取消包含系统环境变量」后，`JAVA_HOME` 为空，脚本 `os.getenv("JAVA_HOME")` 返回 `None` |
| **修复** | 在 CMake 的 **Environment** 中添加 `JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64` |

在 CLion 中修改后，点击 **Reload CMake Project** 即可正常完成配置。

---

**User**

执行了，遇到了新的错误

/usr/bin/cmake -DCMAKE_BUILD_TYPE=Debug -G "Unix Makefiles" -S /home/peter/my-project/starrocks/be -B /home/peter/my-project/starrocks/be/cmake-build-debug-wsl
-- The CXX compiler identification is GNU 10.5.0
-- The C compiler identification is GNU 10.5.0
-- Detecting CXX compiler ABI info
-- Detecting CXX compiler ABI info - done
-- Check for working CXX compiler: /usr/bin/g++ - skipped
-- Detecting CXX compile features
-- Detecting CXX compile features - done
-- Detecting C compiler ABI info
-- Detecting C compiler ABI info - done
-- Check for working C compiler: /usr/bin/gcc - skipped
-- Detecting C compile features
-- Detecting C compile features - done
-- Build type is DEBUG
-- Build target arch is x86_64
-- make test: OFF
-- GCC version 10.5.0 is greater than 10.3.0, disable -Werror. Be careful with compile warnings.
-- defined PIC_LIB_PATH
-- build gensrc if necessary
make: Entering directory '/home/peter/my-project/starrocks/gensrc'
make -C script
make[1]: Entering directory '/home/peter/my-project/starrocks/gensrc/script'
/home/peter/my-project/starrocks/gensrc/script/../../build-support/gen_build_version.py --cpp /home/peter/my-project/starrocks/gensrc/script/../build//gen_cpp --java /home/peter/my-project/starrocks/gensrc/script/../../fe/fe-core/target/generated-sources/build
gen_build_version.py /home/peter/my-project/starrocks/gensrc/script/../build//gen_cpp/version.cpp: old fingerprint = af86e5134798d728ff2995ea720b7a8c, new fingerprint = 2ab776b2a627a202a651e5a9bf88ea58
gen_build_version.py /home/peter/my-project/starrocks/gensrc/script/../../fe/fe-core/target/generated-sources/build/com/starrocks/common/Version.java: old fingerprint = e7c7dcdc84ccd49623343eb79c47ddd4, new fingerprint = c51fecf86dfa1b67753f6f91cf3b3fda
make[1]: Leaving directory '/home/peter/my-project/starrocks/gensrc/script'
make -C proto
make[1]: Entering directory '/home/peter/my-project/starrocks/gensrc/proto'
make[1]: Nothing to be done for 'all'.
make[1]: Leaving directory '/home/peter/my-project/starrocks/gensrc/proto'
make -C thrift
make[1]: Entering directory '/home/peter/my-project/starrocks/gensrc/thrift'
make[1]: Nothing to be done for 'all'.
make[1]: Leaving directory '/home/peter/my-project/starrocks/gensrc/thrift'
make: Leaving directory '/home/peter/my-project/starrocks/gensrc'
-- Performing Test CMAKE_HAVE_LIBC_PTHREAD
-- Performing Test CMAKE_HAVE_LIBC_PTHREAD - Success
-- Found Threads: TRUE  
CMake Error at /usr/share/cmake-3.28/Modules/FindPackageHandleStandardArgs.cmake:230 (message):
  Could NOT find Boost (missing: Boost_INCLUDE_DIR thread regex
  program_options filesystem context) (Required is at least version "1.80.0")
Call Stack (most recent call first):
  /usr/share/cmake-3.28/Modules/FindPackageHandleStandardArgs.cmake:600 (_FPHSA_FAILURE_MESSAGE)
  /usr/share/cmake-3.28/Modules/FindBoost.cmake:2393 (find_package_handle_standard_args)
  CMakeLists.txt:166 (find_package)


-- Configuring incomplete, errors occurred!

[已完成]

---

**Cursor**



这个错误是 CMake 找不到 **Boost 库**。在正常的 `./build.sh` 编译流程中，Boost 是作为第三方依赖编译好放在 `thirdparty/installed/` 目录下的，但 CLion 的 CMake 环境没有指向那个路径。

让我看一下 `CMakeLists.txt` 中是怎么查找 Boost 的，以及 `STARROCKS_CLION_ONLY` 的处理逻辑：

找到原因了！`CMakeLists.txt` 第 65 行通过环境变量 `STARROCKS_THIRDPARTY` 来定位所有第三方库（包括 Boost）的路径。你的 CLion CMake Environment 中没有设置这个变量。

Boost 已经编译好在 `thirdparty/installed/` 下了，只需要在 CLion 的 Environment 中加上 `STARROCKS_THIRDPARTY` 即可。

## 解决方案

在 CLion 的 **Settings → Build, Execution, Deployment → CMake → Environment** 中，加上 `STARROCKS_THIRDPARTY`，完整设置改为：

```
STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr;JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64;STARROCKS_THIRDPARTY=/home/peter/my-project/starrocks/thirdparty
```

然后重新 **Reload CMake Project** 即可。

同时更新一下文档：

```plaintext
STARROCKS_CLION_ONLY=1;STARROCKS_GCC_HOME=/usr;JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64;STARROCKS_THIRDPARTY=/home/peter/my-project/starrocks/thirdparty
```

```markdown
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

1. 确认 BE 已在 WSL 中启动：`ps aux | grep starrocks_be`。
2. CLion 中：**Run → Attach to Process...**，在列表中选 `starrocks_be`。
3. 打开 BE 源码文件，设置断点（红色实心圆），用 MySQL 发 SQL 触发即可。

推荐断点：

| 文件 | 行号 | 说明 |
|------|------|------|
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` | **797** | `_read_chunk_from_storage` 入口，每次从存储读 chunk 都会经过 |
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` | **803** | `_prj_iter->get_next(chunk)`，实际读取数据 |

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

```

## 总结

| 项目 | 说明 |
|------|------|
| **问题** | CMake 找不到 Boost：`Could NOT find Boost (missing: Boost_INCLUDE_DIR ...)` |
| **根因** | `CMakeLists.txt` 第 65 行通过 `$ENV{STARROCKS_THIRDPARTY}` 定位第三方库路径，CLion Environment 中未设置此变量，导致 `THIRDPARTY_DIR` 为空，Boost 搜索路径错误 |
| **修复** | 在 CLion CMake Environment 中添加 `STARROCKS_THIRDPARTY=/home/peter/my-project/starrocks/thirdparty` |

修改后在 CLion 中重新 Reload CMake Project 即可。文档也已同步更新。

---

**User**

OK，我在执行6.2 Attach 调试

以下，确认starrocks_be已经启动
@zsh (839-842) 

在运行-附加到进程中，已经确认找到了starrocks_be
只不过他是在SSH/WSL这个TAB下的，左边还有一个“局部”TAB
点击使用WSL GDB附加

Clion调试控制台上，报了下面的错误

附加调试器失败，请检查权限 - https://www.jetbrains.com/help/clion/attach-to-process.html
ptrace: Operation not permitted.
调试器已分离


---

**Cursor**

这是一个经典的 Linux **ptrace 权限** 问题。默认情况下 Linux 内核限制了 `ptrace` 只能调试子进程，不能 attach 到其他进程。

需要修改 `ptrace_scope` 来允许调试：

果然，`ptrace_scope` 的值是 `1`，表示**只允许父进程调试子进程**，CLion 通过 GDB attach 到 `starrocks_be` 会被拒绝。

把它改为 `0` 即可允许任意进程 attach：

这个命令需要 sudo 密码，你需要在 WSL 终端中手动执行：

```bash
echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope
```

输入密码后就会生效。

然后回到 CLion 重新 **Attach to Process** 即可。

## 补充说明

| 项目 | 说明 |
|------|------|
| **`ptrace_scope = 1`**（默认值） | 只允许父进程调试子进程（安全限制） |
| **`ptrace_scope = 0`** | 允许任意进程 attach（调试需要） |

⚠️ **注意**：这个修改是**临时的**，WSL 重启后会恢复为 `1`。如果想每次 WSL 启动时自动设置，可以在 `~/.bashrc` 或 `~/.zshrc` 末尾加一行：

```bash
echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope > /dev/null 2>&1
```

不过这样每次开终端都会要 sudo 密码。更好的方式是配置 `sudoers` 免密执行这条命令，或者在每次调试前手动执行一次。

我也把这个步骤更新到文档中：

```shellscript
echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope
```

```shellscript
echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope > /dev/null 2>&1
```

```markdown
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
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` | **797** | `_read_chunk_from_storage` 入口，每次从存储读 chunk 都会经过 |
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` | **803** | `_prj_iter->get_next(chunk)`，实际读取数据 |

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

```

## 总结

你只需要在 WSL 终端中执行一条命令：

```bash
echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope
```

输入密码后，回到 CLion 重新 **Attach to Process** 就可以了。这个设置是临时的，WSL 重启后会恢复，每次需要调试前执行一次即可。文档也已更新。

```shellscript
echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope
```

---

**User**

OK，调试器已附加到进程 25579，看起来是连接成功了

我发现一个新问题，### 6.2 Attach 调试 这一章节中，推荐断点：中的内容是被我改过的，我是直接将之前main分支生成的文档复制粘贴过来的

现在我发现olap_chunk_source.cpp文件只有528行，现在这里写的797、803行根本不存在，请你帮我做一下分析和修改，分析出怎么打断点才能让执行SQL这个动作断点住，然后也修改一下md文档，谢谢

---

**Cursor**



好的，让我分析一下 `olap_chunk_source.cpp` 的实际代码，找到正确的断点位置。

现在我已经看完了整个文件。让我找到正确的断点位置，并看一下 SQL 执行链路上其他关键文件：

好的，文件已经完整看完了。在 3.2.16 分支中，`olap_chunk_source.cpp` 只有 **528 行**，关键函数的行号与 main 分支完全不同。以下是正确的断点分析：

## 断点分析

在这个文件中，SQL 查询读取数据的核心路径是：

1. **第 391 行** — `_read_chunk_from_storage` 函数入口：每次从存储引擎读取一批数据（chunk）都会进入此函数

```391:429:/home/peter/my-project/starrocks/be/src/exec/pipeline/scan/olap_chunk_source.cpp
Status OlapChunkSource::_read_chunk_from_storage(RuntimeState* state, Chunk* chunk) {
    if (state->is_cancelled()) {
        return Status::Cancelled("canceled state");
    }

    do {
        RETURN_IF_ERROR(state->check_mem_limit("read chunk from storage"));
        RETURN_IF_ERROR(_prj_iter->get_next(chunk));
        // ... filtering logic ...
    } while (chunk->num_rows() == 0);
    // ...
}
```

2. **第 398 行** — `_prj_iter->get_next(chunk)`：这是真正从底层存储读取数据的调用，是数据读取的核心

3. **第 360 行** — `_read_chunk` 函数：是上层调用 `_read_chunk_from_storage` 的入口

```360:365:/home/peter/my-project/starrocks/be/src/exec/pipeline/scan/olap_chunk_source.cpp
Status OlapChunkSource::_read_chunk(RuntimeState* state, ChunkPtr* chunk) {
    chunk->reset(ChunkHelper::new_chunk_pooled(_prj_iter->output_schema(), _runtime_state->chunk_size(),
                                               _runtime_state->use_column_pool()));
    auto scope = IOProfiler::scope(IOProfiler::TAG_QUERY, _tablet->tablet_id());
    return _read_chunk_from_storage(_runtime_state, (*chunk).get());
}
```

现在更新文档：

```cpp
Status OlapChunkSource::_read_chunk_from_storage(RuntimeState* state, Chunk* chunk) {
    if (state->is_cancelled()) {
        return Status::Cancelled("canceled state");
    }

    do {
        RETURN_IF_ERROR(state->check_mem_limit("read chunk from storage"));
        RETURN_IF_ERROR(_prj_iter->get_next(chunk));
        // ... filtering logic ...
    } while (chunk->num_rows() == 0);
    // ...
}
```

```cpp
Status OlapChunkSource::_read_chunk(RuntimeState* state, ChunkPtr* chunk) {
    chunk->reset(ChunkHelper::new_chunk_pooled(_prj_iter->output_schema(), _runtime_state->chunk_size(),
                                               _runtime_state->use_column_pool()));
    auto scope = IOProfiler::scope(IOProfiler::TAG_QUERY, _tablet->tablet_id());
    return _read_chunk_from_storage(_runtime_state, (*chunk).get());
}
```

```markdown
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
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` | **391** | `_read_chunk_from_storage` 入口，每次从存储读 chunk 都会经过 |
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

```

## 总结

文档已更新。在 **branch-3.2.16** 中，`olap_chunk_source.cpp` 只有 528 行，正确的断点位置是：

| 断点 | 行号 | 函数 | 说明 |
|------|------|------|------|
| 入口 | **391** | `_read_chunk_from_storage` | 每次从存储读一批数据都会经过这里，可以看到 `state`、`chunk` 等上下文 |
| 核心 | **398** | `_prj_iter->get_next(chunk)` | 真正从底层存储迭代器读取数据的调用，在这里可以看到读出的数据内容 |

你现在可以在 CLion 中打开 `be/src/exec/pipeline/scan/olap_chunk_source.cpp`，在 **第 391 行**或**第 398 行**设置断点，然后用 MySQL 执行 `SELECT * FROM demo.t1;`，程序就会在断点处暂停。

