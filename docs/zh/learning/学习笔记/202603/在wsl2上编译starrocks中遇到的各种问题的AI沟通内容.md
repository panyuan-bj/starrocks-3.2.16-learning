# WSL上编译starrocks
_Exported on 3/8/2026 at 23:44:05 GMT+8 from Cursor (2.3.35)_

---

**User**

我在执行这里的内容：/home/peter/my-project/starrocks/docs/zh/learning/在wsl2上进行starrocks编译启动源码debug总结.md

BUILD_TYPE=Debug ./build.sh --be 这一步
遇到下面报错

@zsh (858-1013) 

请问是什么原因，该如何解决？

---

**Cursor**

让我先看看相关的文件和错误详情。

现在我清楚了问题所在。让我看一下编译 rocksdb 时使用的编译选项，确认一下构建脚本的相关部分。

现在我完全理解问题了。让我看看你的 GCC 版本：

原因和解决方案都清楚了。

## 原因分析

你用的是 **GCC 13.3.0**，这个版本对 C++ 代码的检查比较严格。RocksDB 6.22.1 的 `db/db_impl/db_impl.cc` 中有三处 `return std::move(...)` 语句，在 C++17 及更高标准中，return 语句中对局部变量使用 `std::move` 是**多余的**（编译器会自动做 NRVO/隐式移动），GCC 13 会把这个报为 `-Wredundant-move` 警告。

而 RocksDB 的 Makefile 默认开启了 `-Werror`（所有警告当作错误），所以这个警告就变成了编译错误：

```
db/db_impl/db_impl.cc:1250:23: error: redundant move in return statement [-Werror=redundant-move]
db/db_impl/db_impl.cc:1254:23: error: redundant move in return statement [-Werror=redundant-move]
db/db_impl/db_impl.cc:1351:19: error: redundant move in return statement [-Werror=redundant-move]
```

## 解决方案

在 `build-thirdparty.sh` 的 rocksdb 编译部分的 `EXTRA_CXXFLAGS` 中**增加 `-Wno-redundant-move`**，告诉编译器忽略这个警告即可。

当前的 `EXTRA_CXXFLAGS` 已经有 `-Wno-deprecated-copy -Wno-stringop-truncation -Wno-pessimizing-move`，只需要再加一个：

```plaintext
db/db_impl/db_impl.cc:1250:23: error: redundant move in return statement [-Werror=redundant-move]
db/db_impl/db_impl.cc:1254:23: error: redundant move in return statement [-Werror=redundant-move]
db/db_impl/db_impl.cc:1351:19: error: redundant move in return statement [-Werror=redundant-move]
```

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

#################################################################################
# This script will
# 1. Check prerequisite libraries. Including:
#    cmake byacc flex automake libtool binutils-dev libiberty-dev bison
# 2. Compile and install all thirdparties which are downloaded
#    using *download-thirdparty.sh*.
#
# This script will run *download-thirdparty.sh* once again
# to check if all thirdparties have been downloaded, unpacked and patched.
#################################################################################
set -e

curdir=`dirname "$0"`
curdir=`cd "$curdir"; pwd`

export STARROCKS_HOME=${STARROCKS_HOME:-$curdir/..}
export TP_DIR=$curdir

# include custom environment variables
if [[ -f ${STARROCKS_HOME}/env.sh ]]; then
    . ${STARROCKS_HOME}/env.sh
fi

if [[ ! -f ${TP_DIR}/download-thirdparty.sh ]]; then
    echo "Download thirdparty script is missing".
    exit 1
fi

if [ ! -f ${TP_DIR}/vars.sh ]; then
    echo "vars.sh is missing".
    exit 1
fi
. ${TP_DIR}/vars.sh

cd $TP_DIR

# Download thirdparties.
${TP_DIR}/download-thirdparty.sh

# set COMPILER
if [[ ! -z ${STARROCKS_GCC_HOME} ]]; then
    export CC=${STARROCKS_GCC_HOME}/bin/gcc
    export CPP=${STARROCKS_GCC_HOME}/bin/cpp
    export CXX=${STARROCKS_GCC_HOME}/bin/g++
    export PATH=${STARROCKS_GCC_HOME}/bin:$PATH
else
    echo "STARROCKS_GCC_HOME environment variable is not set"
    exit 1
fi

# prepare installed prefix
mkdir -p ${TP_DIR}/installed

check_prerequest() {
    local CMD=$1
    local NAME=$2
    if ! $CMD; then
        echo $NAME is missing
        exit 1
    else
        echo $NAME is found
    fi
}

# sudo apt-get install cmake
# sudo yum install cmake
check_prerequest "${CMAKE_CMD} --version" "cmake"

# sudo apt-get install byacc
# sudo yum install byacc
check_prerequest "byacc -V" "byacc"

# sudo apt-get install flex
# sudo yum install flex
check_prerequest "flex -V" "flex"

# sudo apt-get install automake
# sudo yum install automake
check_prerequest "automake --version" "automake"

# sudo apt-get install libtool
# sudo yum install libtool
check_prerequest "libtoolize --version" "libtool"

BUILD_SYSTEM=${BUILD_SYSTEM:-make}

# sudo apt-get install binutils-dev
# sudo yum install binutils-devel
#check_prerequest "locate libbfd.a" "binutils-dev"

# sudo apt-get install libiberty-dev
# no need in centos 7.1
#check_prerequest "locate libiberty.a" "libiberty-dev"

# sudo apt-get install bison
# sudo yum install bison
#check_prerequest "bison --version" "bison"

#########################
# build all thirdparties
#########################


# Name of cmake build directory in each thirdpary project.
# Do not use `build`, because many projects contained a file named `BUILD`
# and if the filesystem is not case sensitive, `mkdir` will fail.
BUILD_DIR=starrocks_build
MACHINE_TYPE=$(uname -m)

# handle mac m1 platform, change arm64 to aarch64
if [[ "${MACHINE_TYPE}" == "arm64" ]]; then
    MACHINE_TYPE="aarch64"
fi

echo "machine type : $MACHINE_TYPE"

check_if_source_exist() {
    if [ -z $1 ]; then
        echo "dir should specified to check if exist."
        exit 1
    fi

    if [ ! -d $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
    echo "===== begin build $1"
}

check_if_archieve_exist() {
    if [ -z $1 ]; then
        echo "archieve should specified to check if exist."
        exit 1
    fi

    if [ ! -f $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
}

# libevent
build_libevent() {
    check_if_source_exist $LIBEVENT_SOURCE
    cd $TP_SOURCE_DIR/$LIBEVENT_SOURCE
    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

build_openssl() {
    OPENSSL_PLATFORM="linux-x86_64"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        OPENSSL_PLATFORM="linux-aarch64"
    fi

    check_if_source_exist $OPENSSL_SOURCE
    cd $TP_SOURCE_DIR/$OPENSSL_SOURCE

    # use customized CFLAGS/CPPFLAGS/CXXFLAGS/LDFLAGS
    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC"

    LDFLAGS="-L${TP_LIB_DIR}" \
    LIBDIR="lib" \
    ./Configure --prefix=$TP_INSTALL_DIR -lz -no-shared ${OPENSSL_PLATFORM}
    make -j$PARALLEL
    make install_sw

    restore_compile_flags
}

# thrift
build_thrift() {
    check_if_source_exist $THRIFT_SOURCE
    cd $TP_SOURCE_DIR/$THRIFT_SOURCE

    if [ ! -f configure ]; then
        ./bootstrap.sh
    fi

    echo ${TP_LIB_DIR}
    ./configure LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" LIBS="-lssl -lcrypto -ldl" \
    --prefix=$TP_INSTALL_DIR --docdir=$TP_INSTALL_DIR/doc --enable-static --disable-shared --disable-tests \
    --disable-tutorial --without-qt4 --without-qt5 --without-csharp --without-erlang --without-nodejs \
    --without-lua --without-perl --without-php --without-php_extension --without-dart --without-ruby \
    --without-haskell --without-go --without-haxe --without-d --without-python -without-java --with-cpp \
    --with-libevent=$TP_INSTALL_DIR --with-boost=$TP_INSTALL_DIR --with-openssl=$TP_INSTALL_DIR

    if [ -f compiler/cpp/thrifty.hh ];then
        mv compiler/cpp/thrifty.hh compiler/cpp/thrifty.h
    fi

    make -j$PARALLEL
    make install
}

# llvm
build_llvm() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -D_POSIX_C_SOURCE=200112L ${FILE_PREFIX_MAP_OPTION}"
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess ${FILE_PREFIX_MAP_OPTION}"

    LLVM_TARGET="X86"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        LLVM_TARGET="AArch64"
    fi

    LLVM_TARGETS_TO_BUILD=(
        "LLVMBitstreamReader"
        "LLVMRuntimeDyld" 
        "LLVMOption"
        "LLVMAsmPrinter"
        "LLVMProfileData"
        "LLVMAsmParser"
        "LLVMOrcTargetProcess"
        "LLVMExecutionEngine"
        "LLVMBinaryFormat"
        "LLVMDebugInfoDWARF"
        "LLVMObjCARCOpts"
        "LLVMCodeGen"
        "LLVMMCDisassembler"
        "LLVMSupport"
        "LLVMJITLink"
        "LLVMCFGuard"
        "LLVMInstrumentation"
        "LLVMIRReader"
        "LLVMCore"
        "LLVMTarget"
        "LLVMMC"
        "LLVMAnalysis"
        "LLVMGlobalISel"
        "LLVMScalarOpts"
        "LLVMTargetParser"
        "LLVMDemangle"
        "LLVMRemarks"
        "LLVMDebugInfoCodeView"
        "LLVMOrcShared"
        "LLVMOrcJIT"
        "LLVMTextAPI"
        "LLVMBitWriter"
        "LLVMBitReader"
        "LLVMObject"
        "LLVMTransformUtils"
        "LLVMSelectionDAG"
        "LLVMMCParser"
    )
    if [ "${LLVM_TARGET}" == "X86" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMX86Info" "LLVMX86Desc" "LLVMX86CodeGen")
    elif [ "${LLVM_TARGET}" == "AArch64" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMAArch64Info" "LLVMAArch64Desc" "LLVMAArch64CodeGen")
    fi

    LLVM_TARGETS_TO_INSTALL=()
    for target in ${LLVM_TARGETS_TO_BUILD[@]}; do
        LLVM_TARGETS_TO_INSTALL+=("install-${target}")
    done

    check_if_source_exist $LLVM_SOURCE

    cd $TP_SOURCE_DIR
    mkdir -p llvm-build
    cd llvm-build
    rm -rf CMakeCache.txt CMakeFiles/

    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -S ../${LLVM_SOURCE}/llvm -G "${CMAKE_GENERATOR}" \
    -DLLVM_ENABLE_EH:Bool=True \
    -DLLVM_ENABLE_RTTI:Bool=True \
    -DLLVM_ENABLE_PIC:Bool=True \
    -DLLVM_ENABLE_TERMINFO:Bool=False \
    -DLLVM_TARGETS_TO_BUILD=${LLVM_TARGET} \
    -DLLVM_BUILD_LLVM_DYLIB:BOOL=False \
    -DLLVM_INCLUDE_TOOLS:BOOL=False \
    -DLLVM_BUILD_TOOLS:BOOL=False \
    -DLLVM_INCLUDE_EXAMPLES:BOOL=False \
    -DLLVM_INCLUDE_TESTS:BOOL=False \
    -DLLVM_INCLUDE_BENCHMARKS:BOOL=False \
    -DBUILD_SHARED_LIBS:BOOL=False \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}/llvm ../${LLVM_SOURCE}

    # TODO(yueyang): Add more targets.
    # This is a little bit hack, we need to minimize the build time and binary size.
    ${BUILD_SYSTEM} -j$PARALLEL REQUIRES_RTTI=1 ${LLVM_TARGETS_TO_BUILD[@]}
    ${BUILD_SYSTEM} install-llvm-headers
    ${BUILD_SYSTEM} ${LLVM_TARGETS_TO_INSTALL[@]}

    restore_compile_flags
}

# protobuf
build_protobuf() {
    check_if_source_exist $PROTOBUF_SOURCE
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    rm -fr gmock
    mkdir gmock
    cd gmock
    tar xf ${TP_SOURCE_DIR}/$GTEST_NAME
    mv $GTEST_SOURCE gtest
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    ./autogen.sh
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc -pthread -Wl,--whole-archive -lpthread -Wl,--no-whole-archive" \
    ./configure --prefix=${TP_INSTALL_DIR} --disable-shared --enable-static --with-zlib --with-zlib-include=${TP_INSTALL_DIR}/include
    make -j$PARALLEL
    make install
}

# gflags
build_gflags() {
    check_if_source_exist $GFLAGS_SOURCE

    cd $TP_SOURCE_DIR/$GFLAGS_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# glog
build_glog() {
    check_if_source_exist $GLOG_SOURCE
    cd $TP_SOURCE_DIR/$GLOG_SOURCE

    # to generate config.guess and config.sub to support aarch64
    rm -rf config.*
    autoreconf -i

    LDFLAGS="-L${TP_LIB_DIR}" \
    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-frame-pointers --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

# gtest
build_gtest() {
    check_if_source_exist $GTEST_SOURCE

    cd $TP_SOURCE_DIR/$GTEST_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# rapidjson
build_rapidjson() {
    check_if_source_exist $RAPIDJSON_SOURCE

    rm -rf $TP_INSTALL_DIR/rapidjson
    cp -r $TP_SOURCE_DIR/$RAPIDJSON_SOURCE/include/rapidjson $TP_INCLUDE_DIR/
}

# simdjson
build_simdjson() {
    check_if_source_exist $SIMDJSON_SOURCE
    cd $TP_SOURCE_DIR/$SIMDJSON_SOURCE

    #ref: https://github.com/simdjson/simdjson/blob/master/HACKING.md
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_CXX_FLAGS="-O3" -DCMAKE_C_FLAGS="-O3" -DCMAKE_POSITION_INDEPENDENT_CODE=True -DSIMDJSON_AVX512_ALLOWED=OFF ..
    $CMAKE_CMD --build .
    mkdir -p $TP_INSTALL_DIR/lib

    cp $TP_SOURCE_DIR/$SIMDJSON_SOURCE/$BUILD_DIR/libsimdjson.a $TP_INSTALL_DIR/lib
    cp -r $TP_SOURCE_DIR/$SIMDJSON_SOURCE/include/* $TP_INCLUDE_DIR/
}

# snappy
build_snappy() {
    check_if_source_exist $SNAPPY_SOURCE
    cd $TP_SOURCE_DIR/$SNAPPY_SOURCE

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -G "${CMAKE_GENERATOR}" \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On \
    -DCMAKE_INSTALL_INCLUDEDIR=$TP_INCLUDE_DIR/snappy \
    -DSNAPPY_BUILD_TESTS=0 ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    if [ -f $TP_INSTALL_DIR/lib64/libsnappy.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib
        cp $TP_INSTALL_DIR/lib64/libsnappy.a $TP_INSTALL_DIR/lib/libsnappy.a
    fi

    #build for libarrow.a
    cp $TP_INCLUDE_DIR/snappy/snappy-c.h  $TP_INCLUDE_DIR/snappy-c.h
    cp $TP_INCLUDE_DIR/snappy/snappy-sinksource.h  $TP_INCLUDE_DIR/snappy-sinksource.h
    cp $TP_INCLUDE_DIR/snappy/snappy-stubs-public.h  $TP_INCLUDE_DIR/snappy-stubs-public.h
    cp $TP_INCLUDE_DIR/snappy/snappy.h  $TP_INCLUDE_DIR/snappy.h
    cp $TP_INSTALL_DIR/lib/libsnappy.a $TP_INSTALL_DIR/libsnappy.a
}

# gperftools
build_gperftools() {
    check_if_source_exist $GPERFTOOLS_SOURCE
    cd $TP_SOURCE_DIR/$GPERFTOOLS_SOURCE

    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=$TP_INSTALL_DIR/gperftools --disable-shared --enable-static --disable-libunwind --with-pic --enable-frame-pointers
    make -j$PARALLEL
    make install
}

# zlib
build_zlib() {
    check_if_source_exist $ZLIB_SOURCE
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --static
    make -j$PARALLEL
    make install

    # build minizip
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE/contrib/minizip
    autoreconf --force --install
    ./configure --prefix=$TP_INSTALL_DIR --enable-static=yes --enable-shared=no
    make -j$PARALLEL
    make install
}

# lz4
build_lz4() {
    check_if_source_exist $LZ4_SOURCE
    cd $TP_SOURCE_DIR/$LZ4_SOURCE

    make -C lib -j$PARALLEL install PREFIX=$TP_INSTALL_DIR \
    INCLUDEDIR=$TP_INCLUDE_DIR/lz4/ BUILD_SHARED=no
}

# lzo
build_lzo2() {
    check_if_source_exist $LZO2_SOURCE
    cd $TP_SOURCE_DIR/$LZO2_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
        LDFLAGS="-L${TP_LIB_DIR}" \
        ./configure --prefix="${TP_INSTALL_DIR}" --disable-shared --enable-static

    make -j "${PARALLEL}"
    make install
}

# bzip
build_bzip() {
    check_if_source_exist $BZIP_SOURCE
    cd $TP_SOURCE_DIR/$BZIP_SOURCE

    make -j$PARALLEL install PREFIX=$TP_INSTALL_DIR
}

# curl
build_curl() {
    check_if_source_exist $CURL_SOURCE
    cd $TP_SOURCE_DIR/$CURL_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" LIBS="-lssl -lcrypto -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static \
    --without-librtmp --with-ssl=${TP_INSTALL_DIR} --without-libidn2 --without-libgsasl --disable-ldap --enable-ipv6 --without-brotli
    make -j$PARALLEL
    make install
}

# re2
build_re2() {
    check_if_source_exist $RE2_SOURCE
    cd $TP_SOURCE_DIR/$RE2_SOURCE

    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release \
	    -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL install
}

# boost
build_boost() {
    check_if_source_exist $BOOST_SOURCE
    cd $TP_SOURCE_DIR/$BOOST_SOURCE

    # It is difficult to generate static linked b2, so we use LD_LIBRARY_PATH instead
    ./bootstrap.sh --prefix=$TP_INSTALL_DIR
    LD_LIBRARY_PATH=${STARROCKS_GCC_HOME}/lib:${STARROCKS_GCC_HOME}/lib64:${LD_LIBRARY_PATH} \
    ./b2 link=static runtime-link=static -j $PARALLEL --without-test --without-mpi --without-graph --without-graph_parallel --without-python cxxflags="-std=c++11 -g -fPIC -I$TP_INCLUDE_DIR -L$TP_LIB_DIR ${FILE_PREFIX_MAP_OPTION}" install
}

#leveldb
build_leveldb() {
    check_if_source_exist $LEVELDB_SOURCE
    cd $TP_SOURCE_DIR/$LEVELDB_SOURCE
    LDFLAGS="-L ${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    make -j$PARALLEL
    cp out-static/libleveldb.a $TP_LIB_DIR/libleveldb.a
    cp -r include/leveldb $TP_INCLUDE_DIR
}

# brpc
build_brpc() {
    check_if_source_exist $BRPC_SOURCE

    cd $TP_SOURCE_DIR/$BRPC_SOURCE
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    ./config_brpc.sh --headers="$TP_INSTALL_DIR/include" --libs="$TP_INSTALL_DIR/bin $TP_INSTALL_DIR/lib" --with-glog
    make -j$PARALLEL
    cp -rf output/* ${TP_INSTALL_DIR}/
    if [ -f $TP_INSTALL_DIR/lib/libbrpc.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib64
        cp $TP_SOURCE_DIR/$BRPC_SOURCE/output/lib/libbrpc.a $TP_INSTALL_DIR/lib64/
    fi
}

# rocksdb
build_rocksdb() {
    check_if_source_exist $ROCKSDB_SOURCE

    cd $TP_SOURCE_DIR/$ROCKSDB_SOURCE
    make clean

    CFLAGS= \
    EXTRA_CFLAGS="-I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy -I ${TP_INCLUDE_DIR}/lz4 -L${TP_LIB_DIR} ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_CXXFLAGS="-fPIC -Wno-deprecated-copy -Wno-stringop-truncation -Wno-pessimizing-move -Wno-redundant-move -I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_LDFLAGS="-static-libstdc++ -static-libgcc" \
    PORTABLE=1 make USE_RTTI=1 -j$PARALLEL static_lib

    cp librocksdb.a $TP_LIB_DIR/librocksdb.a
    cp -r include/rocksdb $TP_INCLUDE_DIR
}

# kerberos
build_kerberos() {
    check_if_source_exist $KRB5_SOURCE
    cd $TP_SOURCE_DIR/$KRB5_SOURCE/src
    CFLAGS="-fcommon -fPIC ${FILE_PREFIX_MAP_OPTION}" LDFLAGS="-L$TP_INSTALL_DIR/lib -pthread -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-static --disable-shared --with-spake-openssl=$TP_INSTALL_DIR
    make -j$PARALLEL
    make install
}

# sasl
build_sasl() {
    check_if_source_exist $SASL_SOURCE
    cd $TP_SOURCE_DIR/$SASL_SOURCE
    CFLAGS="-fPIC" LDFLAGS="-L$TP_INSTALL_DIR/lib -lresolv -pthread -ldl" ./autogen.sh --prefix=$TP_INSTALL_DIR --enable-gssapi=yes --enable-static --disable-shared --with-openssl=$TP_INSTALL_DIR --with-gss_impl=mit
    make -j$PARALLEL
    make install
}

# librdkafka
build_librdkafka() {
    check_if_source_exist $LIBRDKAFKA_SOURCE

    cd $TP_SOURCE_DIR/$LIBRDKAFKA_SOURCE

    mkdir -p sr_build && cd sr_build
    $CMAKE_CMD -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" \
        -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include;$TP_INSTALL_DIR/include/zstd;$TP_INSTALL_DIR/include/lz4" \
        -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DRDKAFKA_BUILD_STATIC=ON -DWITH_SASL=ON -DWITH_SASL_SCRAM=ON \
        -DRDKAFKA_BUILD_EXAMPLES=OFF -DRDKAFKA_BUILD_TESTS=OFF -DWITH_SSL=ON -DWITH_ZSTD=ON -DCMAKE_INSTALL_LIBDIR=lib ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# pulsar
build_pulsar() {
    check_if_source_exist $PULSAR_SOURCE

    cd $TP_SOURCE_DIR/$PULSAR_SOURCE

    $CMAKE_CMD -DCMAKE_LIBRARY_PATH=$TP_INSTALL_DIR/lib -DCMAKE_INCLUDE_PATH=$TP_INSTALL_DIR/include \
        -DPROTOC_PATH=$TP_INSTALL_DIR/bin/protoc -DBUILD_TESTS=OFF -DBUILD_PYTHON_WRAPPER=OFF -DBUILD_DYNAMIC_LIB=OFF .
    ${BUILD_SYSTEM} -j$PARALLEL

    cp lib/libpulsar.a $TP_INSTALL_DIR/lib/
    cp -r include/pulsar $TP_INSTALL_DIR/include/
}

# flatbuffers
build_flatbuffers() {
  check_if_source_exist $FLATBUFFERS_SOURCE
  cd $TP_SOURCE_DIR/$FLATBUFFERS_SOURCE
  mkdir -p $BUILD_DIR
  cd $BUILD_DIR
  rm -rf CMakeCache.txt CMakeFiles/
  LDFLAGS="-static-libstdc++ -static-libgcc" \
  ${CMAKE_CMD} .. -G "${CMAKE_GENERATOR}" -DFLATBUFFERS_BUILD_TESTS=OFF
  ${BUILD_SYSTEM} -j$PARALLEL
  cp flatc  $TP_INSTALL_DIR/bin/flatc
  cp -r ../include/flatbuffers  $TP_INCLUDE_DIR/flatbuffers
  cp libflatbuffers.a $TP_LIB_DIR/libflatbuffers.a
}

build_brotli() {
    check_if_source_exist $BROTLI_SOURCE
    cd $TP_SOURCE_DIR/$BROTLI_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    ${CMAKE_CMD} .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib64
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    mv -f $TP_INSTALL_DIR/lib64/libbrotlienc-static.a $TP_INSTALL_DIR/lib64/libbrotlienc.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlidec-static.a $TP_INSTALL_DIR/lib64/libbrotlidec.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlicommon-static.a $TP_INSTALL_DIR/lib64/libbrotlicommon.a
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so.*
}

# arrow
build_arrow() {
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CPPFLAGS=$CXXFLAGS

    check_if_source_exist $ARROW_SOURCE
    cd $TP_SOURCE_DIR/$ARROW_SOURCE/cpp
    mkdir -p release
    cd release
    export ARROW_BROTLI_URL=${TP_SOURCE_DIR}/${BROTLI_NAME}
    export ARROW_GLOG_URL=${TP_SOURCE_DIR}/${GLOG_NAME}
    export ARROW_LZ4_URL=${TP_SOURCE_DIR}/${LZ4_NAME}
    export ARROW_SNAPPY_URL=${TP_SOURCE_DIR}/${SNAPPY_NAME}
    export ARROW_ZLIB_URL=${TP_SOURCE_DIR}/${ZLIB_NAME}
    export ARROW_FLATBUFFERS_URL=${TP_SOURCE_DIR}/${FLATBUFFERS_NAME}
    export ARROW_ZSTD_URL=${TP_SOURCE_DIR}/${ZSTD_NAME}
    export LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc"

    # https://github.com/apache/arrow/blob/apache-arrow-5.0.0/cpp/src/arrow/memory_pool.cc#L286
    #
    # JemallocAllocator use mallocx and rallocx to allocate new memory, but mallocx and rallocx are Non-standard APIs,
    # and can not be hooked in BE, the memory used by arrow can not be counted by BE,
    # so disable jemalloc here and use SystemAllocator.
    #
    # Currently, the standard APIs are hooked in BE, so the jemalloc standard APIs will actually be used.
    ${CMAKE_CMD} -DARROW_PARQUET=ON -DARROW_JSON=ON -DARROW_IPC=ON -DARROW_USE_GLOG=OFF -DARROW_BUILD_STATIC=ON -DARROW_BUILD_SHARED=OFF \
    -DARROW_WITH_BROTLI=ON -DARROW_WITH_LZ4=ON -DARROW_WITH_SNAPPY=ON -DARROW_WITH_ZLIB=ON -DARROW_WITH_ZSTD=ON \
    -DARROW_WITH_UTF8PROC=OFF -DARROW_WITH_RE2=OFF \
    -DARROW_JEMALLOC=OFF -DARROW_MIMALLOC=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DARROW_BOOST_USE_SHARED=OFF -DARROW_GFLAGS_USE_SHARED=OFF -DBoost_NO_BOOST_CMAKE=ON -DBOOST_ROOT=$TP_INSTALL_DIR \
    -DJEMALLOC_HOME=$TP_INSTALL_DIR/jemalloc \
    -Dzstd_SOURCE=BUNDLED \
    -DRapidJSON_ROOT=$TP_INSTALL_DIR \
    -DARROW_SNAPPY_USE_SHARED=OFF \
    -DZLIB_ROOT=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DARROW_LZ4_USE_SHARED=OFF \
    -DBROTLI_ROOT=$TP_INSTALL_DIR \
    -DARROW_BROTLI_USE_SHARED=OFF \
    -Dgflags_ROOT=$TP_INSTALL_DIR/ \
    -DSnappy_ROOT=$TP_INSTALL_DIR/ \
    -DGLOG_ROOT=$TP_INSTALL_DIR/ \
    -DLZ4_ROOT=$TP_INSTALL_DIR/ \
    -DBoost_DIR=$TP_INSTALL_DIR \
    -DBoost_ROOT=$TP_INSTALL_DIR \
    -DARROW_BOOST_USE_SHARED=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DThrift_ROOT=$TP_INSTALL_DIR/ ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    if [ -f ./zstd_ep-install/lib64/libzstd.a ]; then
        cp -rf ./zstd_ep-install/lib64/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    else
        cp -rf ./zstd_ep-install/lib/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    fi
    # copy zstd headers
    mkdir -p ${TP_INSTALL_DIR}/include/zstd
    cp ./zstd_ep-install/include/* ${TP_INSTALL_DIR}/include/zstd

    restore_compile_flags
}

# s2
build_s2() {
    check_if_source_exist $S2_SOURCE
    cd $TP_SOURCE_DIR/$S2_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DBUILD_SHARED_LIBS=OFF \
    -DGFLAGS_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GFLAGS=ON \
    -DGLOG_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GLOG=ON \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# bitshuffle
build_bitshuffle() {
    check_if_source_exist $BITSHUFFLE_SOURCE
    cd $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE
    PREFIX=$TP_INSTALL_DIR

    # This library has significant optimizations when built with -mavx2. However,
    # we still need to support non-AVX2-capable hardware. So, we build it twice,
    # once with the flag and once without, and use some linker tricks to
    # suffix the AVX2 symbols with '_avx2'.
    arches="default avx2 avx512"
    # Becuase aarch64 don't support avx2, disable it.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        arches="default neon"
    fi

    to_link=""
    for arch in $arches ; do
        arch_flag=""
        if [ "$arch" == "avx2" ]; then
            arch_flag="-mavx2"
        elif [ "$arch" == "avx512" ]; then
            arch_flag="-march=icelake-server"
        elif [ "$arch" == "neon" ]; then
            arch_flag="-march=armv8-a+crc"
        fi
        tmp_obj=bitshuffle_${arch}_tmp.o
        dst_obj=bitshuffle_${arch}.o
        ${CC:-gcc} $EXTRA_CFLAGS $arch_flag -std=c99 -I$PREFIX/include/lz4/ -O3 -DNDEBUG -fPIC -c \
            "src/bitshuffle_core.c" \
            "src/bitshuffle.c" \
            "src/iochain.c"
        # Merge the object files together to produce a combined .o file.
        ld -r -o $tmp_obj bitshuffle_core.o bitshuffle.o iochain.o
        # For the AVX2 symbols, suffix them.
        if [[ "$arch" == "avx2" || "$arch" == "avx512" || "$arch" == "neon" ]]; then
            # Create a mapping file with '<old_sym> <suffixed_sym>' on each line.
            nm --defined-only --extern-only $tmp_obj | while read addr type sym ; do
              echo ${sym} ${sym}_${arch}
            done > renames.txt
            objcopy --redefine-syms=renames.txt $tmp_obj $dst_obj
        else
            mv $tmp_obj $dst_obj
        fi
        to_link="$to_link $dst_obj"
    done
    rm -f libbitshuffle.a
    ar rs libbitshuffle.a $to_link
    mkdir -p $PREFIX/include/bitshuffle
    cp libbitshuffle.a $PREFIX/lib/
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle.h $PREFIX/include/bitshuffle/bitshuffle.h
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle_core.h $PREFIX/include/bitshuffle/bitshuffle_core.h
}

# croaring bitmap
# If open AVX512 default, current version will be compiled failed on some machine, so close AVX512 default,
# When this problem is solved, a switch will be added to control.
build_croaringbitmap() {
    FORCE_AVX=ON
    # avx2 is not supported by aarch64.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        FORCE_AVX=FALSE
    fi
    if [[ `cat /proc/cpuinfo |grep avx|wc -l` == "0" ]]; then
        FORCE_AVX=FALSE
    fi
    check_if_source_exist $CROARINGBITMAP_SOURCE
    cd $TP_SOURCE_DIR/$CROARINGBITMAP_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DROARING_BUILD_STATIC=ON -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DENABLE_ROARING_TESTS=OFF \
    -DROARING_DISABLE_NATIVE=ON \
    -DFORCE_AVX=$FORCE_AVX \
    -DROARING_DISABLE_AVX512=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}
#orc
build_orc() {
    check_if_source_exist $ORC_SOURCE
    cd $TP_SOURCE_DIR/$ORC_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD ../ -DBUILD_JAVA=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DPROTOBUF_HOME=$TP_INSTALL_DIR \
    -DSNAPPY_HOME=$TP_INSTALL_DIR \
    -DGTEST_HOME=$TP_INSTALL_DIR \
    -DLZ4_HOME=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DZLIB_HOME=$TP_INSTALL_DIR\
    -DBUILD_LIBHDFSPP=OFF \
    -DBUILD_CPP_TESTS=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#cctz
build_cctz() {
    check_if_source_exist $CCTZ_SOURCE
    cd $TP_SOURCE_DIR/$CCTZ_SOURCE

    make -j$PARALLEL
    PREFIX=${TP_INSTALL_DIR} make install
}

#fmt
build_fmt() {
    check_if_source_exist $FMT_SOURCE
    cd $TP_SOURCE_DIR/$FMT_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} ../ \
            -DCMAKE_INSTALL_LIBDIR=lib64 -G "${CMAKE_GENERATOR}" -DFMT_TEST=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#ryu
build_ryu() {
    check_if_source_exist $RYU_SOURCE
    cd $TP_SOURCE_DIR/$RYU_SOURCE/ryu
    make -j$PARALLEL
    make install DESTDIR=${TP_INSTALL_DIR}
    mkdir -p $TP_INSTALL_DIR/include/ryu
    mv $TP_INSTALL_DIR/include/ryu.h $TP_INSTALL_DIR/include/ryu
    # copy to 64 to compatable with current CMake
    cp -f ${TP_INSTALL_DIR}/lib/libryu.a ${TP_INSTALL_DIR}/lib64/libryu.a
}

#break_pad
build_breakpad() {
    check_if_source_exist $BREAK_PAD_SOURCE
    cd $TP_SOURCE_DIR/$BREAK_PAD_SOURCE
    mkdir -p src/third_party/lss
    cp $TP_PATCH_DIR/linux_syscall_support.h src/third_party/lss
    CFLAGS= ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

#hadoop
build_hadoop() {
    check_if_source_exist $HADOOP_SOURCE
    cp -r $TP_SOURCE_DIR/$HADOOP_SOURCE $TP_INSTALL_DIR/hadoop
    # remove unnecessary doc and logs
    rm -rf $TP_INSTALL_DIR/hadoop/logs/* $TP_INSTALL_DIR/hadoop/share/doc/hadoop
    mkdir -p $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/include/hdfs.h $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/lib/native/libhdfs.a $TP_INSTALL_DIR/lib
}

#jdk
build_jdk() {
    check_if_source_exist $JDK_SOURCE
    rm -rf $TP_INSTALL_DIR/open_jdk && cp -r $TP_SOURCE_DIR/$JDK_SOURCE $TP_INSTALL_DIR/open_jdk
}

# ragel
# ragel-6.9+ is used by hypercan, so we build it first.
build_ragel() {
    check_if_source_exist $RAGEL_SOURCE
    cd $TP_SOURCE_DIR/$RAGEL_SOURCE
    # generage a static linked ragel, hyperscan will depend on it
    LDFLAGS=" -static-libstdc++ -static-libgcc" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

#hyperscan
build_hyperscan() {
    check_if_source_exist $HYPERSCAN_SOURCE
    cd $TP_SOURCE_DIR/$HYPERSCAN_SOURCE
    export PATH=$TP_INSTALL_DIR/bin:$PATH
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DBOOST_ROOT=$STARROCKS_THIRDPARTY/installed/include \
          -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc  -DCMAKE_INSTALL_LIBDIR=lib \
          -DBUILD_EXAMPLES=OFF -DBUILD_UNIT=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#mariadb-connector-c
build_mariadb() {
    OLD_CMAKE_GENERATOR=${CMAKE_GENERATOR}
    OLD_BUILD_SYSTEM=${BUILD_SYSTEM}

    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC ${FILE_PREFIX_MAP_OPTION}"

    # force use make build system, since ninja doesn't support install only headers
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'

    check_if_source_exist $MARIADB_SOURCE
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE
    mkdir -p build && cd build

    $CMAKE_CMD .. -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release    \
                  -DWITH_UNIT_TESTS=OFF                                 \
                  -DBUILD_SHARED_LIBS=OFF                               \
                  -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                  \
                  -DOPENSSL_USE_STATIC_LIBS=TRUE                        \
                  -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}
    # we only need build libmariadbclient and headers
    ${BUILD_SYSTEM} -j$PARALLEL mariadbclient
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/libmariadb
    mkdir -p $TP_INSTALL_DIR/lib/mariadb/
    cp libmariadbclient.a $TP_INSTALL_DIR/lib/mariadb/
    # install mariadb headers
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/include
    ${BUILD_SYSTEM} install

    restore_compile_flags
    export CMAKE_GENERATOR=$OLD_CMAKE_GENERATOR
    export BUILD_SYSTEM=$OLD_BUILD_SYSTEM
}

# jindosdk for Aliyun OSS
build_aliyun_jindosdk() {
    check_if_source_exist $JINDOSDK_SOURCE
    mkdir -p $TP_INSTALL_DIR/jindosdk
    cp -r $TP_SOURCE_DIR/$JINDOSDK_SOURCE/lib/*.jar $TP_INSTALL_DIR/jindosdk
}

build_gcs_connector() {
    check_if_source_exist $GCS_CONNECTOR_SOURCE
    mkdir -p $TP_INSTALL_DIR/gcs_connector
    cp -r $TP_SOURCE_DIR/$GCS_CONNECTOR_SOURCE/*.jar $TP_INSTALL_DIR/gcs_connector
}

build_broker_thirdparty_jars() {
    check_if_source_exist $BROKER_THIRDPARTY_JARS_SOURCE
    mkdir -p $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    cp -r $TP_SOURCE_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/* $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/hadoop-aliyun-2.7.2.jar
    # cloudfs-hadoop-with-dependencies will include aws jars, but we already support aws by official sdk, so we don't need it anymore.
    # And it will conflict with Iceberg's S3FileIO, make access S3 files failed.
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/cloudfs-hadoop-with-dependencies-1.1.21.jar
    # ensure read permission is granted for all users
    chmod -R +r $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/
}

build_aws_cpp_sdk() {
    check_if_source_exist $AWS_SDK_CPP_SOURCE
    cd $TP_SOURCE_DIR/$AWS_SDK_CPP_SOURCE
    # only build s3, s3-crt, transfer manager, identity-management and sts, you can add more components if you want.
    $CMAKE_CMD -Bbuild -DBUILD_ONLY="core;s3;s3-crt;transfer;identity-management;sts" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
               -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DENABLE_TESTING=OFF \
               -DENABLE_CURL_LOGGING=OFF \
               -G "${CMAKE_GENERATOR}" \
               -DCURL_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libcurl.a   \
               -DZLIB_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libz.a      \
               -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                     \
               -DOPENSSL_USE_STATIC_LIBS=TRUE                           \
               -Dcrypto_LIBRARY=${TP_INSTALL_DIR}/lib/libcrypto.a

    cd build
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    restore_compile_flags
}

# velocypack
build_vpack() {
    check_if_source_exist $VPACK_SOURCE
    cd $TP_SOURCE_DIR/$VPACK_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# opentelemetry
build_opentelemetry() {
    check_if_source_exist $OPENTELEMETRY_SOURCE

    cd $TP_SOURCE_DIR/$OPENTELEMETRY_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DBUILD_TESTING=OFF -DWITH_EXAMPLES=OFF \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        -DWITH_STL=OFF -DWITH_JAEGER=ON
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# jemalloc
build_jemalloc() {
    check_if_source_exist $JEMALLOC_SOURCE

    cd $TP_SOURCE_DIR/$JEMALLOC_SOURCE
    # jemalloc supports a runtime page size that's smaller or equal to the build
    # time one, but aborts on a larger one. If not defined, it falls back to the
    # the build system's _SC_PAGESIZE, which in many architectures can vary. Set
    # this to 64K (2^16) for arm architecture, and default 4K on x86 for performance.
    local addition_opts=" --with-lg-page=12"
    if [[ $MACHINE_TYPE == "aarch64" ]] ; then
        # change to 64K for arm architecture
        addition_opts=" --with-lg-page=16"
    fi
    # build jemalloc with release
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc --with-jemalloc-prefix=je --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
    # build jemalloc with debug options
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc-debug --with-jemalloc-prefix=je --enable-prof --enable-debug --enable-fill --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
}

# google benchmark
build_benchmark() {
    check_if_source_exist $BENCHMARK_SOURCE
    cd $TP_SOURCE_DIR/$BENCHMARK_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    cmake -DBENCHMARK_DOWNLOAD_DEPENDENCIES=off \
          -DBENCHMARK_ENABLE_GTEST_TESTS=off \
          -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
          -DCMAKE_INSTALL_LIBDIR=lib64 \
          -DCMAKE_BUILD_TYPE=Release ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# fast float
build_fast_float() {
    check_if_source_exist $FAST_FLOAT_SOURCE
    cd $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE
    cp -r $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE/include $TP_INSTALL_DIR
}

build_starcache() {
    check_if_source_exist $STARCACHE_SOURCE
    rm -rf $TP_INSTALL_DIR/$STARCACHE_SOURCE && mv $TP_SOURCE_DIR/$STARCACHE_SOURCE $TP_INSTALL_DIR/
}

# streamvbyte
build_streamvbyte() {
    check_if_source_exist $STREAMVBYTE_SOURCE

    cd $TP_SOURCE_DIR/$STREAMVBYTE_SOURCE/

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/

    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    $CMAKE_CMD .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=$TP_INSTALL_DIR/

    make -j$PARALLEL
    make install
}

# jansson
build_jansson() {
    check_if_source_exist $JANSSON_SOURCE
    cd $TP_SOURCE_DIR/$JANSSON_SOURCE/
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# avro-c
build_avro_c() {
    check_if_source_exist $AVRO_SOURCE
    cd $TP_SOURCE_DIR/$AVRO_SOURCE/lang/c
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    rm ${TP_INSTALL_DIR}/lib64/libavro.so*
}

# serders
build_serdes() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g"
    check_if_source_exist $SERDES_SOURCE
    cd $TP_SOURCE_DIR/$SERDES_SOURCE
    export LIBS="-lrt -lpthread -lcurl -ljansson -lrdkafka -lrdkafka++ -lavro -lssl -lcrypto -ldl"
    ./configure --prefix=${TP_INSTALL_DIR} \
                --libdir=${TP_INSTALL_DIR}/lib \
                --CFLAGS="-I ${TP_INSTALL_DIR}/include"  \
                --CXXFLAGS="-I ${TP_INSTALL_DIR}/include" \
                --LDFLAGS="-L ${TP_INSTALL_DIR}/lib -L ${TP_INSTALL_DIR}/lib64" \
                --enable-static \
                --disable-shared

    make -j$PARALLEL
    make install
    rm ${TP_INSTALL_DIR}/lib/libserdes.so*
    # these symbols also be definition in librdkafka, change these symbols to be local.
    objcopy --localize-symbol=cnd_timedwait ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=cnd_timedwait_ms ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=thrd_is_current ${TP_INSTALL_DIR}/lib/libserdes.a
    unset LIBS
    restore_compile_flags
}

# datasketches
build_datasketches() {
    check_if_source_exist $DATASKETCHES_SOURCE
    mkdir -p $TP_INSTALL_DIR/include/datasketches
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/common/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/cpc/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/fi/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/hll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/kll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/quantiles/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/req/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/sampling/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/theta/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/tuple/include/* $TP_INSTALL_DIR/include/datasketches/
}

# async-profiler
build_async_profiler() {
    check_if_source_exist $ASYNC_PROFILER_SOURCE
    mkdir -p $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/build $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/profiler.sh $TP_INSTALL_DIR/async-profiler
}

# fiu
build_fiu() {
    check_if_source_exist $FIU_SOURCE
    cd $TP_SOURCE_DIR/$FIU_SOURCE
    mkdir -p $TP_SOURCE_DIR/$FIU_SOURCE/installed
    make -j$PARALLEL
    make PREFIX=$TP_SOURCE_DIR/$FIU_SOURCE/installed install

    mkdir -p $TP_INSTALL_DIR/include/fiu
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/include/* $TP_INSTALL_DIR/include/fiu/
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/lib/libfiu.a $TP_INSTALL_DIR/lib/
}

# libdeflate
build_libdeflate() {
    check_if_source_exist $LIBDEFLATE_SOURCE
    mkdir -p $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    cd $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    $CMAKE_CMD .. -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# restore cxxflags/cppflags/cflags to default one
restore_compile_flags() {
    # c preprocessor flags
    export CPPFLAGS=$GLOBAL_CPPFLAGS
    # c flags
    export CFLAGS=$GLOBAL_CFLAGS
    # c++ flags
    export CXXFLAGS=$GLOBAL_CXXFLAGS
}

strip_binary() {
    # strip binary tools and ignore any errors
    echo "Strip binaries in $TP_INSTALL_DIR/bin/ ..."
    strip $TP_INSTALL_DIR/bin/* 2>/dev/null || true
}


# strip `$TP_SOURCE_DIR` and `$TP_INSTALL_DIR` from source code file path
export FILE_PREFIX_MAP_OPTION="-ffile-prefix-map=${TP_SOURCE_DIR}=. -ffile-prefix-map=${TP_INSTALL_DIR}=."
# set GLOBAL_C*FLAGS for easy restore in each sub build process
export GLOBAL_CPPFLAGS="-I ${TP_INCLUDE_DIR}"
# https://stackoverflow.com/questions/42597685/storage-size-of-timespec-isnt-known
export GLOBAL_CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -fPIC -g -D_POSIX_C_SOURCE=200112L -gz=zlib ${FILE_PREFIX_MAP_OPTION}"
export GLOBAL_CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess -fPIC -g -gz=zlib ${FILE_PREFIX_MAP_OPTION}"

# set those GLOBAL_*FLAGS to the CFLAGS/CXXFLAGS/CPPFLAGS
export CPPFLAGS=$GLOBAL_CPPFLAGS
export CXXFLAGS=$GLOBAL_CXXFLAGS
export CFLAGS=$GLOBAL_CFLAGS

build_libevent
build_zlib
build_lz4
build_lzo2
build_bzip
build_openssl
build_boost # must before thrift
build_protobuf
build_gflags
build_gtest
build_glog
build_rapidjson
build_simdjson
build_snappy
build_gperftools
build_curl
build_re2
build_thrift
build_leveldb
build_brpc
build_rocksdb
build_kerberos
build_sasl
build_flatbuffers
build_jemalloc
build_brotli
# must build before arrow
build_arrow
# NOTE: librdkafka depends on ZSTD which is generated by Arrow, So this SHOULD be
# built after arrow
build_librdkafka
build_pulsar
build_s2
build_bitshuffle
build_croaringbitmap
build_cctz
build_fmt
build_ryu
build_hadoop
build_jdk
build_ragel
build_hyperscan
build_mariadb
build_aliyun_jindosdk
build_gcs_connector
build_broker_thirdparty_jars
build_aws_cpp_sdk
build_vpack
build_opentelemetry
build_benchmark
build_fast_float
build_starcache
build_streamvbyte
build_jansson
build_avro_c
build_serdes
build_datasketches
build_async_profiler
build_fiu
build_llvm

if [[ "${MACHINE_TYPE}" != "aarch64" ]]; then
    build_breakpad
    build_libdeflate
fi

# strip unnecessary debug symbol for binaries in thirdparty
strip_binary

echo "Finished to build all thirdparties"

```

修改完成！来总结一下：

## 问题根因

| 项目 | 详情 |
|------|------|
| **GCC 版本** | 13.3.0（较新，检查更严格） |
| **出错位置** | `thirdparty/src/rocksdb-6.22.1/db/db_impl/db_impl.cc` 第 1250、1254、1351 行 |
| **错误类型** | `-Werror=redundant-move`：在 return 语句中使用 `std::move()` 是多余的 |
| **为何是 error** | RocksDB Makefile 开启了 `-Werror`，把警告升级为错误 |

## 解决方法

在 `thirdparty/build-thirdparty.sh` 的 `build_rocksdb()` 函数中，`EXTRA_CXXFLAGS` 增加了 **`-Wno-redundant-move`**，告诉 GCC 忽略这个警告。

修改后重新执行编译即可：

```bash
BUILD_TYPE=Debug ./build.sh --be
```

> 这是一个典型的「老版本第三方库 + 新版本编译器」不兼容的问题。RocksDB 6.22.1 是 2021 年的代码，当时 GCC 还不会对 `return std::move(local_var)` 报 redundant-move 警告，但 GCC 13 对此更严格了。StarRocks 的构建脚本里已经对其他类似问题加了 `-Wno-deprecated-copy` 等绕过，只是漏了这个。

```shellscript
BUILD_TYPE=Debug ./build.sh --be
```

---

**User**

又遇到新问题了

@zsh (811-1023) 、

---

**Cursor**

好的，上一个 `-Wno-redundant-move` 的问题已经解决了（`db_impl.o` 编译通过了），但现在遇到了**新的错误**：

```
./db/compaction/compaction_iteration_stats.h:23:3: error: 'uint64_t' does not name a type
./db/compaction/compaction_iteration_stats.h:9:1: note: 'uint64_t' is defined in header '<cstdint>'; did you forget to '#include <cstdint>'?
```

这是因为 GCC 13 对头文件的隐式包含更加严格了。在旧版 GCC 中，`uint64_t` 可能通过其他头文件间接引入，但 GCC 13 不再如此，需要显式 `#include <cstdint>`。

让我修复这个源文件：

```plaintext
./db/compaction/compaction_iteration_stats.h:23:3: error: 'uint64_t' does not name a type
./db/compaction/compaction_iteration_stats.h:9:1: note: 'uint64_t' is defined in header '<cstdint>'; did you forget to '#include <cstdint>'?
```

```cpp
//  Copyright (c) 2016-present, Facebook, Inc.  All rights reserved.
//  This source code is licensed under both the GPLv2 (found in the
//  COPYING file in the root directory) and Apache 2.0 License
//  (found in the LICENSE.Apache file in the root directory).

#pragma once

#include <cstdint>
#include "rocksdb/rocksdb_namespace.h"

struct CompactionIterationStats {
  // Compaction statistics

  // Doesn't include records skipped because of
  // CompactionFilter::Decision::kRemoveAndSkipUntil.
  int64_t num_record_drop_user = 0;

  int64_t num_record_drop_hidden = 0;
  int64_t num_record_drop_obsolete = 0;
  int64_t num_record_drop_range_del = 0;
  int64_t num_range_del_drop_obsolete = 0;
  // Deletions obsoleted before bottom level due to file gap optimization.
  int64_t num_optimized_del_drop_obsolete = 0;
  uint64_t total_filter_time = 0;

  // Input statistics
  // TODO(noetzli): The stats are incomplete. They are lacking everything
  // consumed by MergeHelper.
  uint64_t num_input_records = 0;
  uint64_t num_input_deletion_records = 0;
  uint64_t num_input_corrupt_records = 0;
  uint64_t total_input_raw_key_bytes = 0;
  uint64_t total_input_raw_value_bytes = 0;

  // Single-Delete diagnostics for exceptional situations
  uint64_t num_single_del_fallthru = 0;
  uint64_t num_single_del_mismatch = 0;

  // Blob related statistics
  uint64_t num_blobs_read = 0;
  uint64_t total_blob_bytes_read = 0;
};

```

修好了。不过根据经验，GCC 13 编译 RocksDB 6.22.1 这种老代码，类似的"缺少 `#include <cstdint>` "的问题可能在**其他头文件**中也会出现。让我提前排查一下：

确实有很多文件都缺少 `<cstdint>`。但逐个修改不现实且容易遗漏。更好的方案是：**通过编译选项全局注入这个头文件**，在 `EXTRA_CXXFLAGS` 中加 `-include cstdint`，这样所有 `.cc`/`.cpp` 文件编译时都会自动先包含 `<cstdint>`，一次性解决所有此类问题。

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

#################################################################################
# This script will
# 1. Check prerequisite libraries. Including:
#    cmake byacc flex automake libtool binutils-dev libiberty-dev bison
# 2. Compile and install all thirdparties which are downloaded
#    using *download-thirdparty.sh*.
#
# This script will run *download-thirdparty.sh* once again
# to check if all thirdparties have been downloaded, unpacked and patched.
#################################################################################
set -e

curdir=`dirname "$0"`
curdir=`cd "$curdir"; pwd`

export STARROCKS_HOME=${STARROCKS_HOME:-$curdir/..}
export TP_DIR=$curdir

# include custom environment variables
if [[ -f ${STARROCKS_HOME}/env.sh ]]; then
    . ${STARROCKS_HOME}/env.sh
fi

if [[ ! -f ${TP_DIR}/download-thirdparty.sh ]]; then
    echo "Download thirdparty script is missing".
    exit 1
fi

if [ ! -f ${TP_DIR}/vars.sh ]; then
    echo "vars.sh is missing".
    exit 1
fi
. ${TP_DIR}/vars.sh

cd $TP_DIR

# Download thirdparties.
${TP_DIR}/download-thirdparty.sh

# set COMPILER
if [[ ! -z ${STARROCKS_GCC_HOME} ]]; then
    export CC=${STARROCKS_GCC_HOME}/bin/gcc
    export CPP=${STARROCKS_GCC_HOME}/bin/cpp
    export CXX=${STARROCKS_GCC_HOME}/bin/g++
    export PATH=${STARROCKS_GCC_HOME}/bin:$PATH
else
    echo "STARROCKS_GCC_HOME environment variable is not set"
    exit 1
fi

# prepare installed prefix
mkdir -p ${TP_DIR}/installed

check_prerequest() {
    local CMD=$1
    local NAME=$2
    if ! $CMD; then
        echo $NAME is missing
        exit 1
    else
        echo $NAME is found
    fi
}

# sudo apt-get install cmake
# sudo yum install cmake
check_prerequest "${CMAKE_CMD} --version" "cmake"

# sudo apt-get install byacc
# sudo yum install byacc
check_prerequest "byacc -V" "byacc"

# sudo apt-get install flex
# sudo yum install flex
check_prerequest "flex -V" "flex"

# sudo apt-get install automake
# sudo yum install automake
check_prerequest "automake --version" "automake"

# sudo apt-get install libtool
# sudo yum install libtool
check_prerequest "libtoolize --version" "libtool"

BUILD_SYSTEM=${BUILD_SYSTEM:-make}

# sudo apt-get install binutils-dev
# sudo yum install binutils-devel
#check_prerequest "locate libbfd.a" "binutils-dev"

# sudo apt-get install libiberty-dev
# no need in centos 7.1
#check_prerequest "locate libiberty.a" "libiberty-dev"

# sudo apt-get install bison
# sudo yum install bison
#check_prerequest "bison --version" "bison"

#########################
# build all thirdparties
#########################


# Name of cmake build directory in each thirdpary project.
# Do not use `build`, because many projects contained a file named `BUILD`
# and if the filesystem is not case sensitive, `mkdir` will fail.
BUILD_DIR=starrocks_build
MACHINE_TYPE=$(uname -m)

# handle mac m1 platform, change arm64 to aarch64
if [[ "${MACHINE_TYPE}" == "arm64" ]]; then
    MACHINE_TYPE="aarch64"
fi

echo "machine type : $MACHINE_TYPE"

check_if_source_exist() {
    if [ -z $1 ]; then
        echo "dir should specified to check if exist."
        exit 1
    fi

    if [ ! -d $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
    echo "===== begin build $1"
}

check_if_archieve_exist() {
    if [ -z $1 ]; then
        echo "archieve should specified to check if exist."
        exit 1
    fi

    if [ ! -f $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
}

# libevent
build_libevent() {
    check_if_source_exist $LIBEVENT_SOURCE
    cd $TP_SOURCE_DIR/$LIBEVENT_SOURCE
    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

build_openssl() {
    OPENSSL_PLATFORM="linux-x86_64"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        OPENSSL_PLATFORM="linux-aarch64"
    fi

    check_if_source_exist $OPENSSL_SOURCE
    cd $TP_SOURCE_DIR/$OPENSSL_SOURCE

    # use customized CFLAGS/CPPFLAGS/CXXFLAGS/LDFLAGS
    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC"

    LDFLAGS="-L${TP_LIB_DIR}" \
    LIBDIR="lib" \
    ./Configure --prefix=$TP_INSTALL_DIR -lz -no-shared ${OPENSSL_PLATFORM}
    make -j$PARALLEL
    make install_sw

    restore_compile_flags
}

# thrift
build_thrift() {
    check_if_source_exist $THRIFT_SOURCE
    cd $TP_SOURCE_DIR/$THRIFT_SOURCE

    if [ ! -f configure ]; then
        ./bootstrap.sh
    fi

    echo ${TP_LIB_DIR}
    ./configure LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" LIBS="-lssl -lcrypto -ldl" \
    --prefix=$TP_INSTALL_DIR --docdir=$TP_INSTALL_DIR/doc --enable-static --disable-shared --disable-tests \
    --disable-tutorial --without-qt4 --without-qt5 --without-csharp --without-erlang --without-nodejs \
    --without-lua --without-perl --without-php --without-php_extension --without-dart --without-ruby \
    --without-haskell --without-go --without-haxe --without-d --without-python -without-java --with-cpp \
    --with-libevent=$TP_INSTALL_DIR --with-boost=$TP_INSTALL_DIR --with-openssl=$TP_INSTALL_DIR

    if [ -f compiler/cpp/thrifty.hh ];then
        mv compiler/cpp/thrifty.hh compiler/cpp/thrifty.h
    fi

    make -j$PARALLEL
    make install
}

# llvm
build_llvm() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -D_POSIX_C_SOURCE=200112L ${FILE_PREFIX_MAP_OPTION}"
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess ${FILE_PREFIX_MAP_OPTION}"

    LLVM_TARGET="X86"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        LLVM_TARGET="AArch64"
    fi

    LLVM_TARGETS_TO_BUILD=(
        "LLVMBitstreamReader"
        "LLVMRuntimeDyld" 
        "LLVMOption"
        "LLVMAsmPrinter"
        "LLVMProfileData"
        "LLVMAsmParser"
        "LLVMOrcTargetProcess"
        "LLVMExecutionEngine"
        "LLVMBinaryFormat"
        "LLVMDebugInfoDWARF"
        "LLVMObjCARCOpts"
        "LLVMCodeGen"
        "LLVMMCDisassembler"
        "LLVMSupport"
        "LLVMJITLink"
        "LLVMCFGuard"
        "LLVMInstrumentation"
        "LLVMIRReader"
        "LLVMCore"
        "LLVMTarget"
        "LLVMMC"
        "LLVMAnalysis"
        "LLVMGlobalISel"
        "LLVMScalarOpts"
        "LLVMTargetParser"
        "LLVMDemangle"
        "LLVMRemarks"
        "LLVMDebugInfoCodeView"
        "LLVMOrcShared"
        "LLVMOrcJIT"
        "LLVMTextAPI"
        "LLVMBitWriter"
        "LLVMBitReader"
        "LLVMObject"
        "LLVMTransformUtils"
        "LLVMSelectionDAG"
        "LLVMMCParser"
    )
    if [ "${LLVM_TARGET}" == "X86" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMX86Info" "LLVMX86Desc" "LLVMX86CodeGen")
    elif [ "${LLVM_TARGET}" == "AArch64" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMAArch64Info" "LLVMAArch64Desc" "LLVMAArch64CodeGen")
    fi

    LLVM_TARGETS_TO_INSTALL=()
    for target in ${LLVM_TARGETS_TO_BUILD[@]}; do
        LLVM_TARGETS_TO_INSTALL+=("install-${target}")
    done

    check_if_source_exist $LLVM_SOURCE

    cd $TP_SOURCE_DIR
    mkdir -p llvm-build
    cd llvm-build
    rm -rf CMakeCache.txt CMakeFiles/

    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -S ../${LLVM_SOURCE}/llvm -G "${CMAKE_GENERATOR}" \
    -DLLVM_ENABLE_EH:Bool=True \
    -DLLVM_ENABLE_RTTI:Bool=True \
    -DLLVM_ENABLE_PIC:Bool=True \
    -DLLVM_ENABLE_TERMINFO:Bool=False \
    -DLLVM_TARGETS_TO_BUILD=${LLVM_TARGET} \
    -DLLVM_BUILD_LLVM_DYLIB:BOOL=False \
    -DLLVM_INCLUDE_TOOLS:BOOL=False \
    -DLLVM_BUILD_TOOLS:BOOL=False \
    -DLLVM_INCLUDE_EXAMPLES:BOOL=False \
    -DLLVM_INCLUDE_TESTS:BOOL=False \
    -DLLVM_INCLUDE_BENCHMARKS:BOOL=False \
    -DBUILD_SHARED_LIBS:BOOL=False \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}/llvm ../${LLVM_SOURCE}

    # TODO(yueyang): Add more targets.
    # This is a little bit hack, we need to minimize the build time and binary size.
    ${BUILD_SYSTEM} -j$PARALLEL REQUIRES_RTTI=1 ${LLVM_TARGETS_TO_BUILD[@]}
    ${BUILD_SYSTEM} install-llvm-headers
    ${BUILD_SYSTEM} ${LLVM_TARGETS_TO_INSTALL[@]}

    restore_compile_flags
}

# protobuf
build_protobuf() {
    check_if_source_exist $PROTOBUF_SOURCE
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    rm -fr gmock
    mkdir gmock
    cd gmock
    tar xf ${TP_SOURCE_DIR}/$GTEST_NAME
    mv $GTEST_SOURCE gtest
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    ./autogen.sh
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc -pthread -Wl,--whole-archive -lpthread -Wl,--no-whole-archive" \
    ./configure --prefix=${TP_INSTALL_DIR} --disable-shared --enable-static --with-zlib --with-zlib-include=${TP_INSTALL_DIR}/include
    make -j$PARALLEL
    make install
}

# gflags
build_gflags() {
    check_if_source_exist $GFLAGS_SOURCE

    cd $TP_SOURCE_DIR/$GFLAGS_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# glog
build_glog() {
    check_if_source_exist $GLOG_SOURCE
    cd $TP_SOURCE_DIR/$GLOG_SOURCE

    # to generate config.guess and config.sub to support aarch64
    rm -rf config.*
    autoreconf -i

    LDFLAGS="-L${TP_LIB_DIR}" \
    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-frame-pointers --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

# gtest
build_gtest() {
    check_if_source_exist $GTEST_SOURCE

    cd $TP_SOURCE_DIR/$GTEST_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# rapidjson
build_rapidjson() {
    check_if_source_exist $RAPIDJSON_SOURCE

    rm -rf $TP_INSTALL_DIR/rapidjson
    cp -r $TP_SOURCE_DIR/$RAPIDJSON_SOURCE/include/rapidjson $TP_INCLUDE_DIR/
}

# simdjson
build_simdjson() {
    check_if_source_exist $SIMDJSON_SOURCE
    cd $TP_SOURCE_DIR/$SIMDJSON_SOURCE

    #ref: https://github.com/simdjson/simdjson/blob/master/HACKING.md
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_CXX_FLAGS="-O3" -DCMAKE_C_FLAGS="-O3" -DCMAKE_POSITION_INDEPENDENT_CODE=True -DSIMDJSON_AVX512_ALLOWED=OFF ..
    $CMAKE_CMD --build .
    mkdir -p $TP_INSTALL_DIR/lib

    cp $TP_SOURCE_DIR/$SIMDJSON_SOURCE/$BUILD_DIR/libsimdjson.a $TP_INSTALL_DIR/lib
    cp -r $TP_SOURCE_DIR/$SIMDJSON_SOURCE/include/* $TP_INCLUDE_DIR/
}

# snappy
build_snappy() {
    check_if_source_exist $SNAPPY_SOURCE
    cd $TP_SOURCE_DIR/$SNAPPY_SOURCE

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -G "${CMAKE_GENERATOR}" \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On \
    -DCMAKE_INSTALL_INCLUDEDIR=$TP_INCLUDE_DIR/snappy \
    -DSNAPPY_BUILD_TESTS=0 ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    if [ -f $TP_INSTALL_DIR/lib64/libsnappy.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib
        cp $TP_INSTALL_DIR/lib64/libsnappy.a $TP_INSTALL_DIR/lib/libsnappy.a
    fi

    #build for libarrow.a
    cp $TP_INCLUDE_DIR/snappy/snappy-c.h  $TP_INCLUDE_DIR/snappy-c.h
    cp $TP_INCLUDE_DIR/snappy/snappy-sinksource.h  $TP_INCLUDE_DIR/snappy-sinksource.h
    cp $TP_INCLUDE_DIR/snappy/snappy-stubs-public.h  $TP_INCLUDE_DIR/snappy-stubs-public.h
    cp $TP_INCLUDE_DIR/snappy/snappy.h  $TP_INCLUDE_DIR/snappy.h
    cp $TP_INSTALL_DIR/lib/libsnappy.a $TP_INSTALL_DIR/libsnappy.a
}

# gperftools
build_gperftools() {
    check_if_source_exist $GPERFTOOLS_SOURCE
    cd $TP_SOURCE_DIR/$GPERFTOOLS_SOURCE

    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=$TP_INSTALL_DIR/gperftools --disable-shared --enable-static --disable-libunwind --with-pic --enable-frame-pointers
    make -j$PARALLEL
    make install
}

# zlib
build_zlib() {
    check_if_source_exist $ZLIB_SOURCE
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --static
    make -j$PARALLEL
    make install

    # build minizip
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE/contrib/minizip
    autoreconf --force --install
    ./configure --prefix=$TP_INSTALL_DIR --enable-static=yes --enable-shared=no
    make -j$PARALLEL
    make install
}

# lz4
build_lz4() {
    check_if_source_exist $LZ4_SOURCE
    cd $TP_SOURCE_DIR/$LZ4_SOURCE

    make -C lib -j$PARALLEL install PREFIX=$TP_INSTALL_DIR \
    INCLUDEDIR=$TP_INCLUDE_DIR/lz4/ BUILD_SHARED=no
}

# lzo
build_lzo2() {
    check_if_source_exist $LZO2_SOURCE
    cd $TP_SOURCE_DIR/$LZO2_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
        LDFLAGS="-L${TP_LIB_DIR}" \
        ./configure --prefix="${TP_INSTALL_DIR}" --disable-shared --enable-static

    make -j "${PARALLEL}"
    make install
}

# bzip
build_bzip() {
    check_if_source_exist $BZIP_SOURCE
    cd $TP_SOURCE_DIR/$BZIP_SOURCE

    make -j$PARALLEL install PREFIX=$TP_INSTALL_DIR
}

# curl
build_curl() {
    check_if_source_exist $CURL_SOURCE
    cd $TP_SOURCE_DIR/$CURL_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" LIBS="-lssl -lcrypto -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static \
    --without-librtmp --with-ssl=${TP_INSTALL_DIR} --without-libidn2 --without-libgsasl --disable-ldap --enable-ipv6 --without-brotli
    make -j$PARALLEL
    make install
}

# re2
build_re2() {
    check_if_source_exist $RE2_SOURCE
    cd $TP_SOURCE_DIR/$RE2_SOURCE

    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release \
	    -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL install
}

# boost
build_boost() {
    check_if_source_exist $BOOST_SOURCE
    cd $TP_SOURCE_DIR/$BOOST_SOURCE

    # It is difficult to generate static linked b2, so we use LD_LIBRARY_PATH instead
    ./bootstrap.sh --prefix=$TP_INSTALL_DIR
    LD_LIBRARY_PATH=${STARROCKS_GCC_HOME}/lib:${STARROCKS_GCC_HOME}/lib64:${LD_LIBRARY_PATH} \
    ./b2 link=static runtime-link=static -j $PARALLEL --without-test --without-mpi --without-graph --without-graph_parallel --without-python cxxflags="-std=c++11 -g -fPIC -I$TP_INCLUDE_DIR -L$TP_LIB_DIR ${FILE_PREFIX_MAP_OPTION}" install
}

#leveldb
build_leveldb() {
    check_if_source_exist $LEVELDB_SOURCE
    cd $TP_SOURCE_DIR/$LEVELDB_SOURCE
    LDFLAGS="-L ${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    make -j$PARALLEL
    cp out-static/libleveldb.a $TP_LIB_DIR/libleveldb.a
    cp -r include/leveldb $TP_INCLUDE_DIR
}

# brpc
build_brpc() {
    check_if_source_exist $BRPC_SOURCE

    cd $TP_SOURCE_DIR/$BRPC_SOURCE
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    ./config_brpc.sh --headers="$TP_INSTALL_DIR/include" --libs="$TP_INSTALL_DIR/bin $TP_INSTALL_DIR/lib" --with-glog
    make -j$PARALLEL
    cp -rf output/* ${TP_INSTALL_DIR}/
    if [ -f $TP_INSTALL_DIR/lib/libbrpc.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib64
        cp $TP_SOURCE_DIR/$BRPC_SOURCE/output/lib/libbrpc.a $TP_INSTALL_DIR/lib64/
    fi
}

# rocksdb
build_rocksdb() {
    check_if_source_exist $ROCKSDB_SOURCE

    cd $TP_SOURCE_DIR/$ROCKSDB_SOURCE
    make clean

    CFLAGS= \
    EXTRA_CFLAGS="-I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy -I ${TP_INCLUDE_DIR}/lz4 -L${TP_LIB_DIR} ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_CXXFLAGS="-fPIC -Wno-deprecated-copy -Wno-stringop-truncation -Wno-pessimizing-move -Wno-redundant-move -include cstdint -I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_LDFLAGS="-static-libstdc++ -static-libgcc" \
    PORTABLE=1 make USE_RTTI=1 -j$PARALLEL static_lib

    cp librocksdb.a $TP_LIB_DIR/librocksdb.a
    cp -r include/rocksdb $TP_INCLUDE_DIR
}

# kerberos
build_kerberos() {
    check_if_source_exist $KRB5_SOURCE
    cd $TP_SOURCE_DIR/$KRB5_SOURCE/src
    CFLAGS="-fcommon -fPIC ${FILE_PREFIX_MAP_OPTION}" LDFLAGS="-L$TP_INSTALL_DIR/lib -pthread -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-static --disable-shared --with-spake-openssl=$TP_INSTALL_DIR
    make -j$PARALLEL
    make install
}

# sasl
build_sasl() {
    check_if_source_exist $SASL_SOURCE
    cd $TP_SOURCE_DIR/$SASL_SOURCE
    CFLAGS="-fPIC" LDFLAGS="-L$TP_INSTALL_DIR/lib -lresolv -pthread -ldl" ./autogen.sh --prefix=$TP_INSTALL_DIR --enable-gssapi=yes --enable-static --disable-shared --with-openssl=$TP_INSTALL_DIR --with-gss_impl=mit
    make -j$PARALLEL
    make install
}

# librdkafka
build_librdkafka() {
    check_if_source_exist $LIBRDKAFKA_SOURCE

    cd $TP_SOURCE_DIR/$LIBRDKAFKA_SOURCE

    mkdir -p sr_build && cd sr_build
    $CMAKE_CMD -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" \
        -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include;$TP_INSTALL_DIR/include/zstd;$TP_INSTALL_DIR/include/lz4" \
        -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DRDKAFKA_BUILD_STATIC=ON -DWITH_SASL=ON -DWITH_SASL_SCRAM=ON \
        -DRDKAFKA_BUILD_EXAMPLES=OFF -DRDKAFKA_BUILD_TESTS=OFF -DWITH_SSL=ON -DWITH_ZSTD=ON -DCMAKE_INSTALL_LIBDIR=lib ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# pulsar
build_pulsar() {
    check_if_source_exist $PULSAR_SOURCE

    cd $TP_SOURCE_DIR/$PULSAR_SOURCE

    $CMAKE_CMD -DCMAKE_LIBRARY_PATH=$TP_INSTALL_DIR/lib -DCMAKE_INCLUDE_PATH=$TP_INSTALL_DIR/include \
        -DPROTOC_PATH=$TP_INSTALL_DIR/bin/protoc -DBUILD_TESTS=OFF -DBUILD_PYTHON_WRAPPER=OFF -DBUILD_DYNAMIC_LIB=OFF .
    ${BUILD_SYSTEM} -j$PARALLEL

    cp lib/libpulsar.a $TP_INSTALL_DIR/lib/
    cp -r include/pulsar $TP_INSTALL_DIR/include/
}

# flatbuffers
build_flatbuffers() {
  check_if_source_exist $FLATBUFFERS_SOURCE
  cd $TP_SOURCE_DIR/$FLATBUFFERS_SOURCE
  mkdir -p $BUILD_DIR
  cd $BUILD_DIR
  rm -rf CMakeCache.txt CMakeFiles/
  LDFLAGS="-static-libstdc++ -static-libgcc" \
  ${CMAKE_CMD} .. -G "${CMAKE_GENERATOR}" -DFLATBUFFERS_BUILD_TESTS=OFF
  ${BUILD_SYSTEM} -j$PARALLEL
  cp flatc  $TP_INSTALL_DIR/bin/flatc
  cp -r ../include/flatbuffers  $TP_INCLUDE_DIR/flatbuffers
  cp libflatbuffers.a $TP_LIB_DIR/libflatbuffers.a
}

build_brotli() {
    check_if_source_exist $BROTLI_SOURCE
    cd $TP_SOURCE_DIR/$BROTLI_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    ${CMAKE_CMD} .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib64
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    mv -f $TP_INSTALL_DIR/lib64/libbrotlienc-static.a $TP_INSTALL_DIR/lib64/libbrotlienc.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlidec-static.a $TP_INSTALL_DIR/lib64/libbrotlidec.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlicommon-static.a $TP_INSTALL_DIR/lib64/libbrotlicommon.a
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so.*
}

# arrow
build_arrow() {
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CPPFLAGS=$CXXFLAGS

    check_if_source_exist $ARROW_SOURCE
    cd $TP_SOURCE_DIR/$ARROW_SOURCE/cpp
    mkdir -p release
    cd release
    export ARROW_BROTLI_URL=${TP_SOURCE_DIR}/${BROTLI_NAME}
    export ARROW_GLOG_URL=${TP_SOURCE_DIR}/${GLOG_NAME}
    export ARROW_LZ4_URL=${TP_SOURCE_DIR}/${LZ4_NAME}
    export ARROW_SNAPPY_URL=${TP_SOURCE_DIR}/${SNAPPY_NAME}
    export ARROW_ZLIB_URL=${TP_SOURCE_DIR}/${ZLIB_NAME}
    export ARROW_FLATBUFFERS_URL=${TP_SOURCE_DIR}/${FLATBUFFERS_NAME}
    export ARROW_ZSTD_URL=${TP_SOURCE_DIR}/${ZSTD_NAME}
    export LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc"

    # https://github.com/apache/arrow/blob/apache-arrow-5.0.0/cpp/src/arrow/memory_pool.cc#L286
    #
    # JemallocAllocator use mallocx and rallocx to allocate new memory, but mallocx and rallocx are Non-standard APIs,
    # and can not be hooked in BE, the memory used by arrow can not be counted by BE,
    # so disable jemalloc here and use SystemAllocator.
    #
    # Currently, the standard APIs are hooked in BE, so the jemalloc standard APIs will actually be used.
    ${CMAKE_CMD} -DARROW_PARQUET=ON -DARROW_JSON=ON -DARROW_IPC=ON -DARROW_USE_GLOG=OFF -DARROW_BUILD_STATIC=ON -DARROW_BUILD_SHARED=OFF \
    -DARROW_WITH_BROTLI=ON -DARROW_WITH_LZ4=ON -DARROW_WITH_SNAPPY=ON -DARROW_WITH_ZLIB=ON -DARROW_WITH_ZSTD=ON \
    -DARROW_WITH_UTF8PROC=OFF -DARROW_WITH_RE2=OFF \
    -DARROW_JEMALLOC=OFF -DARROW_MIMALLOC=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DARROW_BOOST_USE_SHARED=OFF -DARROW_GFLAGS_USE_SHARED=OFF -DBoost_NO_BOOST_CMAKE=ON -DBOOST_ROOT=$TP_INSTALL_DIR \
    -DJEMALLOC_HOME=$TP_INSTALL_DIR/jemalloc \
    -Dzstd_SOURCE=BUNDLED \
    -DRapidJSON_ROOT=$TP_INSTALL_DIR \
    -DARROW_SNAPPY_USE_SHARED=OFF \
    -DZLIB_ROOT=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DARROW_LZ4_USE_SHARED=OFF \
    -DBROTLI_ROOT=$TP_INSTALL_DIR \
    -DARROW_BROTLI_USE_SHARED=OFF \
    -Dgflags_ROOT=$TP_INSTALL_DIR/ \
    -DSnappy_ROOT=$TP_INSTALL_DIR/ \
    -DGLOG_ROOT=$TP_INSTALL_DIR/ \
    -DLZ4_ROOT=$TP_INSTALL_DIR/ \
    -DBoost_DIR=$TP_INSTALL_DIR \
    -DBoost_ROOT=$TP_INSTALL_DIR \
    -DARROW_BOOST_USE_SHARED=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DThrift_ROOT=$TP_INSTALL_DIR/ ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    if [ -f ./zstd_ep-install/lib64/libzstd.a ]; then
        cp -rf ./zstd_ep-install/lib64/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    else
        cp -rf ./zstd_ep-install/lib/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    fi
    # copy zstd headers
    mkdir -p ${TP_INSTALL_DIR}/include/zstd
    cp ./zstd_ep-install/include/* ${TP_INSTALL_DIR}/include/zstd

    restore_compile_flags
}

# s2
build_s2() {
    check_if_source_exist $S2_SOURCE
    cd $TP_SOURCE_DIR/$S2_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DBUILD_SHARED_LIBS=OFF \
    -DGFLAGS_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GFLAGS=ON \
    -DGLOG_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GLOG=ON \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# bitshuffle
build_bitshuffle() {
    check_if_source_exist $BITSHUFFLE_SOURCE
    cd $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE
    PREFIX=$TP_INSTALL_DIR

    # This library has significant optimizations when built with -mavx2. However,
    # we still need to support non-AVX2-capable hardware. So, we build it twice,
    # once with the flag and once without, and use some linker tricks to
    # suffix the AVX2 symbols with '_avx2'.
    arches="default avx2 avx512"
    # Becuase aarch64 don't support avx2, disable it.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        arches="default neon"
    fi

    to_link=""
    for arch in $arches ; do
        arch_flag=""
        if [ "$arch" == "avx2" ]; then
            arch_flag="-mavx2"
        elif [ "$arch" == "avx512" ]; then
            arch_flag="-march=icelake-server"
        elif [ "$arch" == "neon" ]; then
            arch_flag="-march=armv8-a+crc"
        fi
        tmp_obj=bitshuffle_${arch}_tmp.o
        dst_obj=bitshuffle_${arch}.o
        ${CC:-gcc} $EXTRA_CFLAGS $arch_flag -std=c99 -I$PREFIX/include/lz4/ -O3 -DNDEBUG -fPIC -c \
            "src/bitshuffle_core.c" \
            "src/bitshuffle.c" \
            "src/iochain.c"
        # Merge the object files together to produce a combined .o file.
        ld -r -o $tmp_obj bitshuffle_core.o bitshuffle.o iochain.o
        # For the AVX2 symbols, suffix them.
        if [[ "$arch" == "avx2" || "$arch" == "avx512" || "$arch" == "neon" ]]; then
            # Create a mapping file with '<old_sym> <suffixed_sym>' on each line.
            nm --defined-only --extern-only $tmp_obj | while read addr type sym ; do
              echo ${sym} ${sym}_${arch}
            done > renames.txt
            objcopy --redefine-syms=renames.txt $tmp_obj $dst_obj
        else
            mv $tmp_obj $dst_obj
        fi
        to_link="$to_link $dst_obj"
    done
    rm -f libbitshuffle.a
    ar rs libbitshuffle.a $to_link
    mkdir -p $PREFIX/include/bitshuffle
    cp libbitshuffle.a $PREFIX/lib/
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle.h $PREFIX/include/bitshuffle/bitshuffle.h
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle_core.h $PREFIX/include/bitshuffle/bitshuffle_core.h
}

# croaring bitmap
# If open AVX512 default, current version will be compiled failed on some machine, so close AVX512 default,
# When this problem is solved, a switch will be added to control.
build_croaringbitmap() {
    FORCE_AVX=ON
    # avx2 is not supported by aarch64.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        FORCE_AVX=FALSE
    fi
    if [[ `cat /proc/cpuinfo |grep avx|wc -l` == "0" ]]; then
        FORCE_AVX=FALSE
    fi
    check_if_source_exist $CROARINGBITMAP_SOURCE
    cd $TP_SOURCE_DIR/$CROARINGBITMAP_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DROARING_BUILD_STATIC=ON -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DENABLE_ROARING_TESTS=OFF \
    -DROARING_DISABLE_NATIVE=ON \
    -DFORCE_AVX=$FORCE_AVX \
    -DROARING_DISABLE_AVX512=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}
#orc
build_orc() {
    check_if_source_exist $ORC_SOURCE
    cd $TP_SOURCE_DIR/$ORC_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD ../ -DBUILD_JAVA=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DPROTOBUF_HOME=$TP_INSTALL_DIR \
    -DSNAPPY_HOME=$TP_INSTALL_DIR \
    -DGTEST_HOME=$TP_INSTALL_DIR \
    -DLZ4_HOME=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DZLIB_HOME=$TP_INSTALL_DIR\
    -DBUILD_LIBHDFSPP=OFF \
    -DBUILD_CPP_TESTS=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#cctz
build_cctz() {
    check_if_source_exist $CCTZ_SOURCE
    cd $TP_SOURCE_DIR/$CCTZ_SOURCE

    make -j$PARALLEL
    PREFIX=${TP_INSTALL_DIR} make install
}

#fmt
build_fmt() {
    check_if_source_exist $FMT_SOURCE
    cd $TP_SOURCE_DIR/$FMT_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} ../ \
            -DCMAKE_INSTALL_LIBDIR=lib64 -G "${CMAKE_GENERATOR}" -DFMT_TEST=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#ryu
build_ryu() {
    check_if_source_exist $RYU_SOURCE
    cd $TP_SOURCE_DIR/$RYU_SOURCE/ryu
    make -j$PARALLEL
    make install DESTDIR=${TP_INSTALL_DIR}
    mkdir -p $TP_INSTALL_DIR/include/ryu
    mv $TP_INSTALL_DIR/include/ryu.h $TP_INSTALL_DIR/include/ryu
    # copy to 64 to compatable with current CMake
    cp -f ${TP_INSTALL_DIR}/lib/libryu.a ${TP_INSTALL_DIR}/lib64/libryu.a
}

#break_pad
build_breakpad() {
    check_if_source_exist $BREAK_PAD_SOURCE
    cd $TP_SOURCE_DIR/$BREAK_PAD_SOURCE
    mkdir -p src/third_party/lss
    cp $TP_PATCH_DIR/linux_syscall_support.h src/third_party/lss
    CFLAGS= ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

#hadoop
build_hadoop() {
    check_if_source_exist $HADOOP_SOURCE
    cp -r $TP_SOURCE_DIR/$HADOOP_SOURCE $TP_INSTALL_DIR/hadoop
    # remove unnecessary doc and logs
    rm -rf $TP_INSTALL_DIR/hadoop/logs/* $TP_INSTALL_DIR/hadoop/share/doc/hadoop
    mkdir -p $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/include/hdfs.h $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/lib/native/libhdfs.a $TP_INSTALL_DIR/lib
}

#jdk
build_jdk() {
    check_if_source_exist $JDK_SOURCE
    rm -rf $TP_INSTALL_DIR/open_jdk && cp -r $TP_SOURCE_DIR/$JDK_SOURCE $TP_INSTALL_DIR/open_jdk
}

# ragel
# ragel-6.9+ is used by hypercan, so we build it first.
build_ragel() {
    check_if_source_exist $RAGEL_SOURCE
    cd $TP_SOURCE_DIR/$RAGEL_SOURCE
    # generage a static linked ragel, hyperscan will depend on it
    LDFLAGS=" -static-libstdc++ -static-libgcc" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

#hyperscan
build_hyperscan() {
    check_if_source_exist $HYPERSCAN_SOURCE
    cd $TP_SOURCE_DIR/$HYPERSCAN_SOURCE
    export PATH=$TP_INSTALL_DIR/bin:$PATH
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DBOOST_ROOT=$STARROCKS_THIRDPARTY/installed/include \
          -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc  -DCMAKE_INSTALL_LIBDIR=lib \
          -DBUILD_EXAMPLES=OFF -DBUILD_UNIT=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#mariadb-connector-c
build_mariadb() {
    OLD_CMAKE_GENERATOR=${CMAKE_GENERATOR}
    OLD_BUILD_SYSTEM=${BUILD_SYSTEM}

    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC ${FILE_PREFIX_MAP_OPTION}"

    # force use make build system, since ninja doesn't support install only headers
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'

    check_if_source_exist $MARIADB_SOURCE
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE
    mkdir -p build && cd build

    $CMAKE_CMD .. -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release    \
                  -DWITH_UNIT_TESTS=OFF                                 \
                  -DBUILD_SHARED_LIBS=OFF                               \
                  -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                  \
                  -DOPENSSL_USE_STATIC_LIBS=TRUE                        \
                  -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}
    # we only need build libmariadbclient and headers
    ${BUILD_SYSTEM} -j$PARALLEL mariadbclient
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/libmariadb
    mkdir -p $TP_INSTALL_DIR/lib/mariadb/
    cp libmariadbclient.a $TP_INSTALL_DIR/lib/mariadb/
    # install mariadb headers
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/include
    ${BUILD_SYSTEM} install

    restore_compile_flags
    export CMAKE_GENERATOR=$OLD_CMAKE_GENERATOR
    export BUILD_SYSTEM=$OLD_BUILD_SYSTEM
}

# jindosdk for Aliyun OSS
build_aliyun_jindosdk() {
    check_if_source_exist $JINDOSDK_SOURCE
    mkdir -p $TP_INSTALL_DIR/jindosdk
    cp -r $TP_SOURCE_DIR/$JINDOSDK_SOURCE/lib/*.jar $TP_INSTALL_DIR/jindosdk
}

build_gcs_connector() {
    check_if_source_exist $GCS_CONNECTOR_SOURCE
    mkdir -p $TP_INSTALL_DIR/gcs_connector
    cp -r $TP_SOURCE_DIR/$GCS_CONNECTOR_SOURCE/*.jar $TP_INSTALL_DIR/gcs_connector
}

build_broker_thirdparty_jars() {
    check_if_source_exist $BROKER_THIRDPARTY_JARS_SOURCE
    mkdir -p $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    cp -r $TP_SOURCE_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/* $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/hadoop-aliyun-2.7.2.jar
    # cloudfs-hadoop-with-dependencies will include aws jars, but we already support aws by official sdk, so we don't need it anymore.
    # And it will conflict with Iceberg's S3FileIO, make access S3 files failed.
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/cloudfs-hadoop-with-dependencies-1.1.21.jar
    # ensure read permission is granted for all users
    chmod -R +r $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/
}

build_aws_cpp_sdk() {
    check_if_source_exist $AWS_SDK_CPP_SOURCE
    cd $TP_SOURCE_DIR/$AWS_SDK_CPP_SOURCE
    # only build s3, s3-crt, transfer manager, identity-management and sts, you can add more components if you want.
    $CMAKE_CMD -Bbuild -DBUILD_ONLY="core;s3;s3-crt;transfer;identity-management;sts" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
               -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DENABLE_TESTING=OFF \
               -DENABLE_CURL_LOGGING=OFF \
               -G "${CMAKE_GENERATOR}" \
               -DCURL_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libcurl.a   \
               -DZLIB_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libz.a      \
               -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                     \
               -DOPENSSL_USE_STATIC_LIBS=TRUE                           \
               -Dcrypto_LIBRARY=${TP_INSTALL_DIR}/lib/libcrypto.a

    cd build
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    restore_compile_flags
}

# velocypack
build_vpack() {
    check_if_source_exist $VPACK_SOURCE
    cd $TP_SOURCE_DIR/$VPACK_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# opentelemetry
build_opentelemetry() {
    check_if_source_exist $OPENTELEMETRY_SOURCE

    cd $TP_SOURCE_DIR/$OPENTELEMETRY_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DBUILD_TESTING=OFF -DWITH_EXAMPLES=OFF \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        -DWITH_STL=OFF -DWITH_JAEGER=ON
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# jemalloc
build_jemalloc() {
    check_if_source_exist $JEMALLOC_SOURCE

    cd $TP_SOURCE_DIR/$JEMALLOC_SOURCE
    # jemalloc supports a runtime page size that's smaller or equal to the build
    # time one, but aborts on a larger one. If not defined, it falls back to the
    # the build system's _SC_PAGESIZE, which in many architectures can vary. Set
    # this to 64K (2^16) for arm architecture, and default 4K on x86 for performance.
    local addition_opts=" --with-lg-page=12"
    if [[ $MACHINE_TYPE == "aarch64" ]] ; then
        # change to 64K for arm architecture
        addition_opts=" --with-lg-page=16"
    fi
    # build jemalloc with release
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc --with-jemalloc-prefix=je --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
    # build jemalloc with debug options
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc-debug --with-jemalloc-prefix=je --enable-prof --enable-debug --enable-fill --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
}

# google benchmark
build_benchmark() {
    check_if_source_exist $BENCHMARK_SOURCE
    cd $TP_SOURCE_DIR/$BENCHMARK_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    cmake -DBENCHMARK_DOWNLOAD_DEPENDENCIES=off \
          -DBENCHMARK_ENABLE_GTEST_TESTS=off \
          -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
          -DCMAKE_INSTALL_LIBDIR=lib64 \
          -DCMAKE_BUILD_TYPE=Release ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# fast float
build_fast_float() {
    check_if_source_exist $FAST_FLOAT_SOURCE
    cd $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE
    cp -r $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE/include $TP_INSTALL_DIR
}

build_starcache() {
    check_if_source_exist $STARCACHE_SOURCE
    rm -rf $TP_INSTALL_DIR/$STARCACHE_SOURCE && mv $TP_SOURCE_DIR/$STARCACHE_SOURCE $TP_INSTALL_DIR/
}

# streamvbyte
build_streamvbyte() {
    check_if_source_exist $STREAMVBYTE_SOURCE

    cd $TP_SOURCE_DIR/$STREAMVBYTE_SOURCE/

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/

    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    $CMAKE_CMD .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=$TP_INSTALL_DIR/

    make -j$PARALLEL
    make install
}

# jansson
build_jansson() {
    check_if_source_exist $JANSSON_SOURCE
    cd $TP_SOURCE_DIR/$JANSSON_SOURCE/
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# avro-c
build_avro_c() {
    check_if_source_exist $AVRO_SOURCE
    cd $TP_SOURCE_DIR/$AVRO_SOURCE/lang/c
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    rm ${TP_INSTALL_DIR}/lib64/libavro.so*
}

# serders
build_serdes() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g"
    check_if_source_exist $SERDES_SOURCE
    cd $TP_SOURCE_DIR/$SERDES_SOURCE
    export LIBS="-lrt -lpthread -lcurl -ljansson -lrdkafka -lrdkafka++ -lavro -lssl -lcrypto -ldl"
    ./configure --prefix=${TP_INSTALL_DIR} \
                --libdir=${TP_INSTALL_DIR}/lib \
                --CFLAGS="-I ${TP_INSTALL_DIR}/include"  \
                --CXXFLAGS="-I ${TP_INSTALL_DIR}/include" \
                --LDFLAGS="-L ${TP_INSTALL_DIR}/lib -L ${TP_INSTALL_DIR}/lib64" \
                --enable-static \
                --disable-shared

    make -j$PARALLEL
    make install
    rm ${TP_INSTALL_DIR}/lib/libserdes.so*
    # these symbols also be definition in librdkafka, change these symbols to be local.
    objcopy --localize-symbol=cnd_timedwait ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=cnd_timedwait_ms ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=thrd_is_current ${TP_INSTALL_DIR}/lib/libserdes.a
    unset LIBS
    restore_compile_flags
}

# datasketches
build_datasketches() {
    check_if_source_exist $DATASKETCHES_SOURCE
    mkdir -p $TP_INSTALL_DIR/include/datasketches
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/common/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/cpc/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/fi/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/hll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/kll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/quantiles/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/req/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/sampling/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/theta/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/tuple/include/* $TP_INSTALL_DIR/include/datasketches/
}

# async-profiler
build_async_profiler() {
    check_if_source_exist $ASYNC_PROFILER_SOURCE
    mkdir -p $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/build $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/profiler.sh $TP_INSTALL_DIR/async-profiler
}

# fiu
build_fiu() {
    check_if_source_exist $FIU_SOURCE
    cd $TP_SOURCE_DIR/$FIU_SOURCE
    mkdir -p $TP_SOURCE_DIR/$FIU_SOURCE/installed
    make -j$PARALLEL
    make PREFIX=$TP_SOURCE_DIR/$FIU_SOURCE/installed install

    mkdir -p $TP_INSTALL_DIR/include/fiu
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/include/* $TP_INSTALL_DIR/include/fiu/
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/lib/libfiu.a $TP_INSTALL_DIR/lib/
}

# libdeflate
build_libdeflate() {
    check_if_source_exist $LIBDEFLATE_SOURCE
    mkdir -p $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    cd $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    $CMAKE_CMD .. -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# restore cxxflags/cppflags/cflags to default one
restore_compile_flags() {
    # c preprocessor flags
    export CPPFLAGS=$GLOBAL_CPPFLAGS
    # c flags
    export CFLAGS=$GLOBAL_CFLAGS
    # c++ flags
    export CXXFLAGS=$GLOBAL_CXXFLAGS
}

strip_binary() {
    # strip binary tools and ignore any errors
    echo "Strip binaries in $TP_INSTALL_DIR/bin/ ..."
    strip $TP_INSTALL_DIR/bin/* 2>/dev/null || true
}


# strip `$TP_SOURCE_DIR` and `$TP_INSTALL_DIR` from source code file path
export FILE_PREFIX_MAP_OPTION="-ffile-prefix-map=${TP_SOURCE_DIR}=. -ffile-prefix-map=${TP_INSTALL_DIR}=."
# set GLOBAL_C*FLAGS for easy restore in each sub build process
export GLOBAL_CPPFLAGS="-I ${TP_INCLUDE_DIR}"
# https://stackoverflow.com/questions/42597685/storage-size-of-timespec-isnt-known
export GLOBAL_CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -fPIC -g -D_POSIX_C_SOURCE=200112L -gz=zlib ${FILE_PREFIX_MAP_OPTION}"
export GLOBAL_CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess -fPIC -g -gz=zlib ${FILE_PREFIX_MAP_OPTION}"

# set those GLOBAL_*FLAGS to the CFLAGS/CXXFLAGS/CPPFLAGS
export CPPFLAGS=$GLOBAL_CPPFLAGS
export CXXFLAGS=$GLOBAL_CXXFLAGS
export CFLAGS=$GLOBAL_CFLAGS

build_libevent
build_zlib
build_lz4
build_lzo2
build_bzip
build_openssl
build_boost # must before thrift
build_protobuf
build_gflags
build_gtest
build_glog
build_rapidjson
build_simdjson
build_snappy
build_gperftools
build_curl
build_re2
build_thrift
build_leveldb
build_brpc
build_rocksdb
build_kerberos
build_sasl
build_flatbuffers
build_jemalloc
build_brotli
# must build before arrow
build_arrow
# NOTE: librdkafka depends on ZSTD which is generated by Arrow, So this SHOULD be
# built after arrow
build_librdkafka
build_pulsar
build_s2
build_bitshuffle
build_croaringbitmap
build_cctz
build_fmt
build_ryu
build_hadoop
build_jdk
build_ragel
build_hyperscan
build_mariadb
build_aliyun_jindosdk
build_gcs_connector
build_broker_thirdparty_jars
build_aws_cpp_sdk
build_vpack
build_opentelemetry
build_benchmark
build_fast_float
build_starcache
build_streamvbyte
build_jansson
build_avro_c
build_serdes
build_datasketches
build_async_profiler
build_fiu
build_llvm

if [[ "${MACHINE_TYPE}" != "aarch64" ]]; then
    build_breakpad
    build_libdeflate
fi

# strip unnecessary debug symbol for binaries in thirdparty
strip_binary

echo "Finished to build all thirdparties"

```

好，两处都改好了。总结一下：

## 这次的错误

```
./db/compaction/compaction_iteration_stats.h:23:3: error: 'uint64_t' does not name a type
note: 'uint64_t' is defined in header '<cstdint>'; did you forget to '#include <cstdint>'?
```

## 原因

还是 **GCC 13 更严格** 的问题。在旧版 GCC 中，`uint64_t` 等类型会通过其他标准库头文件被间接引入，所以即使源文件没有显式 `#include <cstdint>` 也能编译通过。但 GCC 13 不再保证这种隐式传递，必须显式包含。

RocksDB 6.22.1 有**很多头文件**都存在这个问题（我扫描发现至少 30+ 个），逐个修改不现实。

## 解决方案（两步）

1. **直接修复了出错的源文件** — 在 `compaction_iteration_stats.h` 中添加了 `#include <cstdint>`

2. **在构建脚本中全局注入** — 在 `EXTRA_CXXFLAGS` 中加了 **`-include cstdint`**，效果等同于在每个 `.cc` 文件开头自动插入 `#include <cstdint>`，一劳永逸地解决所有同类问题

修改后重新编译：

```bash
BUILD_TYPE=Debug ./build.sh --be
```

> `-include cstdint` 是 GCC/Clang 的标准选项，意思是"编译每个翻译单元时，先隐式 include 指定的头文件"。这是处理老代码 + 新编译器兼容性问题的常用手段。

```plaintext
./db/compaction/compaction_iteration_stats.h:23:3: error: 'uint64_t' does not name a type
note: 'uint64_t' is defined in header '<cstdint>'; did you forget to '#include <cstdint>'?
```

```shellscript
BUILD_TYPE=Debug ./build.sh --be
```

---

**User**

行，我想提早问一下，万一后面还有错，这个分支有没有推荐的gcc版本呢，我可以改gcc版本的

---

**Cursor**

好问题！让我先确认一下你当前的 StarRocks 分支版本。

现在信息足够了。我来给你一个完整的回答。

## StarRocks 3.2.16 分支推荐的 GCC 版本

从源码中可以确认几个关键信息：

**1. 官方编译镜像用的是 GCC 10.3**

```33:33:docker/dockerfiles/dev-env/dev-env.Dockerfile
FROM starrocks/toolchains-${distro}:main-20230823 as base
```

StarRocks 官方的 `starrocks/toolchains-ubuntu:main-20230823` 镜像内置的是 **GCC 10.3.0**，这就是 CI 用来编译和测试的版本。

**2. CMakeLists.txt 也印证了这一点**

```107:112:be/CMakeLists.txt
    if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER "10.3.0")
        message(STATUS "GCC version ${CMAKE_CXX_COMPILER_VERSION} is greater than 10.3.0, disable -Werror. Be careful with compile warnings.")
    else()
        #   -Werror: compile warnings should be errors when using the toolchain compiler.
        set(CXX_GCC_FLAGS "${CXX_GCC_FLAGS} -Werror")
    endif()
```

代码里以 **10.3.0 为分界线**：≤10.3 开启 `-Werror`（说明这是经过严格测试的版本），>10.3 则主动关掉 `-Werror`（说明官方知道更高版本会有新警告问题）。

## 建议

| 选择 | 版本 | 说明 |
|------|------|------|
| **最稳妥** | **GCC 10.3** | 官方 CI/CD 使用的版本，零兼容性问题 |
| **可接受** | **GCC 11.x** | 基本兼容，偶尔有小警告 |
| **不推荐** | **GCC 13.x**（你当前的） | 对老代码太严格，thirdparty 编译会不断踩坑 |

## 如果你决定换 GCC 版本

Ubuntu 24.04 上安装 GCC 10 最简单的方式：

```bash
# 安装 GCC 10
sudo apt-get install -y gcc-10 g++-10

# 设置为默认
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 100
sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-10 100

# 验证
gcc --version  # 应显示 10.x
```

> ⚠️ Ubuntu 24.04 的 apt 仓库中 GCC 10 可能不可用（默认只有 13/14）。如果 `apt install gcc-10` 失败，可以试 **GCC 11**（`sudo apt install gcc-11 g++-11`），GCC 11 对 thirdparty 的兼容性也比 13 好很多，基本不会遇到你现在碰到的这些问题。

换好 GCC 版本后，记得**清理已编译的 thirdparty 再重新编译**：

```bash
cd /home/peter/my-project/starrocks/thirdparty
rm -rf installed/ src/  # 清理，重新解压和编译
cd ..
BUILD_TYPE=Debug ./build.sh --be
```

如果你不想折腾换 GCC，继续用 13.3 + 我们之前加的那些编译选项修复也完全可以，后面如果还报错我们继续修就行。

```dockerfile
FROM starrocks/toolchains-${distro}:main-20230823 as base
```

```plaintext
    if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER "10.3.0")
        message(STATUS "GCC version ${CMAKE_CXX_COMPILER_VERSION} is greater than 10.3.0, disable -Werror. Be careful with compile warnings.")
    else()
        #   -Werror: compile warnings should be errors when using the toolchain compiler.
        set(CXX_GCC_FLAGS "${CXX_GCC_FLAGS} -Werror")
    endif()
```

```shellscript
# 安装 GCC 10
sudo apt-get install -y gcc-10 g++-10

# 设置为默认
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 100
sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-10 100

# 验证
gcc --version  # 应显示 10.x
```

```shellscript
cd /home/peter/my-project/starrocks/thirdparty
rm -rf installed/ src/  # 清理，重新解压和编译
cd ..
BUILD_TYPE=Debug ./build.sh --be
```

---

**User**

好的，我正在重新编译中。既然如此，请麻烦把 /home/peter/my-project/starrocks/docs/zh/learning/在wsl2上进行starrocks编译启动源码debug总结.md 中的 ## 一、安装编译依赖 章节做一下补充，强调要gcc 10.3版本

---

**Cursor**

让我先看一下当前文档的内容：

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

### 1.1 基础工具

```bash
sudo apt-get update

# 基础工具（不含 GCC、JDK，二者单独安装以控制版本）
sudo apt-get install -y automake binutils-dev bison byacc ccache flex libiberty-dev libtool \
    maven zip python3 python-is-python3 cmake git patch lld bzip2 \
    wget unzip curl make build-essential ninja-build software-properties-common
```

### 1.2 安装 GCC 10（关键）

> **StarRocks 3.2.x 官方 CI 使用 GCC 10.3**（见 `docker/dockerfiles/dev-env/dev-env.Dockerfile` 中的 `starrocks/toolchains-ubuntu:main-20230823` 镜像），`be/CMakeLists.txt` 也以 10.3 为分界线控制 `-Werror`。
>
> **不建议使用 GCC 13+**：RocksDB 6.22.1 等老版本第三方库在 GCC 13 下会因 `-Wredundant-move`、缺少 `#include <cstdint>` 等问题编译失败，需要大量手动修补。GCC 10 可以避免这些问题。

```bash
# Ubuntu 24.04 默认源没有 gcc-10，需要添加 Ubuntu 22.04 (jammy) 的源
sudo add-apt-repository -y 'deb http://archive.ubuntu.com/ubuntu jammy main universe'
sudo add-apt-repository -y 'deb http://archive.ubuntu.com/ubuntu jammy-updates main universe'
sudo apt-get update

# 安装 GCC 10
sudo apt-get install -y gcc-10 g++-10

# 设置为系统默认（优先级 100 高于其他版本）
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 100
sudo update-alternatives --install /usr/bin/cc cc /usr/bin/gcc-10 100
sudo update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++-10 100
```

### 1.3 安装 JDK 17

```bash
# 安装 JDK 17（StarRocks 3.2.x 推荐，不建议用 default-jdk 装到 21，可能有兼容问题）
sudo apt-get install -y openjdk-17-jdk

# 若系统中有多个 JDK 版本，切换到 17
sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac

# 设置 JAVA_HOME（加入 ~/.bashrc 或 ~/.zshrc 以持久化）
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

### 1.4 验证关键版本

```bash
gcc --version    # 需 10.x（推荐 10.3+，不建议 13+）
java --version   # 需 >= 8，推荐 17（当前 17.x ✓）
cmake --version  # 需 >= 3.20.1
mvn --version
```

---

## 二、编译

```bash
cd /home/peter/my-project/starrocks

# 由于编译过程很长，推荐分开编译，分别处理中途问题
# fe、be编译顺序不存在依赖关系，可以先编译fe，再编译be，反之也行

# 编译fe
./build.sh --fe

# 编译be（Debug 模式，首次会自动编译 thirdparty，耗时较长）
BUILD_TYPE=Debug ./build.sh --be
```

> 编译中途遇到的问题，建议使用AI分析解决，效率很高。

> 可用 `-j N` 指定并行度，如 `BUILD_TYPE=Debug ./build.sh --fe --be -j 8`。

`BUILD_TYPE=Debug` 的作用：BE 以 `-O0 -ggdb` 编译（不优化、带完整调试符号），且不会 strip 二进制。这样用 GDB/CLion Attach 时变量可查看、断点精准、单步与源码一致。不加此参数默认为 Release（`-O3` 优化 + strip 符号），调试时变量大量显示 `<optimized out>`，断点乱跳，基本不可用。

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
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` 的 `_read_chunk_from_storage` (797行) | 每次从存储读 chunk 都会经过 |
| `be/src/exec/pipeline/scan/olap_chunk_source.cpp` 的 `_prj_iter->get_next(chunk)` (803行) | 实际读取数据 |

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

已更新完成！主要改动：

1. **拆分为 4 个子章节**（1.1 基础工具、1.2 安装 GCC 10、1.3 安装 JDK 17、1.4 验证），结构更清晰

2. **强调 GCC 10 是关键**，并说明了原因：
   - 官方 CI 镜像 `starrocks/toolchains-ubuntu:main-20230823` 用的就是 GCC 10.3
   - `be/CMakeLists.txt` 以 10.3 为分界线
   - 不建议 GCC 13+，会导致 thirdparty 编译大量报错

3. **提供了 Ubuntu 24.04 上安装 GCC 10 的具体步骤**（因为 24.04 默认源没有 gcc-10，需要添加 jammy 源）

4. **验证部分也更新了**，明确写了 "推荐 10.3+，不建议 13+"

---

**User**

好，我已经在用10.5.0重新编译了

gcc --version
gcc (Ubuntu 10.5.0-4ubuntu2.1) 10.5.0

遇到了下面的错误，请问怎么解决？
@zsh (908-1010)

是要必须gcc回到10.3吗 

---

**Cursor**

这个错误跟 GCC 版本无关，是**网络问题**。让我仔细看一下：

```
error: downloading 'https://github.com/xtensor-stack/xsimd/archive/e9234cd6e6f4428fc260073b2c34ffe86fda1f34.tar.gz' failed
      status_code: 35
      status_string: "SSL connect error"
      
Uses proxy env variable https_proxy == 'https://proxy.zhenguanyu.com:8118'
OpenSSL/3.0.13: error:0A00010B:SSL routines::wrong version number
```

**GCC 10.5 完全没问题**，不需要回退到 10.3。

## 原因

编译 Arrow 时，它会在线下载依赖 `xsimd`。下载过程中走了你的代理 `https://proxy.zhenguanyu.com:8118`，但报了 **SSL wrong version number** 错误。

关键在这一行：

```
Uses proxy env variable https_proxy == 'https://proxy.zhenguanyu.com:8118'
```

你的 `https_proxy` 环境变量设置的是 `https://proxy...`，但你的代理服务器很可能是个 **HTTP 代理**（不是 HTTPS 代理）。curl 用 TLS 去连一个 HTTP 代理端口，所以握手失败报 `wrong version number`。

## 解决方案

把 `https_proxy` 的协议从 `https://` 改成 `http://`：

```bash
export https_proxy=http://proxy.zhenguanyu.com:8118
export http_proxy=http://proxy.zhenguanyu.com:8118
```

然后重新执行编译即可。

或者如果你不需要代理（比如能直接访问 GitHub），可以直接取消代理：

```bash
unset http_proxy https_proxy
```

> **小知识**：`https_proxy` 这个环境变量的值是指**代理服务器本身的协议**，不是指要代理的目标请求的协议。大多数代理服务器（如 Squid、Privoxy、Clash 等）本身监听的是 HTTP 协议，所以即使要代理 HTTPS 请求，`https_proxy` 的值也应该用 `http://`。

```plaintext
error: downloading 'https://github.com/xtensor-stack/xsimd/archive/e9234cd6e6f4428fc260073b2c34ffe86fda1f34.tar.gz' failed
      status_code: 35
      status_string: "SSL connect error"
      
Uses proxy env variable https_proxy == 'https://proxy.zhenguanyu.com:8118'
OpenSSL/3.0.13: error:0A00010B:SSL routines::wrong version number
```

```plaintext
Uses proxy env variable https_proxy == 'https://proxy.zhenguanyu.com:8118'
```

```shellscript
export https_proxy=http://proxy.zhenguanyu.com:8118
export http_proxy=http://proxy.zhenguanyu.com:8118
```

```shellscript
unset http_proxy https_proxy
```

---

**User**

好的，我已经将https_proxy中的https://...改为了http://...

重新编译后，遇到了新问题，如下
@zsh (847-1021) 

---

**Cursor**

这次的错误是编译 **pulsar-client-cpp-3.3.0** 时找不到 OpenSSL：

```
Could NOT find OpenSSL, try to set the path to OpenSSL root folder in the
system variable OPENSSL_ROOT_DIR (missing: OPENSSL_CRYPTO_LIBRARY OPENSSL_INCLUDE_DIR)
```

OpenSSL 其实已经被 thirdparty 编译安装好了（前面编译 librdkafka 时就成功找到了：`Found OpenSSL: .../thirdparty/installed/lib/libcrypto.a`），只是 pulsar-client-cpp 的 CMake 没找到路径。让我看一下构建脚本是怎么配置的：

```plaintext
Could NOT find OpenSSL, try to set the path to OpenSSL root folder in the
system variable OPENSSL_ROOT_DIR (missing: OPENSSL_CRYPTO_LIBRARY OPENSSL_INCLUDE_DIR)
```

问题找到了。`build_pulsar()` 的 CMake 调用中没有设置 `OPENSSL_ROOT_DIR`，而 OpenSSL 安装在 thirdparty 自己的目录中，系统路径下找不到。让我看一下 OpenSSL 安装的位置确认一下：

确认了，OpenSSL 就在 `thirdparty/installed/` 下，只需要告诉 pulsar 的 CMake 去那里找。

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

#################################################################################
# This script will
# 1. Check prerequisite libraries. Including:
#    cmake byacc flex automake libtool binutils-dev libiberty-dev bison
# 2. Compile and install all thirdparties which are downloaded
#    using *download-thirdparty.sh*.
#
# This script will run *download-thirdparty.sh* once again
# to check if all thirdparties have been downloaded, unpacked and patched.
#################################################################################
set -e

curdir=`dirname "$0"`
curdir=`cd "$curdir"; pwd`

export STARROCKS_HOME=${STARROCKS_HOME:-$curdir/..}
export TP_DIR=$curdir

# include custom environment variables
if [[ -f ${STARROCKS_HOME}/env.sh ]]; then
    . ${STARROCKS_HOME}/env.sh
fi

if [[ ! -f ${TP_DIR}/download-thirdparty.sh ]]; then
    echo "Download thirdparty script is missing".
    exit 1
fi

if [ ! -f ${TP_DIR}/vars.sh ]; then
    echo "vars.sh is missing".
    exit 1
fi
. ${TP_DIR}/vars.sh

cd $TP_DIR

# Download thirdparties.
${TP_DIR}/download-thirdparty.sh

# set COMPILER
if [[ ! -z ${STARROCKS_GCC_HOME} ]]; then
    export CC=${STARROCKS_GCC_HOME}/bin/gcc
    export CPP=${STARROCKS_GCC_HOME}/bin/cpp
    export CXX=${STARROCKS_GCC_HOME}/bin/g++
    export PATH=${STARROCKS_GCC_HOME}/bin:$PATH
else
    echo "STARROCKS_GCC_HOME environment variable is not set"
    exit 1
fi

# prepare installed prefix
mkdir -p ${TP_DIR}/installed

check_prerequest() {
    local CMD=$1
    local NAME=$2
    if ! $CMD; then
        echo $NAME is missing
        exit 1
    else
        echo $NAME is found
    fi
}

# sudo apt-get install cmake
# sudo yum install cmake
check_prerequest "${CMAKE_CMD} --version" "cmake"

# sudo apt-get install byacc
# sudo yum install byacc
check_prerequest "byacc -V" "byacc"

# sudo apt-get install flex
# sudo yum install flex
check_prerequest "flex -V" "flex"

# sudo apt-get install automake
# sudo yum install automake
check_prerequest "automake --version" "automake"

# sudo apt-get install libtool
# sudo yum install libtool
check_prerequest "libtoolize --version" "libtool"

BUILD_SYSTEM=${BUILD_SYSTEM:-make}

# sudo apt-get install binutils-dev
# sudo yum install binutils-devel
#check_prerequest "locate libbfd.a" "binutils-dev"

# sudo apt-get install libiberty-dev
# no need in centos 7.1
#check_prerequest "locate libiberty.a" "libiberty-dev"

# sudo apt-get install bison
# sudo yum install bison
#check_prerequest "bison --version" "bison"

#########################
# build all thirdparties
#########################


# Name of cmake build directory in each thirdpary project.
# Do not use `build`, because many projects contained a file named `BUILD`
# and if the filesystem is not case sensitive, `mkdir` will fail.
BUILD_DIR=starrocks_build
MACHINE_TYPE=$(uname -m)

# handle mac m1 platform, change arm64 to aarch64
if [[ "${MACHINE_TYPE}" == "arm64" ]]; then
    MACHINE_TYPE="aarch64"
fi

echo "machine type : $MACHINE_TYPE"

check_if_source_exist() {
    if [ -z $1 ]; then
        echo "dir should specified to check if exist."
        exit 1
    fi

    if [ ! -d $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
    echo "===== begin build $1"
}

check_if_archieve_exist() {
    if [ -z $1 ]; then
        echo "archieve should specified to check if exist."
        exit 1
    fi

    if [ ! -f $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
}

# libevent
build_libevent() {
    check_if_source_exist $LIBEVENT_SOURCE
    cd $TP_SOURCE_DIR/$LIBEVENT_SOURCE
    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

build_openssl() {
    OPENSSL_PLATFORM="linux-x86_64"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        OPENSSL_PLATFORM="linux-aarch64"
    fi

    check_if_source_exist $OPENSSL_SOURCE
    cd $TP_SOURCE_DIR/$OPENSSL_SOURCE

    # use customized CFLAGS/CPPFLAGS/CXXFLAGS/LDFLAGS
    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC"

    LDFLAGS="-L${TP_LIB_DIR}" \
    LIBDIR="lib" \
    ./Configure --prefix=$TP_INSTALL_DIR -lz -no-shared ${OPENSSL_PLATFORM}
    make -j$PARALLEL
    make install_sw

    restore_compile_flags
}

# thrift
build_thrift() {
    check_if_source_exist $THRIFT_SOURCE
    cd $TP_SOURCE_DIR/$THRIFT_SOURCE

    if [ ! -f configure ]; then
        ./bootstrap.sh
    fi

    echo ${TP_LIB_DIR}
    ./configure LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" LIBS="-lssl -lcrypto -ldl" \
    --prefix=$TP_INSTALL_DIR --docdir=$TP_INSTALL_DIR/doc --enable-static --disable-shared --disable-tests \
    --disable-tutorial --without-qt4 --without-qt5 --without-csharp --without-erlang --without-nodejs \
    --without-lua --without-perl --without-php --without-php_extension --without-dart --without-ruby \
    --without-haskell --without-go --without-haxe --without-d --without-python -without-java --with-cpp \
    --with-libevent=$TP_INSTALL_DIR --with-boost=$TP_INSTALL_DIR --with-openssl=$TP_INSTALL_DIR

    if [ -f compiler/cpp/thrifty.hh ];then
        mv compiler/cpp/thrifty.hh compiler/cpp/thrifty.h
    fi

    make -j$PARALLEL
    make install
}

# llvm
build_llvm() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -D_POSIX_C_SOURCE=200112L ${FILE_PREFIX_MAP_OPTION}"
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess ${FILE_PREFIX_MAP_OPTION}"

    LLVM_TARGET="X86"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        LLVM_TARGET="AArch64"
    fi

    LLVM_TARGETS_TO_BUILD=(
        "LLVMBitstreamReader"
        "LLVMRuntimeDyld" 
        "LLVMOption"
        "LLVMAsmPrinter"
        "LLVMProfileData"
        "LLVMAsmParser"
        "LLVMOrcTargetProcess"
        "LLVMExecutionEngine"
        "LLVMBinaryFormat"
        "LLVMDebugInfoDWARF"
        "LLVMObjCARCOpts"
        "LLVMCodeGen"
        "LLVMMCDisassembler"
        "LLVMSupport"
        "LLVMJITLink"
        "LLVMCFGuard"
        "LLVMInstrumentation"
        "LLVMIRReader"
        "LLVMCore"
        "LLVMTarget"
        "LLVMMC"
        "LLVMAnalysis"
        "LLVMGlobalISel"
        "LLVMScalarOpts"
        "LLVMTargetParser"
        "LLVMDemangle"
        "LLVMRemarks"
        "LLVMDebugInfoCodeView"
        "LLVMOrcShared"
        "LLVMOrcJIT"
        "LLVMTextAPI"
        "LLVMBitWriter"
        "LLVMBitReader"
        "LLVMObject"
        "LLVMTransformUtils"
        "LLVMSelectionDAG"
        "LLVMMCParser"
    )
    if [ "${LLVM_TARGET}" == "X86" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMX86Info" "LLVMX86Desc" "LLVMX86CodeGen")
    elif [ "${LLVM_TARGET}" == "AArch64" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMAArch64Info" "LLVMAArch64Desc" "LLVMAArch64CodeGen")
    fi

    LLVM_TARGETS_TO_INSTALL=()
    for target in ${LLVM_TARGETS_TO_BUILD[@]}; do
        LLVM_TARGETS_TO_INSTALL+=("install-${target}")
    done

    check_if_source_exist $LLVM_SOURCE

    cd $TP_SOURCE_DIR
    mkdir -p llvm-build
    cd llvm-build
    rm -rf CMakeCache.txt CMakeFiles/

    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -S ../${LLVM_SOURCE}/llvm -G "${CMAKE_GENERATOR}" \
    -DLLVM_ENABLE_EH:Bool=True \
    -DLLVM_ENABLE_RTTI:Bool=True \
    -DLLVM_ENABLE_PIC:Bool=True \
    -DLLVM_ENABLE_TERMINFO:Bool=False \
    -DLLVM_TARGETS_TO_BUILD=${LLVM_TARGET} \
    -DLLVM_BUILD_LLVM_DYLIB:BOOL=False \
    -DLLVM_INCLUDE_TOOLS:BOOL=False \
    -DLLVM_BUILD_TOOLS:BOOL=False \
    -DLLVM_INCLUDE_EXAMPLES:BOOL=False \
    -DLLVM_INCLUDE_TESTS:BOOL=False \
    -DLLVM_INCLUDE_BENCHMARKS:BOOL=False \
    -DBUILD_SHARED_LIBS:BOOL=False \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}/llvm ../${LLVM_SOURCE}

    # TODO(yueyang): Add more targets.
    # This is a little bit hack, we need to minimize the build time and binary size.
    ${BUILD_SYSTEM} -j$PARALLEL REQUIRES_RTTI=1 ${LLVM_TARGETS_TO_BUILD[@]}
    ${BUILD_SYSTEM} install-llvm-headers
    ${BUILD_SYSTEM} ${LLVM_TARGETS_TO_INSTALL[@]}

    restore_compile_flags
}

# protobuf
build_protobuf() {
    check_if_source_exist $PROTOBUF_SOURCE
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    rm -fr gmock
    mkdir gmock
    cd gmock
    tar xf ${TP_SOURCE_DIR}/$GTEST_NAME
    mv $GTEST_SOURCE gtest
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    ./autogen.sh
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc -pthread -Wl,--whole-archive -lpthread -Wl,--no-whole-archive" \
    ./configure --prefix=${TP_INSTALL_DIR} --disable-shared --enable-static --with-zlib --with-zlib-include=${TP_INSTALL_DIR}/include
    make -j$PARALLEL
    make install
}

# gflags
build_gflags() {
    check_if_source_exist $GFLAGS_SOURCE

    cd $TP_SOURCE_DIR/$GFLAGS_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# glog
build_glog() {
    check_if_source_exist $GLOG_SOURCE
    cd $TP_SOURCE_DIR/$GLOG_SOURCE

    # to generate config.guess and config.sub to support aarch64
    rm -rf config.*
    autoreconf -i

    LDFLAGS="-L${TP_LIB_DIR}" \
    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-frame-pointers --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

# gtest
build_gtest() {
    check_if_source_exist $GTEST_SOURCE

    cd $TP_SOURCE_DIR/$GTEST_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# rapidjson
build_rapidjson() {
    check_if_source_exist $RAPIDJSON_SOURCE

    rm -rf $TP_INSTALL_DIR/rapidjson
    cp -r $TP_SOURCE_DIR/$RAPIDJSON_SOURCE/include/rapidjson $TP_INCLUDE_DIR/
}

# simdjson
build_simdjson() {
    check_if_source_exist $SIMDJSON_SOURCE
    cd $TP_SOURCE_DIR/$SIMDJSON_SOURCE

    #ref: https://github.com/simdjson/simdjson/blob/master/HACKING.md
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_CXX_FLAGS="-O3" -DCMAKE_C_FLAGS="-O3" -DCMAKE_POSITION_INDEPENDENT_CODE=True -DSIMDJSON_AVX512_ALLOWED=OFF ..
    $CMAKE_CMD --build .
    mkdir -p $TP_INSTALL_DIR/lib

    cp $TP_SOURCE_DIR/$SIMDJSON_SOURCE/$BUILD_DIR/libsimdjson.a $TP_INSTALL_DIR/lib
    cp -r $TP_SOURCE_DIR/$SIMDJSON_SOURCE/include/* $TP_INCLUDE_DIR/
}

# snappy
build_snappy() {
    check_if_source_exist $SNAPPY_SOURCE
    cd $TP_SOURCE_DIR/$SNAPPY_SOURCE

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -G "${CMAKE_GENERATOR}" \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On \
    -DCMAKE_INSTALL_INCLUDEDIR=$TP_INCLUDE_DIR/snappy \
    -DSNAPPY_BUILD_TESTS=0 ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    if [ -f $TP_INSTALL_DIR/lib64/libsnappy.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib
        cp $TP_INSTALL_DIR/lib64/libsnappy.a $TP_INSTALL_DIR/lib/libsnappy.a
    fi

    #build for libarrow.a
    cp $TP_INCLUDE_DIR/snappy/snappy-c.h  $TP_INCLUDE_DIR/snappy-c.h
    cp $TP_INCLUDE_DIR/snappy/snappy-sinksource.h  $TP_INCLUDE_DIR/snappy-sinksource.h
    cp $TP_INCLUDE_DIR/snappy/snappy-stubs-public.h  $TP_INCLUDE_DIR/snappy-stubs-public.h
    cp $TP_INCLUDE_DIR/snappy/snappy.h  $TP_INCLUDE_DIR/snappy.h
    cp $TP_INSTALL_DIR/lib/libsnappy.a $TP_INSTALL_DIR/libsnappy.a
}

# gperftools
build_gperftools() {
    check_if_source_exist $GPERFTOOLS_SOURCE
    cd $TP_SOURCE_DIR/$GPERFTOOLS_SOURCE

    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=$TP_INSTALL_DIR/gperftools --disable-shared --enable-static --disable-libunwind --with-pic --enable-frame-pointers
    make -j$PARALLEL
    make install
}

# zlib
build_zlib() {
    check_if_source_exist $ZLIB_SOURCE
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --static
    make -j$PARALLEL
    make install

    # build minizip
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE/contrib/minizip
    autoreconf --force --install
    ./configure --prefix=$TP_INSTALL_DIR --enable-static=yes --enable-shared=no
    make -j$PARALLEL
    make install
}

# lz4
build_lz4() {
    check_if_source_exist $LZ4_SOURCE
    cd $TP_SOURCE_DIR/$LZ4_SOURCE

    make -C lib -j$PARALLEL install PREFIX=$TP_INSTALL_DIR \
    INCLUDEDIR=$TP_INCLUDE_DIR/lz4/ BUILD_SHARED=no
}

# lzo
build_lzo2() {
    check_if_source_exist $LZO2_SOURCE
    cd $TP_SOURCE_DIR/$LZO2_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
        LDFLAGS="-L${TP_LIB_DIR}" \
        ./configure --prefix="${TP_INSTALL_DIR}" --disable-shared --enable-static

    make -j "${PARALLEL}"
    make install
}

# bzip
build_bzip() {
    check_if_source_exist $BZIP_SOURCE
    cd $TP_SOURCE_DIR/$BZIP_SOURCE

    make -j$PARALLEL install PREFIX=$TP_INSTALL_DIR
}

# curl
build_curl() {
    check_if_source_exist $CURL_SOURCE
    cd $TP_SOURCE_DIR/$CURL_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" LIBS="-lssl -lcrypto -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static \
    --without-librtmp --with-ssl=${TP_INSTALL_DIR} --without-libidn2 --without-libgsasl --disable-ldap --enable-ipv6 --without-brotli
    make -j$PARALLEL
    make install
}

# re2
build_re2() {
    check_if_source_exist $RE2_SOURCE
    cd $TP_SOURCE_DIR/$RE2_SOURCE

    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release \
	    -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL install
}

# boost
build_boost() {
    check_if_source_exist $BOOST_SOURCE
    cd $TP_SOURCE_DIR/$BOOST_SOURCE

    # It is difficult to generate static linked b2, so we use LD_LIBRARY_PATH instead
    ./bootstrap.sh --prefix=$TP_INSTALL_DIR
    LD_LIBRARY_PATH=${STARROCKS_GCC_HOME}/lib:${STARROCKS_GCC_HOME}/lib64:${LD_LIBRARY_PATH} \
    ./b2 link=static runtime-link=static -j $PARALLEL --without-test --without-mpi --without-graph --without-graph_parallel --without-python cxxflags="-std=c++11 -g -fPIC -I$TP_INCLUDE_DIR -L$TP_LIB_DIR ${FILE_PREFIX_MAP_OPTION}" install
}

#leveldb
build_leveldb() {
    check_if_source_exist $LEVELDB_SOURCE
    cd $TP_SOURCE_DIR/$LEVELDB_SOURCE
    LDFLAGS="-L ${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    make -j$PARALLEL
    cp out-static/libleveldb.a $TP_LIB_DIR/libleveldb.a
    cp -r include/leveldb $TP_INCLUDE_DIR
}

# brpc
build_brpc() {
    check_if_source_exist $BRPC_SOURCE

    cd $TP_SOURCE_DIR/$BRPC_SOURCE
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    ./config_brpc.sh --headers="$TP_INSTALL_DIR/include" --libs="$TP_INSTALL_DIR/bin $TP_INSTALL_DIR/lib" --with-glog
    make -j$PARALLEL
    cp -rf output/* ${TP_INSTALL_DIR}/
    if [ -f $TP_INSTALL_DIR/lib/libbrpc.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib64
        cp $TP_SOURCE_DIR/$BRPC_SOURCE/output/lib/libbrpc.a $TP_INSTALL_DIR/lib64/
    fi
}

# rocksdb
build_rocksdb() {
    check_if_source_exist $ROCKSDB_SOURCE

    cd $TP_SOURCE_DIR/$ROCKSDB_SOURCE
    make clean

    CFLAGS= \
    EXTRA_CFLAGS="-I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy -I ${TP_INCLUDE_DIR}/lz4 -L${TP_LIB_DIR} ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_CXXFLAGS="-fPIC -Wno-deprecated-copy -Wno-stringop-truncation -Wno-pessimizing-move -I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_LDFLAGS="-static-libstdc++ -static-libgcc" \
    PORTABLE=1 make USE_RTTI=1 -j$PARALLEL static_lib

    cp librocksdb.a $TP_LIB_DIR/librocksdb.a
    cp -r include/rocksdb $TP_INCLUDE_DIR
}

# kerberos
build_kerberos() {
    check_if_source_exist $KRB5_SOURCE
    cd $TP_SOURCE_DIR/$KRB5_SOURCE/src
    CFLAGS="-fcommon -fPIC ${FILE_PREFIX_MAP_OPTION}" LDFLAGS="-L$TP_INSTALL_DIR/lib -pthread -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-static --disable-shared --with-spake-openssl=$TP_INSTALL_DIR
    make -j$PARALLEL
    make install
}

# sasl
build_sasl() {
    check_if_source_exist $SASL_SOURCE
    cd $TP_SOURCE_DIR/$SASL_SOURCE
    CFLAGS="-fPIC" LDFLAGS="-L$TP_INSTALL_DIR/lib -lresolv -pthread -ldl" ./autogen.sh --prefix=$TP_INSTALL_DIR --enable-gssapi=yes --enable-static --disable-shared --with-openssl=$TP_INSTALL_DIR --with-gss_impl=mit
    make -j$PARALLEL
    make install
}

# librdkafka
build_librdkafka() {
    check_if_source_exist $LIBRDKAFKA_SOURCE

    cd $TP_SOURCE_DIR/$LIBRDKAFKA_SOURCE

    mkdir -p sr_build && cd sr_build
    $CMAKE_CMD -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" \
        -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include;$TP_INSTALL_DIR/include/zstd;$TP_INSTALL_DIR/include/lz4" \
        -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DRDKAFKA_BUILD_STATIC=ON -DWITH_SASL=ON -DWITH_SASL_SCRAM=ON \
        -DRDKAFKA_BUILD_EXAMPLES=OFF -DRDKAFKA_BUILD_TESTS=OFF -DWITH_SSL=ON -DWITH_ZSTD=ON -DCMAKE_INSTALL_LIBDIR=lib ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# pulsar
build_pulsar() {
    check_if_source_exist $PULSAR_SOURCE

    cd $TP_SOURCE_DIR/$PULSAR_SOURCE

    $CMAKE_CMD -DCMAKE_LIBRARY_PATH=$TP_INSTALL_DIR/lib -DCMAKE_INCLUDE_PATH=$TP_INSTALL_DIR/include \
        -DOPENSSL_ROOT_DIR=$TP_INSTALL_DIR \
        -DPROTOC_PATH=$TP_INSTALL_DIR/bin/protoc -DBUILD_TESTS=OFF -DBUILD_PYTHON_WRAPPER=OFF -DBUILD_DYNAMIC_LIB=OFF .
    ${BUILD_SYSTEM} -j$PARALLEL

    cp lib/libpulsar.a $TP_INSTALL_DIR/lib/
    cp -r include/pulsar $TP_INSTALL_DIR/include/
}

# flatbuffers
build_flatbuffers() {
  check_if_source_exist $FLATBUFFERS_SOURCE
  cd $TP_SOURCE_DIR/$FLATBUFFERS_SOURCE
  mkdir -p $BUILD_DIR
  cd $BUILD_DIR
  rm -rf CMakeCache.txt CMakeFiles/
  LDFLAGS="-static-libstdc++ -static-libgcc" \
  ${CMAKE_CMD} .. -G "${CMAKE_GENERATOR}" -DFLATBUFFERS_BUILD_TESTS=OFF
  ${BUILD_SYSTEM} -j$PARALLEL
  cp flatc  $TP_INSTALL_DIR/bin/flatc
  cp -r ../include/flatbuffers  $TP_INCLUDE_DIR/flatbuffers
  cp libflatbuffers.a $TP_LIB_DIR/libflatbuffers.a
}

build_brotli() {
    check_if_source_exist $BROTLI_SOURCE
    cd $TP_SOURCE_DIR/$BROTLI_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    ${CMAKE_CMD} .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib64
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    mv -f $TP_INSTALL_DIR/lib64/libbrotlienc-static.a $TP_INSTALL_DIR/lib64/libbrotlienc.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlidec-static.a $TP_INSTALL_DIR/lib64/libbrotlidec.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlicommon-static.a $TP_INSTALL_DIR/lib64/libbrotlicommon.a
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so.*
}

# arrow
build_arrow() {
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CPPFLAGS=$CXXFLAGS

    check_if_source_exist $ARROW_SOURCE
    cd $TP_SOURCE_DIR/$ARROW_SOURCE/cpp
    mkdir -p release
    cd release
    export ARROW_BROTLI_URL=${TP_SOURCE_DIR}/${BROTLI_NAME}
    export ARROW_GLOG_URL=${TP_SOURCE_DIR}/${GLOG_NAME}
    export ARROW_LZ4_URL=${TP_SOURCE_DIR}/${LZ4_NAME}
    export ARROW_SNAPPY_URL=${TP_SOURCE_DIR}/${SNAPPY_NAME}
    export ARROW_ZLIB_URL=${TP_SOURCE_DIR}/${ZLIB_NAME}
    export ARROW_FLATBUFFERS_URL=${TP_SOURCE_DIR}/${FLATBUFFERS_NAME}
    export ARROW_ZSTD_URL=${TP_SOURCE_DIR}/${ZSTD_NAME}
    export LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc"

    # https://github.com/apache/arrow/blob/apache-arrow-5.0.0/cpp/src/arrow/memory_pool.cc#L286
    #
    # JemallocAllocator use mallocx and rallocx to allocate new memory, but mallocx and rallocx are Non-standard APIs,
    # and can not be hooked in BE, the memory used by arrow can not be counted by BE,
    # so disable jemalloc here and use SystemAllocator.
    #
    # Currently, the standard APIs are hooked in BE, so the jemalloc standard APIs will actually be used.
    ${CMAKE_CMD} -DARROW_PARQUET=ON -DARROW_JSON=ON -DARROW_IPC=ON -DARROW_USE_GLOG=OFF -DARROW_BUILD_STATIC=ON -DARROW_BUILD_SHARED=OFF \
    -DARROW_WITH_BROTLI=ON -DARROW_WITH_LZ4=ON -DARROW_WITH_SNAPPY=ON -DARROW_WITH_ZLIB=ON -DARROW_WITH_ZSTD=ON \
    -DARROW_WITH_UTF8PROC=OFF -DARROW_WITH_RE2=OFF \
    -DARROW_JEMALLOC=OFF -DARROW_MIMALLOC=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DARROW_BOOST_USE_SHARED=OFF -DARROW_GFLAGS_USE_SHARED=OFF -DBoost_NO_BOOST_CMAKE=ON -DBOOST_ROOT=$TP_INSTALL_DIR \
    -DJEMALLOC_HOME=$TP_INSTALL_DIR/jemalloc \
    -Dzstd_SOURCE=BUNDLED \
    -DRapidJSON_ROOT=$TP_INSTALL_DIR \
    -DARROW_SNAPPY_USE_SHARED=OFF \
    -DZLIB_ROOT=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DARROW_LZ4_USE_SHARED=OFF \
    -DBROTLI_ROOT=$TP_INSTALL_DIR \
    -DARROW_BROTLI_USE_SHARED=OFF \
    -Dgflags_ROOT=$TP_INSTALL_DIR/ \
    -DSnappy_ROOT=$TP_INSTALL_DIR/ \
    -DGLOG_ROOT=$TP_INSTALL_DIR/ \
    -DLZ4_ROOT=$TP_INSTALL_DIR/ \
    -DBoost_DIR=$TP_INSTALL_DIR \
    -DBoost_ROOT=$TP_INSTALL_DIR \
    -DARROW_BOOST_USE_SHARED=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DThrift_ROOT=$TP_INSTALL_DIR/ ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    if [ -f ./zstd_ep-install/lib64/libzstd.a ]; then
        cp -rf ./zstd_ep-install/lib64/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    else
        cp -rf ./zstd_ep-install/lib/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    fi
    # copy zstd headers
    mkdir -p ${TP_INSTALL_DIR}/include/zstd
    cp ./zstd_ep-install/include/* ${TP_INSTALL_DIR}/include/zstd

    restore_compile_flags
}

# s2
build_s2() {
    check_if_source_exist $S2_SOURCE
    cd $TP_SOURCE_DIR/$S2_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DBUILD_SHARED_LIBS=OFF \
    -DGFLAGS_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GFLAGS=ON \
    -DGLOG_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GLOG=ON \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# bitshuffle
build_bitshuffle() {
    check_if_source_exist $BITSHUFFLE_SOURCE
    cd $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE
    PREFIX=$TP_INSTALL_DIR

    # This library has significant optimizations when built with -mavx2. However,
    # we still need to support non-AVX2-capable hardware. So, we build it twice,
    # once with the flag and once without, and use some linker tricks to
    # suffix the AVX2 symbols with '_avx2'.
    arches="default avx2 avx512"
    # Becuase aarch64 don't support avx2, disable it.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        arches="default neon"
    fi

    to_link=""
    for arch in $arches ; do
        arch_flag=""
        if [ "$arch" == "avx2" ]; then
            arch_flag="-mavx2"
        elif [ "$arch" == "avx512" ]; then
            arch_flag="-march=icelake-server"
        elif [ "$arch" == "neon" ]; then
            arch_flag="-march=armv8-a+crc"
        fi
        tmp_obj=bitshuffle_${arch}_tmp.o
        dst_obj=bitshuffle_${arch}.o
        ${CC:-gcc} $EXTRA_CFLAGS $arch_flag -std=c99 -I$PREFIX/include/lz4/ -O3 -DNDEBUG -fPIC -c \
            "src/bitshuffle_core.c" \
            "src/bitshuffle.c" \
            "src/iochain.c"
        # Merge the object files together to produce a combined .o file.
        ld -r -o $tmp_obj bitshuffle_core.o bitshuffle.o iochain.o
        # For the AVX2 symbols, suffix them.
        if [[ "$arch" == "avx2" || "$arch" == "avx512" || "$arch" == "neon" ]]; then
            # Create a mapping file with '<old_sym> <suffixed_sym>' on each line.
            nm --defined-only --extern-only $tmp_obj | while read addr type sym ; do
              echo ${sym} ${sym}_${arch}
            done > renames.txt
            objcopy --redefine-syms=renames.txt $tmp_obj $dst_obj
        else
            mv $tmp_obj $dst_obj
        fi
        to_link="$to_link $dst_obj"
    done
    rm -f libbitshuffle.a
    ar rs libbitshuffle.a $to_link
    mkdir -p $PREFIX/include/bitshuffle
    cp libbitshuffle.a $PREFIX/lib/
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle.h $PREFIX/include/bitshuffle/bitshuffle.h
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle_core.h $PREFIX/include/bitshuffle/bitshuffle_core.h
}

# croaring bitmap
# If open AVX512 default, current version will be compiled failed on some machine, so close AVX512 default,
# When this problem is solved, a switch will be added to control.
build_croaringbitmap() {
    FORCE_AVX=ON
    # avx2 is not supported by aarch64.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        FORCE_AVX=FALSE
    fi
    if [[ `cat /proc/cpuinfo |grep avx|wc -l` == "0" ]]; then
        FORCE_AVX=FALSE
    fi
    check_if_source_exist $CROARINGBITMAP_SOURCE
    cd $TP_SOURCE_DIR/$CROARINGBITMAP_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DROARING_BUILD_STATIC=ON -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DENABLE_ROARING_TESTS=OFF \
    -DROARING_DISABLE_NATIVE=ON \
    -DFORCE_AVX=$FORCE_AVX \
    -DROARING_DISABLE_AVX512=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}
#orc
build_orc() {
    check_if_source_exist $ORC_SOURCE
    cd $TP_SOURCE_DIR/$ORC_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD ../ -DBUILD_JAVA=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DPROTOBUF_HOME=$TP_INSTALL_DIR \
    -DSNAPPY_HOME=$TP_INSTALL_DIR \
    -DGTEST_HOME=$TP_INSTALL_DIR \
    -DLZ4_HOME=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DZLIB_HOME=$TP_INSTALL_DIR\
    -DBUILD_LIBHDFSPP=OFF \
    -DBUILD_CPP_TESTS=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#cctz
build_cctz() {
    check_if_source_exist $CCTZ_SOURCE
    cd $TP_SOURCE_DIR/$CCTZ_SOURCE

    make -j$PARALLEL
    PREFIX=${TP_INSTALL_DIR} make install
}

#fmt
build_fmt() {
    check_if_source_exist $FMT_SOURCE
    cd $TP_SOURCE_DIR/$FMT_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} ../ \
            -DCMAKE_INSTALL_LIBDIR=lib64 -G "${CMAKE_GENERATOR}" -DFMT_TEST=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#ryu
build_ryu() {
    check_if_source_exist $RYU_SOURCE
    cd $TP_SOURCE_DIR/$RYU_SOURCE/ryu
    make -j$PARALLEL
    make install DESTDIR=${TP_INSTALL_DIR}
    mkdir -p $TP_INSTALL_DIR/include/ryu
    mv $TP_INSTALL_DIR/include/ryu.h $TP_INSTALL_DIR/include/ryu
    # copy to 64 to compatable with current CMake
    cp -f ${TP_INSTALL_DIR}/lib/libryu.a ${TP_INSTALL_DIR}/lib64/libryu.a
}

#break_pad
build_breakpad() {
    check_if_source_exist $BREAK_PAD_SOURCE
    cd $TP_SOURCE_DIR/$BREAK_PAD_SOURCE
    mkdir -p src/third_party/lss
    cp $TP_PATCH_DIR/linux_syscall_support.h src/third_party/lss
    CFLAGS= ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

#hadoop
build_hadoop() {
    check_if_source_exist $HADOOP_SOURCE
    cp -r $TP_SOURCE_DIR/$HADOOP_SOURCE $TP_INSTALL_DIR/hadoop
    # remove unnecessary doc and logs
    rm -rf $TP_INSTALL_DIR/hadoop/logs/* $TP_INSTALL_DIR/hadoop/share/doc/hadoop
    mkdir -p $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/include/hdfs.h $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/lib/native/libhdfs.a $TP_INSTALL_DIR/lib
}

#jdk
build_jdk() {
    check_if_source_exist $JDK_SOURCE
    rm -rf $TP_INSTALL_DIR/open_jdk && cp -r $TP_SOURCE_DIR/$JDK_SOURCE $TP_INSTALL_DIR/open_jdk
}

# ragel
# ragel-6.9+ is used by hypercan, so we build it first.
build_ragel() {
    check_if_source_exist $RAGEL_SOURCE
    cd $TP_SOURCE_DIR/$RAGEL_SOURCE
    # generage a static linked ragel, hyperscan will depend on it
    LDFLAGS=" -static-libstdc++ -static-libgcc" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

#hyperscan
build_hyperscan() {
    check_if_source_exist $HYPERSCAN_SOURCE
    cd $TP_SOURCE_DIR/$HYPERSCAN_SOURCE
    export PATH=$TP_INSTALL_DIR/bin:$PATH
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DBOOST_ROOT=$STARROCKS_THIRDPARTY/installed/include \
          -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc  -DCMAKE_INSTALL_LIBDIR=lib \
          -DBUILD_EXAMPLES=OFF -DBUILD_UNIT=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#mariadb-connector-c
build_mariadb() {
    OLD_CMAKE_GENERATOR=${CMAKE_GENERATOR}
    OLD_BUILD_SYSTEM=${BUILD_SYSTEM}

    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC ${FILE_PREFIX_MAP_OPTION}"

    # force use make build system, since ninja doesn't support install only headers
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'

    check_if_source_exist $MARIADB_SOURCE
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE
    mkdir -p build && cd build

    $CMAKE_CMD .. -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release    \
                  -DWITH_UNIT_TESTS=OFF                                 \
                  -DBUILD_SHARED_LIBS=OFF                               \
                  -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                  \
                  -DOPENSSL_USE_STATIC_LIBS=TRUE                        \
                  -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}
    # we only need build libmariadbclient and headers
    ${BUILD_SYSTEM} -j$PARALLEL mariadbclient
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/libmariadb
    mkdir -p $TP_INSTALL_DIR/lib/mariadb/
    cp libmariadbclient.a $TP_INSTALL_DIR/lib/mariadb/
    # install mariadb headers
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/include
    ${BUILD_SYSTEM} install

    restore_compile_flags
    export CMAKE_GENERATOR=$OLD_CMAKE_GENERATOR
    export BUILD_SYSTEM=$OLD_BUILD_SYSTEM
}

# jindosdk for Aliyun OSS
build_aliyun_jindosdk() {
    check_if_source_exist $JINDOSDK_SOURCE
    mkdir -p $TP_INSTALL_DIR/jindosdk
    cp -r $TP_SOURCE_DIR/$JINDOSDK_SOURCE/lib/*.jar $TP_INSTALL_DIR/jindosdk
}

build_gcs_connector() {
    check_if_source_exist $GCS_CONNECTOR_SOURCE
    mkdir -p $TP_INSTALL_DIR/gcs_connector
    cp -r $TP_SOURCE_DIR/$GCS_CONNECTOR_SOURCE/*.jar $TP_INSTALL_DIR/gcs_connector
}

build_broker_thirdparty_jars() {
    check_if_source_exist $BROKER_THIRDPARTY_JARS_SOURCE
    mkdir -p $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    cp -r $TP_SOURCE_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/* $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/hadoop-aliyun-2.7.2.jar
    # cloudfs-hadoop-with-dependencies will include aws jars, but we already support aws by official sdk, so we don't need it anymore.
    # And it will conflict with Iceberg's S3FileIO, make access S3 files failed.
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/cloudfs-hadoop-with-dependencies-1.1.21.jar
    # ensure read permission is granted for all users
    chmod -R +r $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/
}

build_aws_cpp_sdk() {
    check_if_source_exist $AWS_SDK_CPP_SOURCE
    cd $TP_SOURCE_DIR/$AWS_SDK_CPP_SOURCE
    # only build s3, s3-crt, transfer manager, identity-management and sts, you can add more components if you want.
    $CMAKE_CMD -Bbuild -DBUILD_ONLY="core;s3;s3-crt;transfer;identity-management;sts" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
               -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DENABLE_TESTING=OFF \
               -DENABLE_CURL_LOGGING=OFF \
               -G "${CMAKE_GENERATOR}" \
               -DCURL_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libcurl.a   \
               -DZLIB_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libz.a      \
               -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                     \
               -DOPENSSL_USE_STATIC_LIBS=TRUE                           \
               -Dcrypto_LIBRARY=${TP_INSTALL_DIR}/lib/libcrypto.a

    cd build
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    restore_compile_flags
}

# velocypack
build_vpack() {
    check_if_source_exist $VPACK_SOURCE
    cd $TP_SOURCE_DIR/$VPACK_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# opentelemetry
build_opentelemetry() {
    check_if_source_exist $OPENTELEMETRY_SOURCE

    cd $TP_SOURCE_DIR/$OPENTELEMETRY_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DBUILD_TESTING=OFF -DWITH_EXAMPLES=OFF \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        -DWITH_STL=OFF -DWITH_JAEGER=ON
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# jemalloc
build_jemalloc() {
    check_if_source_exist $JEMALLOC_SOURCE

    cd $TP_SOURCE_DIR/$JEMALLOC_SOURCE
    # jemalloc supports a runtime page size that's smaller or equal to the build
    # time one, but aborts on a larger one. If not defined, it falls back to the
    # the build system's _SC_PAGESIZE, which in many architectures can vary. Set
    # this to 64K (2^16) for arm architecture, and default 4K on x86 for performance.
    local addition_opts=" --with-lg-page=12"
    if [[ $MACHINE_TYPE == "aarch64" ]] ; then
        # change to 64K for arm architecture
        addition_opts=" --with-lg-page=16"
    fi
    # build jemalloc with release
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc --with-jemalloc-prefix=je --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
    # build jemalloc with debug options
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc-debug --with-jemalloc-prefix=je --enable-prof --enable-debug --enable-fill --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
}

# google benchmark
build_benchmark() {
    check_if_source_exist $BENCHMARK_SOURCE
    cd $TP_SOURCE_DIR/$BENCHMARK_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    cmake -DBENCHMARK_DOWNLOAD_DEPENDENCIES=off \
          -DBENCHMARK_ENABLE_GTEST_TESTS=off \
          -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
          -DCMAKE_INSTALL_LIBDIR=lib64 \
          -DCMAKE_BUILD_TYPE=Release ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# fast float
build_fast_float() {
    check_if_source_exist $FAST_FLOAT_SOURCE
    cd $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE
    cp -r $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE/include $TP_INSTALL_DIR
}

build_starcache() {
    check_if_source_exist $STARCACHE_SOURCE
    rm -rf $TP_INSTALL_DIR/$STARCACHE_SOURCE && mv $TP_SOURCE_DIR/$STARCACHE_SOURCE $TP_INSTALL_DIR/
}

# streamvbyte
build_streamvbyte() {
    check_if_source_exist $STREAMVBYTE_SOURCE

    cd $TP_SOURCE_DIR/$STREAMVBYTE_SOURCE/

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/

    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    $CMAKE_CMD .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=$TP_INSTALL_DIR/

    make -j$PARALLEL
    make install
}

# jansson
build_jansson() {
    check_if_source_exist $JANSSON_SOURCE
    cd $TP_SOURCE_DIR/$JANSSON_SOURCE/
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# avro-c
build_avro_c() {
    check_if_source_exist $AVRO_SOURCE
    cd $TP_SOURCE_DIR/$AVRO_SOURCE/lang/c
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    rm ${TP_INSTALL_DIR}/lib64/libavro.so*
}

# serders
build_serdes() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g"
    check_if_source_exist $SERDES_SOURCE
    cd $TP_SOURCE_DIR/$SERDES_SOURCE
    export LIBS="-lrt -lpthread -lcurl -ljansson -lrdkafka -lrdkafka++ -lavro -lssl -lcrypto -ldl"
    ./configure --prefix=${TP_INSTALL_DIR} \
                --libdir=${TP_INSTALL_DIR}/lib \
                --CFLAGS="-I ${TP_INSTALL_DIR}/include"  \
                --CXXFLAGS="-I ${TP_INSTALL_DIR}/include" \
                --LDFLAGS="-L ${TP_INSTALL_DIR}/lib -L ${TP_INSTALL_DIR}/lib64" \
                --enable-static \
                --disable-shared

    make -j$PARALLEL
    make install
    rm ${TP_INSTALL_DIR}/lib/libserdes.so*
    # these symbols also be definition in librdkafka, change these symbols to be local.
    objcopy --localize-symbol=cnd_timedwait ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=cnd_timedwait_ms ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=thrd_is_current ${TP_INSTALL_DIR}/lib/libserdes.a
    unset LIBS
    restore_compile_flags
}

# datasketches
build_datasketches() {
    check_if_source_exist $DATASKETCHES_SOURCE
    mkdir -p $TP_INSTALL_DIR/include/datasketches
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/common/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/cpc/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/fi/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/hll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/kll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/quantiles/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/req/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/sampling/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/theta/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/tuple/include/* $TP_INSTALL_DIR/include/datasketches/
}

# async-profiler
build_async_profiler() {
    check_if_source_exist $ASYNC_PROFILER_SOURCE
    mkdir -p $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/build $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/profiler.sh $TP_INSTALL_DIR/async-profiler
}

# fiu
build_fiu() {
    check_if_source_exist $FIU_SOURCE
    cd $TP_SOURCE_DIR/$FIU_SOURCE
    mkdir -p $TP_SOURCE_DIR/$FIU_SOURCE/installed
    make -j$PARALLEL
    make PREFIX=$TP_SOURCE_DIR/$FIU_SOURCE/installed install

    mkdir -p $TP_INSTALL_DIR/include/fiu
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/include/* $TP_INSTALL_DIR/include/fiu/
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/lib/libfiu.a $TP_INSTALL_DIR/lib/
}

# libdeflate
build_libdeflate() {
    check_if_source_exist $LIBDEFLATE_SOURCE
    mkdir -p $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    cd $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    $CMAKE_CMD .. -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# restore cxxflags/cppflags/cflags to default one
restore_compile_flags() {
    # c preprocessor flags
    export CPPFLAGS=$GLOBAL_CPPFLAGS
    # c flags
    export CFLAGS=$GLOBAL_CFLAGS
    # c++ flags
    export CXXFLAGS=$GLOBAL_CXXFLAGS
}

strip_binary() {
    # strip binary tools and ignore any errors
    echo "Strip binaries in $TP_INSTALL_DIR/bin/ ..."
    strip $TP_INSTALL_DIR/bin/* 2>/dev/null || true
}


# strip `$TP_SOURCE_DIR` and `$TP_INSTALL_DIR` from source code file path
export FILE_PREFIX_MAP_OPTION="-ffile-prefix-map=${TP_SOURCE_DIR}=. -ffile-prefix-map=${TP_INSTALL_DIR}=."
# set GLOBAL_C*FLAGS for easy restore in each sub build process
export GLOBAL_CPPFLAGS="-I ${TP_INCLUDE_DIR}"
# https://stackoverflow.com/questions/42597685/storage-size-of-timespec-isnt-known
export GLOBAL_CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -fPIC -g -D_POSIX_C_SOURCE=200112L -gz=zlib ${FILE_PREFIX_MAP_OPTION}"
export GLOBAL_CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess -fPIC -g -gz=zlib ${FILE_PREFIX_MAP_OPTION}"

# set those GLOBAL_*FLAGS to the CFLAGS/CXXFLAGS/CPPFLAGS
export CPPFLAGS=$GLOBAL_CPPFLAGS
export CXXFLAGS=$GLOBAL_CXXFLAGS
export CFLAGS=$GLOBAL_CFLAGS

build_libevent
build_zlib
build_lz4
build_lzo2
build_bzip
build_openssl
build_boost # must before thrift
build_protobuf
build_gflags
build_gtest
build_glog
build_rapidjson
build_simdjson
build_snappy
build_gperftools
build_curl
build_re2
build_thrift
build_leveldb
build_brpc
build_rocksdb
build_kerberos
build_sasl
build_flatbuffers
build_jemalloc
build_brotli
# must build before arrow
build_arrow
# NOTE: librdkafka depends on ZSTD which is generated by Arrow, So this SHOULD be
# built after arrow
build_librdkafka
build_pulsar
build_s2
build_bitshuffle
build_croaringbitmap
build_cctz
build_fmt
build_ryu
build_hadoop
build_jdk
build_ragel
build_hyperscan
build_mariadb
build_aliyun_jindosdk
build_gcs_connector
build_broker_thirdparty_jars
build_aws_cpp_sdk
build_vpack
build_opentelemetry
build_benchmark
build_fast_float
build_starcache
build_streamvbyte
build_jansson
build_avro_c
build_serdes
build_datasketches
build_async_profiler
build_fiu
build_llvm

if [[ "${MACHINE_TYPE}" != "aarch64" ]]; then
    build_breakpad
    build_libdeflate
fi

# strip unnecessary debug symbol for binaries in thirdparty
strip_binary

echo "Finished to build all thirdparties"

```

修好了。

## 原因

编译 **pulsar-client-cpp** 时，CMake 的 `find_package(OpenSSL)` 找不到 OpenSSL。OpenSSL 已经被 thirdparty 编译并安装到了 `thirdparty/installed/` 目录下，但 pulsar 的 CMake 调用中只设置了 `CMAKE_LIBRARY_PATH` 和 `CMAKE_INCLUDE_PATH`，没有设置 `OPENSSL_ROOT_DIR`，而 CMake 自带的 `FindOpenSSL.cmake` 模块依赖 `OPENSSL_ROOT_DIR` 来定位非系统路径的 OpenSSL。

> 有意思的是，前面 librdkafka 编译时能找到 OpenSSL，是因为 librdkafka 的 CMakeLists 自己做了额外的搜索路径处理。

## 修改

在 `build_pulsar()` 的 CMake 命令中加了 `-DOPENSSL_ROOT_DIR=$TP_INSTALL_DIR`，指向 `thirdparty/installed/`，这样 CMake 就能找到 `lib/libcrypto.a`、`lib/libssl.a` 和 `include/openssl/` 了。

重新执行编译即可：

```bash
BUILD_TYPE=Debug ./build.sh --be
```

```shellscript
BUILD_TYPE=Debug ./build.sh --be
```

---

**User**

好的，我继续编译后又报错了，这次是什么原因？

@zsh (897-1021) 

---

**Cursor**

这次的错误是编译 **aws-sdk-cpp-1.11.267** 时报的：

```
CMake Error at CMakeLists.txt:228 (include):
  include could not find requested file: AwsFindPackage

CMake Error at CMakeLists.txt:240 (add_subdirectory):
  add_subdirectory given source "crt/aws-crt-cpp" which is not an existing directory.

CMake Error at src/aws-cpp-sdk-core/CMakeLists.txt:597 (aws_use_package):
  Unknown CMake command "aws_use_package".
```

这说明 aws-sdk-cpp 的**子模块（git submodule）没有被拉取下来**，缺少 `crt/aws-crt-cpp` 目录和相关的 CMake 模块文件。让我确认一下：

```plaintext
CMake Error at CMakeLists.txt:228 (include):
  include could not find requested file: AwsFindPackage

CMake Error at CMakeLists.txt:240 (add_subdirectory):
  add_subdirectory given source "crt/aws-crt-cpp" which is not an existing directory.

CMake Error at src/aws-cpp-sdk-core/CMakeLists.txt:597 (aws_use_package):
  Unknown CMake command "aws_use_package".
```

让我看一下 build-thirdparty.sh 中是怎么处理 aws-sdk-cpp 的：

现在看看源码是如何被下载/解压的，以及 git submodule 的问题：

问题清楚了。`crt/tmp/` 是空的，说明 `prefetch_crt_dependency.sh` 虽然标记了 `prefetch_crt_dep_ok`，但实际下载**没有成功**（之前代理的 SSL 问题导致 curl 下载失败，但脚本没有做错误检查就继续了）。

需要删掉这个标记文件，然后重新下载：

现在让我确认一下你当前的代理设置是否正确（之前改了 `https://` → `http://`），并测试能否正常访问 GitHub：

当前 shell 中代理已经取消了，且能正常访问 GitHub。

## 原因

编译 **aws-sdk-cpp-1.11.267** 失败，因为 `crt/aws-crt-cpp` 目录不存在。

这是因为之前你的代理配置有问题（`https://` 导致 SSL 错误），`prefetch_crt_dependency.sh` 脚本在下载 AWS CRT 依赖时 curl 全部失败了，但脚本**没有错误检查**，`download-thirdparty.sh` 仍然创建了 `prefetch_crt_dep_ok` 标记文件，导致后续重新编译时跳过了这一步。

## 已修复

我已经删掉了 `prefetch_crt_dep_ok` 标记文件。重新编译时，脚本会重新执行 `prefetch_crt_dependency.sh` 下载所有 AWS CRT 依赖。

现在代理已正常（或已取消），直接重新编译即可：

```bash
BUILD_TYPE=Debug ./build.sh --be
```

```shellscript
BUILD_TYPE=Debug ./build.sh --be
```

---

**User**

继续编译，又遇到错误了

@zsh (748-1011) 

---

**Cursor**

这次是编译 **LLVM 16.0.6** 时报错：

```
make: *** No rule to make target 'LLVMBitstreamReader'.  Stop.
```

让我看一下构建脚本中 LLVM 是怎么编译的：

```plaintext
make: *** No rule to make target 'LLVMBitstreamReader'.  Stop.
```

问题很清楚了。CMake 配置的 source 路径不对，让我检查一下：

注意看！CMake 的构建文件直接写到了源码目录 `llvm-project-16.0.6.src` 里了（看到了 `CMakeCache.txt`、`Makefile`）。但构建脚本期望在 `llvm-build` 目录中构建。让我看一下到底发生了什么：

我看到问题了。CMake 配置命令末尾多了一个 `../${LLVM_SOURCE}` 参数。看一下第 290 和 304 行：

```bash
$CMAKE_CMD -S ../${LLVM_SOURCE}/llvm -G "${CMAKE_GENERATOR}" \
    ...
    -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}/llvm ../${LLVM_SOURCE}
```

`-S ../${LLVM_SOURCE}/llvm` 指定了源码目录为 `llvm` 子目录，但最后一行又加了 `../${LLVM_SOURCE}` 作为位置参数，这会覆盖 `-S` 的设置，导致 CMake 把整个 `llvm-project-16.0.6.src` 当作源码目录（而不是其中的 `llvm` 子目录）。

在较旧的 CMake 版本中，`-S` 可能优先于位置参数，但你的 CMake 3.28 把位置参数当作源码路径覆盖了 `-S`。

让我看一下 `BUILD_SYSTEM` 和 `CMAKE_GENERATOR` 的值，以及 `llvm-build` 目录是否存在：

```shellscript
$CMAKE_CMD -S ../${LLVM_SOURCE}/llvm -G "${CMAKE_GENERATOR}" \
    ...
    -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}/llvm ../${LLVM_SOURCE}
```

好，现在我理解了。你安装了 `ninja-build`，所以 `CMAKE_GENERATOR=Ninja`，`BUILD_SYSTEM=ninja`。

问题的根源是 LLVM CMake 配置命令的第 304 行末尾 `../${LLVM_SOURCE}` 这个参数。在 CMake 3.28 中，这个位置参数被当作了**源码目录**，覆盖了 `-S ../${LLVM_SOURCE}/llvm`。所以 CMake 配置了错误的源码目录（整个 `llvm-project-16.0.6.src` 而不是其中的 `llvm/`），生成了错误的构建目标，导致找不到 `LLVMBitstreamReader`。

而且构建文件还被写到了源码目录本身（`llvm-project-16.0.6.src/`），而不是 `llvm-build/`。

让我检查 CMake 配置输出也确认了这一点：

```
-- Build files have been written to: /home/peter/my-project/starrocks/thirdparty/src/llvm-project-16.0.6.src
```

应该是 `llvm-build` 而不是 `llvm-project-16.0.6.src`。

修复：去掉第 304 行末尾多余的 `../${LLVM_SOURCE}`：

```plaintext
-- Build files have been written to: /home/peter/my-project/starrocks/thirdparty/src/llvm-project-16.0.6.src
```

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

#################################################################################
# This script will
# 1. Check prerequisite libraries. Including:
#    cmake byacc flex automake libtool binutils-dev libiberty-dev bison
# 2. Compile and install all thirdparties which are downloaded
#    using *download-thirdparty.sh*.
#
# This script will run *download-thirdparty.sh* once again
# to check if all thirdparties have been downloaded, unpacked and patched.
#################################################################################
set -e

curdir=`dirname "$0"`
curdir=`cd "$curdir"; pwd`

export STARROCKS_HOME=${STARROCKS_HOME:-$curdir/..}
export TP_DIR=$curdir

# include custom environment variables
if [[ -f ${STARROCKS_HOME}/env.sh ]]; then
    . ${STARROCKS_HOME}/env.sh
fi

if [[ ! -f ${TP_DIR}/download-thirdparty.sh ]]; then
    echo "Download thirdparty script is missing".
    exit 1
fi

if [ ! -f ${TP_DIR}/vars.sh ]; then
    echo "vars.sh is missing".
    exit 1
fi
. ${TP_DIR}/vars.sh

cd $TP_DIR

# Download thirdparties.
${TP_DIR}/download-thirdparty.sh

# set COMPILER
if [[ ! -z ${STARROCKS_GCC_HOME} ]]; then
    export CC=${STARROCKS_GCC_HOME}/bin/gcc
    export CPP=${STARROCKS_GCC_HOME}/bin/cpp
    export CXX=${STARROCKS_GCC_HOME}/bin/g++
    export PATH=${STARROCKS_GCC_HOME}/bin:$PATH
else
    echo "STARROCKS_GCC_HOME environment variable is not set"
    exit 1
fi

# prepare installed prefix
mkdir -p ${TP_DIR}/installed

check_prerequest() {
    local CMD=$1
    local NAME=$2
    if ! $CMD; then
        echo $NAME is missing
        exit 1
    else
        echo $NAME is found
    fi
}

# sudo apt-get install cmake
# sudo yum install cmake
check_prerequest "${CMAKE_CMD} --version" "cmake"

# sudo apt-get install byacc
# sudo yum install byacc
check_prerequest "byacc -V" "byacc"

# sudo apt-get install flex
# sudo yum install flex
check_prerequest "flex -V" "flex"

# sudo apt-get install automake
# sudo yum install automake
check_prerequest "automake --version" "automake"

# sudo apt-get install libtool
# sudo yum install libtool
check_prerequest "libtoolize --version" "libtool"

BUILD_SYSTEM=${BUILD_SYSTEM:-make}

# sudo apt-get install binutils-dev
# sudo yum install binutils-devel
#check_prerequest "locate libbfd.a" "binutils-dev"

# sudo apt-get install libiberty-dev
# no need in centos 7.1
#check_prerequest "locate libiberty.a" "libiberty-dev"

# sudo apt-get install bison
# sudo yum install bison
#check_prerequest "bison --version" "bison"

#########################
# build all thirdparties
#########################


# Name of cmake build directory in each thirdpary project.
# Do not use `build`, because many projects contained a file named `BUILD`
# and if the filesystem is not case sensitive, `mkdir` will fail.
BUILD_DIR=starrocks_build
MACHINE_TYPE=$(uname -m)

# handle mac m1 platform, change arm64 to aarch64
if [[ "${MACHINE_TYPE}" == "arm64" ]]; then
    MACHINE_TYPE="aarch64"
fi

echo "machine type : $MACHINE_TYPE"

check_if_source_exist() {
    if [ -z $1 ]; then
        echo "dir should specified to check if exist."
        exit 1
    fi

    if [ ! -d $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
    echo "===== begin build $1"
}

check_if_archieve_exist() {
    if [ -z $1 ]; then
        echo "archieve should specified to check if exist."
        exit 1
    fi

    if [ ! -f $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
}

# libevent
build_libevent() {
    check_if_source_exist $LIBEVENT_SOURCE
    cd $TP_SOURCE_DIR/$LIBEVENT_SOURCE
    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

build_openssl() {
    OPENSSL_PLATFORM="linux-x86_64"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        OPENSSL_PLATFORM="linux-aarch64"
    fi

    check_if_source_exist $OPENSSL_SOURCE
    cd $TP_SOURCE_DIR/$OPENSSL_SOURCE

    # use customized CFLAGS/CPPFLAGS/CXXFLAGS/LDFLAGS
    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC"

    LDFLAGS="-L${TP_LIB_DIR}" \
    LIBDIR="lib" \
    ./Configure --prefix=$TP_INSTALL_DIR -lz -no-shared ${OPENSSL_PLATFORM}
    make -j$PARALLEL
    make install_sw

    restore_compile_flags
}

# thrift
build_thrift() {
    check_if_source_exist $THRIFT_SOURCE
    cd $TP_SOURCE_DIR/$THRIFT_SOURCE

    if [ ! -f configure ]; then
        ./bootstrap.sh
    fi

    echo ${TP_LIB_DIR}
    ./configure LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" LIBS="-lssl -lcrypto -ldl" \
    --prefix=$TP_INSTALL_DIR --docdir=$TP_INSTALL_DIR/doc --enable-static --disable-shared --disable-tests \
    --disable-tutorial --without-qt4 --without-qt5 --without-csharp --without-erlang --without-nodejs \
    --without-lua --without-perl --without-php --without-php_extension --without-dart --without-ruby \
    --without-haskell --without-go --without-haxe --without-d --without-python -without-java --with-cpp \
    --with-libevent=$TP_INSTALL_DIR --with-boost=$TP_INSTALL_DIR --with-openssl=$TP_INSTALL_DIR

    if [ -f compiler/cpp/thrifty.hh ];then
        mv compiler/cpp/thrifty.hh compiler/cpp/thrifty.h
    fi

    make -j$PARALLEL
    make install
}

# llvm
build_llvm() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -D_POSIX_C_SOURCE=200112L ${FILE_PREFIX_MAP_OPTION}"
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess ${FILE_PREFIX_MAP_OPTION}"

    LLVM_TARGET="X86"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        LLVM_TARGET="AArch64"
    fi

    LLVM_TARGETS_TO_BUILD=(
        "LLVMBitstreamReader"
        "LLVMRuntimeDyld" 
        "LLVMOption"
        "LLVMAsmPrinter"
        "LLVMProfileData"
        "LLVMAsmParser"
        "LLVMOrcTargetProcess"
        "LLVMExecutionEngine"
        "LLVMBinaryFormat"
        "LLVMDebugInfoDWARF"
        "LLVMObjCARCOpts"
        "LLVMCodeGen"
        "LLVMMCDisassembler"
        "LLVMSupport"
        "LLVMJITLink"
        "LLVMCFGuard"
        "LLVMInstrumentation"
        "LLVMIRReader"
        "LLVMCore"
        "LLVMTarget"
        "LLVMMC"
        "LLVMAnalysis"
        "LLVMGlobalISel"
        "LLVMScalarOpts"
        "LLVMTargetParser"
        "LLVMDemangle"
        "LLVMRemarks"
        "LLVMDebugInfoCodeView"
        "LLVMOrcShared"
        "LLVMOrcJIT"
        "LLVMTextAPI"
        "LLVMBitWriter"
        "LLVMBitReader"
        "LLVMObject"
        "LLVMTransformUtils"
        "LLVMSelectionDAG"
        "LLVMMCParser"
    )
    if [ "${LLVM_TARGET}" == "X86" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMX86Info" "LLVMX86Desc" "LLVMX86CodeGen")
    elif [ "${LLVM_TARGET}" == "AArch64" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMAArch64Info" "LLVMAArch64Desc" "LLVMAArch64CodeGen")
    fi

    LLVM_TARGETS_TO_INSTALL=()
    for target in ${LLVM_TARGETS_TO_BUILD[@]}; do
        LLVM_TARGETS_TO_INSTALL+=("install-${target}")
    done

    check_if_source_exist $LLVM_SOURCE

    cd $TP_SOURCE_DIR
    mkdir -p llvm-build
    cd llvm-build
    rm -rf CMakeCache.txt CMakeFiles/

    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -S ../${LLVM_SOURCE}/llvm -G "${CMAKE_GENERATOR}" \
    -DLLVM_ENABLE_EH:Bool=True \
    -DLLVM_ENABLE_RTTI:Bool=True \
    -DLLVM_ENABLE_PIC:Bool=True \
    -DLLVM_ENABLE_TERMINFO:Bool=False \
    -DLLVM_TARGETS_TO_BUILD=${LLVM_TARGET} \
    -DLLVM_BUILD_LLVM_DYLIB:BOOL=False \
    -DLLVM_INCLUDE_TOOLS:BOOL=False \
    -DLLVM_BUILD_TOOLS:BOOL=False \
    -DLLVM_INCLUDE_EXAMPLES:BOOL=False \
    -DLLVM_INCLUDE_TESTS:BOOL=False \
    -DLLVM_INCLUDE_BENCHMARKS:BOOL=False \
    -DBUILD_SHARED_LIBS:BOOL=False \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}/llvm

    # TODO(yueyang): Add more targets.
    # This is a little bit hack, we need to minimize the build time and binary size.
    ${BUILD_SYSTEM} -j$PARALLEL REQUIRES_RTTI=1 ${LLVM_TARGETS_TO_BUILD[@]}
    ${BUILD_SYSTEM} install-llvm-headers
    ${BUILD_SYSTEM} ${LLVM_TARGETS_TO_INSTALL[@]}

    restore_compile_flags
}

# protobuf
build_protobuf() {
    check_if_source_exist $PROTOBUF_SOURCE
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    rm -fr gmock
    mkdir gmock
    cd gmock
    tar xf ${TP_SOURCE_DIR}/$GTEST_NAME
    mv $GTEST_SOURCE gtest
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    ./autogen.sh
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc -pthread -Wl,--whole-archive -lpthread -Wl,--no-whole-archive" \
    ./configure --prefix=${TP_INSTALL_DIR} --disable-shared --enable-static --with-zlib --with-zlib-include=${TP_INSTALL_DIR}/include
    make -j$PARALLEL
    make install
}

# gflags
build_gflags() {
    check_if_source_exist $GFLAGS_SOURCE

    cd $TP_SOURCE_DIR/$GFLAGS_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# glog
build_glog() {
    check_if_source_exist $GLOG_SOURCE
    cd $TP_SOURCE_DIR/$GLOG_SOURCE

    # to generate config.guess and config.sub to support aarch64
    rm -rf config.*
    autoreconf -i

    LDFLAGS="-L${TP_LIB_DIR}" \
    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-frame-pointers --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

# gtest
build_gtest() {
    check_if_source_exist $GTEST_SOURCE

    cd $TP_SOURCE_DIR/$GTEST_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# rapidjson
build_rapidjson() {
    check_if_source_exist $RAPIDJSON_SOURCE

    rm -rf $TP_INSTALL_DIR/rapidjson
    cp -r $TP_SOURCE_DIR/$RAPIDJSON_SOURCE/include/rapidjson $TP_INCLUDE_DIR/
}

# simdjson
build_simdjson() {
    check_if_source_exist $SIMDJSON_SOURCE
    cd $TP_SOURCE_DIR/$SIMDJSON_SOURCE

    #ref: https://github.com/simdjson/simdjson/blob/master/HACKING.md
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_CXX_FLAGS="-O3" -DCMAKE_C_FLAGS="-O3" -DCMAKE_POSITION_INDEPENDENT_CODE=True -DSIMDJSON_AVX512_ALLOWED=OFF ..
    $CMAKE_CMD --build .
    mkdir -p $TP_INSTALL_DIR/lib

    cp $TP_SOURCE_DIR/$SIMDJSON_SOURCE/$BUILD_DIR/libsimdjson.a $TP_INSTALL_DIR/lib
    cp -r $TP_SOURCE_DIR/$SIMDJSON_SOURCE/include/* $TP_INCLUDE_DIR/
}

# snappy
build_snappy() {
    check_if_source_exist $SNAPPY_SOURCE
    cd $TP_SOURCE_DIR/$SNAPPY_SOURCE

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -G "${CMAKE_GENERATOR}" \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On \
    -DCMAKE_INSTALL_INCLUDEDIR=$TP_INCLUDE_DIR/snappy \
    -DSNAPPY_BUILD_TESTS=0 ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    if [ -f $TP_INSTALL_DIR/lib64/libsnappy.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib
        cp $TP_INSTALL_DIR/lib64/libsnappy.a $TP_INSTALL_DIR/lib/libsnappy.a
    fi

    #build for libarrow.a
    cp $TP_INCLUDE_DIR/snappy/snappy-c.h  $TP_INCLUDE_DIR/snappy-c.h
    cp $TP_INCLUDE_DIR/snappy/snappy-sinksource.h  $TP_INCLUDE_DIR/snappy-sinksource.h
    cp $TP_INCLUDE_DIR/snappy/snappy-stubs-public.h  $TP_INCLUDE_DIR/snappy-stubs-public.h
    cp $TP_INCLUDE_DIR/snappy/snappy.h  $TP_INCLUDE_DIR/snappy.h
    cp $TP_INSTALL_DIR/lib/libsnappy.a $TP_INSTALL_DIR/libsnappy.a
}

# gperftools
build_gperftools() {
    check_if_source_exist $GPERFTOOLS_SOURCE
    cd $TP_SOURCE_DIR/$GPERFTOOLS_SOURCE

    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=$TP_INSTALL_DIR/gperftools --disable-shared --enable-static --disable-libunwind --with-pic --enable-frame-pointers
    make -j$PARALLEL
    make install
}

# zlib
build_zlib() {
    check_if_source_exist $ZLIB_SOURCE
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --static
    make -j$PARALLEL
    make install

    # build minizip
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE/contrib/minizip
    autoreconf --force --install
    ./configure --prefix=$TP_INSTALL_DIR --enable-static=yes --enable-shared=no
    make -j$PARALLEL
    make install
}

# lz4
build_lz4() {
    check_if_source_exist $LZ4_SOURCE
    cd $TP_SOURCE_DIR/$LZ4_SOURCE

    make -C lib -j$PARALLEL install PREFIX=$TP_INSTALL_DIR \
    INCLUDEDIR=$TP_INCLUDE_DIR/lz4/ BUILD_SHARED=no
}

# lzo
build_lzo2() {
    check_if_source_exist $LZO2_SOURCE
    cd $TP_SOURCE_DIR/$LZO2_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
        LDFLAGS="-L${TP_LIB_DIR}" \
        ./configure --prefix="${TP_INSTALL_DIR}" --disable-shared --enable-static

    make -j "${PARALLEL}"
    make install
}

# bzip
build_bzip() {
    check_if_source_exist $BZIP_SOURCE
    cd $TP_SOURCE_DIR/$BZIP_SOURCE

    make -j$PARALLEL install PREFIX=$TP_INSTALL_DIR
}

# curl
build_curl() {
    check_if_source_exist $CURL_SOURCE
    cd $TP_SOURCE_DIR/$CURL_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" LIBS="-lssl -lcrypto -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static \
    --without-librtmp --with-ssl=${TP_INSTALL_DIR} --without-libidn2 --without-libgsasl --disable-ldap --enable-ipv6 --without-brotli
    make -j$PARALLEL
    make install
}

# re2
build_re2() {
    check_if_source_exist $RE2_SOURCE
    cd $TP_SOURCE_DIR/$RE2_SOURCE

    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release \
	    -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL install
}

# boost
build_boost() {
    check_if_source_exist $BOOST_SOURCE
    cd $TP_SOURCE_DIR/$BOOST_SOURCE

    # It is difficult to generate static linked b2, so we use LD_LIBRARY_PATH instead
    ./bootstrap.sh --prefix=$TP_INSTALL_DIR
    LD_LIBRARY_PATH=${STARROCKS_GCC_HOME}/lib:${STARROCKS_GCC_HOME}/lib64:${LD_LIBRARY_PATH} \
    ./b2 link=static runtime-link=static -j $PARALLEL --without-test --without-mpi --without-graph --without-graph_parallel --without-python cxxflags="-std=c++11 -g -fPIC -I$TP_INCLUDE_DIR -L$TP_LIB_DIR ${FILE_PREFIX_MAP_OPTION}" install
}

#leveldb
build_leveldb() {
    check_if_source_exist $LEVELDB_SOURCE
    cd $TP_SOURCE_DIR/$LEVELDB_SOURCE
    LDFLAGS="-L ${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    make -j$PARALLEL
    cp out-static/libleveldb.a $TP_LIB_DIR/libleveldb.a
    cp -r include/leveldb $TP_INCLUDE_DIR
}

# brpc
build_brpc() {
    check_if_source_exist $BRPC_SOURCE

    cd $TP_SOURCE_DIR/$BRPC_SOURCE
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    ./config_brpc.sh --headers="$TP_INSTALL_DIR/include" --libs="$TP_INSTALL_DIR/bin $TP_INSTALL_DIR/lib" --with-glog
    make -j$PARALLEL
    cp -rf output/* ${TP_INSTALL_DIR}/
    if [ -f $TP_INSTALL_DIR/lib/libbrpc.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib64
        cp $TP_SOURCE_DIR/$BRPC_SOURCE/output/lib/libbrpc.a $TP_INSTALL_DIR/lib64/
    fi
}

# rocksdb
build_rocksdb() {
    check_if_source_exist $ROCKSDB_SOURCE

    cd $TP_SOURCE_DIR/$ROCKSDB_SOURCE
    make clean

    CFLAGS= \
    EXTRA_CFLAGS="-I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy -I ${TP_INCLUDE_DIR}/lz4 -L${TP_LIB_DIR} ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_CXXFLAGS="-fPIC -Wno-deprecated-copy -Wno-stringop-truncation -Wno-pessimizing-move -I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_LDFLAGS="-static-libstdc++ -static-libgcc" \
    PORTABLE=1 make USE_RTTI=1 -j$PARALLEL static_lib

    cp librocksdb.a $TP_LIB_DIR/librocksdb.a
    cp -r include/rocksdb $TP_INCLUDE_DIR
}

# kerberos
build_kerberos() {
    check_if_source_exist $KRB5_SOURCE
    cd $TP_SOURCE_DIR/$KRB5_SOURCE/src
    CFLAGS="-fcommon -fPIC ${FILE_PREFIX_MAP_OPTION}" LDFLAGS="-L$TP_INSTALL_DIR/lib -pthread -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-static --disable-shared --with-spake-openssl=$TP_INSTALL_DIR
    make -j$PARALLEL
    make install
}

# sasl
build_sasl() {
    check_if_source_exist $SASL_SOURCE
    cd $TP_SOURCE_DIR/$SASL_SOURCE
    CFLAGS="-fPIC" LDFLAGS="-L$TP_INSTALL_DIR/lib -lresolv -pthread -ldl" ./autogen.sh --prefix=$TP_INSTALL_DIR --enable-gssapi=yes --enable-static --disable-shared --with-openssl=$TP_INSTALL_DIR --with-gss_impl=mit
    make -j$PARALLEL
    make install
}

# librdkafka
build_librdkafka() {
    check_if_source_exist $LIBRDKAFKA_SOURCE

    cd $TP_SOURCE_DIR/$LIBRDKAFKA_SOURCE

    mkdir -p sr_build && cd sr_build
    $CMAKE_CMD -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" \
        -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include;$TP_INSTALL_DIR/include/zstd;$TP_INSTALL_DIR/include/lz4" \
        -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DRDKAFKA_BUILD_STATIC=ON -DWITH_SASL=ON -DWITH_SASL_SCRAM=ON \
        -DRDKAFKA_BUILD_EXAMPLES=OFF -DRDKAFKA_BUILD_TESTS=OFF -DWITH_SSL=ON -DWITH_ZSTD=ON -DCMAKE_INSTALL_LIBDIR=lib ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# pulsar
build_pulsar() {
    check_if_source_exist $PULSAR_SOURCE

    cd $TP_SOURCE_DIR/$PULSAR_SOURCE

    $CMAKE_CMD -DCMAKE_LIBRARY_PATH=$TP_INSTALL_DIR/lib -DCMAKE_INCLUDE_PATH=$TP_INSTALL_DIR/include \
        -DOPENSSL_ROOT_DIR=$TP_INSTALL_DIR \
        -DPROTOC_PATH=$TP_INSTALL_DIR/bin/protoc -DBUILD_TESTS=OFF -DBUILD_PYTHON_WRAPPER=OFF -DBUILD_DYNAMIC_LIB=OFF .
    ${BUILD_SYSTEM} -j$PARALLEL

    cp lib/libpulsar.a $TP_INSTALL_DIR/lib/
    cp -r include/pulsar $TP_INSTALL_DIR/include/
}

# flatbuffers
build_flatbuffers() {
  check_if_source_exist $FLATBUFFERS_SOURCE
  cd $TP_SOURCE_DIR/$FLATBUFFERS_SOURCE
  mkdir -p $BUILD_DIR
  cd $BUILD_DIR
  rm -rf CMakeCache.txt CMakeFiles/
  LDFLAGS="-static-libstdc++ -static-libgcc" \
  ${CMAKE_CMD} .. -G "${CMAKE_GENERATOR}" -DFLATBUFFERS_BUILD_TESTS=OFF
  ${BUILD_SYSTEM} -j$PARALLEL
  cp flatc  $TP_INSTALL_DIR/bin/flatc
  cp -r ../include/flatbuffers  $TP_INCLUDE_DIR/flatbuffers
  cp libflatbuffers.a $TP_LIB_DIR/libflatbuffers.a
}

build_brotli() {
    check_if_source_exist $BROTLI_SOURCE
    cd $TP_SOURCE_DIR/$BROTLI_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    ${CMAKE_CMD} .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib64
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    mv -f $TP_INSTALL_DIR/lib64/libbrotlienc-static.a $TP_INSTALL_DIR/lib64/libbrotlienc.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlidec-static.a $TP_INSTALL_DIR/lib64/libbrotlidec.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlicommon-static.a $TP_INSTALL_DIR/lib64/libbrotlicommon.a
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so.*
}

# arrow
build_arrow() {
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CPPFLAGS=$CXXFLAGS

    check_if_source_exist $ARROW_SOURCE
    cd $TP_SOURCE_DIR/$ARROW_SOURCE/cpp
    mkdir -p release
    cd release
    export ARROW_BROTLI_URL=${TP_SOURCE_DIR}/${BROTLI_NAME}
    export ARROW_GLOG_URL=${TP_SOURCE_DIR}/${GLOG_NAME}
    export ARROW_LZ4_URL=${TP_SOURCE_DIR}/${LZ4_NAME}
    export ARROW_SNAPPY_URL=${TP_SOURCE_DIR}/${SNAPPY_NAME}
    export ARROW_ZLIB_URL=${TP_SOURCE_DIR}/${ZLIB_NAME}
    export ARROW_FLATBUFFERS_URL=${TP_SOURCE_DIR}/${FLATBUFFERS_NAME}
    export ARROW_ZSTD_URL=${TP_SOURCE_DIR}/${ZSTD_NAME}
    export LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc"

    # https://github.com/apache/arrow/blob/apache-arrow-5.0.0/cpp/src/arrow/memory_pool.cc#L286
    #
    # JemallocAllocator use mallocx and rallocx to allocate new memory, but mallocx and rallocx are Non-standard APIs,
    # and can not be hooked in BE, the memory used by arrow can not be counted by BE,
    # so disable jemalloc here and use SystemAllocator.
    #
    # Currently, the standard APIs are hooked in BE, so the jemalloc standard APIs will actually be used.
    ${CMAKE_CMD} -DARROW_PARQUET=ON -DARROW_JSON=ON -DARROW_IPC=ON -DARROW_USE_GLOG=OFF -DARROW_BUILD_STATIC=ON -DARROW_BUILD_SHARED=OFF \
    -DARROW_WITH_BROTLI=ON -DARROW_WITH_LZ4=ON -DARROW_WITH_SNAPPY=ON -DARROW_WITH_ZLIB=ON -DARROW_WITH_ZSTD=ON \
    -DARROW_WITH_UTF8PROC=OFF -DARROW_WITH_RE2=OFF \
    -DARROW_JEMALLOC=OFF -DARROW_MIMALLOC=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DARROW_BOOST_USE_SHARED=OFF -DARROW_GFLAGS_USE_SHARED=OFF -DBoost_NO_BOOST_CMAKE=ON -DBOOST_ROOT=$TP_INSTALL_DIR \
    -DJEMALLOC_HOME=$TP_INSTALL_DIR/jemalloc \
    -Dzstd_SOURCE=BUNDLED \
    -DRapidJSON_ROOT=$TP_INSTALL_DIR \
    -DARROW_SNAPPY_USE_SHARED=OFF \
    -DZLIB_ROOT=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DARROW_LZ4_USE_SHARED=OFF \
    -DBROTLI_ROOT=$TP_INSTALL_DIR \
    -DARROW_BROTLI_USE_SHARED=OFF \
    -Dgflags_ROOT=$TP_INSTALL_DIR/ \
    -DSnappy_ROOT=$TP_INSTALL_DIR/ \
    -DGLOG_ROOT=$TP_INSTALL_DIR/ \
    -DLZ4_ROOT=$TP_INSTALL_DIR/ \
    -DBoost_DIR=$TP_INSTALL_DIR \
    -DBoost_ROOT=$TP_INSTALL_DIR \
    -DARROW_BOOST_USE_SHARED=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DThrift_ROOT=$TP_INSTALL_DIR/ ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    if [ -f ./zstd_ep-install/lib64/libzstd.a ]; then
        cp -rf ./zstd_ep-install/lib64/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    else
        cp -rf ./zstd_ep-install/lib/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    fi
    # copy zstd headers
    mkdir -p ${TP_INSTALL_DIR}/include/zstd
    cp ./zstd_ep-install/include/* ${TP_INSTALL_DIR}/include/zstd

    restore_compile_flags
}

# s2
build_s2() {
    check_if_source_exist $S2_SOURCE
    cd $TP_SOURCE_DIR/$S2_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DBUILD_SHARED_LIBS=OFF \
    -DGFLAGS_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GFLAGS=ON \
    -DGLOG_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GLOG=ON \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# bitshuffle
build_bitshuffle() {
    check_if_source_exist $BITSHUFFLE_SOURCE
    cd $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE
    PREFIX=$TP_INSTALL_DIR

    # This library has significant optimizations when built with -mavx2. However,
    # we still need to support non-AVX2-capable hardware. So, we build it twice,
    # once with the flag and once without, and use some linker tricks to
    # suffix the AVX2 symbols with '_avx2'.
    arches="default avx2 avx512"
    # Becuase aarch64 don't support avx2, disable it.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        arches="default neon"
    fi

    to_link=""
    for arch in $arches ; do
        arch_flag=""
        if [ "$arch" == "avx2" ]; then
            arch_flag="-mavx2"
        elif [ "$arch" == "avx512" ]; then
            arch_flag="-march=icelake-server"
        elif [ "$arch" == "neon" ]; then
            arch_flag="-march=armv8-a+crc"
        fi
        tmp_obj=bitshuffle_${arch}_tmp.o
        dst_obj=bitshuffle_${arch}.o
        ${CC:-gcc} $EXTRA_CFLAGS $arch_flag -std=c99 -I$PREFIX/include/lz4/ -O3 -DNDEBUG -fPIC -c \
            "src/bitshuffle_core.c" \
            "src/bitshuffle.c" \
            "src/iochain.c"
        # Merge the object files together to produce a combined .o file.
        ld -r -o $tmp_obj bitshuffle_core.o bitshuffle.o iochain.o
        # For the AVX2 symbols, suffix them.
        if [[ "$arch" == "avx2" || "$arch" == "avx512" || "$arch" == "neon" ]]; then
            # Create a mapping file with '<old_sym> <suffixed_sym>' on each line.
            nm --defined-only --extern-only $tmp_obj | while read addr type sym ; do
              echo ${sym} ${sym}_${arch}
            done > renames.txt
            objcopy --redefine-syms=renames.txt $tmp_obj $dst_obj
        else
            mv $tmp_obj $dst_obj
        fi
        to_link="$to_link $dst_obj"
    done
    rm -f libbitshuffle.a
    ar rs libbitshuffle.a $to_link
    mkdir -p $PREFIX/include/bitshuffle
    cp libbitshuffle.a $PREFIX/lib/
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle.h $PREFIX/include/bitshuffle/bitshuffle.h
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle_core.h $PREFIX/include/bitshuffle/bitshuffle_core.h
}

# croaring bitmap
# If open AVX512 default, current version will be compiled failed on some machine, so close AVX512 default,
# When this problem is solved, a switch will be added to control.
build_croaringbitmap() {
    FORCE_AVX=ON
    # avx2 is not supported by aarch64.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        FORCE_AVX=FALSE
    fi
    if [[ `cat /proc/cpuinfo |grep avx|wc -l` == "0" ]]; then
        FORCE_AVX=FALSE
    fi
    check_if_source_exist $CROARINGBITMAP_SOURCE
    cd $TP_SOURCE_DIR/$CROARINGBITMAP_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DROARING_BUILD_STATIC=ON -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DENABLE_ROARING_TESTS=OFF \
    -DROARING_DISABLE_NATIVE=ON \
    -DFORCE_AVX=$FORCE_AVX \
    -DROARING_DISABLE_AVX512=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}
#orc
build_orc() {
    check_if_source_exist $ORC_SOURCE
    cd $TP_SOURCE_DIR/$ORC_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD ../ -DBUILD_JAVA=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DPROTOBUF_HOME=$TP_INSTALL_DIR \
    -DSNAPPY_HOME=$TP_INSTALL_DIR \
    -DGTEST_HOME=$TP_INSTALL_DIR \
    -DLZ4_HOME=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DZLIB_HOME=$TP_INSTALL_DIR\
    -DBUILD_LIBHDFSPP=OFF \
    -DBUILD_CPP_TESTS=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#cctz
build_cctz() {
    check_if_source_exist $CCTZ_SOURCE
    cd $TP_SOURCE_DIR/$CCTZ_SOURCE

    make -j$PARALLEL
    PREFIX=${TP_INSTALL_DIR} make install
}

#fmt
build_fmt() {
    check_if_source_exist $FMT_SOURCE
    cd $TP_SOURCE_DIR/$FMT_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} ../ \
            -DCMAKE_INSTALL_LIBDIR=lib64 -G "${CMAKE_GENERATOR}" -DFMT_TEST=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#ryu
build_ryu() {
    check_if_source_exist $RYU_SOURCE
    cd $TP_SOURCE_DIR/$RYU_SOURCE/ryu
    make -j$PARALLEL
    make install DESTDIR=${TP_INSTALL_DIR}
    mkdir -p $TP_INSTALL_DIR/include/ryu
    mv $TP_INSTALL_DIR/include/ryu.h $TP_INSTALL_DIR/include/ryu
    # copy to 64 to compatable with current CMake
    cp -f ${TP_INSTALL_DIR}/lib/libryu.a ${TP_INSTALL_DIR}/lib64/libryu.a
}

#break_pad
build_breakpad() {
    check_if_source_exist $BREAK_PAD_SOURCE
    cd $TP_SOURCE_DIR/$BREAK_PAD_SOURCE
    mkdir -p src/third_party/lss
    cp $TP_PATCH_DIR/linux_syscall_support.h src/third_party/lss
    CFLAGS= ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

#hadoop
build_hadoop() {
    check_if_source_exist $HADOOP_SOURCE
    cp -r $TP_SOURCE_DIR/$HADOOP_SOURCE $TP_INSTALL_DIR/hadoop
    # remove unnecessary doc and logs
    rm -rf $TP_INSTALL_DIR/hadoop/logs/* $TP_INSTALL_DIR/hadoop/share/doc/hadoop
    mkdir -p $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/include/hdfs.h $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/lib/native/libhdfs.a $TP_INSTALL_DIR/lib
}

#jdk
build_jdk() {
    check_if_source_exist $JDK_SOURCE
    rm -rf $TP_INSTALL_DIR/open_jdk && cp -r $TP_SOURCE_DIR/$JDK_SOURCE $TP_INSTALL_DIR/open_jdk
}

# ragel
# ragel-6.9+ is used by hypercan, so we build it first.
build_ragel() {
    check_if_source_exist $RAGEL_SOURCE
    cd $TP_SOURCE_DIR/$RAGEL_SOURCE
    # generage a static linked ragel, hyperscan will depend on it
    LDFLAGS=" -static-libstdc++ -static-libgcc" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

#hyperscan
build_hyperscan() {
    check_if_source_exist $HYPERSCAN_SOURCE
    cd $TP_SOURCE_DIR/$HYPERSCAN_SOURCE
    export PATH=$TP_INSTALL_DIR/bin:$PATH
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DBOOST_ROOT=$STARROCKS_THIRDPARTY/installed/include \
          -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc  -DCMAKE_INSTALL_LIBDIR=lib \
          -DBUILD_EXAMPLES=OFF -DBUILD_UNIT=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#mariadb-connector-c
build_mariadb() {
    OLD_CMAKE_GENERATOR=${CMAKE_GENERATOR}
    OLD_BUILD_SYSTEM=${BUILD_SYSTEM}

    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC ${FILE_PREFIX_MAP_OPTION}"

    # force use make build system, since ninja doesn't support install only headers
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'

    check_if_source_exist $MARIADB_SOURCE
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE
    mkdir -p build && cd build

    $CMAKE_CMD .. -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release    \
                  -DWITH_UNIT_TESTS=OFF                                 \
                  -DBUILD_SHARED_LIBS=OFF                               \
                  -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                  \
                  -DOPENSSL_USE_STATIC_LIBS=TRUE                        \
                  -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}
    # we only need build libmariadbclient and headers
    ${BUILD_SYSTEM} -j$PARALLEL mariadbclient
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/libmariadb
    mkdir -p $TP_INSTALL_DIR/lib/mariadb/
    cp libmariadbclient.a $TP_INSTALL_DIR/lib/mariadb/
    # install mariadb headers
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/include
    ${BUILD_SYSTEM} install

    restore_compile_flags
    export CMAKE_GENERATOR=$OLD_CMAKE_GENERATOR
    export BUILD_SYSTEM=$OLD_BUILD_SYSTEM
}

# jindosdk for Aliyun OSS
build_aliyun_jindosdk() {
    check_if_source_exist $JINDOSDK_SOURCE
    mkdir -p $TP_INSTALL_DIR/jindosdk
    cp -r $TP_SOURCE_DIR/$JINDOSDK_SOURCE/lib/*.jar $TP_INSTALL_DIR/jindosdk
}

build_gcs_connector() {
    check_if_source_exist $GCS_CONNECTOR_SOURCE
    mkdir -p $TP_INSTALL_DIR/gcs_connector
    cp -r $TP_SOURCE_DIR/$GCS_CONNECTOR_SOURCE/*.jar $TP_INSTALL_DIR/gcs_connector
}

build_broker_thirdparty_jars() {
    check_if_source_exist $BROKER_THIRDPARTY_JARS_SOURCE
    mkdir -p $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    cp -r $TP_SOURCE_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/* $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/hadoop-aliyun-2.7.2.jar
    # cloudfs-hadoop-with-dependencies will include aws jars, but we already support aws by official sdk, so we don't need it anymore.
    # And it will conflict with Iceberg's S3FileIO, make access S3 files failed.
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/cloudfs-hadoop-with-dependencies-1.1.21.jar
    # ensure read permission is granted for all users
    chmod -R +r $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/
}

build_aws_cpp_sdk() {
    check_if_source_exist $AWS_SDK_CPP_SOURCE
    cd $TP_SOURCE_DIR/$AWS_SDK_CPP_SOURCE
    # only build s3, s3-crt, transfer manager, identity-management and sts, you can add more components if you want.
    $CMAKE_CMD -Bbuild -DBUILD_ONLY="core;s3;s3-crt;transfer;identity-management;sts" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
               -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DENABLE_TESTING=OFF \
               -DENABLE_CURL_LOGGING=OFF \
               -G "${CMAKE_GENERATOR}" \
               -DCURL_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libcurl.a   \
               -DZLIB_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libz.a      \
               -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                     \
               -DOPENSSL_USE_STATIC_LIBS=TRUE                           \
               -Dcrypto_LIBRARY=${TP_INSTALL_DIR}/lib/libcrypto.a

    cd build
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    restore_compile_flags
}

# velocypack
build_vpack() {
    check_if_source_exist $VPACK_SOURCE
    cd $TP_SOURCE_DIR/$VPACK_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# opentelemetry
build_opentelemetry() {
    check_if_source_exist $OPENTELEMETRY_SOURCE

    cd $TP_SOURCE_DIR/$OPENTELEMETRY_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DBUILD_TESTING=OFF -DWITH_EXAMPLES=OFF \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        -DWITH_STL=OFF -DWITH_JAEGER=ON
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# jemalloc
build_jemalloc() {
    check_if_source_exist $JEMALLOC_SOURCE

    cd $TP_SOURCE_DIR/$JEMALLOC_SOURCE
    # jemalloc supports a runtime page size that's smaller or equal to the build
    # time one, but aborts on a larger one. If not defined, it falls back to the
    # the build system's _SC_PAGESIZE, which in many architectures can vary. Set
    # this to 64K (2^16) for arm architecture, and default 4K on x86 for performance.
    local addition_opts=" --with-lg-page=12"
    if [[ $MACHINE_TYPE == "aarch64" ]] ; then
        # change to 64K for arm architecture
        addition_opts=" --with-lg-page=16"
    fi
    # build jemalloc with release
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc --with-jemalloc-prefix=je --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
    # build jemalloc with debug options
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc-debug --with-jemalloc-prefix=je --enable-prof --enable-debug --enable-fill --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
}

# google benchmark
build_benchmark() {
    check_if_source_exist $BENCHMARK_SOURCE
    cd $TP_SOURCE_DIR/$BENCHMARK_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    cmake -DBENCHMARK_DOWNLOAD_DEPENDENCIES=off \
          -DBENCHMARK_ENABLE_GTEST_TESTS=off \
          -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
          -DCMAKE_INSTALL_LIBDIR=lib64 \
          -DCMAKE_BUILD_TYPE=Release ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# fast float
build_fast_float() {
    check_if_source_exist $FAST_FLOAT_SOURCE
    cd $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE
    cp -r $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE/include $TP_INSTALL_DIR
}

build_starcache() {
    check_if_source_exist $STARCACHE_SOURCE
    rm -rf $TP_INSTALL_DIR/$STARCACHE_SOURCE && mv $TP_SOURCE_DIR/$STARCACHE_SOURCE $TP_INSTALL_DIR/
}

# streamvbyte
build_streamvbyte() {
    check_if_source_exist $STREAMVBYTE_SOURCE

    cd $TP_SOURCE_DIR/$STREAMVBYTE_SOURCE/

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/

    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    $CMAKE_CMD .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=$TP_INSTALL_DIR/

    make -j$PARALLEL
    make install
}

# jansson
build_jansson() {
    check_if_source_exist $JANSSON_SOURCE
    cd $TP_SOURCE_DIR/$JANSSON_SOURCE/
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# avro-c
build_avro_c() {
    check_if_source_exist $AVRO_SOURCE
    cd $TP_SOURCE_DIR/$AVRO_SOURCE/lang/c
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    rm ${TP_INSTALL_DIR}/lib64/libavro.so*
}

# serders
build_serdes() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g"
    check_if_source_exist $SERDES_SOURCE
    cd $TP_SOURCE_DIR/$SERDES_SOURCE
    export LIBS="-lrt -lpthread -lcurl -ljansson -lrdkafka -lrdkafka++ -lavro -lssl -lcrypto -ldl"
    ./configure --prefix=${TP_INSTALL_DIR} \
                --libdir=${TP_INSTALL_DIR}/lib \
                --CFLAGS="-I ${TP_INSTALL_DIR}/include"  \
                --CXXFLAGS="-I ${TP_INSTALL_DIR}/include" \
                --LDFLAGS="-L ${TP_INSTALL_DIR}/lib -L ${TP_INSTALL_DIR}/lib64" \
                --enable-static \
                --disable-shared

    make -j$PARALLEL
    make install
    rm ${TP_INSTALL_DIR}/lib/libserdes.so*
    # these symbols also be definition in librdkafka, change these symbols to be local.
    objcopy --localize-symbol=cnd_timedwait ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=cnd_timedwait_ms ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=thrd_is_current ${TP_INSTALL_DIR}/lib/libserdes.a
    unset LIBS
    restore_compile_flags
}

# datasketches
build_datasketches() {
    check_if_source_exist $DATASKETCHES_SOURCE
    mkdir -p $TP_INSTALL_DIR/include/datasketches
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/common/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/cpc/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/fi/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/hll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/kll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/quantiles/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/req/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/sampling/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/theta/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/tuple/include/* $TP_INSTALL_DIR/include/datasketches/
}

# async-profiler
build_async_profiler() {
    check_if_source_exist $ASYNC_PROFILER_SOURCE
    mkdir -p $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/build $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/profiler.sh $TP_INSTALL_DIR/async-profiler
}

# fiu
build_fiu() {
    check_if_source_exist $FIU_SOURCE
    cd $TP_SOURCE_DIR/$FIU_SOURCE
    mkdir -p $TP_SOURCE_DIR/$FIU_SOURCE/installed
    make -j$PARALLEL
    make PREFIX=$TP_SOURCE_DIR/$FIU_SOURCE/installed install

    mkdir -p $TP_INSTALL_DIR/include/fiu
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/include/* $TP_INSTALL_DIR/include/fiu/
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/lib/libfiu.a $TP_INSTALL_DIR/lib/
}

# libdeflate
build_libdeflate() {
    check_if_source_exist $LIBDEFLATE_SOURCE
    mkdir -p $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    cd $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    $CMAKE_CMD .. -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# restore cxxflags/cppflags/cflags to default one
restore_compile_flags() {
    # c preprocessor flags
    export CPPFLAGS=$GLOBAL_CPPFLAGS
    # c flags
    export CFLAGS=$GLOBAL_CFLAGS
    # c++ flags
    export CXXFLAGS=$GLOBAL_CXXFLAGS
}

strip_binary() {
    # strip binary tools and ignore any errors
    echo "Strip binaries in $TP_INSTALL_DIR/bin/ ..."
    strip $TP_INSTALL_DIR/bin/* 2>/dev/null || true
}


# strip `$TP_SOURCE_DIR` and `$TP_INSTALL_DIR` from source code file path
export FILE_PREFIX_MAP_OPTION="-ffile-prefix-map=${TP_SOURCE_DIR}=. -ffile-prefix-map=${TP_INSTALL_DIR}=."
# set GLOBAL_C*FLAGS for easy restore in each sub build process
export GLOBAL_CPPFLAGS="-I ${TP_INCLUDE_DIR}"
# https://stackoverflow.com/questions/42597685/storage-size-of-timespec-isnt-known
export GLOBAL_CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -fPIC -g -D_POSIX_C_SOURCE=200112L -gz=zlib ${FILE_PREFIX_MAP_OPTION}"
export GLOBAL_CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess -fPIC -g -gz=zlib ${FILE_PREFIX_MAP_OPTION}"

# set those GLOBAL_*FLAGS to the CFLAGS/CXXFLAGS/CPPFLAGS
export CPPFLAGS=$GLOBAL_CPPFLAGS
export CXXFLAGS=$GLOBAL_CXXFLAGS
export CFLAGS=$GLOBAL_CFLAGS

build_libevent
build_zlib
build_lz4
build_lzo2
build_bzip
build_openssl
build_boost # must before thrift
build_protobuf
build_gflags
build_gtest
build_glog
build_rapidjson
build_simdjson
build_snappy
build_gperftools
build_curl
build_re2
build_thrift
build_leveldb
build_brpc
build_rocksdb
build_kerberos
build_sasl
build_flatbuffers
build_jemalloc
build_brotli
# must build before arrow
build_arrow
# NOTE: librdkafka depends on ZSTD which is generated by Arrow, So this SHOULD be
# built after arrow
build_librdkafka
build_pulsar
build_s2
build_bitshuffle
build_croaringbitmap
build_cctz
build_fmt
build_ryu
build_hadoop
build_jdk
build_ragel
build_hyperscan
build_mariadb
build_aliyun_jindosdk
build_gcs_connector
build_broker_thirdparty_jars
build_aws_cpp_sdk
build_vpack
build_opentelemetry
build_benchmark
build_fast_float
build_starcache
build_streamvbyte
build_jansson
build_avro_c
build_serdes
build_datasketches
build_async_profiler
build_fiu
build_llvm

if [[ "${MACHINE_TYPE}" != "aarch64" ]]; then
    build_breakpad
    build_libdeflate
fi

# strip unnecessary debug symbol for binaries in thirdparty
strip_binary

echo "Finished to build all thirdparties"

```

然后需要清理掉源码目录里被误写入的构建文件，以及之前错误的 `llvm-build`：

修好了。

## 原因

编译 LLVM 16.0.6 时，CMake 配置命令有 bug：

```bash
$CMAKE_CMD -S ../${LLVM_SOURCE}/llvm -G "${CMAKE_GENERATOR}" \
    ...
    -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}/llvm ../${LLVM_SOURCE}   # ← 末尾多了这个
```

`-S ../${LLVM_SOURCE}/llvm` 正确指定了源码目录为 `llvm` 子目录，但末尾又多了一个 `../${LLVM_SOURCE}` 作为位置参数。在 CMake 3.28 中，这个位置参数**覆盖了 `-S` 的设置**，导致 CMake 把整个 `llvm-project-16.0.6.src/` 当作源码目录（而不是其中的 `llvm/` 子目录），所以生成的构建目标全不对，找不到 `LLVMBitstreamReader`。

> 这个 bug 在旧版 CMake（如 3.16）上可能不会暴露，因为旧版的 `-S` 和位置参数的优先级处理不同。

## 修复

1. 删掉了第 304 行末尾多余的 `../${LLVM_SOURCE}`
2. 清理了源码目录中被误写入的构建文件和错误的 `llvm-build`

重新执行编译即可：

```bash
BUILD_TYPE=Debug ./build.sh --be
```

```shellscript
$CMAKE_CMD -S ../${LLVM_SOURCE}/llvm -G "${CMAKE_GENERATOR}" \
    ...
    -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}/llvm ../${LLVM_SOURCE}   # ← 末尾多了这个
```

```shellscript
BUILD_TYPE=Debug ./build.sh --be
```

---

**User**

@zsh (883-1021) 

继续编译又有新报错了

---

**Cursor**

这次是编译 **breakpad** 时报错：

```
src/processor/exploitability_linux.cc:521:11: error: argument 1 null where non-null expected [-Werror=nonnull]
  521 |     fclose(objdump_fp);
```

GCC 10 的 `-O3` 优化级别下，编译器分析出 `objdump_fp` 在这个代码路径上可能为 NULL，而 `fclose` 被声明为 `__nonnull((1))`，加上 `-Werror` 就变成了编译错误。

让我看一下构建脚本中 breakpad 的编译配置：

```plaintext
src/processor/exploitability_linux.cc:521:11: error: argument 1 null where non-null expected [-Werror=nonnull]
  521 |     fclose(objdump_fp);
```

breakpad 的 configure 会把 `CXXFLAGS` 中的 `-Werror` 带进来。我需要在 `build_breakpad()` 中添加 `-Wno-nonnull` 来抑制这个警告。

最简单的修复方式是在 configure 时设置 `CXXFLAGS`：

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

#################################################################################
# This script will
# 1. Check prerequisite libraries. Including:
#    cmake byacc flex automake libtool binutils-dev libiberty-dev bison
# 2. Compile and install all thirdparties which are downloaded
#    using *download-thirdparty.sh*.
#
# This script will run *download-thirdparty.sh* once again
# to check if all thirdparties have been downloaded, unpacked and patched.
#################################################################################
set -e

curdir=`dirname "$0"`
curdir=`cd "$curdir"; pwd`

export STARROCKS_HOME=${STARROCKS_HOME:-$curdir/..}
export TP_DIR=$curdir

# include custom environment variables
if [[ -f ${STARROCKS_HOME}/env.sh ]]; then
    . ${STARROCKS_HOME}/env.sh
fi

if [[ ! -f ${TP_DIR}/download-thirdparty.sh ]]; then
    echo "Download thirdparty script is missing".
    exit 1
fi

if [ ! -f ${TP_DIR}/vars.sh ]; then
    echo "vars.sh is missing".
    exit 1
fi
. ${TP_DIR}/vars.sh

cd $TP_DIR

# Download thirdparties.
${TP_DIR}/download-thirdparty.sh

# set COMPILER
if [[ ! -z ${STARROCKS_GCC_HOME} ]]; then
    export CC=${STARROCKS_GCC_HOME}/bin/gcc
    export CPP=${STARROCKS_GCC_HOME}/bin/cpp
    export CXX=${STARROCKS_GCC_HOME}/bin/g++
    export PATH=${STARROCKS_GCC_HOME}/bin:$PATH
else
    echo "STARROCKS_GCC_HOME environment variable is not set"
    exit 1
fi

# prepare installed prefix
mkdir -p ${TP_DIR}/installed

check_prerequest() {
    local CMD=$1
    local NAME=$2
    if ! $CMD; then
        echo $NAME is missing
        exit 1
    else
        echo $NAME is found
    fi
}

# sudo apt-get install cmake
# sudo yum install cmake
check_prerequest "${CMAKE_CMD} --version" "cmake"

# sudo apt-get install byacc
# sudo yum install byacc
check_prerequest "byacc -V" "byacc"

# sudo apt-get install flex
# sudo yum install flex
check_prerequest "flex -V" "flex"

# sudo apt-get install automake
# sudo yum install automake
check_prerequest "automake --version" "automake"

# sudo apt-get install libtool
# sudo yum install libtool
check_prerequest "libtoolize --version" "libtool"

BUILD_SYSTEM=${BUILD_SYSTEM:-make}

# sudo apt-get install binutils-dev
# sudo yum install binutils-devel
#check_prerequest "locate libbfd.a" "binutils-dev"

# sudo apt-get install libiberty-dev
# no need in centos 7.1
#check_prerequest "locate libiberty.a" "libiberty-dev"

# sudo apt-get install bison
# sudo yum install bison
#check_prerequest "bison --version" "bison"

#########################
# build all thirdparties
#########################


# Name of cmake build directory in each thirdpary project.
# Do not use `build`, because many projects contained a file named `BUILD`
# and if the filesystem is not case sensitive, `mkdir` will fail.
BUILD_DIR=starrocks_build
MACHINE_TYPE=$(uname -m)

# handle mac m1 platform, change arm64 to aarch64
if [[ "${MACHINE_TYPE}" == "arm64" ]]; then
    MACHINE_TYPE="aarch64"
fi

echo "machine type : $MACHINE_TYPE"

check_if_source_exist() {
    if [ -z $1 ]; then
        echo "dir should specified to check if exist."
        exit 1
    fi

    if [ ! -d $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
    echo "===== begin build $1"
}

check_if_archieve_exist() {
    if [ -z $1 ]; then
        echo "archieve should specified to check if exist."
        exit 1
    fi

    if [ ! -f $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
}

# libevent
build_libevent() {
    check_if_source_exist $LIBEVENT_SOURCE
    cd $TP_SOURCE_DIR/$LIBEVENT_SOURCE
    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

build_openssl() {
    OPENSSL_PLATFORM="linux-x86_64"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        OPENSSL_PLATFORM="linux-aarch64"
    fi

    check_if_source_exist $OPENSSL_SOURCE
    cd $TP_SOURCE_DIR/$OPENSSL_SOURCE

    # use customized CFLAGS/CPPFLAGS/CXXFLAGS/LDFLAGS
    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC"

    LDFLAGS="-L${TP_LIB_DIR}" \
    LIBDIR="lib" \
    ./Configure --prefix=$TP_INSTALL_DIR -lz -no-shared ${OPENSSL_PLATFORM}
    make -j$PARALLEL
    make install_sw

    restore_compile_flags
}

# thrift
build_thrift() {
    check_if_source_exist $THRIFT_SOURCE
    cd $TP_SOURCE_DIR/$THRIFT_SOURCE

    if [ ! -f configure ]; then
        ./bootstrap.sh
    fi

    echo ${TP_LIB_DIR}
    ./configure LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" LIBS="-lssl -lcrypto -ldl" \
    --prefix=$TP_INSTALL_DIR --docdir=$TP_INSTALL_DIR/doc --enable-static --disable-shared --disable-tests \
    --disable-tutorial --without-qt4 --without-qt5 --without-csharp --without-erlang --without-nodejs \
    --without-lua --without-perl --without-php --without-php_extension --without-dart --without-ruby \
    --without-haskell --without-go --without-haxe --without-d --without-python -without-java --with-cpp \
    --with-libevent=$TP_INSTALL_DIR --with-boost=$TP_INSTALL_DIR --with-openssl=$TP_INSTALL_DIR

    if [ -f compiler/cpp/thrifty.hh ];then
        mv compiler/cpp/thrifty.hh compiler/cpp/thrifty.h
    fi

    make -j$PARALLEL
    make install
}

# llvm
build_llvm() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -D_POSIX_C_SOURCE=200112L ${FILE_PREFIX_MAP_OPTION}"
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess ${FILE_PREFIX_MAP_OPTION}"

    LLVM_TARGET="X86"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        LLVM_TARGET="AArch64"
    fi

    LLVM_TARGETS_TO_BUILD=(
        "LLVMBitstreamReader"
        "LLVMRuntimeDyld" 
        "LLVMOption"
        "LLVMAsmPrinter"
        "LLVMProfileData"
        "LLVMAsmParser"
        "LLVMOrcTargetProcess"
        "LLVMExecutionEngine"
        "LLVMBinaryFormat"
        "LLVMDebugInfoDWARF"
        "LLVMObjCARCOpts"
        "LLVMCodeGen"
        "LLVMMCDisassembler"
        "LLVMSupport"
        "LLVMJITLink"
        "LLVMCFGuard"
        "LLVMInstrumentation"
        "LLVMIRReader"
        "LLVMCore"
        "LLVMTarget"
        "LLVMMC"
        "LLVMAnalysis"
        "LLVMGlobalISel"
        "LLVMScalarOpts"
        "LLVMTargetParser"
        "LLVMDemangle"
        "LLVMRemarks"
        "LLVMDebugInfoCodeView"
        "LLVMOrcShared"
        "LLVMOrcJIT"
        "LLVMTextAPI"
        "LLVMBitWriter"
        "LLVMBitReader"
        "LLVMObject"
        "LLVMTransformUtils"
        "LLVMSelectionDAG"
        "LLVMMCParser"
    )
    if [ "${LLVM_TARGET}" == "X86" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMX86Info" "LLVMX86Desc" "LLVMX86CodeGen")
    elif [ "${LLVM_TARGET}" == "AArch64" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMAArch64Info" "LLVMAArch64Desc" "LLVMAArch64CodeGen")
    fi

    LLVM_TARGETS_TO_INSTALL=()
    for target in ${LLVM_TARGETS_TO_BUILD[@]}; do
        LLVM_TARGETS_TO_INSTALL+=("install-${target}")
    done

    check_if_source_exist $LLVM_SOURCE

    cd $TP_SOURCE_DIR
    mkdir -p llvm-build
    cd llvm-build
    rm -rf CMakeCache.txt CMakeFiles/

    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -S ../${LLVM_SOURCE}/llvm -G "${CMAKE_GENERATOR}" \
    -DLLVM_ENABLE_EH:Bool=True \
    -DLLVM_ENABLE_RTTI:Bool=True \
    -DLLVM_ENABLE_PIC:Bool=True \
    -DLLVM_ENABLE_TERMINFO:Bool=False \
    -DLLVM_TARGETS_TO_BUILD=${LLVM_TARGET} \
    -DLLVM_BUILD_LLVM_DYLIB:BOOL=False \
    -DLLVM_INCLUDE_TOOLS:BOOL=False \
    -DLLVM_BUILD_TOOLS:BOOL=False \
    -DLLVM_INCLUDE_EXAMPLES:BOOL=False \
    -DLLVM_INCLUDE_TESTS:BOOL=False \
    -DLLVM_INCLUDE_BENCHMARKS:BOOL=False \
    -DBUILD_SHARED_LIBS:BOOL=False \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}/llvm

    # TODO(yueyang): Add more targets.
    # This is a little bit hack, we need to minimize the build time and binary size.
    ${BUILD_SYSTEM} -j$PARALLEL REQUIRES_RTTI=1 ${LLVM_TARGETS_TO_BUILD[@]}
    ${BUILD_SYSTEM} install-llvm-headers
    ${BUILD_SYSTEM} ${LLVM_TARGETS_TO_INSTALL[@]}

    restore_compile_flags
}

# protobuf
build_protobuf() {
    check_if_source_exist $PROTOBUF_SOURCE
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    rm -fr gmock
    mkdir gmock
    cd gmock
    tar xf ${TP_SOURCE_DIR}/$GTEST_NAME
    mv $GTEST_SOURCE gtest
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    ./autogen.sh
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc -pthread -Wl,--whole-archive -lpthread -Wl,--no-whole-archive" \
    ./configure --prefix=${TP_INSTALL_DIR} --disable-shared --enable-static --with-zlib --with-zlib-include=${TP_INSTALL_DIR}/include
    make -j$PARALLEL
    make install
}

# gflags
build_gflags() {
    check_if_source_exist $GFLAGS_SOURCE

    cd $TP_SOURCE_DIR/$GFLAGS_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# glog
build_glog() {
    check_if_source_exist $GLOG_SOURCE
    cd $TP_SOURCE_DIR/$GLOG_SOURCE

    # to generate config.guess and config.sub to support aarch64
    rm -rf config.*
    autoreconf -i

    LDFLAGS="-L${TP_LIB_DIR}" \
    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-frame-pointers --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

# gtest
build_gtest() {
    check_if_source_exist $GTEST_SOURCE

    cd $TP_SOURCE_DIR/$GTEST_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# rapidjson
build_rapidjson() {
    check_if_source_exist $RAPIDJSON_SOURCE

    rm -rf $TP_INSTALL_DIR/rapidjson
    cp -r $TP_SOURCE_DIR/$RAPIDJSON_SOURCE/include/rapidjson $TP_INCLUDE_DIR/
}

# simdjson
build_simdjson() {
    check_if_source_exist $SIMDJSON_SOURCE
    cd $TP_SOURCE_DIR/$SIMDJSON_SOURCE

    #ref: https://github.com/simdjson/simdjson/blob/master/HACKING.md
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_CXX_FLAGS="-O3" -DCMAKE_C_FLAGS="-O3" -DCMAKE_POSITION_INDEPENDENT_CODE=True -DSIMDJSON_AVX512_ALLOWED=OFF ..
    $CMAKE_CMD --build .
    mkdir -p $TP_INSTALL_DIR/lib

    cp $TP_SOURCE_DIR/$SIMDJSON_SOURCE/$BUILD_DIR/libsimdjson.a $TP_INSTALL_DIR/lib
    cp -r $TP_SOURCE_DIR/$SIMDJSON_SOURCE/include/* $TP_INCLUDE_DIR/
}

# snappy
build_snappy() {
    check_if_source_exist $SNAPPY_SOURCE
    cd $TP_SOURCE_DIR/$SNAPPY_SOURCE

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -G "${CMAKE_GENERATOR}" \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On \
    -DCMAKE_INSTALL_INCLUDEDIR=$TP_INCLUDE_DIR/snappy \
    -DSNAPPY_BUILD_TESTS=0 ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    if [ -f $TP_INSTALL_DIR/lib64/libsnappy.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib
        cp $TP_INSTALL_DIR/lib64/libsnappy.a $TP_INSTALL_DIR/lib/libsnappy.a
    fi

    #build for libarrow.a
    cp $TP_INCLUDE_DIR/snappy/snappy-c.h  $TP_INCLUDE_DIR/snappy-c.h
    cp $TP_INCLUDE_DIR/snappy/snappy-sinksource.h  $TP_INCLUDE_DIR/snappy-sinksource.h
    cp $TP_INCLUDE_DIR/snappy/snappy-stubs-public.h  $TP_INCLUDE_DIR/snappy-stubs-public.h
    cp $TP_INCLUDE_DIR/snappy/snappy.h  $TP_INCLUDE_DIR/snappy.h
    cp $TP_INSTALL_DIR/lib/libsnappy.a $TP_INSTALL_DIR/libsnappy.a
}

# gperftools
build_gperftools() {
    check_if_source_exist $GPERFTOOLS_SOURCE
    cd $TP_SOURCE_DIR/$GPERFTOOLS_SOURCE

    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=$TP_INSTALL_DIR/gperftools --disable-shared --enable-static --disable-libunwind --with-pic --enable-frame-pointers
    make -j$PARALLEL
    make install
}

# zlib
build_zlib() {
    check_if_source_exist $ZLIB_SOURCE
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --static
    make -j$PARALLEL
    make install

    # build minizip
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE/contrib/minizip
    autoreconf --force --install
    ./configure --prefix=$TP_INSTALL_DIR --enable-static=yes --enable-shared=no
    make -j$PARALLEL
    make install
}

# lz4
build_lz4() {
    check_if_source_exist $LZ4_SOURCE
    cd $TP_SOURCE_DIR/$LZ4_SOURCE

    make -C lib -j$PARALLEL install PREFIX=$TP_INSTALL_DIR \
    INCLUDEDIR=$TP_INCLUDE_DIR/lz4/ BUILD_SHARED=no
}

# lzo
build_lzo2() {
    check_if_source_exist $LZO2_SOURCE
    cd $TP_SOURCE_DIR/$LZO2_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
        LDFLAGS="-L${TP_LIB_DIR}" \
        ./configure --prefix="${TP_INSTALL_DIR}" --disable-shared --enable-static

    make -j "${PARALLEL}"
    make install
}

# bzip
build_bzip() {
    check_if_source_exist $BZIP_SOURCE
    cd $TP_SOURCE_DIR/$BZIP_SOURCE

    make -j$PARALLEL install PREFIX=$TP_INSTALL_DIR
}

# curl
build_curl() {
    check_if_source_exist $CURL_SOURCE
    cd $TP_SOURCE_DIR/$CURL_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" LIBS="-lssl -lcrypto -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static \
    --without-librtmp --with-ssl=${TP_INSTALL_DIR} --without-libidn2 --without-libgsasl --disable-ldap --enable-ipv6 --without-brotli
    make -j$PARALLEL
    make install
}

# re2
build_re2() {
    check_if_source_exist $RE2_SOURCE
    cd $TP_SOURCE_DIR/$RE2_SOURCE

    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release \
	    -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL install
}

# boost
build_boost() {
    check_if_source_exist $BOOST_SOURCE
    cd $TP_SOURCE_DIR/$BOOST_SOURCE

    # It is difficult to generate static linked b2, so we use LD_LIBRARY_PATH instead
    ./bootstrap.sh --prefix=$TP_INSTALL_DIR
    LD_LIBRARY_PATH=${STARROCKS_GCC_HOME}/lib:${STARROCKS_GCC_HOME}/lib64:${LD_LIBRARY_PATH} \
    ./b2 link=static runtime-link=static -j $PARALLEL --without-test --without-mpi --without-graph --without-graph_parallel --without-python cxxflags="-std=c++11 -g -fPIC -I$TP_INCLUDE_DIR -L$TP_LIB_DIR ${FILE_PREFIX_MAP_OPTION}" install
}

#leveldb
build_leveldb() {
    check_if_source_exist $LEVELDB_SOURCE
    cd $TP_SOURCE_DIR/$LEVELDB_SOURCE
    LDFLAGS="-L ${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    make -j$PARALLEL
    cp out-static/libleveldb.a $TP_LIB_DIR/libleveldb.a
    cp -r include/leveldb $TP_INCLUDE_DIR
}

# brpc
build_brpc() {
    check_if_source_exist $BRPC_SOURCE

    cd $TP_SOURCE_DIR/$BRPC_SOURCE
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    ./config_brpc.sh --headers="$TP_INSTALL_DIR/include" --libs="$TP_INSTALL_DIR/bin $TP_INSTALL_DIR/lib" --with-glog
    make -j$PARALLEL
    cp -rf output/* ${TP_INSTALL_DIR}/
    if [ -f $TP_INSTALL_DIR/lib/libbrpc.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib64
        cp $TP_SOURCE_DIR/$BRPC_SOURCE/output/lib/libbrpc.a $TP_INSTALL_DIR/lib64/
    fi
}

# rocksdb
build_rocksdb() {
    check_if_source_exist $ROCKSDB_SOURCE

    cd $TP_SOURCE_DIR/$ROCKSDB_SOURCE
    make clean

    CFLAGS= \
    EXTRA_CFLAGS="-I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy -I ${TP_INCLUDE_DIR}/lz4 -L${TP_LIB_DIR} ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_CXXFLAGS="-fPIC -Wno-deprecated-copy -Wno-stringop-truncation -Wno-pessimizing-move -I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_LDFLAGS="-static-libstdc++ -static-libgcc" \
    PORTABLE=1 make USE_RTTI=1 -j$PARALLEL static_lib

    cp librocksdb.a $TP_LIB_DIR/librocksdb.a
    cp -r include/rocksdb $TP_INCLUDE_DIR
}

# kerberos
build_kerberos() {
    check_if_source_exist $KRB5_SOURCE
    cd $TP_SOURCE_DIR/$KRB5_SOURCE/src
    CFLAGS="-fcommon -fPIC ${FILE_PREFIX_MAP_OPTION}" LDFLAGS="-L$TP_INSTALL_DIR/lib -pthread -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-static --disable-shared --with-spake-openssl=$TP_INSTALL_DIR
    make -j$PARALLEL
    make install
}

# sasl
build_sasl() {
    check_if_source_exist $SASL_SOURCE
    cd $TP_SOURCE_DIR/$SASL_SOURCE
    CFLAGS="-fPIC" LDFLAGS="-L$TP_INSTALL_DIR/lib -lresolv -pthread -ldl" ./autogen.sh --prefix=$TP_INSTALL_DIR --enable-gssapi=yes --enable-static --disable-shared --with-openssl=$TP_INSTALL_DIR --with-gss_impl=mit
    make -j$PARALLEL
    make install
}

# librdkafka
build_librdkafka() {
    check_if_source_exist $LIBRDKAFKA_SOURCE

    cd $TP_SOURCE_DIR/$LIBRDKAFKA_SOURCE

    mkdir -p sr_build && cd sr_build
    $CMAKE_CMD -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" \
        -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include;$TP_INSTALL_DIR/include/zstd;$TP_INSTALL_DIR/include/lz4" \
        -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DRDKAFKA_BUILD_STATIC=ON -DWITH_SASL=ON -DWITH_SASL_SCRAM=ON \
        -DRDKAFKA_BUILD_EXAMPLES=OFF -DRDKAFKA_BUILD_TESTS=OFF -DWITH_SSL=ON -DWITH_ZSTD=ON -DCMAKE_INSTALL_LIBDIR=lib ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# pulsar
build_pulsar() {
    check_if_source_exist $PULSAR_SOURCE

    cd $TP_SOURCE_DIR/$PULSAR_SOURCE

    $CMAKE_CMD -DCMAKE_LIBRARY_PATH=$TP_INSTALL_DIR/lib -DCMAKE_INCLUDE_PATH=$TP_INSTALL_DIR/include \
        -DOPENSSL_ROOT_DIR=$TP_INSTALL_DIR \
        -DPROTOC_PATH=$TP_INSTALL_DIR/bin/protoc -DBUILD_TESTS=OFF -DBUILD_PYTHON_WRAPPER=OFF -DBUILD_DYNAMIC_LIB=OFF .
    ${BUILD_SYSTEM} -j$PARALLEL

    cp lib/libpulsar.a $TP_INSTALL_DIR/lib/
    cp -r include/pulsar $TP_INSTALL_DIR/include/
}

# flatbuffers
build_flatbuffers() {
  check_if_source_exist $FLATBUFFERS_SOURCE
  cd $TP_SOURCE_DIR/$FLATBUFFERS_SOURCE
  mkdir -p $BUILD_DIR
  cd $BUILD_DIR
  rm -rf CMakeCache.txt CMakeFiles/
  LDFLAGS="-static-libstdc++ -static-libgcc" \
  ${CMAKE_CMD} .. -G "${CMAKE_GENERATOR}" -DFLATBUFFERS_BUILD_TESTS=OFF
  ${BUILD_SYSTEM} -j$PARALLEL
  cp flatc  $TP_INSTALL_DIR/bin/flatc
  cp -r ../include/flatbuffers  $TP_INCLUDE_DIR/flatbuffers
  cp libflatbuffers.a $TP_LIB_DIR/libflatbuffers.a
}

build_brotli() {
    check_if_source_exist $BROTLI_SOURCE
    cd $TP_SOURCE_DIR/$BROTLI_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    ${CMAKE_CMD} .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib64
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    mv -f $TP_INSTALL_DIR/lib64/libbrotlienc-static.a $TP_INSTALL_DIR/lib64/libbrotlienc.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlidec-static.a $TP_INSTALL_DIR/lib64/libbrotlidec.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlicommon-static.a $TP_INSTALL_DIR/lib64/libbrotlicommon.a
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so.*
}

# arrow
build_arrow() {
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CPPFLAGS=$CXXFLAGS

    check_if_source_exist $ARROW_SOURCE
    cd $TP_SOURCE_DIR/$ARROW_SOURCE/cpp
    mkdir -p release
    cd release
    export ARROW_BROTLI_URL=${TP_SOURCE_DIR}/${BROTLI_NAME}
    export ARROW_GLOG_URL=${TP_SOURCE_DIR}/${GLOG_NAME}
    export ARROW_LZ4_URL=${TP_SOURCE_DIR}/${LZ4_NAME}
    export ARROW_SNAPPY_URL=${TP_SOURCE_DIR}/${SNAPPY_NAME}
    export ARROW_ZLIB_URL=${TP_SOURCE_DIR}/${ZLIB_NAME}
    export ARROW_FLATBUFFERS_URL=${TP_SOURCE_DIR}/${FLATBUFFERS_NAME}
    export ARROW_ZSTD_URL=${TP_SOURCE_DIR}/${ZSTD_NAME}
    export LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc"

    # https://github.com/apache/arrow/blob/apache-arrow-5.0.0/cpp/src/arrow/memory_pool.cc#L286
    #
    # JemallocAllocator use mallocx and rallocx to allocate new memory, but mallocx and rallocx are Non-standard APIs,
    # and can not be hooked in BE, the memory used by arrow can not be counted by BE,
    # so disable jemalloc here and use SystemAllocator.
    #
    # Currently, the standard APIs are hooked in BE, so the jemalloc standard APIs will actually be used.
    ${CMAKE_CMD} -DARROW_PARQUET=ON -DARROW_JSON=ON -DARROW_IPC=ON -DARROW_USE_GLOG=OFF -DARROW_BUILD_STATIC=ON -DARROW_BUILD_SHARED=OFF \
    -DARROW_WITH_BROTLI=ON -DARROW_WITH_LZ4=ON -DARROW_WITH_SNAPPY=ON -DARROW_WITH_ZLIB=ON -DARROW_WITH_ZSTD=ON \
    -DARROW_WITH_UTF8PROC=OFF -DARROW_WITH_RE2=OFF \
    -DARROW_JEMALLOC=OFF -DARROW_MIMALLOC=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DARROW_BOOST_USE_SHARED=OFF -DARROW_GFLAGS_USE_SHARED=OFF -DBoost_NO_BOOST_CMAKE=ON -DBOOST_ROOT=$TP_INSTALL_DIR \
    -DJEMALLOC_HOME=$TP_INSTALL_DIR/jemalloc \
    -Dzstd_SOURCE=BUNDLED \
    -DRapidJSON_ROOT=$TP_INSTALL_DIR \
    -DARROW_SNAPPY_USE_SHARED=OFF \
    -DZLIB_ROOT=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DARROW_LZ4_USE_SHARED=OFF \
    -DBROTLI_ROOT=$TP_INSTALL_DIR \
    -DARROW_BROTLI_USE_SHARED=OFF \
    -Dgflags_ROOT=$TP_INSTALL_DIR/ \
    -DSnappy_ROOT=$TP_INSTALL_DIR/ \
    -DGLOG_ROOT=$TP_INSTALL_DIR/ \
    -DLZ4_ROOT=$TP_INSTALL_DIR/ \
    -DBoost_DIR=$TP_INSTALL_DIR \
    -DBoost_ROOT=$TP_INSTALL_DIR \
    -DARROW_BOOST_USE_SHARED=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DThrift_ROOT=$TP_INSTALL_DIR/ ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    if [ -f ./zstd_ep-install/lib64/libzstd.a ]; then
        cp -rf ./zstd_ep-install/lib64/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    else
        cp -rf ./zstd_ep-install/lib/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    fi
    # copy zstd headers
    mkdir -p ${TP_INSTALL_DIR}/include/zstd
    cp ./zstd_ep-install/include/* ${TP_INSTALL_DIR}/include/zstd

    restore_compile_flags
}

# s2
build_s2() {
    check_if_source_exist $S2_SOURCE
    cd $TP_SOURCE_DIR/$S2_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DBUILD_SHARED_LIBS=OFF \
    -DGFLAGS_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GFLAGS=ON \
    -DGLOG_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GLOG=ON \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# bitshuffle
build_bitshuffle() {
    check_if_source_exist $BITSHUFFLE_SOURCE
    cd $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE
    PREFIX=$TP_INSTALL_DIR

    # This library has significant optimizations when built with -mavx2. However,
    # we still need to support non-AVX2-capable hardware. So, we build it twice,
    # once with the flag and once without, and use some linker tricks to
    # suffix the AVX2 symbols with '_avx2'.
    arches="default avx2 avx512"
    # Becuase aarch64 don't support avx2, disable it.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        arches="default neon"
    fi

    to_link=""
    for arch in $arches ; do
        arch_flag=""
        if [ "$arch" == "avx2" ]; then
            arch_flag="-mavx2"
        elif [ "$arch" == "avx512" ]; then
            arch_flag="-march=icelake-server"
        elif [ "$arch" == "neon" ]; then
            arch_flag="-march=armv8-a+crc"
        fi
        tmp_obj=bitshuffle_${arch}_tmp.o
        dst_obj=bitshuffle_${arch}.o
        ${CC:-gcc} $EXTRA_CFLAGS $arch_flag -std=c99 -I$PREFIX/include/lz4/ -O3 -DNDEBUG -fPIC -c \
            "src/bitshuffle_core.c" \
            "src/bitshuffle.c" \
            "src/iochain.c"
        # Merge the object files together to produce a combined .o file.
        ld -r -o $tmp_obj bitshuffle_core.o bitshuffle.o iochain.o
        # For the AVX2 symbols, suffix them.
        if [[ "$arch" == "avx2" || "$arch" == "avx512" || "$arch" == "neon" ]]; then
            # Create a mapping file with '<old_sym> <suffixed_sym>' on each line.
            nm --defined-only --extern-only $tmp_obj | while read addr type sym ; do
              echo ${sym} ${sym}_${arch}
            done > renames.txt
            objcopy --redefine-syms=renames.txt $tmp_obj $dst_obj
        else
            mv $tmp_obj $dst_obj
        fi
        to_link="$to_link $dst_obj"
    done
    rm -f libbitshuffle.a
    ar rs libbitshuffle.a $to_link
    mkdir -p $PREFIX/include/bitshuffle
    cp libbitshuffle.a $PREFIX/lib/
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle.h $PREFIX/include/bitshuffle/bitshuffle.h
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle_core.h $PREFIX/include/bitshuffle/bitshuffle_core.h
}

# croaring bitmap
# If open AVX512 default, current version will be compiled failed on some machine, so close AVX512 default,
# When this problem is solved, a switch will be added to control.
build_croaringbitmap() {
    FORCE_AVX=ON
    # avx2 is not supported by aarch64.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        FORCE_AVX=FALSE
    fi
    if [[ `cat /proc/cpuinfo |grep avx|wc -l` == "0" ]]; then
        FORCE_AVX=FALSE
    fi
    check_if_source_exist $CROARINGBITMAP_SOURCE
    cd $TP_SOURCE_DIR/$CROARINGBITMAP_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DROARING_BUILD_STATIC=ON -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DENABLE_ROARING_TESTS=OFF \
    -DROARING_DISABLE_NATIVE=ON \
    -DFORCE_AVX=$FORCE_AVX \
    -DROARING_DISABLE_AVX512=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}
#orc
build_orc() {
    check_if_source_exist $ORC_SOURCE
    cd $TP_SOURCE_DIR/$ORC_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD ../ -DBUILD_JAVA=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DPROTOBUF_HOME=$TP_INSTALL_DIR \
    -DSNAPPY_HOME=$TP_INSTALL_DIR \
    -DGTEST_HOME=$TP_INSTALL_DIR \
    -DLZ4_HOME=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DZLIB_HOME=$TP_INSTALL_DIR\
    -DBUILD_LIBHDFSPP=OFF \
    -DBUILD_CPP_TESTS=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#cctz
build_cctz() {
    check_if_source_exist $CCTZ_SOURCE
    cd $TP_SOURCE_DIR/$CCTZ_SOURCE

    make -j$PARALLEL
    PREFIX=${TP_INSTALL_DIR} make install
}

#fmt
build_fmt() {
    check_if_source_exist $FMT_SOURCE
    cd $TP_SOURCE_DIR/$FMT_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} ../ \
            -DCMAKE_INSTALL_LIBDIR=lib64 -G "${CMAKE_GENERATOR}" -DFMT_TEST=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#ryu
build_ryu() {
    check_if_source_exist $RYU_SOURCE
    cd $TP_SOURCE_DIR/$RYU_SOURCE/ryu
    make -j$PARALLEL
    make install DESTDIR=${TP_INSTALL_DIR}
    mkdir -p $TP_INSTALL_DIR/include/ryu
    mv $TP_INSTALL_DIR/include/ryu.h $TP_INSTALL_DIR/include/ryu
    # copy to 64 to compatable with current CMake
    cp -f ${TP_INSTALL_DIR}/lib/libryu.a ${TP_INSTALL_DIR}/lib64/libryu.a
}

#break_pad
build_breakpad() {
    check_if_source_exist $BREAK_PAD_SOURCE
    cd $TP_SOURCE_DIR/$BREAK_PAD_SOURCE
    mkdir -p src/third_party/lss
    cp $TP_PATCH_DIR/linux_syscall_support.h src/third_party/lss
    CFLAGS= CXXFLAGS="${CXXFLAGS} -Wno-nonnull" ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

#hadoop
build_hadoop() {
    check_if_source_exist $HADOOP_SOURCE
    cp -r $TP_SOURCE_DIR/$HADOOP_SOURCE $TP_INSTALL_DIR/hadoop
    # remove unnecessary doc and logs
    rm -rf $TP_INSTALL_DIR/hadoop/logs/* $TP_INSTALL_DIR/hadoop/share/doc/hadoop
    mkdir -p $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/include/hdfs.h $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/lib/native/libhdfs.a $TP_INSTALL_DIR/lib
}

#jdk
build_jdk() {
    check_if_source_exist $JDK_SOURCE
    rm -rf $TP_INSTALL_DIR/open_jdk && cp -r $TP_SOURCE_DIR/$JDK_SOURCE $TP_INSTALL_DIR/open_jdk
}

# ragel
# ragel-6.9+ is used by hypercan, so we build it first.
build_ragel() {
    check_if_source_exist $RAGEL_SOURCE
    cd $TP_SOURCE_DIR/$RAGEL_SOURCE
    # generage a static linked ragel, hyperscan will depend on it
    LDFLAGS=" -static-libstdc++ -static-libgcc" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

#hyperscan
build_hyperscan() {
    check_if_source_exist $HYPERSCAN_SOURCE
    cd $TP_SOURCE_DIR/$HYPERSCAN_SOURCE
    export PATH=$TP_INSTALL_DIR/bin:$PATH
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DBOOST_ROOT=$STARROCKS_THIRDPARTY/installed/include \
          -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc  -DCMAKE_INSTALL_LIBDIR=lib \
          -DBUILD_EXAMPLES=OFF -DBUILD_UNIT=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#mariadb-connector-c
build_mariadb() {
    OLD_CMAKE_GENERATOR=${CMAKE_GENERATOR}
    OLD_BUILD_SYSTEM=${BUILD_SYSTEM}

    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC ${FILE_PREFIX_MAP_OPTION}"

    # force use make build system, since ninja doesn't support install only headers
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'

    check_if_source_exist $MARIADB_SOURCE
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE
    mkdir -p build && cd build

    $CMAKE_CMD .. -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release    \
                  -DWITH_UNIT_TESTS=OFF                                 \
                  -DBUILD_SHARED_LIBS=OFF                               \
                  -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                  \
                  -DOPENSSL_USE_STATIC_LIBS=TRUE                        \
                  -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}
    # we only need build libmariadbclient and headers
    ${BUILD_SYSTEM} -j$PARALLEL mariadbclient
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/libmariadb
    mkdir -p $TP_INSTALL_DIR/lib/mariadb/
    cp libmariadbclient.a $TP_INSTALL_DIR/lib/mariadb/
    # install mariadb headers
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/include
    ${BUILD_SYSTEM} install

    restore_compile_flags
    export CMAKE_GENERATOR=$OLD_CMAKE_GENERATOR
    export BUILD_SYSTEM=$OLD_BUILD_SYSTEM
}

# jindosdk for Aliyun OSS
build_aliyun_jindosdk() {
    check_if_source_exist $JINDOSDK_SOURCE
    mkdir -p $TP_INSTALL_DIR/jindosdk
    cp -r $TP_SOURCE_DIR/$JINDOSDK_SOURCE/lib/*.jar $TP_INSTALL_DIR/jindosdk
}

build_gcs_connector() {
    check_if_source_exist $GCS_CONNECTOR_SOURCE
    mkdir -p $TP_INSTALL_DIR/gcs_connector
    cp -r $TP_SOURCE_DIR/$GCS_CONNECTOR_SOURCE/*.jar $TP_INSTALL_DIR/gcs_connector
}

build_broker_thirdparty_jars() {
    check_if_source_exist $BROKER_THIRDPARTY_JARS_SOURCE
    mkdir -p $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    cp -r $TP_SOURCE_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/* $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/hadoop-aliyun-2.7.2.jar
    # cloudfs-hadoop-with-dependencies will include aws jars, but we already support aws by official sdk, so we don't need it anymore.
    # And it will conflict with Iceberg's S3FileIO, make access S3 files failed.
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/cloudfs-hadoop-with-dependencies-1.1.21.jar
    # ensure read permission is granted for all users
    chmod -R +r $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/
}

build_aws_cpp_sdk() {
    check_if_source_exist $AWS_SDK_CPP_SOURCE
    cd $TP_SOURCE_DIR/$AWS_SDK_CPP_SOURCE
    # only build s3, s3-crt, transfer manager, identity-management and sts, you can add more components if you want.
    $CMAKE_CMD -Bbuild -DBUILD_ONLY="core;s3;s3-crt;transfer;identity-management;sts" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
               -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DENABLE_TESTING=OFF \
               -DENABLE_CURL_LOGGING=OFF \
               -G "${CMAKE_GENERATOR}" \
               -DCURL_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libcurl.a   \
               -DZLIB_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libz.a      \
               -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                     \
               -DOPENSSL_USE_STATIC_LIBS=TRUE                           \
               -Dcrypto_LIBRARY=${TP_INSTALL_DIR}/lib/libcrypto.a

    cd build
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    restore_compile_flags
}

# velocypack
build_vpack() {
    check_if_source_exist $VPACK_SOURCE
    cd $TP_SOURCE_DIR/$VPACK_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# opentelemetry
build_opentelemetry() {
    check_if_source_exist $OPENTELEMETRY_SOURCE

    cd $TP_SOURCE_DIR/$OPENTELEMETRY_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DBUILD_TESTING=OFF -DWITH_EXAMPLES=OFF \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        -DWITH_STL=OFF -DWITH_JAEGER=ON
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# jemalloc
build_jemalloc() {
    check_if_source_exist $JEMALLOC_SOURCE

    cd $TP_SOURCE_DIR/$JEMALLOC_SOURCE
    # jemalloc supports a runtime page size that's smaller or equal to the build
    # time one, but aborts on a larger one. If not defined, it falls back to the
    # the build system's _SC_PAGESIZE, which in many architectures can vary. Set
    # this to 64K (2^16) for arm architecture, and default 4K on x86 for performance.
    local addition_opts=" --with-lg-page=12"
    if [[ $MACHINE_TYPE == "aarch64" ]] ; then
        # change to 64K for arm architecture
        addition_opts=" --with-lg-page=16"
    fi
    # build jemalloc with release
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc --with-jemalloc-prefix=je --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
    # build jemalloc with debug options
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc-debug --with-jemalloc-prefix=je --enable-prof --enable-debug --enable-fill --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
}

# google benchmark
build_benchmark() {
    check_if_source_exist $BENCHMARK_SOURCE
    cd $TP_SOURCE_DIR/$BENCHMARK_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    cmake -DBENCHMARK_DOWNLOAD_DEPENDENCIES=off \
          -DBENCHMARK_ENABLE_GTEST_TESTS=off \
          -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
          -DCMAKE_INSTALL_LIBDIR=lib64 \
          -DCMAKE_BUILD_TYPE=Release ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# fast float
build_fast_float() {
    check_if_source_exist $FAST_FLOAT_SOURCE
    cd $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE
    cp -r $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE/include $TP_INSTALL_DIR
}

build_starcache() {
    check_if_source_exist $STARCACHE_SOURCE
    rm -rf $TP_INSTALL_DIR/$STARCACHE_SOURCE && mv $TP_SOURCE_DIR/$STARCACHE_SOURCE $TP_INSTALL_DIR/
}

# streamvbyte
build_streamvbyte() {
    check_if_source_exist $STREAMVBYTE_SOURCE

    cd $TP_SOURCE_DIR/$STREAMVBYTE_SOURCE/

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/

    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    $CMAKE_CMD .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=$TP_INSTALL_DIR/

    make -j$PARALLEL
    make install
}

# jansson
build_jansson() {
    check_if_source_exist $JANSSON_SOURCE
    cd $TP_SOURCE_DIR/$JANSSON_SOURCE/
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# avro-c
build_avro_c() {
    check_if_source_exist $AVRO_SOURCE
    cd $TP_SOURCE_DIR/$AVRO_SOURCE/lang/c
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    rm ${TP_INSTALL_DIR}/lib64/libavro.so*
}

# serders
build_serdes() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g"
    check_if_source_exist $SERDES_SOURCE
    cd $TP_SOURCE_DIR/$SERDES_SOURCE
    export LIBS="-lrt -lpthread -lcurl -ljansson -lrdkafka -lrdkafka++ -lavro -lssl -lcrypto -ldl"
    ./configure --prefix=${TP_INSTALL_DIR} \
                --libdir=${TP_INSTALL_DIR}/lib \
                --CFLAGS="-I ${TP_INSTALL_DIR}/include"  \
                --CXXFLAGS="-I ${TP_INSTALL_DIR}/include" \
                --LDFLAGS="-L ${TP_INSTALL_DIR}/lib -L ${TP_INSTALL_DIR}/lib64" \
                --enable-static \
                --disable-shared

    make -j$PARALLEL
    make install
    rm ${TP_INSTALL_DIR}/lib/libserdes.so*
    # these symbols also be definition in librdkafka, change these symbols to be local.
    objcopy --localize-symbol=cnd_timedwait ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=cnd_timedwait_ms ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=thrd_is_current ${TP_INSTALL_DIR}/lib/libserdes.a
    unset LIBS
    restore_compile_flags
}

# datasketches
build_datasketches() {
    check_if_source_exist $DATASKETCHES_SOURCE
    mkdir -p $TP_INSTALL_DIR/include/datasketches
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/common/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/cpc/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/fi/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/hll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/kll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/quantiles/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/req/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/sampling/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/theta/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/tuple/include/* $TP_INSTALL_DIR/include/datasketches/
}

# async-profiler
build_async_profiler() {
    check_if_source_exist $ASYNC_PROFILER_SOURCE
    mkdir -p $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/build $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/profiler.sh $TP_INSTALL_DIR/async-profiler
}

# fiu
build_fiu() {
    check_if_source_exist $FIU_SOURCE
    cd $TP_SOURCE_DIR/$FIU_SOURCE
    mkdir -p $TP_SOURCE_DIR/$FIU_SOURCE/installed
    make -j$PARALLEL
    make PREFIX=$TP_SOURCE_DIR/$FIU_SOURCE/installed install

    mkdir -p $TP_INSTALL_DIR/include/fiu
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/include/* $TP_INSTALL_DIR/include/fiu/
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/lib/libfiu.a $TP_INSTALL_DIR/lib/
}

# libdeflate
build_libdeflate() {
    check_if_source_exist $LIBDEFLATE_SOURCE
    mkdir -p $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    cd $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    $CMAKE_CMD .. -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# restore cxxflags/cppflags/cflags to default one
restore_compile_flags() {
    # c preprocessor flags
    export CPPFLAGS=$GLOBAL_CPPFLAGS
    # c flags
    export CFLAGS=$GLOBAL_CFLAGS
    # c++ flags
    export CXXFLAGS=$GLOBAL_CXXFLAGS
}

strip_binary() {
    # strip binary tools and ignore any errors
    echo "Strip binaries in $TP_INSTALL_DIR/bin/ ..."
    strip $TP_INSTALL_DIR/bin/* 2>/dev/null || true
}


# strip `$TP_SOURCE_DIR` and `$TP_INSTALL_DIR` from source code file path
export FILE_PREFIX_MAP_OPTION="-ffile-prefix-map=${TP_SOURCE_DIR}=. -ffile-prefix-map=${TP_INSTALL_DIR}=."
# set GLOBAL_C*FLAGS for easy restore in each sub build process
export GLOBAL_CPPFLAGS="-I ${TP_INCLUDE_DIR}"
# https://stackoverflow.com/questions/42597685/storage-size-of-timespec-isnt-known
export GLOBAL_CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -fPIC -g -D_POSIX_C_SOURCE=200112L -gz=zlib ${FILE_PREFIX_MAP_OPTION}"
export GLOBAL_CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess -fPIC -g -gz=zlib ${FILE_PREFIX_MAP_OPTION}"

# set those GLOBAL_*FLAGS to the CFLAGS/CXXFLAGS/CPPFLAGS
export CPPFLAGS=$GLOBAL_CPPFLAGS
export CXXFLAGS=$GLOBAL_CXXFLAGS
export CFLAGS=$GLOBAL_CFLAGS

build_libevent
build_zlib
build_lz4
build_lzo2
build_bzip
build_openssl
build_boost # must before thrift
build_protobuf
build_gflags
build_gtest
build_glog
build_rapidjson
build_simdjson
build_snappy
build_gperftools
build_curl
build_re2
build_thrift
build_leveldb
build_brpc
build_rocksdb
build_kerberos
build_sasl
build_flatbuffers
build_jemalloc
build_brotli
# must build before arrow
build_arrow
# NOTE: librdkafka depends on ZSTD which is generated by Arrow, So this SHOULD be
# built after arrow
build_librdkafka
build_pulsar
build_s2
build_bitshuffle
build_croaringbitmap
build_cctz
build_fmt
build_ryu
build_hadoop
build_jdk
build_ragel
build_hyperscan
build_mariadb
build_aliyun_jindosdk
build_gcs_connector
build_broker_thirdparty_jars
build_aws_cpp_sdk
build_vpack
build_opentelemetry
build_benchmark
build_fast_float
build_starcache
build_streamvbyte
build_jansson
build_avro_c
build_serdes
build_datasketches
build_async_profiler
build_fiu
build_llvm

if [[ "${MACHINE_TYPE}" != "aarch64" ]]; then
    build_breakpad
    build_libdeflate
fi

# strip unnecessary debug symbol for binaries in thirdparty
strip_binary

echo "Finished to build all thirdparties"

```

等一下，我需要确认一下 breakpad 用的是 autotools 构建系统，configure 后 CXXFLAGS 怎么传递的。让我看看编译命令中的 flags 来确保修改正确：

从终端输出可以看到编译命令中已经有了：`-Werror`，是通过 configure 设置的。`CXXFLAGS` 是在 configure 时传入的，我的改法应该可以。但让我检查一下是否 `${CXXFLAGS}` 已经有值：

可以看到全局 `CXXFLAGS` 已经设置了值（第 1239 行），所以 `${CXXFLAGS} -Wno-nonnull` 会正确地在现有 flags 基础上追加。修改没问题。

## 原因

编译 **breakpad** 的 `src/processor/exploitability_linux.cc` 时，GCC 10 在 `-O3` 优化下分析出 `fclose(objdump_fp)` 中的 `objdump_fp` 在该代码路径上可能为 NULL，而 glibc 的 `fclose` 声明了 `__nonnull((1))` 属性（参数 1 不允许为 NULL），触发了 `-Wnonnull` 警告。加上 breakpad 的编译带有 `-Werror`，警告升级为错误。

## 修复

在 `build_breakpad()` 的 configure 命令中，给 `CXXFLAGS` 追加了 `-Wno-nonnull`，忽略此警告。

重新编译：

```bash
BUILD_TYPE=Debug ./build.sh --be
```

```shellscript
BUILD_TYPE=Debug ./build.sh --be
```

---

**User**

@zsh (990-1019) 

新问题

---

**Cursor**

这次已经到了 **BE 本体的编译阶段**（thirdparty 编译已经通过了！），但 ninja 报找不到 `libbreakpad_client.a`：

```
ninja: error: '/home/peter/my-project/starrocks/thirdparty/installed/lib/libbreakpad_client.a', missing and no known rule to make it
```

说明 breakpad 上一轮因为 `-Wnonnull` 错误编译失败了，虽然我们修了构建脚本，但 breakpad 没有被重新编译安装。让我确认一下：

```plaintext
ninja: error: '/home/peter/my-project/starrocks/thirdparty/installed/lib/libbreakpad_client.a', missing and no known rule to make it
```

确认了，`libbreakpad_client.a` 不存在。需要单独重新编译安装 breakpad。因为 `build.sh --be` 不会重新执行 thirdparty 的构建（thirdparty 只在首次或显式调用时编译），我们需要手动触发 breakpad 的重新编译：

这些文件是 gitignore 的，可能是由 build 过程生成的。让我换个方式，直接在 breakpad 目录下手动重新编译安装：

`libbreakpad_client.a` 已成功编译并安装到 `thirdparty/installed/lib/` 目录下了。

让我解释一下：

## 问题原因

之前编译 thirdparty 时，**breakpad** 这个库因为 GCC 13 的 `-Wnonnull` 警告被当做错误而编译失败了，导致 `libbreakpad_client.a` 没有被生成。虽然后续你改了 `build-thirdparty.sh` 修了其他库的编译问题，但 breakpad 没有被重新编译，它的产物一直缺失。

当 `build.sh --be` 进入 BE 本体编译阶段时，ninja 发现链接需要的 `libbreakpad_client.a` 不存在，所以报错。

## 已完成的修复

我手动重新编译了 breakpad，并添加了 `-Wno-nonnull` 标志来绕过 GCC 13 对 breakpad 代码的警告。现在 `libbreakpad_client.a` 已经生成。

## 下一步

请重新执行 BE 编译：

```bash
BUILD_TYPE=Debug ./build.sh --be
```

这次应该能顺利继续了（thirdparty 不会再重编，直接进入 BE 本体编译）。

```shellscript
BUILD_TYPE=Debug ./build.sh --be
```

---

**User**

@zsh (988-1013) 

还是有问题

---

**Cursor**

又是类似的问题，这次是 `libdeflate.a` 缺失。注意路径是 `lib64` 而不是 `lib`。让我检查一下 thirdparty 中还有哪些库缺失了，一次性全部解决：

`lib64` 存在但没有 `libdeflate.a`。让我看看 deflate 库的编译情况以及 BE 链接需要哪些库：

看到了，`libdeflate` 的编译函数里指定了 `CMAKE_INSTALL_LIBDIR=lib64`，所以它应该被安装到 `lib64` 目录。让我检查 libdeflate 源码是否存在并手动编译：

好，源码存在。但在手动编译这一个之前，我觉得应该检查还有哪些 thirdparty 库可能也缺失了，一次性全部解决，避免反复折腾：

这个方法不太靠谱，让我用更好的方式提取：

现在我有了完整的依赖库列表。让我批量检查哪些还缺失：

太好了！**只缺 `libdeflate.a` 这一个了**，其他所有 thirdparty 库都已就位。让我手动编译安装 libdeflate：

`libdeflate.a` 编译安装成功！而且前面的检查已经确认 **这是最后一个缺失的 thirdparty 库** — 其他所有依赖库都存在。

## 问题原因

和之前 breakpad 一样，`libdeflate` 也是在之前 thirdparty 编译过程中因为某些原因（可能是前面的错误导致后续构建被跳过）没有成功编译安装。由于 `build_libdeflate` 在 `build-thirdparty.sh` 中排在最后面（`build_breakpad` 之后），breakpad 编译失败后脚本就中断了，libdeflate 根本没有被执行到。

## 现在的状态

我已经批量检查了 `build.ninja` 中所有需要的 thirdparty `.a` 文件，**现在全部齐了，没有任何缺失**。

请重新执行 BE 编译：

```bash
BUILD_TYPE=Debug ./build.sh --be
```

这次应该能真正进入 BE C++ 代码的编译了！

```shellscript
BUILD_TYPE=Debug ./build.sh --be
```

---

**User**

刚才wsl好像崩了，如下
@anysphere.remote-wsl.Remote - WSL (1-13) 

内存占比特别高，我给wsl分配了24GB，当时跑到了22.5GB
我关闭cursor后，内存降下来了

我重新连接wsl命令行，能连上去，但是过了一会又崩了好像，如下

➜  starrocks git:(branch-3.2.16-learning) ✗ cursor .
➜  starrocks git:(branch-3.2.16-learning) ✗
[已退出进程，代码为 1 (0x00000001)]
现在可以使用Ctrl+D关闭此终端，或按 Enter 重新启动。

然后cursor也跟着一起崩，我又wsl和重启cursor

我是在wsl命令行里，以cursor .这样的方式来启动cursor的

有什么好解决办法吗？

---

**Cursor**

这是一个很常见的 WSL2 + 大型 C++ 项目编译时的内存问题。让我分析一下原因和解决方案：

## 问题原因

StarRocks BE 编译是一个**极其消耗内存**的过程，尤其是 Debug 模式。每个 C++ 编译进程可能占用 1-3GB 内存，默认情况下 `ninja` 会根据 CPU 核心数启动大量并行编译任务（比如你有 12 核就同时跑 12 个），24GB 内存很容易被瞬间吃满，导致 WSL2 OOM（内存耗尽）崩溃。

## 解决方案

### 方案一：限制编译并行度（最直接有效）

编译时限制并行任务数，比如只用 4 个并行：

```bash
BUILD_TYPE=Debug ./build.sh --be -j 4
```

如果 24GB 还是不够，可以进一步降低到 `-j 2`。

### 方案二：给 WSL2 增加 swap 空间

编辑 Windows 上的 `C:\Users\<你的用户名>\.wslconfig` 文件（不存在就新建），添加：

```ini
[wsl2]
memory=24GB
swap=16GB
```

保存后在 PowerShell 中执行 `wsl --shutdown`，然后重新打开 WSL。这样即使物理内存不够，还有 16GB 的 swap 缓冲。

### 方案三：两者结合（推荐）

既增加 swap，又限制并行度到合理范围：

```ini
[wsl2]
memory=24GB
swap=16GB
```

然后编译用：

```bash
BUILD_TYPE=Debug ./build.sh --be -j 4
```

### 关于 Cursor 连接崩溃

WSL OOM 时整个 WSL 实例会被 kill，所以 Cursor 的远程连接也会断。这不是 Cursor 的 bug，是 WSL2 没内存了。解决了内存问题，Cursor 就不会崩了。

### 额外建议

1. **编译时先不要打开 Cursor**，在普通 WSL 终端里编译完再用 `cursor .` 打开。Cursor 的 Language Server（clangd 等）本身也很吃内存，编译期间同时跑会雪上加霜。

2. **编译完成后再打开 Cursor**，这样 Cursor 做代码索引时不会和编译抢内存。

3. 如果你想监控内存使用情况，编译时可以在另一个终端跑：

```bash
watch -n 1 free -h
```

---

**总结：先配置 `.wslconfig` 加 swap，编译用 `-j 4`，编译期间不开 Cursor，编完再开。** 这样基本不会再 OOM 崩溃了。

```shellscript
BUILD_TYPE=Debug ./build.sh --be -j 4
```

```ini
[wsl2]
memory=24GB
swap=16GB
```

```ini
[wsl2]
memory=24GB
swap=16GB
```

```shellscript
BUILD_TYPE=Debug ./build.sh --be -j 4
```

```shellscript
watch -n 1 free -h
```

---

**User**

行，我一会关了cursor，在命令行里执行编译，并且限制并发数，提高内存

请问怎么在wsl命令行里查看分配了多少内存，验证我配置成功了

---

**Cursor**

在 WSL 里执行以下命令就可以查看：

```bash
# 查看总内存和 swap
free -h
```

输出类似这样：

```
              total        used        free      shared  buff/cache   available
Mem:           24Gi        2Gi       20Gi       ...       ...         21Gi
Swap:          16Gi        0Bi       16Gi
```

- **Mem total** 对应你 `.wslconfig` 里的 `memory=24GB`
- **Swap total** 对应你 `.wslconfig` 里的 `swap=16GB`

如果看到数值和你配置的一致，就说明生效了。

**注意：** 修改 `.wslconfig` 后必须在 Windows PowerShell 里执行 `wsl --shutdown`，然后重新进入 WSL 才会生效。

```shellscript
# 查看总内存和 swap
free -h
```

```plaintext
              total        used        free      shared  buff/cache   available
Mem:           24Gi        2Gi       20Gi       ...       ...         21Gi
Swap:          16Gi        0Bi       16Gi
```

---

**User**

已经重新设置了内存，编译后，又遇到新问题

➜  starrocks git:(branch-3.2.16-learning) ✗ BUILD_TYPE=Debug ./build.sh --be -j 4
Found python3, version: Python 3.12.3
Apache Maven 3.8.7
Maven home: /usr/share/maven
Java version: 17.0.18, vendor: Ubuntu, runtime: /usr/lib/jvm/java-17-openjdk-amd64
Default locale: en, platform encoding: UTF-8
OS name: "linux", version: "6.6.87.2-microsoft-standard-wsl2", arch: "amd64", family: "unix"
1.11.1
Get params:
    BUILD_BE            -- 1
    BE_CMAKE_TYPE       -- Debug
    BUILD_FE            -- 0
    BUILD_SPARK_DPP     -- 0
    BUILD_HIVE_UDF      -- 0
    CCACHE              -- ccache
    CLEAN               -- 0
    RUN_UT              -- 0
    WITH_GCOV           -- OFF
    WITH_BENCH          -- OFF
    WITH_CLANG_TIDY     -- OFF
    WITH_COMPRESS_DEBUG_SYMBOL  -- ON
    WITH_STARCACHE      -- ON
    ENABLE_SHARED_DATA  -- OFF
    USE_AVX2            -- ON
    USE_AVX512          -- OFF
    USE_SSE4_2          -- ON
    JEMALLOC_DEBUG      -- OFF
    PARALLEL            -- 4
    ENABLE_QUERY_DEBUG_TRACE -- OFF
    ENABLE_FAULT_INJECTION -- OFF
    BUILD_JAVA_EXT      -- ON
    WITH_RELATIVE_SRC_PATH      -- ON
    WITH_MAVEN_BATCH_MODE       -- OFF

Build generated code
make -C script
make[1]: Entering directory '/home/peter/my-project/starrocks/gensrc/script'
python3 /home/peter/my-project/starrocks/gensrc/script/../../build-support/gen_build_version.py --cpp /home/peter/my-project/starrocks/gensrc/script/../build//gen_cpp --java /home/peter/my-project/starrocks/gensrc/script/../../fe/fe-core/target/generated-sources/build
gen_build_version.py /home/peter/my-project/starrocks/gensrc/script/../build//gen_cpp/version.cpp: old fingerprint = 4b84c0627b16d0c10468e878744137a2, new fingerprint = 4b84c0627b16d0c10468e878744137a2
gen_build_version.py /home/peter/my-project/starrocks/gensrc/script/../../fe/fe-core/target/generated-sources/build/com/starrocks/common/Version.java: old fingerprint = 701b03f3cebd4709a25fd9f1820cda47, new fingerprint = 701b03f3cebd4709a25fd9f1820cda47
make[1]: Leaving directory '/home/peter/my-project/starrocks/gensrc/script'
make -C proto
make[1]: Entering directory '/home/peter/my-project/starrocks/gensrc/proto'
make[1]: Nothing to be done for 'all'.
make[1]: Leaving directory '/home/peter/my-project/starrocks/gensrc/proto'
make -C thrift
make[1]: Entering directory '/home/peter/my-project/starrocks/gensrc/thrift'
make[1]: Nothing to be done for 'all'.
make[1]: Leaving directory '/home/peter/my-project/starrocks/gensrc/thrift'
cmake version 3.28.3

CMake suite maintained and supported by Kitware (kitware.com/cmake).
Build Backend: Debug
-- Build type is DEBUG
-- Build target arch is x86_64
-- make test: OFF
-- GCC version 10.5.0 is greater than 10.3.0, disable -Werror. Be careful with compile warnings.
-- defined PIC_LIB_PATH
-- build gensrc if necessary
make: Entering directory '/home/peter/my-project/starrocks/gensrc'
make -C script
make[1]: Entering directory '/home/peter/my-project/starrocks/gensrc/script'
python3 /home/peter/my-project/starrocks/gensrc/script/../../build-support/gen_build_version.py --cpp /home/peter/my-project/starrocks/gensrc/script/../build//gen_cpp --java /home/peter/my-project/starrocks/gensrc/script/../../fe/fe-core/target/generated-sources/build
gen_build_version.py /home/peter/my-project/starrocks/gensrc/script/../build//gen_cpp/version.cpp: old fingerprint = 4b84c0627b16d0c10468e878744137a2, new fingerprint = 4b84c0627b16d0c10468e878744137a2
gen_build_version.py /home/peter/my-project/starrocks/gensrc/script/../../fe/fe-core/target/generated-sources/build/com/starrocks/common/Version.java: old fingerprint = 701b03f3cebd4709a25fd9f1820cda47, new fingerprint = 701b03f3cebd4709a25fd9f1820cda47
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
-- /home/peter/my-project/starrocks/thirdparty/installed/lib/libboost_thread.a/home/peter/my-project/starrocks/thirdparty/installed/lib/libboost_regex.a/home/peter/my-project/starrocks/thirdparty/installed/lib/libboost_program_options.a/home/peter/my-project/starrocks/thirdparty/installed/lib/libboost_filesystem.a/home/peter/my-project/starrocks/thirdparty/installed/lib/libboost_context.a/home/peter/my-project/starrocks/thirdparty/installed/lib/libboost_chrono.a/home/peter/my-project/starrocks/thirdparty/installed/lib/libboost_atomic.a
-- Using OpenSSL Root Dir: /home/peter/my-project/starrocks/thirdparty/installed/
-- Found AWS SDK for C++, Version: 1.11.267, Install Root:/home/peter/my-project/starrocks/thirdparty/installed, Platform Prefix:, Platform Dependent Libraries: pthread;crypto;ssl;z;curl
-- Components specified for AWSSDK: core;s3;s3-crt;transfer;identity-management;sts, application will be depending on libs: aws-cpp-sdk-s3-crt;aws-cpp-sdk-transfer;aws-cpp-sdk-identity-management;aws-cpp-sdk-cognito-identity;aws-cpp-sdk-sts;aws-cpp-sdk-s3;aws-cpp-sdk-core;aws-crt-cpp;aws-c-auth;aws-c-cal;aws-c-common;aws-c-compression;aws-c-event-stream;aws-c-http;aws-c-io;aws-c-mqtt;aws-c-s3;aws-checksums;aws-c-sdkutils;pthread;crypto;ssl;z;curl
-- Try finding aws-cpp-sdk-core
-- S2N found target: crypto
-- crypto Include Dir: crypto_INCLUDE_DIR-NOTFOUND
-- Found aws-cpp-sdk-core
-- Try finding aws-cpp-sdk-s3
-- Found aws-cpp-sdk-s3
-- Try finding aws-cpp-sdk-sts
-- Found aws-cpp-sdk-sts
-- Try finding aws-cpp-sdk-cognito-identity
-- Found aws-cpp-sdk-cognito-identity
-- Try finding aws-cpp-sdk-identity-management
-- Found aws-cpp-sdk-identity-management
-- Try finding aws-cpp-sdk-transfer
-- Found aws-cpp-sdk-transfer
-- Try finding aws-cpp-sdk-s3-crt
-- Found aws-cpp-sdk-s3-crt
-- link the starcache in directory: /home/peter/my-project/starrocks/thirdparty/installed//starcache
-- Compiler Flags:   -Wall -Wno-sign-compare -Wno-unknown-pragmas -pthread -Wno-register -Wno-strict-aliasing -fno-omit-frame-pointer -std=gnu++20 -D__STDC_FORMAT_MACROS -Wno-deprecated -Wno-vla -Wno-comment -ffile-prefix-map=/home/peter/my-project/starrocks/be=be -fno-sized-deallocation -DBOOST_DATE_TIME_POSIX_TIME_STD_CONFIG -DBOOST_SYSTEM_NO_DEPRECATED -DBOOST_UUID_RANDOM_PROVIDER_FORCE_POSIX -Werror=return-type -Werror=switch -DWITH_STARCACHE -msse4.2 -mavx2  -Wno-attributes -DS2_USE_GFLAGS -DS2_USE_GLOG -faligned-new -gz=zlib  -fcoroutines -g -Wno-unused-local-typedefs -ggdb -O0 -gdwarf-4 -DDEBUG
use jemalloc
CMake Deprecation Warning at src/formats/orc/apache-orc/CMakeLists.txt:15 (cmake_minimum_required):
  Compatibility with CMake < 3.5 will be removed from a future version of
  CMake.

  Update the VERSION argument <min> value or use a ...<max> suffix to tell
  CMake that the project does not need compatibility with older versions.


++++ <STARROCKS_HOME> is set. formats/orc/apache-orc is compiled in StarRocks env ++++
-- Build type: DEBUG
-- compiler GNU version 10.5.0
-- SNAPPY_HOME: /home/peter/my-project/starrocks/thirdparty/installed
-- Found the Snappy header: /home/peter/my-project/starrocks/thirdparty/installed/include/snappy.h
-- Found the Snappy library: /home/peter/my-project/starrocks/thirdparty/installed/lib/libsnappy.a
-- ZLIB_HOME: /home/peter/my-project/starrocks/thirdparty/installed
-- Found the ZLIB header: /home/peter/my-project/starrocks/thirdparty/installed/include/zlib.h
-- Found the ZLIB library: /home/peter/my-project/starrocks/thirdparty/installed/lib/libz.a
-- Found the ZLIB static library: /home/peter/my-project/starrocks/thirdparty/installed/lib/libz.a
-- ZSTD_HOME: /home/peter/my-project/starrocks/thirdparty/installed
-- Found the zstd header: /home/peter/my-project/starrocks/thirdparty/installed/include/zstd/zstd.h
-- Found the zstd library: /home/peter/my-project/starrocks/thirdparty/installed/lib
-- LZ4_HOME: /home/peter/my-project/starrocks/thirdparty/installed
-- Found the LZ4 header: /home/peter/my-project/starrocks/thirdparty/installed/include/lz4/lz4.h
-- Found the LZ4 library: /home/peter/my-project/starrocks/thirdparty/installed/lib
-- PROTOBUF_HOME: /home/peter/my-project/starrocks/thirdparty/installed
-- Found the Protobuf headers: /home/peter/my-project/starrocks/thirdparty/installed/include
-- Found the Protobuf library: /home/peter/my-project/starrocks/thirdparty/installed/lib/libprotobuf.a
-- Found the Protoc library: /home/peter/my-project/starrocks/thirdparty/installed/lib/libprotoc.a
-- Found the Protoc executable: /home/peter/my-project/starrocks/thirdparty/installed/bin/protoc
-- Found the Protobuf static library: /home/peter/my-project/starrocks/thirdparty/installed/lib/libprotobuf.a
-- Found the Protoc static library: /home/peter/my-project/starrocks/thirdparty/installed/lib/libprotoc.a
CMake Deprecation Warning at src/exec/CMakeLists.txt:15 (cmake_minimum_required):
  Compatibility with CMake < 3.5 will be removed from a future version of
  CMake.

  Update the VERSION argument <min> value or use a ...<max> suffix to tell
  CMake that the project does not need compatibility with older versions.


-- Configuring done (0.9s)
-- Generating done (0.1s)
-- Build files have been written to: /home/peter/my-project/starrocks/be/build_Debug
[1/1] Linking CXX executable /home/peter/my-project/starrocks/be/output/lib/starrocks_be
FAILED: /home/peter/my-project/starrocks/be/output/lib/starrocks_be
: && /usr/bin/../bin/g++ -Wall -Wno-sign-compare -Wno-unknown-pragmas -pthread -Wno-register -Wno-strict-aliasing -fno-omit-frame-pointer -std=gnu++20 -D__STDC_FORMAT_MACROS -Wno-deprecated -Wno-vla -Wno-comment -ffile-prefix-map=/home/peter/my-project/starrocks/be=be -fno-sized-deallocation -DBOOST_DATE_TIME_POSIX_TIME_STD_CONFIG -DBOOST_SYSTEM_NO_DEPRECATED -DBOOST_UUID_RANDOM_PROVIDER_FORCE_POSIX -Werror=return-type -Werror=switch -DWITH_STARCACHE -msse4.2 -mavx2  -Wno-attributes -DS2_USE_GFLAGS -DS2_USE_GLOG -faligned-new -gz=zlib  -fcoroutines -g -Wno-unused-local-typedefs -ggdb -O0 -gdwarf-4 -DDEBUG -g -no-pie CMakeFiles/build_version.dir/build_version.cc.o src/service/CMakeFiles/starrocks_be.dir/starrocks_main.cpp.o -o /home/peter/my-project/starrocks/be/output/lib/starrocks_be -L/home/peter/my-project/starrocks/thirdparty/installed/lib   -L/home/peter/my-project/starrocks/thirdparty/installed/lib64 -Wl,--start-group  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libAgent.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libCommon.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libColumn.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libConnector.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libExec.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libExprs.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libFileSystem.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libFormats.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libGutil.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libIO.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libSerde.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libStorage.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libRowset.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libRuntime.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libService.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libServiceBE.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libTypes.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libUdf.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libUtil.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libScript.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libStarRocksGen.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libWebserver.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libTestUtil.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libTools.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libGeo.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/libBlockCache.a  -Wl,--end-group  /home/peter/my-project/starrocks/thirdparty/installed//lib/mariadb/libmariadbclient.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libhdfs.a  /home/peter/my-project/starrocks/thirdparty/installed//open_jdk//jre/lib/amd64/server/libjvm.so  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-cpp-sdk-s3-crt.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-cpp-sdk-transfer.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-cpp-sdk-identity-management.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-cpp-sdk-cognito-identity.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-cpp-sdk-sts.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-cpp-sdk-s3.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-cpp-sdk-core.a  -Wl,--start-group  /home/peter/my-project/starrocks/thirdparty/installed//lib/librocksdb.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libs2.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libsnappy.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libboost_thread.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libboost_regex.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libboost_program_options.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libboost_filesystem.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libboost_context.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libboost_chrono.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libboost_atomic.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libthrift.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libthriftnb.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libglog.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libre2.a  /home/peter/my-project/starrocks/thirdparty/installed//gperftools/lib/libprofiler.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/liblz4.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libevent.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libcurl.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libz.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libbz2.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libgflags.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libbrpc.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libprotobuf.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libssl.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libcrypto.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libleveldb.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libbitshuffle.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libroaring.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libbrotlicommon.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libbrotlidec.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libbrotlienc.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libzstd.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libstreamvbyte_static.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libarrow.a  /home/peter/my-project/starrocks/thirdparty/installed//jemalloc/lib/libjemalloc_pic.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libparquet.a  /home/peter/my-project/starrocks/be/output/tmp/DEBUG/liborc.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libcctz.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libfmt.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libryu.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libhs.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libsimdjson.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libsasl2.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libgssapi_krb5.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libkrb5.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libkrb5support.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libk5crypto.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libcom_err.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/librdkafka++.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/librdkafka.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libpulsar.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libvelocypack.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libopentelemetry_trace.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libhttp_client_curl.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libopentelemetry_resources.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libopentelemetry_common.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libopentelemetry_exporter_jaeger_trace.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libjansson.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libavro.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libserdes.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libfiu.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMRuntimeDyld.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMBitstreamReader.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMOption.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMAsmPrinter.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMProfileData.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMAsmParser.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMOrcTargetProcess.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMExecutionEngine.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMBinaryFormat.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMDebugInfoDWARF.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMObjCARCOpts.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMCodeGen.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMMCDisassembler.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMSupport.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMJITLink.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMCFGuard.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMInstrumentation.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMIRReader.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMCore.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMTarget.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMMC.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMAnalysis.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMGlobalISel.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMScalarOpts.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMTargetParser.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMDemangle.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMRemarks.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMDebugInfoCodeView.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMOrcShared.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMOrcJIT.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMTextAPI.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMBitWriter.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMBitReader.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMObject.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMTransformUtils.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMSelectionDAG.a  /home/peter/my-project/starrocks/thirdparty/installed//llvm/lib/libLLVMMCParser.a  -Wl,--end-group  -Wl,--start-group  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libbrpc.a  /home/peter/my-project/starrocks/thirdparty/installed//starcache/lib/libstarcache.a  -Wl,--end-group  /home/peter/my-project/starrocks/thirdparty/installed//lib/libbreakpad_client.a  /home/peter/my-project/starrocks/thirdparty/installed//lib64/libdeflate.a  -static-libstdc++  -static-libgcc  -lresolv  /home/peter/my-project/starrocks/thirdparty/installed//jemalloc/lib/libjemalloc_pic.a  -Wl,-Bstatic  -lbfd  -Wl,-Bdynamic  -liberty  -lc  -lm  -ldl  -rdynamic  -pthread  -Wl,-wrap=__cxa_throw  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-crt-cpp.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-c-mqtt.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-c-event-stream.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-c-s3.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-c-auth.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-c-http.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-c-io.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libs2n.a  /home/peter/my-project/starrocks/thirdparty/installed//lib/libcrypto.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-c-compression.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-c-cal.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libcrypto.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-c-sdkutils.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-checksums.a  /home/peter/my-project/starrocks/thirdparty/installed/lib/libaws-c-common.a  -ldl  -lm  -lrt  -lpthread && :
/usr/bin/ld: /usr/lib/gcc/x86_64-linux-gnu/10/../../../x86_64-linux-gnu/libbfd.a(elfxx-x86.o): in function `_bfd_x86_elf_write_sframe_plt':
./builddir-single/bfd/../../bfd/elfxx-x86.c:1985:(.text+0xb09): undefined reference to `sframe_encoder_write'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1991:(.text+0xb3d): undefined reference to `sframe_encoder_free'
/usr/bin/ld: /usr/lib/gcc/x86_64-linux-gnu/10/../../../x86_64-linux-gnu/libbfd.a(elfxx-x86.o): in function `_bfd_x86_elf_create_sframe_plt':
./builddir-single/bfd/../../bfd/elfxx-x86.c:1880:(.text+0xc48): undefined reference to `sframe_encode'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1888:(.text+0xc59): undefined reference to `sframe_calc_fre_type'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1889:(.text+0xc64): undefined reference to `sframe_fde_create_func_info'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1897:(.text+0xc7e): undefined reference to `sframe_encoder_add_funcdesc_v2'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1908:(.text+0xcc4): undefined reference to `sframe_encoder_add_fre'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1880:(.text+0xd27): undefined reference to `sframe_encode'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1888:(.text+0xd38): undefined reference to `sframe_calc_fre_type'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1889:(.text+0xd43): undefined reference to `sframe_fde_create_func_info'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1880:(.text+0xdb1): undefined reference to `sframe_encode'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1888:(.text+0xdc2): undefined reference to `sframe_calc_fre_type'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1889:(.text+0xdcd): undefined reference to `sframe_fde_create_func_info'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1920:(.text+0xdeb): undefined reference to `sframe_fde_create_func_info'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1926:(.text+0xe0b): undefined reference to `sframe_encoder_add_funcdesc_v2'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1939:(.text+0xe4f): undefined reference to `sframe_encoder_add_fre'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elfxx-x86.c:1880:(.text+0xea7): undefined reference to `sframe_encode'
/usr/bin/ld: /usr/lib/gcc/x86_64-linux-gnu/10/../../../x86_64-linux-gnu/libbfd.a(elf-sframe.o): in function `_bfd_elf_parse_sframe':
./builddir-single/bfd/../../bfd/elf-sframe.c:220:(.text+0x102): undefined reference to `sframe_decode'
/usr/bin/ld: /usr/lib/gcc/x86_64-linux-gnu/10/../../../x86_64-linux-gnu/libbfd.a(elf-sframe.o): in function `sframe_decoder_init_func_bfdinfo':
./builddir-single/bfd/../../bfd/elf-sframe.c:107:(.text+0x11a): undefined reference to `sframe_decoder_get_num_fidx'
/usr/bin/ld: /usr/lib/gcc/x86_64-linux-gnu/10/../../../x86_64-linux-gnu/libbfd.a(elf-sframe.o): in function `_bfd_elf_parse_sframe':
./builddir-single/bfd/../../bfd/elf-sframe.c:229:(.text+0x21d): undefined reference to `sframe_decoder_free'
/usr/bin/ld: /usr/lib/gcc/x86_64-linux-gnu/10/../../../x86_64-linux-gnu/libbfd.a(elf-sframe.o): in function `_bfd_elf_discard_section_sframe':
./builddir-single/bfd/../../bfd/elf-sframe.c:278:(.text+0x2fe): undefined reference to `sframe_decoder_get_num_fidx'
/usr/bin/ld: /usr/lib/gcc/x86_64-linux-gnu/10/../../../x86_64-linux-gnu/libbfd.a(elf-sframe.o): in function `_bfd_elf_merge_section_sframe':
./builddir-single/bfd/../../bfd/elf-sframe.c:396:(.text+0x555): undefined reference to `sframe_decoder_get_abi_arch'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:397:(.text+0x55f): undefined reference to `sframe_encoder_get_abi_arch'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:406:(.text+0x57c): undefined reference to `sframe_decoder_get_version'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:407:(.text+0x586): undefined reference to `sframe_encoder_get_version'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:422:(.text+0x5a4): undefined reference to `sframe_decoder_get_num_fidx'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:423:(.text+0x5b4): undefined reference to `sframe_encoder_get_num_fidx'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:437:(.text+0x65b): undefined reference to `sframe_decoder_get_funcdesc_v2'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:468:(.text+0x6ae): undefined reference to `sframe_decoder_get_hdr_size'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:494:(.text+0x739): undefined reference to `sframe_encoder_add_funcdesc_v2'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:504:(.text+0x76f): undefined reference to `sframe_decoder_get_fre'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:506:(.text+0x787): undefined reference to `sframe_encoder_add_fre'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:514:(.text+0x7cc): undefined reference to `sframe_decoder_free'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:358:(.text+0x9db): undefined reference to `sframe_decoder_get_abi_arch'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:359:(.text+0x9e7): undefined reference to `sframe_decoder_get_fixed_fp_offset'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:360:(.text+0x9f2): undefined reference to `sframe_decoder_get_fixed_ra_offset'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:366:(.text+0xa16): undefined reference to `sframe_encode'
/usr/bin/ld: /usr/lib/gcc/x86_64-linux-gnu/10/../../../x86_64-linux-gnu/libbfd.a(elf-sframe.o): in function `_bfd_elf_write_section_sframe':
./builddir-single/bfd/../../bfd/elf-sframe.c:544:(.text+0xae8): undefined reference to `sframe_encoder_write'
/usr/bin/ld: ./builddir-single/bfd/../../bfd/elf-sframe.c:559:(.text+0xb15): undefined reference to `sframe_encoder_free'
collect2: error: ld returned 1 exit status
ninja: build stopped: subcommand failed.

real    1m36.386s
user    0m48.941s
sys     0m39.656s

---

**Cursor**

这个错误是链接阶段的问题。系统的 `libbfd.a`（来自 Ubuntu 24.04 的 binutils）引用了 `sframe_*` 系列函数，但链接时没有找到对应的 `libsframe` 库。

**根本原因：** Ubuntu 24.04 的 binutils 版本较新（2.42），它的 `libbfd.a` 依赖 `libsframe`。而 StarRocks 的链接命令中通过 `-Wl,-Bstatic -lbfd` 静态链接了 `libbfd`，但没有同时链接 `libsframe`。

让我先看一下 CMake 中是怎么配置这个链接的：

好的，`libsframe.a` 确实存在于系统中。问题很明确：Ubuntu 24.04 的 `libbfd.a` (binutils 2.42) 新增了对 `libsframe` 的依赖，但 StarRocks 的 CMakeLists.txt 没有链接它。

我来修复 `be/CMakeLists.txt`，在 `-lbfd` 后面加上 `-lsframe`：

```plaintext
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

cmake_minimum_required(VERSION 3.11.1)

# set CMAKE_C_COMPILER, this must set before project command
if (DEFINED ENV{CC} AND DEFINED ENV{CXX})
    set(CMAKE_C_COMPILER "$ENV{CC}")
    set(CMAKE_CXX_COMPILER "$ENV{CXX}")
elseif (DEFINED ENV{STARROCKS_GCC_HOME})
    # prefer GCC
    set(CMAKE_C_COMPILER "$ENV{STARROCKS_GCC_HOME}/bin/gcc")
    set(CMAKE_CXX_COMPILER "$ENV{STARROCKS_GCC_HOME}/bin/g++")
elseif (DEFINED ENV{STARROCKS_LLVM_HOME})
    set(CMAKE_C_COMPILER "$ENV{STARROCKS_LLVM_HOME}/bin/clang")
    set(CMAKE_CXX_COMPILER "$ENV{STARROCKS_LLVM_HOME}/bin/clang++")
else()
    message(FATAL_ERROR "STARROCKS_GCC_HOME environment variable is not set")
endif()

# disable pkgconfig searching libraries, all libraries are static imported
set(CMAKE_DISABLE_FIND_PACKAGE_PkgConfig ON)
# Workaround error of `Unknown CMake command "pkg_check_modules".'`
# refer to: https://gitlab.kitware.com/cmake/cmake/-/issues/17043
macro( pkg_check_modules )
endmacro()

project(starrocks CXX C)

# set CMAKE_BUILD_TYPE
if (NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE RELEASE)
endif()

string(TOUPPER ${CMAKE_BUILD_TYPE} CMAKE_BUILD_TYPE)
message(STATUS "Build type is ${CMAKE_BUILD_TYPE}")

# set CMAKE_BUILD_TARGET_ARCH
# use `lscpu | grep 'Architecture' | awk '{print $2}'` only support system which language is en_US.UTF-8
execute_process(COMMAND bash "-c" "uname -m"
                OUTPUT_VARIABLE
                CMAKE_BUILD_TARGET_ARCH
                OUTPUT_STRIP_TRAILING_WHITESPACE)
message(STATUS "Build target arch is ${CMAKE_BUILD_TARGET_ARCH}")

# Set dirs
set(BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(RELATIVE_BASE_DIR "be")
set(FILE_PREFIX_MAP_FLAG "-ffile-prefix-map=${BASE_DIR}=${RELATIVE_BASE_DIR}")
set(BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}")
set(THIRDPARTY_DIR "$ENV{STARROCKS_THIRDPARTY}/installed/")
set(STARROCKS_THIRDPARTY "$ENV{STARROCKS_THIRDPARTY}")
set(SRC_DIR "${BASE_DIR}/src")
set(GENSRC_DIR "${SRC_DIR}/gen_cpp/build")
set(TEST_DIR "${CMAKE_SOURCE_DIR}/test/")
set(OUTPUT_DIR "${BASE_DIR}/output")
set(CONTRIB_DIR "${BASE_DIR}/../contrib/")
set(CMAKE_EXPORT_COMPILECOMMANDS ON)

if (APPLE)
    set(MAKE_TEST "ON")
else()
    option(MAKE_TEST "ON for make unit test or OFF for not" OFF)
endif()
message(STATUS "make test: ${MAKE_TEST}")

option(WITH_GCOV "Build binary with gcov to get code coverage" OFF)

option(WITH_COMPRESS "Build binary with compresss debug section" ON)

option(WITH_CACHELIB "Build binary with cachelib library" OFF)

option(WITH_STARCACHE "Build binary with starcache library" ON)

option(WITH_BENCH "Build binary with bench" OFF)

option(USE_STAROS "Use StarOS to manager tablet info" OFF)

option(USE_SSE4_2 "Build with SSE4.2 instruction" ON)

option(USE_AVX2 "Build with AVX2 instruction" ON)

option(USE_AVX512 "Build with AVX512f/AVX512BW instruction" OFF)

option(WITH_RELATIVE_SRC_PATH "Build source file with relative path" ON)

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
elseif (CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
elseif (NOT APPLE)
    message(FATAL_ERROR "Compiler should be GNU")
endif()

set(PIC_LIB_PATH "${THIRDPARTY_DIR}")
if(PIC_LIB_PATH)
    message(STATUS "defined PIC_LIB_PATH")
    set(CMAKE_SKIP_RPATH TRUE)
    set(Boost_USE_STATIC_LIBS ON)
    set(Boost_USE_STATIC_RUNTIME ON)
    set(LIBBZ2 ${PIC_LIB_PATH}/lib/libbz2.a)
    set(LIBZ ${PIC_LIB_PATH}/lib/libz.a)
    set(LIBEVENT ${PIC_LIB_PATH}/lib/libevent.a)
else()
    message(STATUS "undefined PIC_LIB_PATH")
    set(Boost_USE_STATIC_LIBS ON)
    set(Boost_USE_STATIC_RUNTIME ON)
    set(LIBBZ2 -lbz2)
    set(LIBZ -lz)
    set(LIBEVENT event)
endif()


# Compile generated source if necessary
message(STATUS "build gensrc if necessary")
execute_process(COMMAND make -C ${BASE_DIR}/../gensrc/
                RESULT_VARIABLE MAKE_GENSRC_RESULT)
if(NOT ${MAKE_GENSRC_RESULT} EQUAL 0 AND NOT APPLE)
    message(FATAL_ERROR "Failed to build ${BASE_DIR}/../gensrc/")
endif()

#
set(BUILD_VERSION_CC ${CMAKE_BINARY_DIR}/build_version.cc)
configure_file(${SRC_DIR}/common/build_version.cc.in ${BUILD_VERSION_CC} @ONLY)
add_library(build_version OBJECT ${BUILD_VERSION_CC})
target_include_directories(build_version PRIVATE ${SRC_DIR}/common)

# Add common cmake prefix path and link library path
list(APPEND CMAKE_PREFIX_PATH ${THIRDPARTY_DIR}/lib/cmake)
list(APPEND CMAKE_PREFIX_PATH ${THIRDPARTY_DIR}/lib64/cmake)
link_directories(${THIRDPARTY_DIR}/lib ${THIRDPARTY_DIR}/lib64)

# Set Boost
set(Boost_DEBUG FALSE)
set(Boost_USE_MULTITHREADED ON)
set(Boost_NO_BOOST_CMAKE ON)
set(BOOST_ROOT ${THIRDPARTY_DIR})
# boost suppress warning is supported on cmake 3.20
# https://cmake.org/cmake/help/latest/module/FindBoost.html
set(Boost_NO_WARN_NEW_VERSIONS ON)

if (NOT APPLE)
    find_package(Boost 1.80.0 REQUIRED COMPONENTS thread regex program_options filesystem context)
else()
    find_package(Boost 1.80.0 COMPONENTS thread regex program_options filesystem context)
endif()
include_directories(${Boost_INCLUDE_DIRS})
message(STATUS ${Boost_LIBRARIES})

set(GPERFTOOLS_HOME "${THIRDPARTY_DIR}/gperftools")
set(JEMALLOC_HOME "${THIRDPARTY_DIR}/jemalloc")

if (${JEMALLOC_DEBUG})
    set(JEMALLOC_HOME "${THIRDPARTY_DIR}/jemalloc-debug")
endif()

# Set all libraries

add_library(gflags STATIC IMPORTED GLOBAL)
set_target_properties(gflags PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libgflags.a)

add_library(glog STATIC IMPORTED GLOBAL)
set_target_properties(glog PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libglog.a)

add_library(re2 STATIC IMPORTED GLOBAL)
set_target_properties(re2 PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libre2.a)

add_library(pprof STATIC IMPORTED)
set_target_properties(pprof PROPERTIES IMPORTED_LOCATION
    ${GPERFTOOLS_HOME}/lib/libprofiler.a)

add_library(tcmalloc STATIC IMPORTED)
set_target_properties(tcmalloc PROPERTIES IMPORTED_LOCATION
    ${GPERFTOOLS_HOME}/lib/libtcmalloc.a)

add_library(protobuf STATIC IMPORTED GLOBAL)
set_target_properties(protobuf PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libprotobuf.a)

add_library(protoc STATIC IMPORTED)
set_target_properties(protoc PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libprotoc.a)

add_library(gtest STATIC IMPORTED)
set_target_properties(gtest PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libgtest.a)

add_library(gmock STATIC IMPORTED)
set_target_properties(gmock PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libgmock.a)

add_library(snappy STATIC IMPORTED GLOBAL)
set_target_properties(snappy PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libsnappy.a)

set(CURL_INCLUDE_DIR "${THIRDPARTY_DIR}/include" CACHE PATH "curl include path")
set(CURL_LIBRARY "${THIRDPARTY_DIR}/lib/libcurl.a" CACHE FILEPATH "curl static library")
add_library(curl STATIC IMPORTED GLOBAL)
set_target_properties(curl PROPERTIES IMPORTED_LOCATION ${CURL_LIBRARY})

add_library(lz4 STATIC IMPORTED)
set_target_properties(lz4 PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/liblz4.a)

add_library(thrift STATIC IMPORTED)
set_target_properties(thrift PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libthrift.a)

add_library(thriftnb STATIC IMPORTED)
set_target_properties(thriftnb PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libthriftnb.a)

add_library(mysql STATIC IMPORTED)
set_target_properties(mysql PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/mariadb/libmariadbclient.a)

add_library(hdfs STATIC IMPORTED GLOBAL)
set_target_properties(hdfs PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libhdfs.a)

add_library(fiu STATIC IMPORTED)
set_target_properties(fiu PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libfiu.a)

# Allow FindOpenSSL() to find correct static libraries
set(OPENSSL_ROOT_DIR ${THIRDPARTY_DIR} CACHE STRING "root directory of an OpenSSL installation")
message(STATUS "Using OpenSSL Root Dir: ${OPENSSL_ROOT_DIR}")
add_library(crypto STATIC IMPORTED GLOBAL)
set_target_properties(crypto PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libcrypto.a)

add_library(AWS::crypto ALIAS crypto)
set(AWSSDK_ROOT_DIR ${THIRDPARTY_DIR})
set(AWSSDK_COMMON_RUNTIME_LIBS "aws-crt-cpp;aws-c-auth;aws-c-cal;aws-c-common;aws-c-compression;aws-c-event-stream;aws-c-http;aws-c-io;aws-c-mqtt;aws-c-s3;aws-checksums;s2n;aws-c-sdkutils")
foreach(lib IN ITEMS ${AWSSDK_COMMON_RUNTIME_LIBS})
    list(APPEND CMAKE_PREFIX_PATH ${THIRDPARTY_DIR}/lib/${lib}/cmake)
    list(APPEND CMAKE_PREFIX_PATH ${THIRDPARTY_DIR}/lib64/${lib}/cmake)
endforeach()
find_package(AWSSDK REQUIRED COMPONENTS core s3 s3-crt transfer identity-management sts)
include_directories(${AWSSDK_INCLUDE_DIRS})

add_library(libevent STATIC IMPORTED)
set_target_properties(libevent PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libevent.a)

add_library(openssl STATIC IMPORTED)
set_target_properties(openssl PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libssl.a)

add_library(leveldb STATIC IMPORTED GLOBAL)
set_target_properties(leveldb PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libleveldb.a)

add_library(jemalloc STATIC IMPORTED)
set_target_properties(jemalloc PROPERTIES IMPORTED_LOCATION ${JEMALLOC_HOME}/lib/libjemalloc_pic.a)

add_library(brotlicommon STATIC IMPORTED)
set_target_properties(brotlicommon PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libbrotlicommon.a)

add_library(brotlidec STATIC IMPORTED)
set_target_properties(brotlidec PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libbrotlidec.a)

add_library(brotlienc STATIC IMPORTED)
set_target_properties(brotlienc PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libbrotlienc.a)

add_library(zstd STATIC IMPORTED)
set_target_properties(zstd PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libzstd.a)

add_library(streamvbyte STATIC IMPORTED)
set_target_properties(streamvbyte PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libstreamvbyte_static.a)

add_library(arrow STATIC IMPORTED)
set_target_properties(arrow PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libarrow.a)

add_library(parquet STATIC IMPORTED)
set_target_properties(parquet PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libparquet.a)

add_library(brpc STATIC IMPORTED GLOBAL)
set_target_properties(brpc PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libbrpc.a)

add_library(rocksdb STATIC IMPORTED GLOBAL)
set_target_properties(rocksdb PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/librocksdb.a)

add_library(krb5support STATIC IMPORTED)
set_target_properties(krb5support PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libkrb5support.a)

add_library(krb5 STATIC IMPORTED)
set_target_properties(krb5 PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libkrb5.a)

add_library(com_err STATIC IMPORTED)
set_target_properties(com_err PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libcom_err.a)

add_library(k5crypto STATIC IMPORTED)
set_target_properties(k5crypto PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libk5crypto.a)

add_library(gssapi_krb5 STATIC IMPORTED)
set_target_properties(gssapi_krb5 PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libgssapi_krb5.a)

add_library(sasl STATIC IMPORTED GLOBAL)
set_target_properties(sasl PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libsasl2.a)

add_library(librdkafka_cpp STATIC IMPORTED)
set_target_properties(librdkafka_cpp PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/librdkafka++.a)

add_library(librdkafka STATIC IMPORTED)
set_target_properties(librdkafka PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/librdkafka.a)

add_library(libpulsar STATIC IMPORTED)
set_target_properties(libpulsar PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libpulsar.a)

add_library(libs2 STATIC IMPORTED)
set_target_properties(libs2 PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libs2.a)

add_library(bitshuffle STATIC IMPORTED)
set_target_properties(bitshuffle PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libbitshuffle.a)

add_library(roaring STATIC IMPORTED)
set_target_properties(roaring PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libroaring.a)

add_library(cctz STATIC IMPORTED)
set_target_properties(cctz PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libcctz.a)

add_library(benchmark STATIC IMPORTED)
set_target_properties(benchmark PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libbenchmark.a)

add_library(benchmark_main STATIC IMPORTED)
set_target_properties(benchmark_main PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libbenchmark_main.a)

add_library(fmt STATIC IMPORTED)
set_target_properties(fmt PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libfmt.a)

add_library(ryu STATIC IMPORTED)
set_target_properties(ryu PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libryu.a)

# Disable minidump on aarch64, hence breakpad is not needed.
if ("${CMAKE_BUILD_TARGET_ARCH}" STREQUAL "x86" OR "${CMAKE_BUILD_TARGET_ARCH}" STREQUAL "x86_64")
    add_library(breakpad STATIC IMPORTED)
    set_target_properties(breakpad PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libbreakpad_client.a)
endif()

add_library(hyperscan STATIC IMPORTED)
set_target_properties(hyperscan PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libhs.a)

add_library(simdjson STATIC IMPORTED)
set_target_properties(simdjson PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libsimdjson.a)

add_library(velocypack STATIC IMPORTED)
set_target_properties(velocypack PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libvelocypack.a)

find_program(THRIFT_COMPILER thrift ${CMAKE_SOURCE_DIR}/bin)

add_library(http_client_curl STATIC IMPORTED GLOBAL)
set_target_properties(http_client_curl PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libhttp_client_curl.a)

add_library(opentelemetry_common STATIC IMPORTED GLOBAL)
set_target_properties(opentelemetry_common PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libopentelemetry_common.a)

add_library(opentelemetry_trace STATIC IMPORTED GLOBAL)
set_target_properties(opentelemetry_trace PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libopentelemetry_trace.a)

add_library(opentelemetry_resources STATIC IMPORTED GLOBAL)
set_target_properties(opentelemetry_resources PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libopentelemetry_resources.a)

add_library(jansson STATIC IMPORTED GLOBAL)
set_target_properties(jansson PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libjansson.a)

add_library(avro STATIC IMPORTED GLOBAL)
set_target_properties(avro PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libavro.a)

add_library(serdes STATIC IMPORTED GLOBAL)
set_target_properties(serdes PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib/libserdes.a)

add_library(opentelemetry_exporter_jaeger_trace STATIC IMPORTED GLOBAL)
set_target_properties(opentelemetry_exporter_jaeger_trace PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libopentelemetry_exporter_jaeger_trace.a)

# Disable libdefalte on aarch64
if ("${CMAKE_BUILD_TARGET_ARCH}" STREQUAL "x86" OR "${CMAKE_BUILD_TARGET_ARCH}" STREQUAL "x86_64")
    add_library(libdeflate STATIC IMPORTED GLOBAL)
    set_target_properties(libdeflate PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/lib64/libdeflate.a)
endif()

# cachelib
set(CACHELIB_DEPENDENCIES
    cachelib_common
    cachelib_allocator
    cachelib_datatype
    cachelib_navy
    cachelib_shm
    folly
    fmtd
    thriftcpp2
    thrift-core
    thriftmetadata
    thriftfrozen2
    thriftprotocol
    thrifttype
    transport
    rpcmetadata
    thriftanyrep
    thrifttyperep
    thriftannotation
    concurrency
    async
    wangle
)

if (${WITH_CACHELIB} STREQUAL "ON")
    LINK_LIBRARIES(${THIRDPARTY_DIR}/cachelib/deps/lib64/libunwind.so)
    LINK_LIBRARIES(${THIRDPARTY_DIR}/cachelib/deps/lib64/liblzma.so)
    foreach(dep ${CACHELIB_DEPENDENCIES})
        add_library(${dep} STATIC IMPORTED)
        set(location "${THIRDPARTY_DIR}/cachelib/lib/lib${dep}.a")
        if(NOT EXISTS ${location})
            set(location "${THIRDPARTY_DIR}/cachelib/lib64/lib${dep}.a")
        endif()
        set_target_properties(${dep} PROPERTIES IMPORTED_LOCATION "${location}")
        message(STATUS "add cachelib dependency: ${location}")
    endforeach()
endif()

if (${WITH_STARCACHE} STREQUAL "ON")
    add_library(starcache STATIC IMPORTED GLOBAL)
    if ("${USE_STAROS}" STREQUAL "ON")
        set(STARCACHE_DIR "${STARLET_INSTALL_DIR}/starlet_install")
    else()
        set(STARCACHE_DIR "${THIRDPARTY_DIR}/starcache")
    endif()
    set_target_properties(starcache PROPERTIES IMPORTED_LOCATION ${STARCACHE_DIR}/lib/libstarcache.a)
    include_directories(SYSTEM ${STARCACHE_DIR}/include)
    message(STATUS "link the starcache in directory: ${STARCACHE_DIR}")
endif()

if ("${USE_STAROS}" STREQUAL "ON")
    if (DEFINED ENV{STARLET_INSTALL_DIR})
        set(STARLET_INSTALL_DIR "$ENV{STARLET_INSTALL_DIR}")
    else()
        set(STARLET_INSTALL_DIR "${THIRDPARTY_DIR}/starlet")
    endif()
    if (NOT EXISTS ${STARLET_INSTALL_DIR})
        message(FATAL_ERROR "Starlet thirdparty directory ${STARLET_INSTALL_DIR} not exist!")
    else()
        message(STATUS "Searching starlet related libraries from ${STARLET_INSTALL_DIR} ...")
    endif()

    # explicitly import ZLIB::ZLIB which is required by starlet thirdparty
    add_library(ZLIB::ZLIB STATIC IMPORTED)
    set_target_properties(ZLIB::ZLIB PROPERTIES IMPORTED_LOCATION ${LIBZ})

    # Tell cmake that PROTOBUF library is already found
    set(PROTOBUF_FOUND TRUE)
    # starrocks project has its imported libprotobuf.a and libre2.a
    # add following ALIAS so grpc can find the correct dependent libraries
    add_library(protobuf::libprotobuf ALIAS protobuf)
    add_library(re2::re2 ALIAS re2)
    add_library(glog::glog ALIAS glog)
    add_library(gflags::gflags_static ALIAS gflags)
    add_library(hdfs::hdfs ALIAS hdfs)
    add_library(brpc::brpc ALIAS brpc)
    add_library(leveldb::leveldb ALIAS leveldb)
    add_library(CURL::libcurl ALIAS curl)
    add_library(rocksdb::rocksdb ALIAS rocksdb)
    add_library(starcache::starcache ALIAS starcache)
    add_library(Snappy::snappy ALIAS snappy)

    set(absl_DIR "${STARLET_INSTALL_DIR}/third_party/lib/cmake/absl" CACHE PATH "absl search path" FORCE)
    find_package(absl CONFIG REQUIRED)

    # required by azure-*
    set(LIBXML2_INCLUDE_DIR "${STARLET_INSTALL_DIR}/third_party/include/libxml2" CACHE PATH "libxml2 include path")
    set(LIBXML2_LIBRARY "${STARLET_INSTALL_DIR}/third_party/lib/libxml2.a" CACHE FILEPATH "libxml2 static library")
    add_library(libxml2 STATIC IMPORTED GLOBAL)
    set_target_properties(libxml2 PROPERTIES IMPORTED_LOCATION ${LIBXML2_LIBRARY})

    set(gRPC_DIR "${STARLET_INSTALL_DIR}/third_party/lib/cmake/grpc" CACHE PATH "grpc search path")
    find_package(gRPC CONFIG REQUIRED)
    message(STATUS "Using gRPC ${gRPC_VERSION}")
    get_target_property(gRPC_INCLUDE_DIR gRPC::grpc INTERFACE_INCLUDE_DIRECTORIES)
    include_directories(SYSTEM ${gRPC_INCLUDE_DIR})

    set(prometheus-cpp_DIR "${STARLET_INSTALL_DIR}/third_party/lib/cmake/prometheus-cpp" CACHE PATH "prometheus cpp client search path")
    find_package (prometheus-cpp CONFIG REQUIRED)
    get_target_property(prometheus-cpp_INCLUDE_DIR prometheus-cpp::core INTERFACE_INCLUDE_DIRECTORIES)
    message(STATUS "Using prometheus-cpp")
    message(STATUS "  include: ${prometheus-cpp_INCLUDE_DIR}")
    include_directories(SYSTEM ${prometheus-cpp_INCLUDE_DIR})

    set(azure-core-cpp_DIR "${STARLET_INSTALL_DIR}/third_party/share/azure-core-cpp" CACHE PATH "azure core cpp search path")
    find_package(azure-core-cpp CONFIG REQUIRED)
    set(azure-identity-cpp_DIR "${STARLET_INSTALL_DIR}/third_party/share/azure-identity-cpp" CACHE PATH "azure identity cpp search path")
    find_package(azure-identity-cpp CONFIG REQUIRED)
    set(azure-storage-common-cpp_DIR "${STARLET_INSTALL_DIR}/third_party/share/azure-storage-common-cpp" CACHE PATH "azure storage common search path")
    find_package(azure-storage-common-cpp CONFIG REQUIRED)
    set(azure-storage-blobs-cpp_DIR "${STARLET_INSTALL_DIR}/third_party/share/azure-storage-blobs-cpp" CACHE PATH "azure storage blobs search path")
    find_package(azure-storage-blobs-cpp CONFIG REQUIRED)
    set(AZURE_SDK_LIB Azure::azure-identity Azure::azure-storage-blobs Azure::azure-core Azure::azure-storage-common)

    set(starlet_DIR "${STARLET_INSTALL_DIR}/starlet_install/lib/cmake" CACHE PATH "starlet search path")
    find_package(starlet CONFIG REQUIRED)
    message(STATUS "Using starlet ${starlet_VERSION}")
    message(STATUS "starlet inc dir: ${STARLET_INCLUDE_DIRS}")
    message(STATUS "starlet lib dir: ${STARLET_LIBS}")
    include_directories(SYSTEM ${STARLET_INCLUDE_DIRS})

    set_target_properties(starlet::starlet_fslib_all PROPERTIES IMPORTED_GLOBAL TRUE)
    add_library(starlet_fslib_all ALIAS starlet::starlet_fslib_all)
    set_target_properties(starlet::starlet PROPERTIES IMPORTED_GLOBAL TRUE)
    add_library(starlet ALIAS starlet::starlet)

    set(STARROCKS_DEPENDENCIES
       ${STARROCKS_DEPENDENCIES}
       starlet
       starlet_fslib_all
       starcache
       ${AZURE_SDK_LIB}
       )
endif()

# LLVM
# TODO(yueyang): Adjust libraries during the implementation of JIT.
set (LLVM_LIBRARIES
    LLVMRuntimeDyld
    LLVMBitstreamReader
    LLVMOption
    LLVMAsmPrinter
    LLVMProfileData
    LLVMAsmParser
    LLVMOrcTargetProcess
    LLVMExecutionEngine
    LLVMBinaryFormat
    LLVMDebugInfoDWARF
    LLVMObjCARCOpts
    LLVMCodeGen
    LLVMMCDisassembler
    LLVMSupport
    LLVMJITLink
    LLVMCFGuard
    LLVMInstrumentation
    LLVMIRReader
    LLVMCore
    LLVMTarget
    LLVMMC
    LLVMAnalysis
    LLVMGlobalISel
    LLVMScalarOpts
    LLVMTargetParser
    LLVMDemangle
    LLVMRemarks
    LLVMDebugInfoCodeView
    LLVMOrcShared
    LLVMOrcJIT
    LLVMTextAPI
    LLVMBitWriter
    LLVMBitReader
    LLVMObject
    LLVMTransformUtils
    LLVMSelectionDAG
    LLVMMCParser
)
if ("${CMAKE_BUILD_TARGET_ARCH}" STREQUAL "x86" OR "${CMAKE_BUILD_TARGET_ARCH}" STREQUAL "x86_64")
    set(${LLVM_LIBRARIES} ${LLVM_LIBRARIES} LLVMX86CodeGen LLVMX86Desc LLVMX86Info)
elseif ("${CMAKE_BUILD_TARGET_ARCH}" STREQUAL "aarch64")
    set(${LLVM_LIBRARIES} ${LLVM_LIBRARIES} LLVMAArch64CodeGen LLVMAArch64Desc LLVMAArch64Info)
endif()

foreach(lib IN ITEMS ${LLVM_LIBRARIES})
    add_library(${lib} STATIC IMPORTED GLOBAL)
    set_target_properties(${lib} PROPERTIES IMPORTED_LOCATION ${THIRDPARTY_DIR}/llvm/lib/lib${lib}.a)
endforeach()

# Check Clang-Tidy
include(cmake_modules/FindClangTidy.cmake)

# Check if functions are supported in this platform. All flags will generated
# in gensrc/build/common/env_config.h.
# You can check funcion here which depends on platform. Don't forget add this
# to be/src/common/env_config.h.in
include(CheckFunctionExists)
check_function_exists(sched_getcpu HAVE_SCHED_GETCPU)

# support to pass cxx flags from environment.
set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} $ENV{STARROCKS_CXX_COMMON_FLAGS}")

# -no-pie: Disable Position Independent Executables (PIE) as certain libraries cannot be linked against PIE executables.
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -no-pie")
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} $ENV{STARROCKS_CXX_LINKER_FLAGS}")

# compiler flags that are common across debug/release builds
#  -Wall: Enable all warnings.
#  -Wno-sign-compare: suppress warnings for comparison between signed and unsigned
#    integers
#   -fno-strict-aliasing: disable optimizations that assume strict aliasing. This
#       is unsafe to do if the code uses casts (which we obviously do).
#  -Wno-unknown-pragmas: suppress warnings for unknown (compiler specific) pragmas
#  -Wno-deprecated: gutil contains deprecated headers
#  -Wno-vla: we use C99-style variable-length arrays
#  -pthread: enable multithreaded malloc
#  -DBOOST_DATE_TIME_POSIX_TIME_STD_CONFIG: enable nanosecond precision for boost
#  -fno-omit-frame-pointers: Keep frame pointer for functions in register
set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wall -Wno-sign-compare -Wno-unknown-pragmas -pthread -Wno-register")
set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-strict-aliasing -fno-omit-frame-pointer")
set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -std=gnu++20 -D__STDC_FORMAT_MACROS")
set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-deprecated -Wno-vla -Wno-comment")
if("${WITH_RELATIVE_SRC_PATH}" STREQUAL "ON")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} ${FILE_PREFIX_MAP_FLAG}")
endif()
# disable link delete(void*, long)
set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -fno-sized-deallocation")

if (CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-unused-parameter -Wno-documentation -Wno-weak-vtables")
    # Turn on following warning as error explicitly
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Werror=string-plus-int")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Werror=pessimizing-move")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Werror=delete-non-virtual-dtor")
    if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "11.0.0")
        set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-reserved-identifier -Wno-suggest-destructor-override")
    endif()
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-documentation-unknown-command -Wno-old-style-cast")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-c++20-designator -Wno-mismatched-tags")
    if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "14.0.0")
        set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-bitwise-instead-of-logical -Wno-inconsistent-missing-override -Wno-ambiguous-reversed-operator")
    endif()
    if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL "16.0.0")
        # ignore warning from apache-orc
        set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Wno-unsafe-buffer-usage")
    endif ()
else ()
    set(CXX_GCC_FLAGS "${CXX_GCC_FLAGS} -fcoroutines")
endif()

set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -DBOOST_DATE_TIME_POSIX_TIME_STD_CONFIG")
set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -DBOOST_SYSTEM_NO_DEPRECATED -DBOOST_UUID_RANDOM_PROVIDER_FORCE_POSIX")
set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -Werror=return-type -Werror=switch")
if (${USE_STAROS} STREQUAL "ON")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -DUSE_STAROS")
endif()
if (${WITH_CACHELIB} STREQUAL "ON")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -DWITH_CACHELIB")
endif()
if (${WITH_STARCACHE} STREQUAL "ON")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -DWITH_STARCACHE")
endif()

# When LLVM is used, should give GCC_HOME to get c++11 header to use new string and list
if (CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    if (DEFINED ENV{STARROCKS_GCC_HOME})
        set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} --gcc-toolchain=$ENV{STARROCKS_GCC_HOME}")
    else()
        message(WARNING "STARROCKS_GCC_HOME evnironment variable is not set, ")
    endif()
endif()

if ("${CMAKE_BUILD_TARGET_ARCH}" STREQUAL "x86" OR "${CMAKE_BUILD_TARGET_ARCH}" STREQUAL "x86_64")
    if (${USE_SSE4_2})
        # the compiler will define __SSE4_2__
        set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -msse4.2")
    endif()
    if (${USE_AVX2})
        # the compiler will define __AVX2__
        set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -mavx2")
    endif()
    if (${USE_AVX512})
        # the compiler will define __AVX512F__ __AVX512BW__
        set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -mavx512f -mavx512bw")
    endif()
elseif ("${CMAKE_BUILD_TARGET_ARCH}" STREQUAL "aarch64")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -march=armv8-a+crc")
endif()
set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS}  -Wno-attributes -DS2_USE_GFLAGS -DS2_USE_GLOG")

if (CMAKE_CXX_COMPILER_VERSION VERSION_GREATER 7.0)
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -faligned-new")
endif()

# For any gcc builds:
#   -g: Enable symbols for profiler tools
#   -Wno-unused-local-typedefs: Do not warn for local typedefs that are unused.
set(CXX_GCC_FLAGS "${CXX_GCC_FLAGS} -g -Wno-unused-local-typedefs")

if (WITH_GCOV)
    # To generate flags to code coverage
    set(CXX_GCC_FLAGS "${CXX_GCC_FLAGS} -fprofile-arcs -ftest-coverage")
endif()

if (WITH_COMPRESS)
    # to compresss debug section. https://gcc.gnu.org/onlinedocs/gcc/Debugging-Options.html
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -gz=zlib")
endif()

if (ENABLE_QUERY_DEBUG_TRACE)
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -DENABLE_QUERY_DEBUG_TRACE")
    message(STATUS "enable query debug trace")
endif()

if (ENABLE_FAULT_INJECTION)
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -DFIU_ENABLE")
    message(STATUS "enable fault injection")
endif()

option(ASSERT_STATUS_CHECKED "build with assert status checked" OFF)
if (ASSERT_STATUS_CHECKED)
    message(STATUS "Build with assert status checked")
    set(CXX_COMMON_FLAGS "${CXX_COMMON_FLAGS} -DSTARROCKS_ASSERT_STATUS_CHECKED")
endif()

# For CMAKE_BUILD_TYPE=Debug
#   -ggdb: Enable gdb debugging
# Debug information is stored as dwarf2 to be as compatible as possible
#   -Werror: compile warnings should be errors when using the toolchain compiler.
# Only enable for debug builds because this is what we test in pre-commit tests.
set(CXX_FLAGS_DEBUG "${CXX_GCC_FLAGS} -ggdb -O0 -gdwarf-4 -DDEBUG")

# For CMAKE_BUILD_TYPE=Release
#   -O3: Enable all compiler optimizations
#   -DNDEBUG: Turn off dchecks/asserts/debug only code.
#   -gdwarf-4: Debug information is stored as dwarf2 to be as compatible as possible
set(CXX_FLAGS_RELEASE "${CXX_GCC_FLAGS} -O3 -gdwarf-4 -DNDEBUG")

SET(CXX_FLAGS_ASAN "${CXX_GCC_FLAGS} -ggdb3 -O0 -gdwarf-4 -fsanitize=address -DADDRESS_SANITIZER")
SET(CXX_FLAGS_LSAN "${CXX_GCC_FLAGS} -ggdb3 -O0 -gdwarf-4 -fsanitize=leak -DLEAK_SANITIZER")

# Set the flags to the undefined behavior sanitizer, also known as "ubsan"
# Turn on sanitizer and debug symbols to get stack traces:
SET(CXX_FLAGS_UBSAN "${CXX_FLAGS_RELEASE} -fsanitize=undefined")
# Ignore a number of noisy errors with too many false positives:
# TODO(zc):
# SET(CXX_FLAGS_UBSAN "${CXX_FLAGS_UBSAN} -fno-sanitize=alignment,function,vptr,float-divide-by-zero,float-cast-overflow")
# Don't enforce wrapped signed integer arithmetic so that the sanitizer actually sees

# Set the flags to the thread sanitizer, also known as "tsan"
# Turn on sanitizer and debug symbols to get stack traces:
SET(CXX_FLAGS_TSAN "${CXX_GCC_FLAGS} -O0 -ggdb3 -fsanitize=thread -DTHREAD_SANITIZER")

# Set compile flags based on the build type.
if ("${CMAKE_BUILD_TYPE}" STREQUAL "DEBUG")
    SET(CMAKE_CXX_FLAGS ${CXX_FLAGS_DEBUG})
elseif ("${CMAKE_BUILD_TYPE}" STREQUAL "RELEASE")
    SET(CMAKE_CXX_FLAGS ${CXX_FLAGS_RELEASE})
elseif ("${CMAKE_BUILD_TYPE}" STREQUAL "ASAN")
    SET(CMAKE_CXX_FLAGS "${CXX_FLAGS_ASAN}")
elseif ("${CMAKE_BUILD_TYPE}" STREQUAL "LSAN")
    SET(CMAKE_CXX_FLAGS "${CXX_FLAGS_LSAN}")
elseif ("${CMAKE_BUILD_TYPE}" STREQUAL "UBSAN")
    SET(CMAKE_CXX_FLAGS "${CXX_FLAGS_UBSAN}")
elseif ("${CMAKE_BUILD_TYPE}" STREQUAL "TSAN")
    SET(CMAKE_CXX_FLAGS "${CXX_FLAGS_TSAN}")
else()
    message(FATAL_ERROR "Unknown build type: ${CMAKE_BUILD_TYPE}")
endif()

# Add flags that are common across build types
SET(CMAKE_CXX_FLAGS "${CXX_COMMON_FLAGS} ${CMAKE_CXX_FLAGS}")
if("${WITH_RELATIVE_SRC_PATH}" STREQUAL "ON")
    # apply -ffile-prefix-map option to .c source files as well
    SET(CMAKE_C_FLAGS "${FILE_PREFIX_MAP_FLAG} ${CMAKE_C_FLAGS}")
endif()

message(STATUS "Compiler Flags: ${CMAKE_CXX_FLAGS}")

# Thrift requires these two definitions for some types that we use
add_definitions(-DHAVE_INTTYPES_H -DHAVE_NETINET_IN_H)

# Set include dirs
include_directories(
    BEFORE
    ${SRC_DIR}/formats/orc/apache-orc/c++/include/
)
include_directories(
    ${SRC_DIR}/
    ${TEST_DIR}/
    ${GENSRC_DIR}/
    SYSTEM ${THIRDPARTY_DIR}/include
    SYSTEM ${GPERFTOOLS_HOME}/include
    SYSTEM ${JEMALLOC_HOME}/include
    SYSTEM ${THIRDPARTY_DIR}/include/thrift/
    SYSTEM ${THIRDPARTY_DIR}/include/event/
    SYSTEM ${THIRDPARTY_DIR}/llvm/include/
)


if ("${CMAKE_BUILD_TARGET_ARCH}" STREQUAL "x86" OR "${CMAKE_BUILD_TARGET_ARCH}" STREQUAL "x86_64")
    include_directories(${THIRDPARTY_DIR}/include/breakpad/)
endif()

set(WL_START_GROUP "-Wl,--start-group")
set(WL_END_GROUP "-Wl,--end-group")
set(WL_LINK_STATIC "-Wl,-Bstatic")
set(WL_LINK_DYNAMIC "-Wl,-Bdynamic")

# Set starrocks libraries
set(STARROCKS_LINK_LIBS
    ${WL_START_GROUP}
    Agent
    Common
    Column
    Connector
    Exec
    Exprs
    FileSystem
    Formats
    Gutil
    IO
    Serde
    Storage
    Rowset
    Runtime
    Service
    ServiceBE
    Types
    Udf
    Util
    Script
    StarRocksGen
    Webserver
    TestUtil
    Tools
    Geo
    BlockCache
    ${WL_END_GROUP}
)

set(STARROCKS_DEPENDENCIES ${STARROCKS_DEPENDENCIES}
    mysql
)


set(STARROCKS_DEPENDENCIES ${STARROCKS_DEPENDENCIES}
    hdfs
    jvm
)
set(JAVA_HOME ${THIRDPARTY_DIR}/open_jdk/)
add_library(jvm SHARED IMPORTED)
FILE(GLOB_RECURSE LIB_JVM ${JAVA_HOME}/jre/lib/*/libjvm.so)
set_target_properties(jvm PROPERTIES IMPORTED_LOCATION ${LIB_JVM})
include_directories(${JAVA_HOME}/include)
include_directories(${JAVA_HOME}/include/linux)

set(STARROCKS_DEPENDENCIES ${STARROCKS_DEPENDENCIES}
    ${AWSSDK_LINK_LIBRARIES}
)
set_target_properties(aws-cpp-sdk-core PROPERTIES INTERFACE_LINK_LIBRARIES AWS::aws-crt-cpp)

# Set thirdparty libraries
set(STARROCKS_DEPENDENCIES
    ${STARROCKS_DEPENDENCIES}
    ${WL_START_GROUP}
    build_version
    rocksdb
    libs2
    snappy
    ${Boost_LIBRARIES}
    thrift
    thriftnb
    glog
    re2
    pprof
    # Put lz4 in front of librdkafka to make sure that segment use the native lz4 library to compress/decompress page
    # Otherwise, he will use the lz4 Library in librdkafka
    lz4
    libevent
    curl
    ${LIBZ}
    ${LIBBZ2}
    gflags
    brpc
    protobuf
    openssl
    crypto
    leveldb
    bitshuffle
    roaring
    brotlicommon
    brotlidec
    brotlienc
    zstd
    streamvbyte
    arrow
    jemalloc # required by arrow
    parquet
    orc
    cctz
    fmt
    ryu
    hyperscan
    simdjson
    sasl
    gssapi_krb5
    krb5
    krb5support
    k5crypto
    com_err
    librdkafka_cpp
    librdkafka
    libpulsar
    velocypack
    opentelemetry_trace
    http_client_curl
    opentelemetry_resources
    opentelemetry_common
    opentelemetry_exporter_jaeger_trace
    jansson
    avro
    serdes
    fiu
    ${LLVM_LIBRARIES}
    ${WL_END_GROUP}
)

if (${WITH_CACHELIB} STREQUAL "ON")
    set(STARROCKS_DEPENDENCIES
        ${STARROCKS_DEPENDENCIES}
        ${WL_START_GROUP}
        ${Boost_LIBRARIES}
        ${CACHELIB_DEPENDENCIES}
        ${WL_END_GROUP}
    )
endif()

if (${WITH_STARCACHE} STREQUAL "ON")
    set(STARROCKS_DEPENDENCIES
        ${STARROCKS_DEPENDENCIES}
        ${WL_START_GROUP}
        brpc
        starcache
        ${WL_END_GROUP}
    )
endif()

if ("${CMAKE_BUILD_TARGET_ARCH}" STREQUAL "x86" OR "${CMAKE_BUILD_TARGET_ARCH}" STREQUAL "x86_64")
    set(STARROCKS_DEPENDENCIES
        ${STARROCKS_DEPENDENCIES}
        breakpad
        libdeflate
    )
endif()

# Add all external dependencies. They should come after the starrocks libs.
# static link gcc's lib
set(STARROCKS_LINK_LIBS ${STARROCKS_LINK_LIBS}
    ${STARROCKS_DEPENDENCIES}
    -static-libstdc++
    -static-libgcc
    -lresolv
)

# Add sanitize static link flags or jemalloc
if ("${CMAKE_BUILD_TYPE}" STREQUAL "DEBUG" OR "${CMAKE_BUILD_TYPE}" STREQUAL "RELEASE")
    message("use jemalloc")
    set(STARROCKS_LINK_LIBS ${STARROCKS_LINK_LIBS} jemalloc)
elseif ("${CMAKE_BUILD_TYPE}" STREQUAL "ASAN")
    if (CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
        set(STARROCKS_LINK_LIBS ${STARROCKS_LINK_LIBS} -static-libsan)
    else()
        set(STARROCKS_LINK_LIBS ${STARROCKS_LINK_LIBS} -static-libasan)
    endif()
elseif ("${CMAKE_BUILD_TYPE}" STREQUAL "LSAN")
    set(STARROCKS_LINK_LIBS ${STARROCKS_LINK_LIBS} -static-liblsan)
elseif ("${CMAKE_BUILD_TYPE}" STREQUAL "UBSAN")
    message("use jemalloc")
    set(STARROCKS_LINK_LIBS ${STARROCKS_LINK_LIBS} -static-libubsan jemalloc)
elseif ("${CMAKE_BUILD_TYPE}" STREQUAL "TSAN")
    set(STARROCKS_LINK_LIBS ${STARROCKS_LINK_LIBS} -static-libtsan)
else()
    message(FATAL_ERROR "Unknown build type: ${CMAKE_BUILD_TYPE}")
endif()

set(STARROCKS_LINK_LIBS ${STARROCKS_LINK_LIBS}
    ${WL_LINK_STATIC} -lbfd -lsframe
    ${WL_LINK_DYNAMIC} -liberty -lc -lm -ldl -rdynamic -pthread -Wl,-wrap=__cxa_throw
)

# link gcov if WITH_GCOV is on
if (WITH_GCOV)
    set(STARROCKS_LINK_LIBS ${STARROCKS_LINK_LIBS} -lgcov)
endif()

# Set libraries for test
set (TEST_LINK_LIBS ${STARROCKS_LINK_LIBS}
    ${WL_START_GROUP}
    gmock
    gtest
    ${WL_END_GROUP}
)

# Only build static libs
set(BUILD_SHARED_LIBS OFF)

if (NOT $ENV{STARROCKS_LINKER} STREQUAL "")
    add_link_options("-fuse-ld=$ENV{STARROCKS_LINKER}")
endif ()

if (${MAKE_TEST} STREQUAL "ON")
    SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -DGTEST_USE_OWN_TR1_TUPLE=0")
    add_definitions(-DBE_TEST)
    add_definitions(-DFIU_ENABLE)
else()
    # output *.a, *.so, *.dylib to output/tmp
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${OUTPUT_DIR}/tmp/${CMAKE_BUILD_TYPE})
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${OUTPUT_DIR}/tmp/${CMAKE_BUILD_TYPE})
    # output *.exe to output/lib
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${OUTPUT_DIR}/lib)
endif ()

# Utility CMake function to make specifying tests and benchmarks less verbose
FUNCTION(ADD_BE_TEST TEST_NAME)
    set(BUILD_OUTPUT_ROOT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/")
    # This gets the directory where the test is from (e.g. 'exprs' or 'runtime')
    get_filename_component(DIR_NAME ${CMAKE_CURRENT_SOURCE_DIR} NAME)
    get_filename_component(TEST_DIR_NAME ${TEST_NAME} PATH)
    get_filename_component(TEST_FILE_NAME ${TEST_NAME} NAME)

    ADD_EXECUTABLE(${TEST_FILE_NAME} ${TEST_NAME}.cpp)
    TARGET_LINK_LIBRARIES(${TEST_FILE_NAME} ${TEST_LINK_LIBS} gtest_main)
    SET_TARGET_PROPERTIES(${TEST_FILE_NAME} PROPERTIES COMPILE_FLAGS "-fno-access-control")
    if (NOT "${TEST_DIR_NAME}" STREQUAL "")
        SET_TARGET_PROPERTIES(${TEST_FILE_NAME} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${BUILD_OUTPUT_ROOT_DIRECTORY}/${TEST_DIR_NAME}")
    endif()
    ADD_TEST(${TEST_FILE_NAME} "${BUILD_OUTPUT_ROOT_DIRECTORY}/${TEST_NAME}")
ENDFUNCTION()

# Add a benchmark to BE
FUNCTION(ADD_BE_BENCH BENCH_NAME)
    message(STATUS "Add Be Bench")
    set(BUILD_OUTPUT_ROOT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/")
    # This gets the directory where the test is from (e.g. 'exprs' or 'runtime')
    get_filename_component(DIR_NAME ${CMAKE_CURRENT_SOURCE_DIR} NAME)
    get_filename_component(BENCH_DIR_NAME ${BENCH_NAME} PATH)
    set(BENCH_OUTPUT_DIR_NAME "output")
    get_filename_component(BENCH_FILE_NAME ${BENCH_NAME} NAME)
    
    find_package(benchmark REQUIRED)
    ADD_EXECUTABLE(${BENCH_FILE_NAME} ${BENCH_NAME}.cpp)
    TARGET_LINK_LIBRARIES(${BENCH_FILE_NAME} ${TEST_LINK_LIBS} benchmark benchmark_main)

    SET_TARGET_PROPERTIES(${BENCH_FILE_NAME} PROPERTIES COMPILE_FLAGS "-fno-access-control")
    SET_TARGET_PROPERTIES(${BENCH_FILE_NAME} PROPERTIES COMPILE_FLAGS ${CXX_FLAGS_RELEASE})
    if (NOT "${BENCH_OUTPUT_DIR_NAME}" STREQUAL "")
        SET_TARGET_PROPERTIES(${BENCH_FILE_NAME} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${BUILD_OUTPUT_ROOT_DIRECTORY}/${BENCH_OUTPUT_DIR_NAME}")
    endif()
    ADD_TEST(${BENCH_FILE_NAME} "${BUILD_OUTPUT_ROOT_DIRECTORY}/${BENCH_NAME}")
ENDFUNCTION()

add_subdirectory(${SRC_DIR}/agent)
add_subdirectory(${SRC_DIR}/common)
add_subdirectory(${SRC_DIR}/connector)
add_subdirectory(${SRC_DIR}/column)
add_subdirectory(${SRC_DIR}/formats)
add_subdirectory(${SRC_DIR}/fs)
add_subdirectory(${SRC_DIR}/exec)
add_subdirectory(${SRC_DIR}/exprs)
add_subdirectory(${SRC_DIR}/gen_cpp)
add_subdirectory(${SRC_DIR}/geo)
add_subdirectory(${SRC_DIR}/gutil)
add_subdirectory(${SRC_DIR}/http)
add_subdirectory(${SRC_DIR}/io)
add_subdirectory(${SRC_DIR}/storage)
add_subdirectory(${SRC_DIR}/runtime)
add_subdirectory(${SRC_DIR}/serde)
add_subdirectory(${SRC_DIR}/service)
add_subdirectory(${SRC_DIR}/testutil)
add_subdirectory(${SRC_DIR}/types)
add_subdirectory(${SRC_DIR}/udf)
add_subdirectory(${SRC_DIR}/block_cache)

add_subdirectory(${SRC_DIR}/tools)
add_subdirectory(${SRC_DIR}/util)
add_subdirectory(${SRC_DIR}/script)

if (WITH_BENCH STREQUAL "ON")
     message(STATUS "Build binary with bench")
    add_subdirectory(${SRC_DIR}/bench)
endif()

if (${MAKE_TEST} STREQUAL "ON")
    add_subdirectory(test)
endif ()

# Install be
install(DIRECTORY DESTINATION ${OUTPUT_DIR})
install(DIRECTORY DESTINATION ${OUTPUT_DIR}/bin)
install(DIRECTORY DESTINATION ${OUTPUT_DIR}/conf)
install(DIRECTORY DESTINATION ${OUTPUT_DIR}/lib)

install(FILES
    ${BASE_DIR}/../bin/common.sh
    ${BASE_DIR}/../bin/start_backend.sh
    ${BASE_DIR}/../bin/start_be.sh
    ${BASE_DIR}/../bin/start_cn.sh
    ${BASE_DIR}/../bin/stop_be.sh
    ${BASE_DIR}/../bin/stop_cn.sh
    ${BASE_DIR}/../bin/show_be_version.sh
    ${BASE_DIR}/../bin/meta_tool.sh
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
    GROUP_READ GROUP_WRITE GROUP_EXECUTE
    WORLD_READ WORLD_EXECUTE
    DESTINATION ${OUTPUT_DIR}/bin)

install(FILES
    ${BASE_DIR}/../conf/be.conf
    ${BASE_DIR}/../conf/be_test.conf
    ${BASE_DIR}/../conf/cn.conf
    ${BASE_DIR}/../conf/hadoop_env.sh
    ${BASE_DIR}/../conf/log4j2.properties
    ${BASE_DIR}/../conf/udf_security.policy
    ${BASE_DIR}/../conf/core-site.xml
    DESTINATION ${OUTPUT_DIR}/conf)

if ("${CMAKE_BUILD_TYPE}" STREQUAL "ASAN" OR "${CMAKE_BUILD_TYPE}" STREQUAL "LSAN")
install(FILES
    ${BASE_DIR}/../conf/asan_suppressions.conf
    DESTINATION ${OUTPUT_DIR}/conf)
endif()

install(DIRECTORY
    ${BASE_DIR}/../webroot/be/
    DESTINATION ${OUTPUT_DIR}/www)


```

修改完成！

**原因分析：**

Ubuntu 24.04 的 binutils 版本是 **2.42**，它的 `libbfd.a` 新增了对 `libsframe`（SFrame 格式支持）的依赖。而 StarRocks 3.2 分支的 CMakeLists.txt 是针对较老的 binutils 编写的，没有链接 `-lsframe`。

**修改内容：**

在 `be/CMakeLists.txt` 第 976 行，在 `-lbfd` 后面加了 `-lsframe`：

```
${WL_LINK_STATIC} -lbfd -lsframe
```

现在你可以重新编译了：

```bash
BUILD_TYPE=Debug ./build.sh --be -j 4
```

```plaintext
${WL_LINK_STATIC} -lbfd -lsframe
```

```shellscript
BUILD_TYPE=Debug ./build.sh --be -j 4
```

---

**User**

由于我cursor崩了，我与你沟通的所有历史信息，改的本地文件，都没改成，我没有备份，你能帮我先总结一下一共要改哪些文件吗？我先看一下，没问题后，让你帮我再改一下，这次我一定备份

---

**Cursor**



好的，我来帮你整理一下。根据我们之前所有对话的历史记录，一共需要修改以下文件：

---

## 需要修改的文件总结

### 1. `thirdparty/build-thirdparty.sh`

这个文件改动最多，涉及多个第三方库的编译修复：

| 修改位置 | 修改内容 | 解决的问题 |
|---------|---------|-----------|
| `build_rocksdb()` 函数中的 `EXTRA_CXXFLAGS` | 添加 `-Wno-redundant-move` 和 `-include cstdint` | RocksDB 编译报 `redundant move` 错误和 `uint64_t does not name a type` 错误 |
| `build_breakpad()` 函数中的 `./configure` | 添加 `CXXFLAGS="${CXXFLAGS} -Wno-nonnull"` | Breakpad 编译报 `-Wnonnull` 错误 |
| `build_pulsar()` 函数中的 `CMAKE_CMD` | 添加 `-DOPENSSL_ROOT_DIR=$TP_INSTALL_DIR` | Pulsar 编译找不到 OpenSSL |
| `build_llvm()` 函数中的 `CMAKE_CMD` | 删除末尾多余的 `../${LLVM_SOURCE}` | LLVM 编译报 `No rule to make target 'LLVMBitstreamReader'` |

### 2. `be/CMakeLists.txt`

| 修改位置 | 修改内容 | 解决的问题 |
|---------|---------|-----------|
| 第 976 行 `-lbfd` 后面 | 添加 `-lsframe` | 链接阶段 `sframe_*` 系列函数 undefined reference（Ubuntu 24.04 binutils 2.42 新增依赖） |

### 3. `docs/zh/learning/在wsl2上进行starrocks编译启动源码debug总结.md`

| 修改内容 | 说明 |
|---------|------|
| 重写了"安装编译依赖"章节 | 强调推荐使用 GCC 10，提供了 Ubuntu 24.04 安装 GCC 10 的步骤，说明 GCC 13+ 不建议使用的原因 |
| 新增了"零、基础准备"章节 | 包含安装 WSL2、下载源码、使用 Cursor/Claude Code、安装 CLion 等子章节 |

### 4. `thirdparty/src/rocksdb-6.22.1/db/compaction/compaction_iteration_stats.h`

| 修改内容 | 说明 |
|---------|------|
| 添加 `#include <cstdint>` | 这个改动**可以不做**，因为后来在 `build-thirdparty.sh` 中通过全局 `-include cstdint` 标志已经覆盖了 |

---

## 总结

**必须修改的核心文件只有 2 个：**
1. **`thirdparty/build-thirdparty.sh`** — 4 处修改，修复第三方库编译
2. **`be/CMakeLists.txt`** — 1 处修改，修复链接 libsframe

**可选修改的文件：**
3. **`docs/zh/learning/在wsl2上进行starrocks编译启动源码debug总结.md`** — 文档完善（推荐 GCC 版本等）
4. **`thirdparty/src/rocksdb-6.22.1/db/compaction/compaction_iteration_stats.h`** — 不需要改（已被全局方案覆盖）

---

你确认没问题后，告诉我，我帮你把这些文件全部改好。建议你先用 `git stash` 或者 `cp` 备份一下当前状态。

---

**User**

1、2、3都改，谢谢

---

**Cursor**



好的，我先读取这三个文件的当前内容，然后逐一修改。

好的，我已经读取了所有三个文件的当前内容。现在开始逐一修改。

### 修改 1：`thirdparty/build-thirdparty.sh`（4 处修改）

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

#################################################################################
# This script will
# 1. Check prerequisite libraries. Including:
#    cmake byacc flex automake libtool binutils-dev libiberty-dev bison
# 2. Compile and install all thirdparties which are downloaded
#    using *download-thirdparty.sh*.
#
# This script will run *download-thirdparty.sh* once again
# to check if all thirdparties have been downloaded, unpacked and patched.
#################################################################################
set -e

curdir=`dirname "$0"`
curdir=`cd "$curdir"; pwd`

export STARROCKS_HOME=${STARROCKS_HOME:-$curdir/..}
export TP_DIR=$curdir

# include custom environment variables
if [[ -f ${STARROCKS_HOME}/env.sh ]]; then
    . ${STARROCKS_HOME}/env.sh
fi

if [[ ! -f ${TP_DIR}/download-thirdparty.sh ]]; then
    echo "Download thirdparty script is missing".
    exit 1
fi

if [ ! -f ${TP_DIR}/vars.sh ]; then
    echo "vars.sh is missing".
    exit 1
fi
. ${TP_DIR}/vars.sh

cd $TP_DIR

# Download thirdparties.
${TP_DIR}/download-thirdparty.sh

# set COMPILER
if [[ ! -z ${STARROCKS_GCC_HOME} ]]; then
    export CC=${STARROCKS_GCC_HOME}/bin/gcc
    export CPP=${STARROCKS_GCC_HOME}/bin/cpp
    export CXX=${STARROCKS_GCC_HOME}/bin/g++
    export PATH=${STARROCKS_GCC_HOME}/bin:$PATH
else
    echo "STARROCKS_GCC_HOME environment variable is not set"
    exit 1
fi

# prepare installed prefix
mkdir -p ${TP_DIR}/installed

check_prerequest() {
    local CMD=$1
    local NAME=$2
    if ! $CMD; then
        echo $NAME is missing
        exit 1
    else
        echo $NAME is found
    fi
}

# sudo apt-get install cmake
# sudo yum install cmake
check_prerequest "${CMAKE_CMD} --version" "cmake"

# sudo apt-get install byacc
# sudo yum install byacc
check_prerequest "byacc -V" "byacc"

# sudo apt-get install flex
# sudo yum install flex
check_prerequest "flex -V" "flex"

# sudo apt-get install automake
# sudo yum install automake
check_prerequest "automake --version" "automake"

# sudo apt-get install libtool
# sudo yum install libtool
check_prerequest "libtoolize --version" "libtool"

BUILD_SYSTEM=${BUILD_SYSTEM:-make}

# sudo apt-get install binutils-dev
# sudo yum install binutils-devel
#check_prerequest "locate libbfd.a" "binutils-dev"

# sudo apt-get install libiberty-dev
# no need in centos 7.1
#check_prerequest "locate libiberty.a" "libiberty-dev"

# sudo apt-get install bison
# sudo yum install bison
#check_prerequest "bison --version" "bison"

#########################
# build all thirdparties
#########################


# Name of cmake build directory in each thirdpary project.
# Do not use `build`, because many projects contained a file named `BUILD`
# and if the filesystem is not case sensitive, `mkdir` will fail.
BUILD_DIR=starrocks_build
MACHINE_TYPE=$(uname -m)

# handle mac m1 platform, change arm64 to aarch64
if [[ "${MACHINE_TYPE}" == "arm64" ]]; then
    MACHINE_TYPE="aarch64"
fi

echo "machine type : $MACHINE_TYPE"

check_if_source_exist() {
    if [ -z $1 ]; then
        echo "dir should specified to check if exist."
        exit 1
    fi

    if [ ! -d $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
    echo "===== begin build $1"
}

check_if_archieve_exist() {
    if [ -z $1 ]; then
        echo "archieve should specified to check if exist."
        exit 1
    fi

    if [ ! -f $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
}

# libevent
build_libevent() {
    check_if_source_exist $LIBEVENT_SOURCE
    cd $TP_SOURCE_DIR/$LIBEVENT_SOURCE
    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

build_openssl() {
    OPENSSL_PLATFORM="linux-x86_64"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        OPENSSL_PLATFORM="linux-aarch64"
    fi

    check_if_source_exist $OPENSSL_SOURCE
    cd $TP_SOURCE_DIR/$OPENSSL_SOURCE

    # use customized CFLAGS/CPPFLAGS/CXXFLAGS/LDFLAGS
    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC"

    LDFLAGS="-L${TP_LIB_DIR}" \
    LIBDIR="lib" \
    ./Configure --prefix=$TP_INSTALL_DIR -lz -no-shared ${OPENSSL_PLATFORM}
    make -j$PARALLEL
    make install_sw

    restore_compile_flags
}

# thrift
build_thrift() {
    check_if_source_exist $THRIFT_SOURCE
    cd $TP_SOURCE_DIR/$THRIFT_SOURCE

    if [ ! -f configure ]; then
        ./bootstrap.sh
    fi

    echo ${TP_LIB_DIR}
    ./configure LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" LIBS="-lssl -lcrypto -ldl" \
    --prefix=$TP_INSTALL_DIR --docdir=$TP_INSTALL_DIR/doc --enable-static --disable-shared --disable-tests \
    --disable-tutorial --without-qt4 --without-qt5 --without-csharp --without-erlang --without-nodejs \
    --without-lua --without-perl --without-php --without-php_extension --without-dart --without-ruby \
    --without-haskell --without-go --without-haxe --without-d --without-python -without-java --with-cpp \
    --with-libevent=$TP_INSTALL_DIR --with-boost=$TP_INSTALL_DIR --with-openssl=$TP_INSTALL_DIR

    if [ -f compiler/cpp/thrifty.hh ];then
        mv compiler/cpp/thrifty.hh compiler/cpp/thrifty.h
    fi

    make -j$PARALLEL
    make install
}

# llvm
build_llvm() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -D_POSIX_C_SOURCE=200112L ${FILE_PREFIX_MAP_OPTION}"
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess ${FILE_PREFIX_MAP_OPTION}"

    LLVM_TARGET="X86"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        LLVM_TARGET="AArch64"
    fi

    LLVM_TARGETS_TO_BUILD=(
        "LLVMBitstreamReader"
        "LLVMRuntimeDyld" 
        "LLVMOption"
        "LLVMAsmPrinter"
        "LLVMProfileData"
        "LLVMAsmParser"
        "LLVMOrcTargetProcess"
        "LLVMExecutionEngine"
        "LLVMBinaryFormat"
        "LLVMDebugInfoDWARF"
        "LLVMObjCARCOpts"
        "LLVMCodeGen"
        "LLVMMCDisassembler"
        "LLVMSupport"
        "LLVMJITLink"
        "LLVMCFGuard"
        "LLVMInstrumentation"
        "LLVMIRReader"
        "LLVMCore"
        "LLVMTarget"
        "LLVMMC"
        "LLVMAnalysis"
        "LLVMGlobalISel"
        "LLVMScalarOpts"
        "LLVMTargetParser"
        "LLVMDemangle"
        "LLVMRemarks"
        "LLVMDebugInfoCodeView"
        "LLVMOrcShared"
        "LLVMOrcJIT"
        "LLVMTextAPI"
        "LLVMBitWriter"
        "LLVMBitReader"
        "LLVMObject"
        "LLVMTransformUtils"
        "LLVMSelectionDAG"
        "LLVMMCParser"
    )
    if [ "${LLVM_TARGET}" == "X86" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMX86Info" "LLVMX86Desc" "LLVMX86CodeGen")
    elif [ "${LLVM_TARGET}" == "AArch64" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMAArch64Info" "LLVMAArch64Desc" "LLVMAArch64CodeGen")
    fi

    LLVM_TARGETS_TO_INSTALL=()
    for target in ${LLVM_TARGETS_TO_BUILD[@]}; do
        LLVM_TARGETS_TO_INSTALL+=("install-${target}")
    done

    check_if_source_exist $LLVM_SOURCE

    cd $TP_SOURCE_DIR
    mkdir -p llvm-build
    cd llvm-build
    rm -rf CMakeCache.txt CMakeFiles/

    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -S ../${LLVM_SOURCE}/llvm -G "${CMAKE_GENERATOR}" \
    -DLLVM_ENABLE_EH:Bool=True \
    -DLLVM_ENABLE_RTTI:Bool=True \
    -DLLVM_ENABLE_PIC:Bool=True \
    -DLLVM_ENABLE_TERMINFO:Bool=False \
    -DLLVM_TARGETS_TO_BUILD=${LLVM_TARGET} \
    -DLLVM_BUILD_LLVM_DYLIB:BOOL=False \
    -DLLVM_INCLUDE_TOOLS:BOOL=False \
    -DLLVM_BUILD_TOOLS:BOOL=False \
    -DLLVM_INCLUDE_EXAMPLES:BOOL=False \
    -DLLVM_INCLUDE_TESTS:BOOL=False \
    -DLLVM_INCLUDE_BENCHMARKS:BOOL=False \
    -DBUILD_SHARED_LIBS:BOOL=False \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}/llvm ../${LLVM_SOURCE}

    # TODO(yueyang): Add more targets.
    # This is a little bit hack, we need to minimize the build time and binary size.
    ${BUILD_SYSTEM} -j$PARALLEL REQUIRES_RTTI=1 ${LLVM_TARGETS_TO_BUILD[@]}
    ${BUILD_SYSTEM} install-llvm-headers
    ${BUILD_SYSTEM} ${LLVM_TARGETS_TO_INSTALL[@]}

    restore_compile_flags
}

# protobuf
build_protobuf() {
    check_if_source_exist $PROTOBUF_SOURCE
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    rm -fr gmock
    mkdir gmock
    cd gmock
    tar xf ${TP_SOURCE_DIR}/$GTEST_NAME
    mv $GTEST_SOURCE gtest
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    ./autogen.sh
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc -pthread -Wl,--whole-archive -lpthread -Wl,--no-whole-archive" \
    ./configure --prefix=${TP_INSTALL_DIR} --disable-shared --enable-static --with-zlib --with-zlib-include=${TP_INSTALL_DIR}/include
    make -j$PARALLEL
    make install
}

# gflags
build_gflags() {
    check_if_source_exist $GFLAGS_SOURCE

    cd $TP_SOURCE_DIR/$GFLAGS_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# glog
build_glog() {
    check_if_source_exist $GLOG_SOURCE
    cd $TP_SOURCE_DIR/$GLOG_SOURCE

    # to generate config.guess and config.sub to support aarch64
    rm -rf config.*
    autoreconf -i

    LDFLAGS="-L${TP_LIB_DIR}" \
    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-frame-pointers --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

# gtest
build_gtest() {
    check_if_source_exist $GTEST_SOURCE

    cd $TP_SOURCE_DIR/$GTEST_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# rapidjson
build_rapidjson() {
    check_if_source_exist $RAPIDJSON_SOURCE

    rm -rf $TP_INSTALL_DIR/rapidjson
    cp -r $TP_SOURCE_DIR/$RAPIDJSON_SOURCE/include/rapidjson $TP_INCLUDE_DIR/
}

# simdjson
build_simdjson() {
    check_if_source_exist $SIMDJSON_SOURCE
    cd $TP_SOURCE_DIR/$SIMDJSON_SOURCE

    #ref: https://github.com/simdjson/simdjson/blob/master/HACKING.md
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_CXX_FLAGS="-O3" -DCMAKE_C_FLAGS="-O3" -DCMAKE_POSITION_INDEPENDENT_CODE=True -DSIMDJSON_AVX512_ALLOWED=OFF ..
    $CMAKE_CMD --build .
    mkdir -p $TP_INSTALL_DIR/lib

    cp $TP_SOURCE_DIR/$SIMDJSON_SOURCE/$BUILD_DIR/libsimdjson.a $TP_INSTALL_DIR/lib
    cp -r $TP_SOURCE_DIR/$SIMDJSON_SOURCE/include/* $TP_INCLUDE_DIR/
}

# snappy
build_snappy() {
    check_if_source_exist $SNAPPY_SOURCE
    cd $TP_SOURCE_DIR/$SNAPPY_SOURCE

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -G "${CMAKE_GENERATOR}" \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On \
    -DCMAKE_INSTALL_INCLUDEDIR=$TP_INCLUDE_DIR/snappy \
    -DSNAPPY_BUILD_TESTS=0 ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    if [ -f $TP_INSTALL_DIR/lib64/libsnappy.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib
        cp $TP_INSTALL_DIR/lib64/libsnappy.a $TP_INSTALL_DIR/lib/libsnappy.a
    fi

    #build for libarrow.a
    cp $TP_INCLUDE_DIR/snappy/snappy-c.h  $TP_INCLUDE_DIR/snappy-c.h
    cp $TP_INCLUDE_DIR/snappy/snappy-sinksource.h  $TP_INCLUDE_DIR/snappy-sinksource.h
    cp $TP_INCLUDE_DIR/snappy/snappy-stubs-public.h  $TP_INCLUDE_DIR/snappy-stubs-public.h
    cp $TP_INCLUDE_DIR/snappy/snappy.h  $TP_INCLUDE_DIR/snappy.h
    cp $TP_INSTALL_DIR/lib/libsnappy.a $TP_INSTALL_DIR/libsnappy.a
}

# gperftools
build_gperftools() {
    check_if_source_exist $GPERFTOOLS_SOURCE
    cd $TP_SOURCE_DIR/$GPERFTOOLS_SOURCE

    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=$TP_INSTALL_DIR/gperftools --disable-shared --enable-static --disable-libunwind --with-pic --enable-frame-pointers
    make -j$PARALLEL
    make install
}

# zlib
build_zlib() {
    check_if_source_exist $ZLIB_SOURCE
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --static
    make -j$PARALLEL
    make install

    # build minizip
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE/contrib/minizip
    autoreconf --force --install
    ./configure --prefix=$TP_INSTALL_DIR --enable-static=yes --enable-shared=no
    make -j$PARALLEL
    make install
}

# lz4
build_lz4() {
    check_if_source_exist $LZ4_SOURCE
    cd $TP_SOURCE_DIR/$LZ4_SOURCE

    make -C lib -j$PARALLEL install PREFIX=$TP_INSTALL_DIR \
    INCLUDEDIR=$TP_INCLUDE_DIR/lz4/ BUILD_SHARED=no
}

# lzo
build_lzo2() {
    check_if_source_exist $LZO2_SOURCE
    cd $TP_SOURCE_DIR/$LZO2_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
        LDFLAGS="-L${TP_LIB_DIR}" \
        ./configure --prefix="${TP_INSTALL_DIR}" --disable-shared --enable-static

    make -j "${PARALLEL}"
    make install
}

# bzip
build_bzip() {
    check_if_source_exist $BZIP_SOURCE
    cd $TP_SOURCE_DIR/$BZIP_SOURCE

    make -j$PARALLEL install PREFIX=$TP_INSTALL_DIR
}

# curl
build_curl() {
    check_if_source_exist $CURL_SOURCE
    cd $TP_SOURCE_DIR/$CURL_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" LIBS="-lssl -lcrypto -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static \
    --without-librtmp --with-ssl=${TP_INSTALL_DIR} --without-libidn2 --without-libgsasl --disable-ldap --enable-ipv6 --without-brotli
    make -j$PARALLEL
    make install
}

# re2
build_re2() {
    check_if_source_exist $RE2_SOURCE
    cd $TP_SOURCE_DIR/$RE2_SOURCE

    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release \
	    -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL install
}

# boost
build_boost() {
    check_if_source_exist $BOOST_SOURCE
    cd $TP_SOURCE_DIR/$BOOST_SOURCE

    # It is difficult to generate static linked b2, so we use LD_LIBRARY_PATH instead
    ./bootstrap.sh --prefix=$TP_INSTALL_DIR
    LD_LIBRARY_PATH=${STARROCKS_GCC_HOME}/lib:${STARROCKS_GCC_HOME}/lib64:${LD_LIBRARY_PATH} \
    ./b2 link=static runtime-link=static -j $PARALLEL --without-test --without-mpi --without-graph --without-graph_parallel --without-python cxxflags="-std=c++11 -g -fPIC -I$TP_INCLUDE_DIR -L$TP_LIB_DIR ${FILE_PREFIX_MAP_OPTION}" install
}

#leveldb
build_leveldb() {
    check_if_source_exist $LEVELDB_SOURCE
    cd $TP_SOURCE_DIR/$LEVELDB_SOURCE
    LDFLAGS="-L ${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    make -j$PARALLEL
    cp out-static/libleveldb.a $TP_LIB_DIR/libleveldb.a
    cp -r include/leveldb $TP_INCLUDE_DIR
}

# brpc
build_brpc() {
    check_if_source_exist $BRPC_SOURCE

    cd $TP_SOURCE_DIR/$BRPC_SOURCE
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    ./config_brpc.sh --headers="$TP_INSTALL_DIR/include" --libs="$TP_INSTALL_DIR/bin $TP_INSTALL_DIR/lib" --with-glog
    make -j$PARALLEL
    cp -rf output/* ${TP_INSTALL_DIR}/
    if [ -f $TP_INSTALL_DIR/lib/libbrpc.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib64
        cp $TP_SOURCE_DIR/$BRPC_SOURCE/output/lib/libbrpc.a $TP_INSTALL_DIR/lib64/
    fi
}

# rocksdb
build_rocksdb() {
    check_if_source_exist $ROCKSDB_SOURCE

    cd $TP_SOURCE_DIR/$ROCKSDB_SOURCE
    make clean

    CFLAGS= \
    EXTRA_CFLAGS="-I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy -I ${TP_INCLUDE_DIR}/lz4 -L${TP_LIB_DIR} ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_CXXFLAGS="-fPIC -Wno-deprecated-copy -Wno-stringop-truncation -Wno-pessimizing-move -Wno-redundant-move -I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy -include cstdint ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_LDFLAGS="-static-libstdc++ -static-libgcc" \
    PORTABLE=1 make USE_RTTI=1 -j$PARALLEL static_lib

    cp librocksdb.a $TP_LIB_DIR/librocksdb.a
    cp -r include/rocksdb $TP_INCLUDE_DIR
}

# kerberos
build_kerberos() {
    check_if_source_exist $KRB5_SOURCE
    cd $TP_SOURCE_DIR/$KRB5_SOURCE/src
    CFLAGS="-fcommon -fPIC ${FILE_PREFIX_MAP_OPTION}" LDFLAGS="-L$TP_INSTALL_DIR/lib -pthread -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-static --disable-shared --with-spake-openssl=$TP_INSTALL_DIR
    make -j$PARALLEL
    make install
}

# sasl
build_sasl() {
    check_if_source_exist $SASL_SOURCE
    cd $TP_SOURCE_DIR/$SASL_SOURCE
    CFLAGS="-fPIC" LDFLAGS="-L$TP_INSTALL_DIR/lib -lresolv -pthread -ldl" ./autogen.sh --prefix=$TP_INSTALL_DIR --enable-gssapi=yes --enable-static --disable-shared --with-openssl=$TP_INSTALL_DIR --with-gss_impl=mit
    make -j$PARALLEL
    make install
}

# librdkafka
build_librdkafka() {
    check_if_source_exist $LIBRDKAFKA_SOURCE

    cd $TP_SOURCE_DIR/$LIBRDKAFKA_SOURCE

    mkdir -p sr_build && cd sr_build
    $CMAKE_CMD -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" \
        -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include;$TP_INSTALL_DIR/include/zstd;$TP_INSTALL_DIR/include/lz4" \
        -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DRDKAFKA_BUILD_STATIC=ON -DWITH_SASL=ON -DWITH_SASL_SCRAM=ON \
        -DRDKAFKA_BUILD_EXAMPLES=OFF -DRDKAFKA_BUILD_TESTS=OFF -DWITH_SSL=ON -DWITH_ZSTD=ON -DCMAKE_INSTALL_LIBDIR=lib ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# pulsar
build_pulsar() {
    check_if_source_exist $PULSAR_SOURCE

    cd $TP_SOURCE_DIR/$PULSAR_SOURCE

    $CMAKE_CMD -DCMAKE_LIBRARY_PATH=$TP_INSTALL_DIR/lib -DCMAKE_INCLUDE_PATH=$TP_INSTALL_DIR/include \
        -DPROTOC_PATH=$TP_INSTALL_DIR/bin/protoc -DBUILD_TESTS=OFF -DBUILD_PYTHON_WRAPPER=OFF -DBUILD_DYNAMIC_LIB=OFF .
    ${BUILD_SYSTEM} -j$PARALLEL

    cp lib/libpulsar.a $TP_INSTALL_DIR/lib/
    cp -r include/pulsar $TP_INSTALL_DIR/include/
}

# flatbuffers
build_flatbuffers() {
  check_if_source_exist $FLATBUFFERS_SOURCE
  cd $TP_SOURCE_DIR/$FLATBUFFERS_SOURCE
  mkdir -p $BUILD_DIR
  cd $BUILD_DIR
  rm -rf CMakeCache.txt CMakeFiles/
  LDFLAGS="-static-libstdc++ -static-libgcc" \
  ${CMAKE_CMD} .. -G "${CMAKE_GENERATOR}" -DFLATBUFFERS_BUILD_TESTS=OFF
  ${BUILD_SYSTEM} -j$PARALLEL
  cp flatc  $TP_INSTALL_DIR/bin/flatc
  cp -r ../include/flatbuffers  $TP_INCLUDE_DIR/flatbuffers
  cp libflatbuffers.a $TP_LIB_DIR/libflatbuffers.a
}

build_brotli() {
    check_if_source_exist $BROTLI_SOURCE
    cd $TP_SOURCE_DIR/$BROTLI_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    ${CMAKE_CMD} .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib64
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    mv -f $TP_INSTALL_DIR/lib64/libbrotlienc-static.a $TP_INSTALL_DIR/lib64/libbrotlienc.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlidec-static.a $TP_INSTALL_DIR/lib64/libbrotlidec.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlicommon-static.a $TP_INSTALL_DIR/lib64/libbrotlicommon.a
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so.*
}

# arrow
build_arrow() {
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CPPFLAGS=$CXXFLAGS

    check_if_source_exist $ARROW_SOURCE
    cd $TP_SOURCE_DIR/$ARROW_SOURCE/cpp
    mkdir -p release
    cd release
    export ARROW_BROTLI_URL=${TP_SOURCE_DIR}/${BROTLI_NAME}
    export ARROW_GLOG_URL=${TP_SOURCE_DIR}/${GLOG_NAME}
    export ARROW_LZ4_URL=${TP_SOURCE_DIR}/${LZ4_NAME}
    export ARROW_SNAPPY_URL=${TP_SOURCE_DIR}/${SNAPPY_NAME}
    export ARROW_ZLIB_URL=${TP_SOURCE_DIR}/${ZLIB_NAME}
    export ARROW_FLATBUFFERS_URL=${TP_SOURCE_DIR}/${FLATBUFFERS_NAME}
    export ARROW_ZSTD_URL=${TP_SOURCE_DIR}/${ZSTD_NAME}
    export LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc"

    # https://github.com/apache/arrow/blob/apache-arrow-5.0.0/cpp/src/arrow/memory_pool.cc#L286
    #
    # JemallocAllocator use mallocx and rallocx to allocate new memory, but mallocx and rallocx are Non-standard APIs,
    # and can not be hooked in BE, the memory used by arrow can not be counted by BE,
    # so disable jemalloc here and use SystemAllocator.
    #
    # Currently, the standard APIs are hooked in BE, so the jemalloc standard APIs will actually be used.
    ${CMAKE_CMD} -DARROW_PARQUET=ON -DARROW_JSON=ON -DARROW_IPC=ON -DARROW_USE_GLOG=OFF -DARROW_BUILD_STATIC=ON -DARROW_BUILD_SHARED=OFF \
    -DARROW_WITH_BROTLI=ON -DARROW_WITH_LZ4=ON -DARROW_WITH_SNAPPY=ON -DARROW_WITH_ZLIB=ON -DARROW_WITH_ZSTD=ON \
    -DARROW_WITH_UTF8PROC=OFF -DARROW_WITH_RE2=OFF \
    -DARROW_JEMALLOC=OFF -DARROW_MIMALLOC=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DARROW_BOOST_USE_SHARED=OFF -DARROW_GFLAGS_USE_SHARED=OFF -DBoost_NO_BOOST_CMAKE=ON -DBOOST_ROOT=$TP_INSTALL_DIR \
    -DJEMALLOC_HOME=$TP_INSTALL_DIR/jemalloc \
    -Dzstd_SOURCE=BUNDLED \
    -DRapidJSON_ROOT=$TP_INSTALL_DIR \
    -DARROW_SNAPPY_USE_SHARED=OFF \
    -DZLIB_ROOT=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DARROW_LZ4_USE_SHARED=OFF \
    -DBROTLI_ROOT=$TP_INSTALL_DIR \
    -DARROW_BROTLI_USE_SHARED=OFF \
    -Dgflags_ROOT=$TP_INSTALL_DIR/ \
    -DSnappy_ROOT=$TP_INSTALL_DIR/ \
    -DGLOG_ROOT=$TP_INSTALL_DIR/ \
    -DLZ4_ROOT=$TP_INSTALL_DIR/ \
    -DBoost_DIR=$TP_INSTALL_DIR \
    -DBoost_ROOT=$TP_INSTALL_DIR \
    -DARROW_BOOST_USE_SHARED=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DThrift_ROOT=$TP_INSTALL_DIR/ ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    if [ -f ./zstd_ep-install/lib64/libzstd.a ]; then
        cp -rf ./zstd_ep-install/lib64/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    else
        cp -rf ./zstd_ep-install/lib/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    fi
    # copy zstd headers
    mkdir -p ${TP_INSTALL_DIR}/include/zstd
    cp ./zstd_ep-install/include/* ${TP_INSTALL_DIR}/include/zstd

    restore_compile_flags
}

# s2
build_s2() {
    check_if_source_exist $S2_SOURCE
    cd $TP_SOURCE_DIR/$S2_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DBUILD_SHARED_LIBS=OFF \
    -DGFLAGS_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GFLAGS=ON \
    -DGLOG_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GLOG=ON \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# bitshuffle
build_bitshuffle() {
    check_if_source_exist $BITSHUFFLE_SOURCE
    cd $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE
    PREFIX=$TP_INSTALL_DIR

    # This library has significant optimizations when built with -mavx2. However,
    # we still need to support non-AVX2-capable hardware. So, we build it twice,
    # once with the flag and once without, and use some linker tricks to
    # suffix the AVX2 symbols with '_avx2'.
    arches="default avx2 avx512"
    # Becuase aarch64 don't support avx2, disable it.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        arches="default neon"
    fi

    to_link=""
    for arch in $arches ; do
        arch_flag=""
        if [ "$arch" == "avx2" ]; then
            arch_flag="-mavx2"
        elif [ "$arch" == "avx512" ]; then
            arch_flag="-march=icelake-server"
        elif [ "$arch" == "neon" ]; then
            arch_flag="-march=armv8-a+crc"
        fi
        tmp_obj=bitshuffle_${arch}_tmp.o
        dst_obj=bitshuffle_${arch}.o
        ${CC:-gcc} $EXTRA_CFLAGS $arch_flag -std=c99 -I$PREFIX/include/lz4/ -O3 -DNDEBUG -fPIC -c \
            "src/bitshuffle_core.c" \
            "src/bitshuffle.c" \
            "src/iochain.c"
        # Merge the object files together to produce a combined .o file.
        ld -r -o $tmp_obj bitshuffle_core.o bitshuffle.o iochain.o
        # For the AVX2 symbols, suffix them.
        if [[ "$arch" == "avx2" || "$arch" == "avx512" || "$arch" == "neon" ]]; then
            # Create a mapping file with '<old_sym> <suffixed_sym>' on each line.
            nm --defined-only --extern-only $tmp_obj | while read addr type sym ; do
              echo ${sym} ${sym}_${arch}
            done > renames.txt
            objcopy --redefine-syms=renames.txt $tmp_obj $dst_obj
        else
            mv $tmp_obj $dst_obj
        fi
        to_link="$to_link $dst_obj"
    done
    rm -f libbitshuffle.a
    ar rs libbitshuffle.a $to_link
    mkdir -p $PREFIX/include/bitshuffle
    cp libbitshuffle.a $PREFIX/lib/
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle.h $PREFIX/include/bitshuffle/bitshuffle.h
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle_core.h $PREFIX/include/bitshuffle/bitshuffle_core.h
}

# croaring bitmap
# If open AVX512 default, current version will be compiled failed on some machine, so close AVX512 default,
# When this problem is solved, a switch will be added to control.
build_croaringbitmap() {
    FORCE_AVX=ON
    # avx2 is not supported by aarch64.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        FORCE_AVX=FALSE
    fi
    if [[ `cat /proc/cpuinfo |grep avx|wc -l` == "0" ]]; then
        FORCE_AVX=FALSE
    fi
    check_if_source_exist $CROARINGBITMAP_SOURCE
    cd $TP_SOURCE_DIR/$CROARINGBITMAP_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DROARING_BUILD_STATIC=ON -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DENABLE_ROARING_TESTS=OFF \
    -DROARING_DISABLE_NATIVE=ON \
    -DFORCE_AVX=$FORCE_AVX \
    -DROARING_DISABLE_AVX512=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}
#orc
build_orc() {
    check_if_source_exist $ORC_SOURCE
    cd $TP_SOURCE_DIR/$ORC_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD ../ -DBUILD_JAVA=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DPROTOBUF_HOME=$TP_INSTALL_DIR \
    -DSNAPPY_HOME=$TP_INSTALL_DIR \
    -DGTEST_HOME=$TP_INSTALL_DIR \
    -DLZ4_HOME=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DZLIB_HOME=$TP_INSTALL_DIR\
    -DBUILD_LIBHDFSPP=OFF \
    -DBUILD_CPP_TESTS=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#cctz
build_cctz() {
    check_if_source_exist $CCTZ_SOURCE
    cd $TP_SOURCE_DIR/$CCTZ_SOURCE

    make -j$PARALLEL
    PREFIX=${TP_INSTALL_DIR} make install
}

#fmt
build_fmt() {
    check_if_source_exist $FMT_SOURCE
    cd $TP_SOURCE_DIR/$FMT_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} ../ \
            -DCMAKE_INSTALL_LIBDIR=lib64 -G "${CMAKE_GENERATOR}" -DFMT_TEST=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#ryu
build_ryu() {
    check_if_source_exist $RYU_SOURCE
    cd $TP_SOURCE_DIR/$RYU_SOURCE/ryu
    make -j$PARALLEL
    make install DESTDIR=${TP_INSTALL_DIR}
    mkdir -p $TP_INSTALL_DIR/include/ryu
    mv $TP_INSTALL_DIR/include/ryu.h $TP_INSTALL_DIR/include/ryu
    # copy to 64 to compatable with current CMake
    cp -f ${TP_INSTALL_DIR}/lib/libryu.a ${TP_INSTALL_DIR}/lib64/libryu.a
}

#break_pad
build_breakpad() {
    check_if_source_exist $BREAK_PAD_SOURCE
    cd $TP_SOURCE_DIR/$BREAK_PAD_SOURCE
    mkdir -p src/third_party/lss
    cp $TP_PATCH_DIR/linux_syscall_support.h src/third_party/lss
    CFLAGS= ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

#hadoop
build_hadoop() {
    check_if_source_exist $HADOOP_SOURCE
    cp -r $TP_SOURCE_DIR/$HADOOP_SOURCE $TP_INSTALL_DIR/hadoop
    # remove unnecessary doc and logs
    rm -rf $TP_INSTALL_DIR/hadoop/logs/* $TP_INSTALL_DIR/hadoop/share/doc/hadoop
    mkdir -p $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/include/hdfs.h $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/lib/native/libhdfs.a $TP_INSTALL_DIR/lib
}

#jdk
build_jdk() {
    check_if_source_exist $JDK_SOURCE
    rm -rf $TP_INSTALL_DIR/open_jdk && cp -r $TP_SOURCE_DIR/$JDK_SOURCE $TP_INSTALL_DIR/open_jdk
}

# ragel
# ragel-6.9+ is used by hypercan, so we build it first.
build_ragel() {
    check_if_source_exist $RAGEL_SOURCE
    cd $TP_SOURCE_DIR/$RAGEL_SOURCE
    # generage a static linked ragel, hyperscan will depend on it
    LDFLAGS=" -static-libstdc++ -static-libgcc" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

#hyperscan
build_hyperscan() {
    check_if_source_exist $HYPERSCAN_SOURCE
    cd $TP_SOURCE_DIR/$HYPERSCAN_SOURCE
    export PATH=$TP_INSTALL_DIR/bin:$PATH
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DBOOST_ROOT=$STARROCKS_THIRDPARTY/installed/include \
          -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc  -DCMAKE_INSTALL_LIBDIR=lib \
          -DBUILD_EXAMPLES=OFF -DBUILD_UNIT=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#mariadb-connector-c
build_mariadb() {
    OLD_CMAKE_GENERATOR=${CMAKE_GENERATOR}
    OLD_BUILD_SYSTEM=${BUILD_SYSTEM}

    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC ${FILE_PREFIX_MAP_OPTION}"

    # force use make build system, since ninja doesn't support install only headers
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'

    check_if_source_exist $MARIADB_SOURCE
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE
    mkdir -p build && cd build

    $CMAKE_CMD .. -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release    \
                  -DWITH_UNIT_TESTS=OFF                                 \
                  -DBUILD_SHARED_LIBS=OFF                               \
                  -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                  \
                  -DOPENSSL_USE_STATIC_LIBS=TRUE                        \
                  -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}
    # we only need build libmariadbclient and headers
    ${BUILD_SYSTEM} -j$PARALLEL mariadbclient
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/libmariadb
    mkdir -p $TP_INSTALL_DIR/lib/mariadb/
    cp libmariadbclient.a $TP_INSTALL_DIR/lib/mariadb/
    # install mariadb headers
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/include
    ${BUILD_SYSTEM} install

    restore_compile_flags
    export CMAKE_GENERATOR=$OLD_CMAKE_GENERATOR
    export BUILD_SYSTEM=$OLD_BUILD_SYSTEM
}

# jindosdk for Aliyun OSS
build_aliyun_jindosdk() {
    check_if_source_exist $JINDOSDK_SOURCE
    mkdir -p $TP_INSTALL_DIR/jindosdk
    cp -r $TP_SOURCE_DIR/$JINDOSDK_SOURCE/lib/*.jar $TP_INSTALL_DIR/jindosdk
}

build_gcs_connector() {
    check_if_source_exist $GCS_CONNECTOR_SOURCE
    mkdir -p $TP_INSTALL_DIR/gcs_connector
    cp -r $TP_SOURCE_DIR/$GCS_CONNECTOR_SOURCE/*.jar $TP_INSTALL_DIR/gcs_connector
}

build_broker_thirdparty_jars() {
    check_if_source_exist $BROKER_THIRDPARTY_JARS_SOURCE
    mkdir -p $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    cp -r $TP_SOURCE_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/* $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/hadoop-aliyun-2.7.2.jar
    # cloudfs-hadoop-with-dependencies will include aws jars, but we already support aws by official sdk, so we don't need it anymore.
    # And it will conflict with Iceberg's S3FileIO, make access S3 files failed.
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/cloudfs-hadoop-with-dependencies-1.1.21.jar
    # ensure read permission is granted for all users
    chmod -R +r $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/
}

build_aws_cpp_sdk() {
    check_if_source_exist $AWS_SDK_CPP_SOURCE
    cd $TP_SOURCE_DIR/$AWS_SDK_CPP_SOURCE
    # only build s3, s3-crt, transfer manager, identity-management and sts, you can add more components if you want.
    $CMAKE_CMD -Bbuild -DBUILD_ONLY="core;s3;s3-crt;transfer;identity-management;sts" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
               -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DENABLE_TESTING=OFF \
               -DENABLE_CURL_LOGGING=OFF \
               -G "${CMAKE_GENERATOR}" \
               -DCURL_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libcurl.a   \
               -DZLIB_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libz.a      \
               -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                     \
               -DOPENSSL_USE_STATIC_LIBS=TRUE                           \
               -Dcrypto_LIBRARY=${TP_INSTALL_DIR}/lib/libcrypto.a

    cd build
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    restore_compile_flags
}

# velocypack
build_vpack() {
    check_if_source_exist $VPACK_SOURCE
    cd $TP_SOURCE_DIR/$VPACK_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# opentelemetry
build_opentelemetry() {
    check_if_source_exist $OPENTELEMETRY_SOURCE

    cd $TP_SOURCE_DIR/$OPENTELEMETRY_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DBUILD_TESTING=OFF -DWITH_EXAMPLES=OFF \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        -DWITH_STL=OFF -DWITH_JAEGER=ON
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# jemalloc
build_jemalloc() {
    check_if_source_exist $JEMALLOC_SOURCE

    cd $TP_SOURCE_DIR/$JEMALLOC_SOURCE
    # jemalloc supports a runtime page size that's smaller or equal to the build
    # time one, but aborts on a larger one. If not defined, it falls back to the
    # the build system's _SC_PAGESIZE, which in many architectures can vary. Set
    # this to 64K (2^16) for arm architecture, and default 4K on x86 for performance.
    local addition_opts=" --with-lg-page=12"
    if [[ $MACHINE_TYPE == "aarch64" ]] ; then
        # change to 64K for arm architecture
        addition_opts=" --with-lg-page=16"
    fi
    # build jemalloc with release
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc --with-jemalloc-prefix=je --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
    # build jemalloc with debug options
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc-debug --with-jemalloc-prefix=je --enable-prof --enable-debug --enable-fill --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
}

# google benchmark
build_benchmark() {
    check_if_source_exist $BENCHMARK_SOURCE
    cd $TP_SOURCE_DIR/$BENCHMARK_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    cmake -DBENCHMARK_DOWNLOAD_DEPENDENCIES=off \
          -DBENCHMARK_ENABLE_GTEST_TESTS=off \
          -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
          -DCMAKE_INSTALL_LIBDIR=lib64 \
          -DCMAKE_BUILD_TYPE=Release ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# fast float
build_fast_float() {
    check_if_source_exist $FAST_FLOAT_SOURCE
    cd $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE
    cp -r $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE/include $TP_INSTALL_DIR
}

build_starcache() {
    check_if_source_exist $STARCACHE_SOURCE
    rm -rf $TP_INSTALL_DIR/$STARCACHE_SOURCE && mv $TP_SOURCE_DIR/$STARCACHE_SOURCE $TP_INSTALL_DIR/
}

# streamvbyte
build_streamvbyte() {
    check_if_source_exist $STREAMVBYTE_SOURCE

    cd $TP_SOURCE_DIR/$STREAMVBYTE_SOURCE/

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/

    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    $CMAKE_CMD .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=$TP_INSTALL_DIR/

    make -j$PARALLEL
    make install
}

# jansson
build_jansson() {
    check_if_source_exist $JANSSON_SOURCE
    cd $TP_SOURCE_DIR/$JANSSON_SOURCE/
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# avro-c
build_avro_c() {
    check_if_source_exist $AVRO_SOURCE
    cd $TP_SOURCE_DIR/$AVRO_SOURCE/lang/c
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    rm ${TP_INSTALL_DIR}/lib64/libavro.so*
}

# serders
build_serdes() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g"
    check_if_source_exist $SERDES_SOURCE
    cd $TP_SOURCE_DIR/$SERDES_SOURCE
    export LIBS="-lrt -lpthread -lcurl -ljansson -lrdkafka -lrdkafka++ -lavro -lssl -lcrypto -ldl"
    ./configure --prefix=${TP_INSTALL_DIR} \
                --libdir=${TP_INSTALL_DIR}/lib \
                --CFLAGS="-I ${TP_INSTALL_DIR}/include"  \
                --CXXFLAGS="-I ${TP_INSTALL_DIR}/include" \
                --LDFLAGS="-L ${TP_INSTALL_DIR}/lib -L ${TP_INSTALL_DIR}/lib64" \
                --enable-static \
                --disable-shared

    make -j$PARALLEL
    make install
    rm ${TP_INSTALL_DIR}/lib/libserdes.so*
    # these symbols also be definition in librdkafka, change these symbols to be local.
    objcopy --localize-symbol=cnd_timedwait ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=cnd_timedwait_ms ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=thrd_is_current ${TP_INSTALL_DIR}/lib/libserdes.a
    unset LIBS
    restore_compile_flags
}

# datasketches
build_datasketches() {
    check_if_source_exist $DATASKETCHES_SOURCE
    mkdir -p $TP_INSTALL_DIR/include/datasketches
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/common/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/cpc/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/fi/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/hll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/kll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/quantiles/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/req/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/sampling/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/theta/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/tuple/include/* $TP_INSTALL_DIR/include/datasketches/
}

# async-profiler
build_async_profiler() {
    check_if_source_exist $ASYNC_PROFILER_SOURCE
    mkdir -p $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/build $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/profiler.sh $TP_INSTALL_DIR/async-profiler
}

# fiu
build_fiu() {
    check_if_source_exist $FIU_SOURCE
    cd $TP_SOURCE_DIR/$FIU_SOURCE
    mkdir -p $TP_SOURCE_DIR/$FIU_SOURCE/installed
    make -j$PARALLEL
    make PREFIX=$TP_SOURCE_DIR/$FIU_SOURCE/installed install

    mkdir -p $TP_INSTALL_DIR/include/fiu
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/include/* $TP_INSTALL_DIR/include/fiu/
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/lib/libfiu.a $TP_INSTALL_DIR/lib/
}

# libdeflate
build_libdeflate() {
    check_if_source_exist $LIBDEFLATE_SOURCE
    mkdir -p $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    cd $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    $CMAKE_CMD .. -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# restore cxxflags/cppflags/cflags to default one
restore_compile_flags() {
    # c preprocessor flags
    export CPPFLAGS=$GLOBAL_CPPFLAGS
    # c flags
    export CFLAGS=$GLOBAL_CFLAGS
    # c++ flags
    export CXXFLAGS=$GLOBAL_CXXFLAGS
}

strip_binary() {
    # strip binary tools and ignore any errors
    echo "Strip binaries in $TP_INSTALL_DIR/bin/ ..."
    strip $TP_INSTALL_DIR/bin/* 2>/dev/null || true
}


# strip `$TP_SOURCE_DIR` and `$TP_INSTALL_DIR` from source code file path
export FILE_PREFIX_MAP_OPTION="-ffile-prefix-map=${TP_SOURCE_DIR}=. -ffile-prefix-map=${TP_INSTALL_DIR}=."
# set GLOBAL_C*FLAGS for easy restore in each sub build process
export GLOBAL_CPPFLAGS="-I ${TP_INCLUDE_DIR}"
# https://stackoverflow.com/questions/42597685/storage-size-of-timespec-isnt-known
export GLOBAL_CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -fPIC -g -D_POSIX_C_SOURCE=200112L -gz=zlib ${FILE_PREFIX_MAP_OPTION}"
export GLOBAL_CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess -fPIC -g -gz=zlib ${FILE_PREFIX_MAP_OPTION}"

# set those GLOBAL_*FLAGS to the CFLAGS/CXXFLAGS/CPPFLAGS
export CPPFLAGS=$GLOBAL_CPPFLAGS
export CXXFLAGS=$GLOBAL_CXXFLAGS
export CFLAGS=$GLOBAL_CFLAGS

build_libevent
build_zlib
build_lz4
build_lzo2
build_bzip
build_openssl
build_boost # must before thrift
build_protobuf
build_gflags
build_gtest
build_glog
build_rapidjson
build_simdjson
build_snappy
build_gperftools
build_curl
build_re2
build_thrift
build_leveldb
build_brpc
build_rocksdb
build_kerberos
build_sasl
build_flatbuffers
build_jemalloc
build_brotli
# must build before arrow
build_arrow
# NOTE: librdkafka depends on ZSTD which is generated by Arrow, So this SHOULD be
# built after arrow
build_librdkafka
build_pulsar
build_s2
build_bitshuffle
build_croaringbitmap
build_cctz
build_fmt
build_ryu
build_hadoop
build_jdk
build_ragel
build_hyperscan
build_mariadb
build_aliyun_jindosdk
build_gcs_connector
build_broker_thirdparty_jars
build_aws_cpp_sdk
build_vpack
build_opentelemetry
build_benchmark
build_fast_float
build_starcache
build_streamvbyte
build_jansson
build_avro_c
build_serdes
build_datasketches
build_async_profiler
build_fiu
build_llvm

if [[ "${MACHINE_TYPE}" != "aarch64" ]]; then
    build_breakpad
    build_libdeflate
fi

# strip unnecessary debug symbol for binaries in thirdparty
strip_binary

echo "Finished to build all thirdparties"

```

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

#################################################################################
# This script will
# 1. Check prerequisite libraries. Including:
#    cmake byacc flex automake libtool binutils-dev libiberty-dev bison
# 2. Compile and install all thirdparties which are downloaded
#    using *download-thirdparty.sh*.
#
# This script will run *download-thirdparty.sh* once again
# to check if all thirdparties have been downloaded, unpacked and patched.
#################################################################################
set -e

curdir=`dirname "$0"`
curdir=`cd "$curdir"; pwd`

export STARROCKS_HOME=${STARROCKS_HOME:-$curdir/..}
export TP_DIR=$curdir

# include custom environment variables
if [[ -f ${STARROCKS_HOME}/env.sh ]]; then
    . ${STARROCKS_HOME}/env.sh
fi

if [[ ! -f ${TP_DIR}/download-thirdparty.sh ]]; then
    echo "Download thirdparty script is missing".
    exit 1
fi

if [ ! -f ${TP_DIR}/vars.sh ]; then
    echo "vars.sh is missing".
    exit 1
fi
. ${TP_DIR}/vars.sh

cd $TP_DIR

# Download thirdparties.
${TP_DIR}/download-thirdparty.sh

# set COMPILER
if [[ ! -z ${STARROCKS_GCC_HOME} ]]; then
    export CC=${STARROCKS_GCC_HOME}/bin/gcc
    export CPP=${STARROCKS_GCC_HOME}/bin/cpp
    export CXX=${STARROCKS_GCC_HOME}/bin/g++
    export PATH=${STARROCKS_GCC_HOME}/bin:$PATH
else
    echo "STARROCKS_GCC_HOME environment variable is not set"
    exit 1
fi

# prepare installed prefix
mkdir -p ${TP_DIR}/installed

check_prerequest() {
    local CMD=$1
    local NAME=$2
    if ! $CMD; then
        echo $NAME is missing
        exit 1
    else
        echo $NAME is found
    fi
}

# sudo apt-get install cmake
# sudo yum install cmake
check_prerequest "${CMAKE_CMD} --version" "cmake"

# sudo apt-get install byacc
# sudo yum install byacc
check_prerequest "byacc -V" "byacc"

# sudo apt-get install flex
# sudo yum install flex
check_prerequest "flex -V" "flex"

# sudo apt-get install automake
# sudo yum install automake
check_prerequest "automake --version" "automake"

# sudo apt-get install libtool
# sudo yum install libtool
check_prerequest "libtoolize --version" "libtool"

BUILD_SYSTEM=${BUILD_SYSTEM:-make}

# sudo apt-get install binutils-dev
# sudo yum install binutils-devel
#check_prerequest "locate libbfd.a" "binutils-dev"

# sudo apt-get install libiberty-dev
# no need in centos 7.1
#check_prerequest "locate libiberty.a" "libiberty-dev"

# sudo apt-get install bison
# sudo yum install bison
#check_prerequest "bison --version" "bison"

#########################
# build all thirdparties
#########################


# Name of cmake build directory in each thirdpary project.
# Do not use `build`, because many projects contained a file named `BUILD`
# and if the filesystem is not case sensitive, `mkdir` will fail.
BUILD_DIR=starrocks_build
MACHINE_TYPE=$(uname -m)

# handle mac m1 platform, change arm64 to aarch64
if [[ "${MACHINE_TYPE}" == "arm64" ]]; then
    MACHINE_TYPE="aarch64"
fi

echo "machine type : $MACHINE_TYPE"

check_if_source_exist() {
    if [ -z $1 ]; then
        echo "dir should specified to check if exist."
        exit 1
    fi

    if [ ! -d $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
    echo "===== begin build $1"
}

check_if_archieve_exist() {
    if [ -z $1 ]; then
        echo "archieve should specified to check if exist."
        exit 1
    fi

    if [ ! -f $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
}

# libevent
build_libevent() {
    check_if_source_exist $LIBEVENT_SOURCE
    cd $TP_SOURCE_DIR/$LIBEVENT_SOURCE
    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

build_openssl() {
    OPENSSL_PLATFORM="linux-x86_64"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        OPENSSL_PLATFORM="linux-aarch64"
    fi

    check_if_source_exist $OPENSSL_SOURCE
    cd $TP_SOURCE_DIR/$OPENSSL_SOURCE

    # use customized CFLAGS/CPPFLAGS/CXXFLAGS/LDFLAGS
    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC"

    LDFLAGS="-L${TP_LIB_DIR}" \
    LIBDIR="lib" \
    ./Configure --prefix=$TP_INSTALL_DIR -lz -no-shared ${OPENSSL_PLATFORM}
    make -j$PARALLEL
    make install_sw

    restore_compile_flags
}

# thrift
build_thrift() {
    check_if_source_exist $THRIFT_SOURCE
    cd $TP_SOURCE_DIR/$THRIFT_SOURCE

    if [ ! -f configure ]; then
        ./bootstrap.sh
    fi

    echo ${TP_LIB_DIR}
    ./configure LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" LIBS="-lssl -lcrypto -ldl" \
    --prefix=$TP_INSTALL_DIR --docdir=$TP_INSTALL_DIR/doc --enable-static --disable-shared --disable-tests \
    --disable-tutorial --without-qt4 --without-qt5 --without-csharp --without-erlang --without-nodejs \
    --without-lua --without-perl --without-php --without-php_extension --without-dart --without-ruby \
    --without-haskell --without-go --without-haxe --without-d --without-python -without-java --with-cpp \
    --with-libevent=$TP_INSTALL_DIR --with-boost=$TP_INSTALL_DIR --with-openssl=$TP_INSTALL_DIR

    if [ -f compiler/cpp/thrifty.hh ];then
        mv compiler/cpp/thrifty.hh compiler/cpp/thrifty.h
    fi

    make -j$PARALLEL
    make install
}

# llvm
build_llvm() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -D_POSIX_C_SOURCE=200112L ${FILE_PREFIX_MAP_OPTION}"
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess ${FILE_PREFIX_MAP_OPTION}"

    LLVM_TARGET="X86"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        LLVM_TARGET="AArch64"
    fi

    LLVM_TARGETS_TO_BUILD=(
        "LLVMBitstreamReader"
        "LLVMRuntimeDyld" 
        "LLVMOption"
        "LLVMAsmPrinter"
        "LLVMProfileData"
        "LLVMAsmParser"
        "LLVMOrcTargetProcess"
        "LLVMExecutionEngine"
        "LLVMBinaryFormat"
        "LLVMDebugInfoDWARF"
        "LLVMObjCARCOpts"
        "LLVMCodeGen"
        "LLVMMCDisassembler"
        "LLVMSupport"
        "LLVMJITLink"
        "LLVMCFGuard"
        "LLVMInstrumentation"
        "LLVMIRReader"
        "LLVMCore"
        "LLVMTarget"
        "LLVMMC"
        "LLVMAnalysis"
        "LLVMGlobalISel"
        "LLVMScalarOpts"
        "LLVMTargetParser"
        "LLVMDemangle"
        "LLVMRemarks"
        "LLVMDebugInfoCodeView"
        "LLVMOrcShared"
        "LLVMOrcJIT"
        "LLVMTextAPI"
        "LLVMBitWriter"
        "LLVMBitReader"
        "LLVMObject"
        "LLVMTransformUtils"
        "LLVMSelectionDAG"
        "LLVMMCParser"
    )
    if [ "${LLVM_TARGET}" == "X86" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMX86Info" "LLVMX86Desc" "LLVMX86CodeGen")
    elif [ "${LLVM_TARGET}" == "AArch64" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMAArch64Info" "LLVMAArch64Desc" "LLVMAArch64CodeGen")
    fi

    LLVM_TARGETS_TO_INSTALL=()
    for target in ${LLVM_TARGETS_TO_BUILD[@]}; do
        LLVM_TARGETS_TO_INSTALL+=("install-${target}")
    done

    check_if_source_exist $LLVM_SOURCE

    cd $TP_SOURCE_DIR
    mkdir -p llvm-build
    cd llvm-build
    rm -rf CMakeCache.txt CMakeFiles/

    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -S ../${LLVM_SOURCE}/llvm -G "${CMAKE_GENERATOR}" \
    -DLLVM_ENABLE_EH:Bool=True \
    -DLLVM_ENABLE_RTTI:Bool=True \
    -DLLVM_ENABLE_PIC:Bool=True \
    -DLLVM_ENABLE_TERMINFO:Bool=False \
    -DLLVM_TARGETS_TO_BUILD=${LLVM_TARGET} \
    -DLLVM_BUILD_LLVM_DYLIB:BOOL=False \
    -DLLVM_INCLUDE_TOOLS:BOOL=False \
    -DLLVM_BUILD_TOOLS:BOOL=False \
    -DLLVM_INCLUDE_EXAMPLES:BOOL=False \
    -DLLVM_INCLUDE_TESTS:BOOL=False \
    -DLLVM_INCLUDE_BENCHMARKS:BOOL=False \
    -DBUILD_SHARED_LIBS:BOOL=False \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}/llvm ../${LLVM_SOURCE}

    # TODO(yueyang): Add more targets.
    # This is a little bit hack, we need to minimize the build time and binary size.
    ${BUILD_SYSTEM} -j$PARALLEL REQUIRES_RTTI=1 ${LLVM_TARGETS_TO_BUILD[@]}
    ${BUILD_SYSTEM} install-llvm-headers
    ${BUILD_SYSTEM} ${LLVM_TARGETS_TO_INSTALL[@]}

    restore_compile_flags
}

# protobuf
build_protobuf() {
    check_if_source_exist $PROTOBUF_SOURCE
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    rm -fr gmock
    mkdir gmock
    cd gmock
    tar xf ${TP_SOURCE_DIR}/$GTEST_NAME
    mv $GTEST_SOURCE gtest
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    ./autogen.sh
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc -pthread -Wl,--whole-archive -lpthread -Wl,--no-whole-archive" \
    ./configure --prefix=${TP_INSTALL_DIR} --disable-shared --enable-static --with-zlib --with-zlib-include=${TP_INSTALL_DIR}/include
    make -j$PARALLEL
    make install
}

# gflags
build_gflags() {
    check_if_source_exist $GFLAGS_SOURCE

    cd $TP_SOURCE_DIR/$GFLAGS_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# glog
build_glog() {
    check_if_source_exist $GLOG_SOURCE
    cd $TP_SOURCE_DIR/$GLOG_SOURCE

    # to generate config.guess and config.sub to support aarch64
    rm -rf config.*
    autoreconf -i

    LDFLAGS="-L${TP_LIB_DIR}" \
    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-frame-pointers --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

# gtest
build_gtest() {
    check_if_source_exist $GTEST_SOURCE

    cd $TP_SOURCE_DIR/$GTEST_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# rapidjson
build_rapidjson() {
    check_if_source_exist $RAPIDJSON_SOURCE

    rm -rf $TP_INSTALL_DIR/rapidjson
    cp -r $TP_SOURCE_DIR/$RAPIDJSON_SOURCE/include/rapidjson $TP_INCLUDE_DIR/
}

# simdjson
build_simdjson() {
    check_if_source_exist $SIMDJSON_SOURCE
    cd $TP_SOURCE_DIR/$SIMDJSON_SOURCE

    #ref: https://github.com/simdjson/simdjson/blob/master/HACKING.md
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_CXX_FLAGS="-O3" -DCMAKE_C_FLAGS="-O3" -DCMAKE_POSITION_INDEPENDENT_CODE=True -DSIMDJSON_AVX512_ALLOWED=OFF ..
    $CMAKE_CMD --build .
    mkdir -p $TP_INSTALL_DIR/lib

    cp $TP_SOURCE_DIR/$SIMDJSON_SOURCE/$BUILD_DIR/libsimdjson.a $TP_INSTALL_DIR/lib
    cp -r $TP_SOURCE_DIR/$SIMDJSON_SOURCE/include/* $TP_INCLUDE_DIR/
}

# snappy
build_snappy() {
    check_if_source_exist $SNAPPY_SOURCE
    cd $TP_SOURCE_DIR/$SNAPPY_SOURCE

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -G "${CMAKE_GENERATOR}" \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On \
    -DCMAKE_INSTALL_INCLUDEDIR=$TP_INCLUDE_DIR/snappy \
    -DSNAPPY_BUILD_TESTS=0 ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    if [ -f $TP_INSTALL_DIR/lib64/libsnappy.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib
        cp $TP_INSTALL_DIR/lib64/libsnappy.a $TP_INSTALL_DIR/lib/libsnappy.a
    fi

    #build for libarrow.a
    cp $TP_INCLUDE_DIR/snappy/snappy-c.h  $TP_INCLUDE_DIR/snappy-c.h
    cp $TP_INCLUDE_DIR/snappy/snappy-sinksource.h  $TP_INCLUDE_DIR/snappy-sinksource.h
    cp $TP_INCLUDE_DIR/snappy/snappy-stubs-public.h  $TP_INCLUDE_DIR/snappy-stubs-public.h
    cp $TP_INCLUDE_DIR/snappy/snappy.h  $TP_INCLUDE_DIR/snappy.h
    cp $TP_INSTALL_DIR/lib/libsnappy.a $TP_INSTALL_DIR/libsnappy.a
}

# gperftools
build_gperftools() {
    check_if_source_exist $GPERFTOOLS_SOURCE
    cd $TP_SOURCE_DIR/$GPERFTOOLS_SOURCE

    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=$TP_INSTALL_DIR/gperftools --disable-shared --enable-static --disable-libunwind --with-pic --enable-frame-pointers
    make -j$PARALLEL
    make install
}

# zlib
build_zlib() {
    check_if_source_exist $ZLIB_SOURCE
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --static
    make -j$PARALLEL
    make install

    # build minizip
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE/contrib/minizip
    autoreconf --force --install
    ./configure --prefix=$TP_INSTALL_DIR --enable-static=yes --enable-shared=no
    make -j$PARALLEL
    make install
}

# lz4
build_lz4() {
    check_if_source_exist $LZ4_SOURCE
    cd $TP_SOURCE_DIR/$LZ4_SOURCE

    make -C lib -j$PARALLEL install PREFIX=$TP_INSTALL_DIR \
    INCLUDEDIR=$TP_INCLUDE_DIR/lz4/ BUILD_SHARED=no
}

# lzo
build_lzo2() {
    check_if_source_exist $LZO2_SOURCE
    cd $TP_SOURCE_DIR/$LZO2_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
        LDFLAGS="-L${TP_LIB_DIR}" \
        ./configure --prefix="${TP_INSTALL_DIR}" --disable-shared --enable-static

    make -j "${PARALLEL}"
    make install
}

# bzip
build_bzip() {
    check_if_source_exist $BZIP_SOURCE
    cd $TP_SOURCE_DIR/$BZIP_SOURCE

    make -j$PARALLEL install PREFIX=$TP_INSTALL_DIR
}

# curl
build_curl() {
    check_if_source_exist $CURL_SOURCE
    cd $TP_SOURCE_DIR/$CURL_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" LIBS="-lssl -lcrypto -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static \
    --without-librtmp --with-ssl=${TP_INSTALL_DIR} --without-libidn2 --without-libgsasl --disable-ldap --enable-ipv6 --without-brotli
    make -j$PARALLEL
    make install
}

# re2
build_re2() {
    check_if_source_exist $RE2_SOURCE
    cd $TP_SOURCE_DIR/$RE2_SOURCE

    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release \
	    -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL install
}

# boost
build_boost() {
    check_if_source_exist $BOOST_SOURCE
    cd $TP_SOURCE_DIR/$BOOST_SOURCE

    # It is difficult to generate static linked b2, so we use LD_LIBRARY_PATH instead
    ./bootstrap.sh --prefix=$TP_INSTALL_DIR
    LD_LIBRARY_PATH=${STARROCKS_GCC_HOME}/lib:${STARROCKS_GCC_HOME}/lib64:${LD_LIBRARY_PATH} \
    ./b2 link=static runtime-link=static -j $PARALLEL --without-test --without-mpi --without-graph --without-graph_parallel --without-python cxxflags="-std=c++11 -g -fPIC -I$TP_INCLUDE_DIR -L$TP_LIB_DIR ${FILE_PREFIX_MAP_OPTION}" install
}

#leveldb
build_leveldb() {
    check_if_source_exist $LEVELDB_SOURCE
    cd $TP_SOURCE_DIR/$LEVELDB_SOURCE
    LDFLAGS="-L ${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    make -j$PARALLEL
    cp out-static/libleveldb.a $TP_LIB_DIR/libleveldb.a
    cp -r include/leveldb $TP_INCLUDE_DIR
}

# brpc
build_brpc() {
    check_if_source_exist $BRPC_SOURCE

    cd $TP_SOURCE_DIR/$BRPC_SOURCE
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    ./config_brpc.sh --headers="$TP_INSTALL_DIR/include" --libs="$TP_INSTALL_DIR/bin $TP_INSTALL_DIR/lib" --with-glog
    make -j$PARALLEL
    cp -rf output/* ${TP_INSTALL_DIR}/
    if [ -f $TP_INSTALL_DIR/lib/libbrpc.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib64
        cp $TP_SOURCE_DIR/$BRPC_SOURCE/output/lib/libbrpc.a $TP_INSTALL_DIR/lib64/
    fi
}

# rocksdb
build_rocksdb() {
    check_if_source_exist $ROCKSDB_SOURCE

    cd $TP_SOURCE_DIR/$ROCKSDB_SOURCE
    make clean

    CFLAGS= \
    EXTRA_CFLAGS="-I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy -I ${TP_INCLUDE_DIR}/lz4 -L${TP_LIB_DIR} ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_CXXFLAGS="-fPIC -Wno-deprecated-copy -Wno-stringop-truncation -Wno-pessimizing-move -Wno-redundant-move -I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy -include cstdint ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_LDFLAGS="-static-libstdc++ -static-libgcc" \
    PORTABLE=1 make USE_RTTI=1 -j$PARALLEL static_lib

    cp librocksdb.a $TP_LIB_DIR/librocksdb.a
    cp -r include/rocksdb $TP_INCLUDE_DIR
}

# kerberos
build_kerberos() {
    check_if_source_exist $KRB5_SOURCE
    cd $TP_SOURCE_DIR/$KRB5_SOURCE/src
    CFLAGS="-fcommon -fPIC ${FILE_PREFIX_MAP_OPTION}" LDFLAGS="-L$TP_INSTALL_DIR/lib -pthread -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-static --disable-shared --with-spake-openssl=$TP_INSTALL_DIR
    make -j$PARALLEL
    make install
}

# sasl
build_sasl() {
    check_if_source_exist $SASL_SOURCE
    cd $TP_SOURCE_DIR/$SASL_SOURCE
    CFLAGS="-fPIC" LDFLAGS="-L$TP_INSTALL_DIR/lib -lresolv -pthread -ldl" ./autogen.sh --prefix=$TP_INSTALL_DIR --enable-gssapi=yes --enable-static --disable-shared --with-openssl=$TP_INSTALL_DIR --with-gss_impl=mit
    make -j$PARALLEL
    make install
}

# librdkafka
build_librdkafka() {
    check_if_source_exist $LIBRDKAFKA_SOURCE

    cd $TP_SOURCE_DIR/$LIBRDKAFKA_SOURCE

    mkdir -p sr_build && cd sr_build
    $CMAKE_CMD -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" \
        -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include;$TP_INSTALL_DIR/include/zstd;$TP_INSTALL_DIR/include/lz4" \
        -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DRDKAFKA_BUILD_STATIC=ON -DWITH_SASL=ON -DWITH_SASL_SCRAM=ON \
        -DRDKAFKA_BUILD_EXAMPLES=OFF -DRDKAFKA_BUILD_TESTS=OFF -DWITH_SSL=ON -DWITH_ZSTD=ON -DCMAKE_INSTALL_LIBDIR=lib ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# pulsar
build_pulsar() {
    check_if_source_exist $PULSAR_SOURCE

    cd $TP_SOURCE_DIR/$PULSAR_SOURCE

    $CMAKE_CMD -DCMAKE_LIBRARY_PATH=$TP_INSTALL_DIR/lib -DCMAKE_INCLUDE_PATH=$TP_INSTALL_DIR/include \
        -DPROTOC_PATH=$TP_INSTALL_DIR/bin/protoc -DBUILD_TESTS=OFF -DBUILD_PYTHON_WRAPPER=OFF -DBUILD_DYNAMIC_LIB=OFF .
    ${BUILD_SYSTEM} -j$PARALLEL

    cp lib/libpulsar.a $TP_INSTALL_DIR/lib/
    cp -r include/pulsar $TP_INSTALL_DIR/include/
}

# flatbuffers
build_flatbuffers() {
  check_if_source_exist $FLATBUFFERS_SOURCE
  cd $TP_SOURCE_DIR/$FLATBUFFERS_SOURCE
  mkdir -p $BUILD_DIR
  cd $BUILD_DIR
  rm -rf CMakeCache.txt CMakeFiles/
  LDFLAGS="-static-libstdc++ -static-libgcc" \
  ${CMAKE_CMD} .. -G "${CMAKE_GENERATOR}" -DFLATBUFFERS_BUILD_TESTS=OFF
  ${BUILD_SYSTEM} -j$PARALLEL
  cp flatc  $TP_INSTALL_DIR/bin/flatc
  cp -r ../include/flatbuffers  $TP_INCLUDE_DIR/flatbuffers
  cp libflatbuffers.a $TP_LIB_DIR/libflatbuffers.a
}

build_brotli() {
    check_if_source_exist $BROTLI_SOURCE
    cd $TP_SOURCE_DIR/$BROTLI_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    ${CMAKE_CMD} .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib64
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    mv -f $TP_INSTALL_DIR/lib64/libbrotlienc-static.a $TP_INSTALL_DIR/lib64/libbrotlienc.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlidec-static.a $TP_INSTALL_DIR/lib64/libbrotlidec.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlicommon-static.a $TP_INSTALL_DIR/lib64/libbrotlicommon.a
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so.*
}

# arrow
build_arrow() {
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CPPFLAGS=$CXXFLAGS

    check_if_source_exist $ARROW_SOURCE
    cd $TP_SOURCE_DIR/$ARROW_SOURCE/cpp
    mkdir -p release
    cd release
    export ARROW_BROTLI_URL=${TP_SOURCE_DIR}/${BROTLI_NAME}
    export ARROW_GLOG_URL=${TP_SOURCE_DIR}/${GLOG_NAME}
    export ARROW_LZ4_URL=${TP_SOURCE_DIR}/${LZ4_NAME}
    export ARROW_SNAPPY_URL=${TP_SOURCE_DIR}/${SNAPPY_NAME}
    export ARROW_ZLIB_URL=${TP_SOURCE_DIR}/${ZLIB_NAME}
    export ARROW_FLATBUFFERS_URL=${TP_SOURCE_DIR}/${FLATBUFFERS_NAME}
    export ARROW_ZSTD_URL=${TP_SOURCE_DIR}/${ZSTD_NAME}
    export LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc"

    # https://github.com/apache/arrow/blob/apache-arrow-5.0.0/cpp/src/arrow/memory_pool.cc#L286
    #
    # JemallocAllocator use mallocx and rallocx to allocate new memory, but mallocx and rallocx are Non-standard APIs,
    # and can not be hooked in BE, the memory used by arrow can not be counted by BE,
    # so disable jemalloc here and use SystemAllocator.
    #
    # Currently, the standard APIs are hooked in BE, so the jemalloc standard APIs will actually be used.
    ${CMAKE_CMD} -DARROW_PARQUET=ON -DARROW_JSON=ON -DARROW_IPC=ON -DARROW_USE_GLOG=OFF -DARROW_BUILD_STATIC=ON -DARROW_BUILD_SHARED=OFF \
    -DARROW_WITH_BROTLI=ON -DARROW_WITH_LZ4=ON -DARROW_WITH_SNAPPY=ON -DARROW_WITH_ZLIB=ON -DARROW_WITH_ZSTD=ON \
    -DARROW_WITH_UTF8PROC=OFF -DARROW_WITH_RE2=OFF \
    -DARROW_JEMALLOC=OFF -DARROW_MIMALLOC=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DARROW_BOOST_USE_SHARED=OFF -DARROW_GFLAGS_USE_SHARED=OFF -DBoost_NO_BOOST_CMAKE=ON -DBOOST_ROOT=$TP_INSTALL_DIR \
    -DJEMALLOC_HOME=$TP_INSTALL_DIR/jemalloc \
    -Dzstd_SOURCE=BUNDLED \
    -DRapidJSON_ROOT=$TP_INSTALL_DIR \
    -DARROW_SNAPPY_USE_SHARED=OFF \
    -DZLIB_ROOT=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DARROW_LZ4_USE_SHARED=OFF \
    -DBROTLI_ROOT=$TP_INSTALL_DIR \
    -DARROW_BROTLI_USE_SHARED=OFF \
    -Dgflags_ROOT=$TP_INSTALL_DIR/ \
    -DSnappy_ROOT=$TP_INSTALL_DIR/ \
    -DGLOG_ROOT=$TP_INSTALL_DIR/ \
    -DLZ4_ROOT=$TP_INSTALL_DIR/ \
    -DBoost_DIR=$TP_INSTALL_DIR \
    -DBoost_ROOT=$TP_INSTALL_DIR \
    -DARROW_BOOST_USE_SHARED=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DThrift_ROOT=$TP_INSTALL_DIR/ ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    if [ -f ./zstd_ep-install/lib64/libzstd.a ]; then
        cp -rf ./zstd_ep-install/lib64/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    else
        cp -rf ./zstd_ep-install/lib/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    fi
    # copy zstd headers
    mkdir -p ${TP_INSTALL_DIR}/include/zstd
    cp ./zstd_ep-install/include/* ${TP_INSTALL_DIR}/include/zstd

    restore_compile_flags
}

# s2
build_s2() {
    check_if_source_exist $S2_SOURCE
    cd $TP_SOURCE_DIR/$S2_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DBUILD_SHARED_LIBS=OFF \
    -DGFLAGS_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GFLAGS=ON \
    -DGLOG_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GLOG=ON \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# bitshuffle
build_bitshuffle() {
    check_if_source_exist $BITSHUFFLE_SOURCE
    cd $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE
    PREFIX=$TP_INSTALL_DIR

    # This library has significant optimizations when built with -mavx2. However,
    # we still need to support non-AVX2-capable hardware. So, we build it twice,
    # once with the flag and once without, and use some linker tricks to
    # suffix the AVX2 symbols with '_avx2'.
    arches="default avx2 avx512"
    # Becuase aarch64 don't support avx2, disable it.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        arches="default neon"
    fi

    to_link=""
    for arch in $arches ; do
        arch_flag=""
        if [ "$arch" == "avx2" ]; then
            arch_flag="-mavx2"
        elif [ "$arch" == "avx512" ]; then
            arch_flag="-march=icelake-server"
        elif [ "$arch" == "neon" ]; then
            arch_flag="-march=armv8-a+crc"
        fi
        tmp_obj=bitshuffle_${arch}_tmp.o
        dst_obj=bitshuffle_${arch}.o
        ${CC:-gcc} $EXTRA_CFLAGS $arch_flag -std=c99 -I$PREFIX/include/lz4/ -O3 -DNDEBUG -fPIC -c \
            "src/bitshuffle_core.c" \
            "src/bitshuffle.c" \
            "src/iochain.c"
        # Merge the object files together to produce a combined .o file.
        ld -r -o $tmp_obj bitshuffle_core.o bitshuffle.o iochain.o
        # For the AVX2 symbols, suffix them.
        if [[ "$arch" == "avx2" || "$arch" == "avx512" || "$arch" == "neon" ]]; then
            # Create a mapping file with '<old_sym> <suffixed_sym>' on each line.
            nm --defined-only --extern-only $tmp_obj | while read addr type sym ; do
              echo ${sym} ${sym}_${arch}
            done > renames.txt
            objcopy --redefine-syms=renames.txt $tmp_obj $dst_obj
        else
            mv $tmp_obj $dst_obj
        fi
        to_link="$to_link $dst_obj"
    done
    rm -f libbitshuffle.a
    ar rs libbitshuffle.a $to_link
    mkdir -p $PREFIX/include/bitshuffle
    cp libbitshuffle.a $PREFIX/lib/
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle.h $PREFIX/include/bitshuffle/bitshuffle.h
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle_core.h $PREFIX/include/bitshuffle/bitshuffle_core.h
}

# croaring bitmap
# If open AVX512 default, current version will be compiled failed on some machine, so close AVX512 default,
# When this problem is solved, a switch will be added to control.
build_croaringbitmap() {
    FORCE_AVX=ON
    # avx2 is not supported by aarch64.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        FORCE_AVX=FALSE
    fi
    if [[ `cat /proc/cpuinfo |grep avx|wc -l` == "0" ]]; then
        FORCE_AVX=FALSE
    fi
    check_if_source_exist $CROARINGBITMAP_SOURCE
    cd $TP_SOURCE_DIR/$CROARINGBITMAP_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DROARING_BUILD_STATIC=ON -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DENABLE_ROARING_TESTS=OFF \
    -DROARING_DISABLE_NATIVE=ON \
    -DFORCE_AVX=$FORCE_AVX \
    -DROARING_DISABLE_AVX512=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}
#orc
build_orc() {
    check_if_source_exist $ORC_SOURCE
    cd $TP_SOURCE_DIR/$ORC_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD ../ -DBUILD_JAVA=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DPROTOBUF_HOME=$TP_INSTALL_DIR \
    -DSNAPPY_HOME=$TP_INSTALL_DIR \
    -DGTEST_HOME=$TP_INSTALL_DIR \
    -DLZ4_HOME=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DZLIB_HOME=$TP_INSTALL_DIR\
    -DBUILD_LIBHDFSPP=OFF \
    -DBUILD_CPP_TESTS=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#cctz
build_cctz() {
    check_if_source_exist $CCTZ_SOURCE
    cd $TP_SOURCE_DIR/$CCTZ_SOURCE

    make -j$PARALLEL
    PREFIX=${TP_INSTALL_DIR} make install
}

#fmt
build_fmt() {
    check_if_source_exist $FMT_SOURCE
    cd $TP_SOURCE_DIR/$FMT_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} ../ \
            -DCMAKE_INSTALL_LIBDIR=lib64 -G "${CMAKE_GENERATOR}" -DFMT_TEST=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#ryu
build_ryu() {
    check_if_source_exist $RYU_SOURCE
    cd $TP_SOURCE_DIR/$RYU_SOURCE/ryu
    make -j$PARALLEL
    make install DESTDIR=${TP_INSTALL_DIR}
    mkdir -p $TP_INSTALL_DIR/include/ryu
    mv $TP_INSTALL_DIR/include/ryu.h $TP_INSTALL_DIR/include/ryu
    # copy to 64 to compatable with current CMake
    cp -f ${TP_INSTALL_DIR}/lib/libryu.a ${TP_INSTALL_DIR}/lib64/libryu.a
}

#break_pad
build_breakpad() {
    check_if_source_exist $BREAK_PAD_SOURCE
    cd $TP_SOURCE_DIR/$BREAK_PAD_SOURCE
    mkdir -p src/third_party/lss
    cp $TP_PATCH_DIR/linux_syscall_support.h src/third_party/lss
    CFLAGS= CXXFLAGS="${CXXFLAGS} -Wno-nonnull" ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

#hadoop
build_hadoop() {
    check_if_source_exist $HADOOP_SOURCE
    cp -r $TP_SOURCE_DIR/$HADOOP_SOURCE $TP_INSTALL_DIR/hadoop
    # remove unnecessary doc and logs
    rm -rf $TP_INSTALL_DIR/hadoop/logs/* $TP_INSTALL_DIR/hadoop/share/doc/hadoop
    mkdir -p $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/include/hdfs.h $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/lib/native/libhdfs.a $TP_INSTALL_DIR/lib
}

#jdk
build_jdk() {
    check_if_source_exist $JDK_SOURCE
    rm -rf $TP_INSTALL_DIR/open_jdk && cp -r $TP_SOURCE_DIR/$JDK_SOURCE $TP_INSTALL_DIR/open_jdk
}

# ragel
# ragel-6.9+ is used by hypercan, so we build it first.
build_ragel() {
    check_if_source_exist $RAGEL_SOURCE
    cd $TP_SOURCE_DIR/$RAGEL_SOURCE
    # generage a static linked ragel, hyperscan will depend on it
    LDFLAGS=" -static-libstdc++ -static-libgcc" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

#hyperscan
build_hyperscan() {
    check_if_source_exist $HYPERSCAN_SOURCE
    cd $TP_SOURCE_DIR/$HYPERSCAN_SOURCE
    export PATH=$TP_INSTALL_DIR/bin:$PATH
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DBOOST_ROOT=$STARROCKS_THIRDPARTY/installed/include \
          -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc  -DCMAKE_INSTALL_LIBDIR=lib \
          -DBUILD_EXAMPLES=OFF -DBUILD_UNIT=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#mariadb-connector-c
build_mariadb() {
    OLD_CMAKE_GENERATOR=${CMAKE_GENERATOR}
    OLD_BUILD_SYSTEM=${BUILD_SYSTEM}

    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC ${FILE_PREFIX_MAP_OPTION}"

    # force use make build system, since ninja doesn't support install only headers
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'

    check_if_source_exist $MARIADB_SOURCE
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE
    mkdir -p build && cd build

    $CMAKE_CMD .. -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release    \
                  -DWITH_UNIT_TESTS=OFF                                 \
                  -DBUILD_SHARED_LIBS=OFF                               \
                  -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                  \
                  -DOPENSSL_USE_STATIC_LIBS=TRUE                        \
                  -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}
    # we only need build libmariadbclient and headers
    ${BUILD_SYSTEM} -j$PARALLEL mariadbclient
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/libmariadb
    mkdir -p $TP_INSTALL_DIR/lib/mariadb/
    cp libmariadbclient.a $TP_INSTALL_DIR/lib/mariadb/
    # install mariadb headers
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/include
    ${BUILD_SYSTEM} install

    restore_compile_flags
    export CMAKE_GENERATOR=$OLD_CMAKE_GENERATOR
    export BUILD_SYSTEM=$OLD_BUILD_SYSTEM
}

# jindosdk for Aliyun OSS
build_aliyun_jindosdk() {
    check_if_source_exist $JINDOSDK_SOURCE
    mkdir -p $TP_INSTALL_DIR/jindosdk
    cp -r $TP_SOURCE_DIR/$JINDOSDK_SOURCE/lib/*.jar $TP_INSTALL_DIR/jindosdk
}

build_gcs_connector() {
    check_if_source_exist $GCS_CONNECTOR_SOURCE
    mkdir -p $TP_INSTALL_DIR/gcs_connector
    cp -r $TP_SOURCE_DIR/$GCS_CONNECTOR_SOURCE/*.jar $TP_INSTALL_DIR/gcs_connector
}

build_broker_thirdparty_jars() {
    check_if_source_exist $BROKER_THIRDPARTY_JARS_SOURCE
    mkdir -p $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    cp -r $TP_SOURCE_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/* $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/hadoop-aliyun-2.7.2.jar
    # cloudfs-hadoop-with-dependencies will include aws jars, but we already support aws by official sdk, so we don't need it anymore.
    # And it will conflict with Iceberg's S3FileIO, make access S3 files failed.
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/cloudfs-hadoop-with-dependencies-1.1.21.jar
    # ensure read permission is granted for all users
    chmod -R +r $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/
}

build_aws_cpp_sdk() {
    check_if_source_exist $AWS_SDK_CPP_SOURCE
    cd $TP_SOURCE_DIR/$AWS_SDK_CPP_SOURCE
    # only build s3, s3-crt, transfer manager, identity-management and sts, you can add more components if you want.
    $CMAKE_CMD -Bbuild -DBUILD_ONLY="core;s3;s3-crt;transfer;identity-management;sts" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
               -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DENABLE_TESTING=OFF \
               -DENABLE_CURL_LOGGING=OFF \
               -G "${CMAKE_GENERATOR}" \
               -DCURL_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libcurl.a   \
               -DZLIB_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libz.a      \
               -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                     \
               -DOPENSSL_USE_STATIC_LIBS=TRUE                           \
               -Dcrypto_LIBRARY=${TP_INSTALL_DIR}/lib/libcrypto.a

    cd build
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    restore_compile_flags
}

# velocypack
build_vpack() {
    check_if_source_exist $VPACK_SOURCE
    cd $TP_SOURCE_DIR/$VPACK_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# opentelemetry
build_opentelemetry() {
    check_if_source_exist $OPENTELEMETRY_SOURCE

    cd $TP_SOURCE_DIR/$OPENTELEMETRY_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DBUILD_TESTING=OFF -DWITH_EXAMPLES=OFF \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        -DWITH_STL=OFF -DWITH_JAEGER=ON
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# jemalloc
build_jemalloc() {
    check_if_source_exist $JEMALLOC_SOURCE

    cd $TP_SOURCE_DIR/$JEMALLOC_SOURCE
    # jemalloc supports a runtime page size that's smaller or equal to the build
    # time one, but aborts on a larger one. If not defined, it falls back to the
    # the build system's _SC_PAGESIZE, which in many architectures can vary. Set
    # this to 64K (2^16) for arm architecture, and default 4K on x86 for performance.
    local addition_opts=" --with-lg-page=12"
    if [[ $MACHINE_TYPE == "aarch64" ]] ; then
        # change to 64K for arm architecture
        addition_opts=" --with-lg-page=16"
    fi
    # build jemalloc with release
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc --with-jemalloc-prefix=je --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
    # build jemalloc with debug options
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc-debug --with-jemalloc-prefix=je --enable-prof --enable-debug --enable-fill --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
}

# google benchmark
build_benchmark() {
    check_if_source_exist $BENCHMARK_SOURCE
    cd $TP_SOURCE_DIR/$BENCHMARK_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    cmake -DBENCHMARK_DOWNLOAD_DEPENDENCIES=off \
          -DBENCHMARK_ENABLE_GTEST_TESTS=off \
          -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
          -DCMAKE_INSTALL_LIBDIR=lib64 \
          -DCMAKE_BUILD_TYPE=Release ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# fast float
build_fast_float() {
    check_if_source_exist $FAST_FLOAT_SOURCE
    cd $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE
    cp -r $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE/include $TP_INSTALL_DIR
}

build_starcache() {
    check_if_source_exist $STARCACHE_SOURCE
    rm -rf $TP_INSTALL_DIR/$STARCACHE_SOURCE && mv $TP_SOURCE_DIR/$STARCACHE_SOURCE $TP_INSTALL_DIR/
}

# streamvbyte
build_streamvbyte() {
    check_if_source_exist $STREAMVBYTE_SOURCE

    cd $TP_SOURCE_DIR/$STREAMVBYTE_SOURCE/

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/

    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    $CMAKE_CMD .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=$TP_INSTALL_DIR/

    make -j$PARALLEL
    make install
}

# jansson
build_jansson() {
    check_if_source_exist $JANSSON_SOURCE
    cd $TP_SOURCE_DIR/$JANSSON_SOURCE/
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# avro-c
build_avro_c() {
    check_if_source_exist $AVRO_SOURCE
    cd $TP_SOURCE_DIR/$AVRO_SOURCE/lang/c
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    rm ${TP_INSTALL_DIR}/lib64/libavro.so*
}

# serders
build_serdes() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g"
    check_if_source_exist $SERDES_SOURCE
    cd $TP_SOURCE_DIR/$SERDES_SOURCE
    export LIBS="-lrt -lpthread -lcurl -ljansson -lrdkafka -lrdkafka++ -lavro -lssl -lcrypto -ldl"
    ./configure --prefix=${TP_INSTALL_DIR} \
                --libdir=${TP_INSTALL_DIR}/lib \
                --CFLAGS="-I ${TP_INSTALL_DIR}/include"  \
                --CXXFLAGS="-I ${TP_INSTALL_DIR}/include" \
                --LDFLAGS="-L ${TP_INSTALL_DIR}/lib -L ${TP_INSTALL_DIR}/lib64" \
                --enable-static \
                --disable-shared

    make -j$PARALLEL
    make install
    rm ${TP_INSTALL_DIR}/lib/libserdes.so*
    # these symbols also be definition in librdkafka, change these symbols to be local.
    objcopy --localize-symbol=cnd_timedwait ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=cnd_timedwait_ms ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=thrd_is_current ${TP_INSTALL_DIR}/lib/libserdes.a
    unset LIBS
    restore_compile_flags
}

# datasketches
build_datasketches() {
    check_if_source_exist $DATASKETCHES_SOURCE
    mkdir -p $TP_INSTALL_DIR/include/datasketches
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/common/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/cpc/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/fi/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/hll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/kll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/quantiles/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/req/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/sampling/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/theta/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/tuple/include/* $TP_INSTALL_DIR/include/datasketches/
}

# async-profiler
build_async_profiler() {
    check_if_source_exist $ASYNC_PROFILER_SOURCE
    mkdir -p $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/build $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/profiler.sh $TP_INSTALL_DIR/async-profiler
}

# fiu
build_fiu() {
    check_if_source_exist $FIU_SOURCE
    cd $TP_SOURCE_DIR/$FIU_SOURCE
    mkdir -p $TP_SOURCE_DIR/$FIU_SOURCE/installed
    make -j$PARALLEL
    make PREFIX=$TP_SOURCE_DIR/$FIU_SOURCE/installed install

    mkdir -p $TP_INSTALL_DIR/include/fiu
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/include/* $TP_INSTALL_DIR/include/fiu/
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/lib/libfiu.a $TP_INSTALL_DIR/lib/
}

# libdeflate
build_libdeflate() {
    check_if_source_exist $LIBDEFLATE_SOURCE
    mkdir -p $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    cd $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    $CMAKE_CMD .. -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# restore cxxflags/cppflags/cflags to default one
restore_compile_flags() {
    # c preprocessor flags
    export CPPFLAGS=$GLOBAL_CPPFLAGS
    # c flags
    export CFLAGS=$GLOBAL_CFLAGS
    # c++ flags
    export CXXFLAGS=$GLOBAL_CXXFLAGS
}

strip_binary() {
    # strip binary tools and ignore any errors
    echo "Strip binaries in $TP_INSTALL_DIR/bin/ ..."
    strip $TP_INSTALL_DIR/bin/* 2>/dev/null || true
}


# strip `$TP_SOURCE_DIR` and `$TP_INSTALL_DIR` from source code file path
export FILE_PREFIX_MAP_OPTION="-ffile-prefix-map=${TP_SOURCE_DIR}=. -ffile-prefix-map=${TP_INSTALL_DIR}=."
# set GLOBAL_C*FLAGS for easy restore in each sub build process
export GLOBAL_CPPFLAGS="-I ${TP_INCLUDE_DIR}"
# https://stackoverflow.com/questions/42597685/storage-size-of-timespec-isnt-known
export GLOBAL_CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -fPIC -g -D_POSIX_C_SOURCE=200112L -gz=zlib ${FILE_PREFIX_MAP_OPTION}"
export GLOBAL_CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess -fPIC -g -gz=zlib ${FILE_PREFIX_MAP_OPTION}"

# set those GLOBAL_*FLAGS to the CFLAGS/CXXFLAGS/CPPFLAGS
export CPPFLAGS=$GLOBAL_CPPFLAGS
export CXXFLAGS=$GLOBAL_CXXFLAGS
export CFLAGS=$GLOBAL_CFLAGS

build_libevent
build_zlib
build_lz4
build_lzo2
build_bzip
build_openssl
build_boost # must before thrift
build_protobuf
build_gflags
build_gtest
build_glog
build_rapidjson
build_simdjson
build_snappy
build_gperftools
build_curl
build_re2
build_thrift
build_leveldb
build_brpc
build_rocksdb
build_kerberos
build_sasl
build_flatbuffers
build_jemalloc
build_brotli
# must build before arrow
build_arrow
# NOTE: librdkafka depends on ZSTD which is generated by Arrow, So this SHOULD be
# built after arrow
build_librdkafka
build_pulsar
build_s2
build_bitshuffle
build_croaringbitmap
build_cctz
build_fmt
build_ryu
build_hadoop
build_jdk
build_ragel
build_hyperscan
build_mariadb
build_aliyun_jindosdk
build_gcs_connector
build_broker_thirdparty_jars
build_aws_cpp_sdk
build_vpack
build_opentelemetry
build_benchmark
build_fast_float
build_starcache
build_streamvbyte
build_jansson
build_avro_c
build_serdes
build_datasketches
build_async_profiler
build_fiu
build_llvm

if [[ "${MACHINE_TYPE}" != "aarch64" ]]; then
    build_breakpad
    build_libdeflate
fi

# strip unnecessary debug symbol for binaries in thirdparty
strip_binary

echo "Finished to build all thirdparties"

```

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

#################################################################################
# This script will
# 1. Check prerequisite libraries. Including:
#    cmake byacc flex automake libtool binutils-dev libiberty-dev bison
# 2. Compile and install all thirdparties which are downloaded
#    using *download-thirdparty.sh*.
#
# This script will run *download-thirdparty.sh* once again
# to check if all thirdparties have been downloaded, unpacked and patched.
#################################################################################
set -e

curdir=`dirname "$0"`
curdir=`cd "$curdir"; pwd`

export STARROCKS_HOME=${STARROCKS_HOME:-$curdir/..}
export TP_DIR=$curdir

# include custom environment variables
if [[ -f ${STARROCKS_HOME}/env.sh ]]; then
    . ${STARROCKS_HOME}/env.sh
fi

if [[ ! -f ${TP_DIR}/download-thirdparty.sh ]]; then
    echo "Download thirdparty script is missing".
    exit 1
fi

if [ ! -f ${TP_DIR}/vars.sh ]; then
    echo "vars.sh is missing".
    exit 1
fi
. ${TP_DIR}/vars.sh

cd $TP_DIR

# Download thirdparties.
${TP_DIR}/download-thirdparty.sh

# set COMPILER
if [[ ! -z ${STARROCKS_GCC_HOME} ]]; then
    export CC=${STARROCKS_GCC_HOME}/bin/gcc
    export CPP=${STARROCKS_GCC_HOME}/bin/cpp
    export CXX=${STARROCKS_GCC_HOME}/bin/g++
    export PATH=${STARROCKS_GCC_HOME}/bin:$PATH
else
    echo "STARROCKS_GCC_HOME environment variable is not set"
    exit 1
fi

# prepare installed prefix
mkdir -p ${TP_DIR}/installed

check_prerequest() {
    local CMD=$1
    local NAME=$2
    if ! $CMD; then
        echo $NAME is missing
        exit 1
    else
        echo $NAME is found
    fi
}

# sudo apt-get install cmake
# sudo yum install cmake
check_prerequest "${CMAKE_CMD} --version" "cmake"

# sudo apt-get install byacc
# sudo yum install byacc
check_prerequest "byacc -V" "byacc"

# sudo apt-get install flex
# sudo yum install flex
check_prerequest "flex -V" "flex"

# sudo apt-get install automake
# sudo yum install automake
check_prerequest "automake --version" "automake"

# sudo apt-get install libtool
# sudo yum install libtool
check_prerequest "libtoolize --version" "libtool"

BUILD_SYSTEM=${BUILD_SYSTEM:-make}

# sudo apt-get install binutils-dev
# sudo yum install binutils-devel
#check_prerequest "locate libbfd.a" "binutils-dev"

# sudo apt-get install libiberty-dev
# no need in centos 7.1
#check_prerequest "locate libiberty.a" "libiberty-dev"

# sudo apt-get install bison
# sudo yum install bison
#check_prerequest "bison --version" "bison"

#########################
# build all thirdparties
#########################


# Name of cmake build directory in each thirdpary project.
# Do not use `build`, because many projects contained a file named `BUILD`
# and if the filesystem is not case sensitive, `mkdir` will fail.
BUILD_DIR=starrocks_build
MACHINE_TYPE=$(uname -m)

# handle mac m1 platform, change arm64 to aarch64
if [[ "${MACHINE_TYPE}" == "arm64" ]]; then
    MACHINE_TYPE="aarch64"
fi

echo "machine type : $MACHINE_TYPE"

check_if_source_exist() {
    if [ -z $1 ]; then
        echo "dir should specified to check if exist."
        exit 1
    fi

    if [ ! -d $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
    echo "===== begin build $1"
}

check_if_archieve_exist() {
    if [ -z $1 ]; then
        echo "archieve should specified to check if exist."
        exit 1
    fi

    if [ ! -f $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
}

# libevent
build_libevent() {
    check_if_source_exist $LIBEVENT_SOURCE
    cd $TP_SOURCE_DIR/$LIBEVENT_SOURCE
    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

build_openssl() {
    OPENSSL_PLATFORM="linux-x86_64"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        OPENSSL_PLATFORM="linux-aarch64"
    fi

    check_if_source_exist $OPENSSL_SOURCE
    cd $TP_SOURCE_DIR/$OPENSSL_SOURCE

    # use customized CFLAGS/CPPFLAGS/CXXFLAGS/LDFLAGS
    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC"

    LDFLAGS="-L${TP_LIB_DIR}" \
    LIBDIR="lib" \
    ./Configure --prefix=$TP_INSTALL_DIR -lz -no-shared ${OPENSSL_PLATFORM}
    make -j$PARALLEL
    make install_sw

    restore_compile_flags
}

# thrift
build_thrift() {
    check_if_source_exist $THRIFT_SOURCE
    cd $TP_SOURCE_DIR/$THRIFT_SOURCE

    if [ ! -f configure ]; then
        ./bootstrap.sh
    fi

    echo ${TP_LIB_DIR}
    ./configure LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" LIBS="-lssl -lcrypto -ldl" \
    --prefix=$TP_INSTALL_DIR --docdir=$TP_INSTALL_DIR/doc --enable-static --disable-shared --disable-tests \
    --disable-tutorial --without-qt4 --without-qt5 --without-csharp --without-erlang --without-nodejs \
    --without-lua --without-perl --without-php --without-php_extension --without-dart --without-ruby \
    --without-haskell --without-go --without-haxe --without-d --without-python -without-java --with-cpp \
    --with-libevent=$TP_INSTALL_DIR --with-boost=$TP_INSTALL_DIR --with-openssl=$TP_INSTALL_DIR

    if [ -f compiler/cpp/thrifty.hh ];then
        mv compiler/cpp/thrifty.hh compiler/cpp/thrifty.h
    fi

    make -j$PARALLEL
    make install
}

# llvm
build_llvm() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -D_POSIX_C_SOURCE=200112L ${FILE_PREFIX_MAP_OPTION}"
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess ${FILE_PREFIX_MAP_OPTION}"

    LLVM_TARGET="X86"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        LLVM_TARGET="AArch64"
    fi

    LLVM_TARGETS_TO_BUILD=(
        "LLVMBitstreamReader"
        "LLVMRuntimeDyld" 
        "LLVMOption"
        "LLVMAsmPrinter"
        "LLVMProfileData"
        "LLVMAsmParser"
        "LLVMOrcTargetProcess"
        "LLVMExecutionEngine"
        "LLVMBinaryFormat"
        "LLVMDebugInfoDWARF"
        "LLVMObjCARCOpts"
        "LLVMCodeGen"
        "LLVMMCDisassembler"
        "LLVMSupport"
        "LLVMJITLink"
        "LLVMCFGuard"
        "LLVMInstrumentation"
        "LLVMIRReader"
        "LLVMCore"
        "LLVMTarget"
        "LLVMMC"
        "LLVMAnalysis"
        "LLVMGlobalISel"
        "LLVMScalarOpts"
        "LLVMTargetParser"
        "LLVMDemangle"
        "LLVMRemarks"
        "LLVMDebugInfoCodeView"
        "LLVMOrcShared"
        "LLVMOrcJIT"
        "LLVMTextAPI"
        "LLVMBitWriter"
        "LLVMBitReader"
        "LLVMObject"
        "LLVMTransformUtils"
        "LLVMSelectionDAG"
        "LLVMMCParser"
    )
    if [ "${LLVM_TARGET}" == "X86" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMX86Info" "LLVMX86Desc" "LLVMX86CodeGen")
    elif [ "${LLVM_TARGET}" == "AArch64" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMAArch64Info" "LLVMAArch64Desc" "LLVMAArch64CodeGen")
    fi

    LLVM_TARGETS_TO_INSTALL=()
    for target in ${LLVM_TARGETS_TO_BUILD[@]}; do
        LLVM_TARGETS_TO_INSTALL+=("install-${target}")
    done

    check_if_source_exist $LLVM_SOURCE

    cd $TP_SOURCE_DIR
    mkdir -p llvm-build
    cd llvm-build
    rm -rf CMakeCache.txt CMakeFiles/

    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -S ../${LLVM_SOURCE}/llvm -G "${CMAKE_GENERATOR}" \
    -DLLVM_ENABLE_EH:Bool=True \
    -DLLVM_ENABLE_RTTI:Bool=True \
    -DLLVM_ENABLE_PIC:Bool=True \
    -DLLVM_ENABLE_TERMINFO:Bool=False \
    -DLLVM_TARGETS_TO_BUILD=${LLVM_TARGET} \
    -DLLVM_BUILD_LLVM_DYLIB:BOOL=False \
    -DLLVM_INCLUDE_TOOLS:BOOL=False \
    -DLLVM_BUILD_TOOLS:BOOL=False \
    -DLLVM_INCLUDE_EXAMPLES:BOOL=False \
    -DLLVM_INCLUDE_TESTS:BOOL=False \
    -DLLVM_INCLUDE_BENCHMARKS:BOOL=False \
    -DBUILD_SHARED_LIBS:BOOL=False \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}/llvm ../${LLVM_SOURCE}

    # TODO(yueyang): Add more targets.
    # This is a little bit hack, we need to minimize the build time and binary size.
    ${BUILD_SYSTEM} -j$PARALLEL REQUIRES_RTTI=1 ${LLVM_TARGETS_TO_BUILD[@]}
    ${BUILD_SYSTEM} install-llvm-headers
    ${BUILD_SYSTEM} ${LLVM_TARGETS_TO_INSTALL[@]}

    restore_compile_flags
}

# protobuf
build_protobuf() {
    check_if_source_exist $PROTOBUF_SOURCE
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    rm -fr gmock
    mkdir gmock
    cd gmock
    tar xf ${TP_SOURCE_DIR}/$GTEST_NAME
    mv $GTEST_SOURCE gtest
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    ./autogen.sh
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc -pthread -Wl,--whole-archive -lpthread -Wl,--no-whole-archive" \
    ./configure --prefix=${TP_INSTALL_DIR} --disable-shared --enable-static --with-zlib --with-zlib-include=${TP_INSTALL_DIR}/include
    make -j$PARALLEL
    make install
}

# gflags
build_gflags() {
    check_if_source_exist $GFLAGS_SOURCE

    cd $TP_SOURCE_DIR/$GFLAGS_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# glog
build_glog() {
    check_if_source_exist $GLOG_SOURCE
    cd $TP_SOURCE_DIR/$GLOG_SOURCE

    # to generate config.guess and config.sub to support aarch64
    rm -rf config.*
    autoreconf -i

    LDFLAGS="-L${TP_LIB_DIR}" \
    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-frame-pointers --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

# gtest
build_gtest() {
    check_if_source_exist $GTEST_SOURCE

    cd $TP_SOURCE_DIR/$GTEST_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# rapidjson
build_rapidjson() {
    check_if_source_exist $RAPIDJSON_SOURCE

    rm -rf $TP_INSTALL_DIR/rapidjson
    cp -r $TP_SOURCE_DIR/$RAPIDJSON_SOURCE/include/rapidjson $TP_INCLUDE_DIR/
}

# simdjson
build_simdjson() {
    check_if_source_exist $SIMDJSON_SOURCE
    cd $TP_SOURCE_DIR/$SIMDJSON_SOURCE

    #ref: https://github.com/simdjson/simdjson/blob/master/HACKING.md
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_CXX_FLAGS="-O3" -DCMAKE_C_FLAGS="-O3" -DCMAKE_POSITION_INDEPENDENT_CODE=True -DSIMDJSON_AVX512_ALLOWED=OFF ..
    $CMAKE_CMD --build .
    mkdir -p $TP_INSTALL_DIR/lib

    cp $TP_SOURCE_DIR/$SIMDJSON_SOURCE/$BUILD_DIR/libsimdjson.a $TP_INSTALL_DIR/lib
    cp -r $TP_SOURCE_DIR/$SIMDJSON_SOURCE/include/* $TP_INCLUDE_DIR/
}

# snappy
build_snappy() {
    check_if_source_exist $SNAPPY_SOURCE
    cd $TP_SOURCE_DIR/$SNAPPY_SOURCE

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -G "${CMAKE_GENERATOR}" \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On \
    -DCMAKE_INSTALL_INCLUDEDIR=$TP_INCLUDE_DIR/snappy \
    -DSNAPPY_BUILD_TESTS=0 ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    if [ -f $TP_INSTALL_DIR/lib64/libsnappy.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib
        cp $TP_INSTALL_DIR/lib64/libsnappy.a $TP_INSTALL_DIR/lib/libsnappy.a
    fi

    #build for libarrow.a
    cp $TP_INCLUDE_DIR/snappy/snappy-c.h  $TP_INCLUDE_DIR/snappy-c.h
    cp $TP_INCLUDE_DIR/snappy/snappy-sinksource.h  $TP_INCLUDE_DIR/snappy-sinksource.h
    cp $TP_INCLUDE_DIR/snappy/snappy-stubs-public.h  $TP_INCLUDE_DIR/snappy-stubs-public.h
    cp $TP_INCLUDE_DIR/snappy/snappy.h  $TP_INCLUDE_DIR/snappy.h
    cp $TP_INSTALL_DIR/lib/libsnappy.a $TP_INSTALL_DIR/libsnappy.a
}

# gperftools
build_gperftools() {
    check_if_source_exist $GPERFTOOLS_SOURCE
    cd $TP_SOURCE_DIR/$GPERFTOOLS_SOURCE

    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=$TP_INSTALL_DIR/gperftools --disable-shared --enable-static --disable-libunwind --with-pic --enable-frame-pointers
    make -j$PARALLEL
    make install
}

# zlib
build_zlib() {
    check_if_source_exist $ZLIB_SOURCE
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --static
    make -j$PARALLEL
    make install

    # build minizip
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE/contrib/minizip
    autoreconf --force --install
    ./configure --prefix=$TP_INSTALL_DIR --enable-static=yes --enable-shared=no
    make -j$PARALLEL
    make install
}

# lz4
build_lz4() {
    check_if_source_exist $LZ4_SOURCE
    cd $TP_SOURCE_DIR/$LZ4_SOURCE

    make -C lib -j$PARALLEL install PREFIX=$TP_INSTALL_DIR \
    INCLUDEDIR=$TP_INCLUDE_DIR/lz4/ BUILD_SHARED=no
}

# lzo
build_lzo2() {
    check_if_source_exist $LZO2_SOURCE
    cd $TP_SOURCE_DIR/$LZO2_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
        LDFLAGS="-L${TP_LIB_DIR}" \
        ./configure --prefix="${TP_INSTALL_DIR}" --disable-shared --enable-static

    make -j "${PARALLEL}"
    make install
}

# bzip
build_bzip() {
    check_if_source_exist $BZIP_SOURCE
    cd $TP_SOURCE_DIR/$BZIP_SOURCE

    make -j$PARALLEL install PREFIX=$TP_INSTALL_DIR
}

# curl
build_curl() {
    check_if_source_exist $CURL_SOURCE
    cd $TP_SOURCE_DIR/$CURL_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" LIBS="-lssl -lcrypto -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static \
    --without-librtmp --with-ssl=${TP_INSTALL_DIR} --without-libidn2 --without-libgsasl --disable-ldap --enable-ipv6 --without-brotli
    make -j$PARALLEL
    make install
}

# re2
build_re2() {
    check_if_source_exist $RE2_SOURCE
    cd $TP_SOURCE_DIR/$RE2_SOURCE

    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release \
	    -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL install
}

# boost
build_boost() {
    check_if_source_exist $BOOST_SOURCE
    cd $TP_SOURCE_DIR/$BOOST_SOURCE

    # It is difficult to generate static linked b2, so we use LD_LIBRARY_PATH instead
    ./bootstrap.sh --prefix=$TP_INSTALL_DIR
    LD_LIBRARY_PATH=${STARROCKS_GCC_HOME}/lib:${STARROCKS_GCC_HOME}/lib64:${LD_LIBRARY_PATH} \
    ./b2 link=static runtime-link=static -j $PARALLEL --without-test --without-mpi --without-graph --without-graph_parallel --without-python cxxflags="-std=c++11 -g -fPIC -I$TP_INCLUDE_DIR -L$TP_LIB_DIR ${FILE_PREFIX_MAP_OPTION}" install
}

#leveldb
build_leveldb() {
    check_if_source_exist $LEVELDB_SOURCE
    cd $TP_SOURCE_DIR/$LEVELDB_SOURCE
    LDFLAGS="-L ${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    make -j$PARALLEL
    cp out-static/libleveldb.a $TP_LIB_DIR/libleveldb.a
    cp -r include/leveldb $TP_INCLUDE_DIR
}

# brpc
build_brpc() {
    check_if_source_exist $BRPC_SOURCE

    cd $TP_SOURCE_DIR/$BRPC_SOURCE
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    ./config_brpc.sh --headers="$TP_INSTALL_DIR/include" --libs="$TP_INSTALL_DIR/bin $TP_INSTALL_DIR/lib" --with-glog
    make -j$PARALLEL
    cp -rf output/* ${TP_INSTALL_DIR}/
    if [ -f $TP_INSTALL_DIR/lib/libbrpc.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib64
        cp $TP_SOURCE_DIR/$BRPC_SOURCE/output/lib/libbrpc.a $TP_INSTALL_DIR/lib64/
    fi
}

# rocksdb
build_rocksdb() {
    check_if_source_exist $ROCKSDB_SOURCE

    cd $TP_SOURCE_DIR/$ROCKSDB_SOURCE
    make clean

    CFLAGS= \
    EXTRA_CFLAGS="-I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy -I ${TP_INCLUDE_DIR}/lz4 -L${TP_LIB_DIR} ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_CXXFLAGS="-fPIC -Wno-deprecated-copy -Wno-stringop-truncation -Wno-pessimizing-move -Wno-redundant-move -I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy -include cstdint ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_LDFLAGS="-static-libstdc++ -static-libgcc" \
    PORTABLE=1 make USE_RTTI=1 -j$PARALLEL static_lib

    cp librocksdb.a $TP_LIB_DIR/librocksdb.a
    cp -r include/rocksdb $TP_INCLUDE_DIR
}

# kerberos
build_kerberos() {
    check_if_source_exist $KRB5_SOURCE
    cd $TP_SOURCE_DIR/$KRB5_SOURCE/src
    CFLAGS="-fcommon -fPIC ${FILE_PREFIX_MAP_OPTION}" LDFLAGS="-L$TP_INSTALL_DIR/lib -pthread -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-static --disable-shared --with-spake-openssl=$TP_INSTALL_DIR
    make -j$PARALLEL
    make install
}

# sasl
build_sasl() {
    check_if_source_exist $SASL_SOURCE
    cd $TP_SOURCE_DIR/$SASL_SOURCE
    CFLAGS="-fPIC" LDFLAGS="-L$TP_INSTALL_DIR/lib -lresolv -pthread -ldl" ./autogen.sh --prefix=$TP_INSTALL_DIR --enable-gssapi=yes --enable-static --disable-shared --with-openssl=$TP_INSTALL_DIR --with-gss_impl=mit
    make -j$PARALLEL
    make install
}

# librdkafka
build_librdkafka() {
    check_if_source_exist $LIBRDKAFKA_SOURCE

    cd $TP_SOURCE_DIR/$LIBRDKAFKA_SOURCE

    mkdir -p sr_build && cd sr_build
    $CMAKE_CMD -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" \
        -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include;$TP_INSTALL_DIR/include/zstd;$TP_INSTALL_DIR/include/lz4" \
        -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DRDKAFKA_BUILD_STATIC=ON -DWITH_SASL=ON -DWITH_SASL_SCRAM=ON \
        -DRDKAFKA_BUILD_EXAMPLES=OFF -DRDKAFKA_BUILD_TESTS=OFF -DWITH_SSL=ON -DWITH_ZSTD=ON -DCMAKE_INSTALL_LIBDIR=lib ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# pulsar
build_pulsar() {
    check_if_source_exist $PULSAR_SOURCE

    cd $TP_SOURCE_DIR/$PULSAR_SOURCE

    $CMAKE_CMD -DCMAKE_LIBRARY_PATH=$TP_INSTALL_DIR/lib -DCMAKE_INCLUDE_PATH=$TP_INSTALL_DIR/include \
        -DPROTOC_PATH=$TP_INSTALL_DIR/bin/protoc -DBUILD_TESTS=OFF -DBUILD_PYTHON_WRAPPER=OFF -DBUILD_DYNAMIC_LIB=OFF \
        -DOPENSSL_ROOT_DIR=$TP_INSTALL_DIR .
    ${BUILD_SYSTEM} -j$PARALLEL

    cp lib/libpulsar.a $TP_INSTALL_DIR/lib/
    cp -r include/pulsar $TP_INSTALL_DIR/include/
}

# flatbuffers
build_flatbuffers() {
  check_if_source_exist $FLATBUFFERS_SOURCE
  cd $TP_SOURCE_DIR/$FLATBUFFERS_SOURCE
  mkdir -p $BUILD_DIR
  cd $BUILD_DIR
  rm -rf CMakeCache.txt CMakeFiles/
  LDFLAGS="-static-libstdc++ -static-libgcc" \
  ${CMAKE_CMD} .. -G "${CMAKE_GENERATOR}" -DFLATBUFFERS_BUILD_TESTS=OFF
  ${BUILD_SYSTEM} -j$PARALLEL
  cp flatc  $TP_INSTALL_DIR/bin/flatc
  cp -r ../include/flatbuffers  $TP_INCLUDE_DIR/flatbuffers
  cp libflatbuffers.a $TP_LIB_DIR/libflatbuffers.a
}

build_brotli() {
    check_if_source_exist $BROTLI_SOURCE
    cd $TP_SOURCE_DIR/$BROTLI_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    ${CMAKE_CMD} .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib64
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    mv -f $TP_INSTALL_DIR/lib64/libbrotlienc-static.a $TP_INSTALL_DIR/lib64/libbrotlienc.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlidec-static.a $TP_INSTALL_DIR/lib64/libbrotlidec.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlicommon-static.a $TP_INSTALL_DIR/lib64/libbrotlicommon.a
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so.*
}

# arrow
build_arrow() {
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CPPFLAGS=$CXXFLAGS

    check_if_source_exist $ARROW_SOURCE
    cd $TP_SOURCE_DIR/$ARROW_SOURCE/cpp
    mkdir -p release
    cd release
    export ARROW_BROTLI_URL=${TP_SOURCE_DIR}/${BROTLI_NAME}
    export ARROW_GLOG_URL=${TP_SOURCE_DIR}/${GLOG_NAME}
    export ARROW_LZ4_URL=${TP_SOURCE_DIR}/${LZ4_NAME}
    export ARROW_SNAPPY_URL=${TP_SOURCE_DIR}/${SNAPPY_NAME}
    export ARROW_ZLIB_URL=${TP_SOURCE_DIR}/${ZLIB_NAME}
    export ARROW_FLATBUFFERS_URL=${TP_SOURCE_DIR}/${FLATBUFFERS_NAME}
    export ARROW_ZSTD_URL=${TP_SOURCE_DIR}/${ZSTD_NAME}
    export LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc"

    # https://github.com/apache/arrow/blob/apache-arrow-5.0.0/cpp/src/arrow/memory_pool.cc#L286
    #
    # JemallocAllocator use mallocx and rallocx to allocate new memory, but mallocx and rallocx are Non-standard APIs,
    # and can not be hooked in BE, the memory used by arrow can not be counted by BE,
    # so disable jemalloc here and use SystemAllocator.
    #
    # Currently, the standard APIs are hooked in BE, so the jemalloc standard APIs will actually be used.
    ${CMAKE_CMD} -DARROW_PARQUET=ON -DARROW_JSON=ON -DARROW_IPC=ON -DARROW_USE_GLOG=OFF -DARROW_BUILD_STATIC=ON -DARROW_BUILD_SHARED=OFF \
    -DARROW_WITH_BROTLI=ON -DARROW_WITH_LZ4=ON -DARROW_WITH_SNAPPY=ON -DARROW_WITH_ZLIB=ON -DARROW_WITH_ZSTD=ON \
    -DARROW_WITH_UTF8PROC=OFF -DARROW_WITH_RE2=OFF \
    -DARROW_JEMALLOC=OFF -DARROW_MIMALLOC=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DARROW_BOOST_USE_SHARED=OFF -DARROW_GFLAGS_USE_SHARED=OFF -DBoost_NO_BOOST_CMAKE=ON -DBOOST_ROOT=$TP_INSTALL_DIR \
    -DJEMALLOC_HOME=$TP_INSTALL_DIR/jemalloc \
    -Dzstd_SOURCE=BUNDLED \
    -DRapidJSON_ROOT=$TP_INSTALL_DIR \
    -DARROW_SNAPPY_USE_SHARED=OFF \
    -DZLIB_ROOT=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DARROW_LZ4_USE_SHARED=OFF \
    -DBROTLI_ROOT=$TP_INSTALL_DIR \
    -DARROW_BROTLI_USE_SHARED=OFF \
    -Dgflags_ROOT=$TP_INSTALL_DIR/ \
    -DSnappy_ROOT=$TP_INSTALL_DIR/ \
    -DGLOG_ROOT=$TP_INSTALL_DIR/ \
    -DLZ4_ROOT=$TP_INSTALL_DIR/ \
    -DBoost_DIR=$TP_INSTALL_DIR \
    -DBoost_ROOT=$TP_INSTALL_DIR \
    -DARROW_BOOST_USE_SHARED=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DThrift_ROOT=$TP_INSTALL_DIR/ ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    if [ -f ./zstd_ep-install/lib64/libzstd.a ]; then
        cp -rf ./zstd_ep-install/lib64/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    else
        cp -rf ./zstd_ep-install/lib/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    fi
    # copy zstd headers
    mkdir -p ${TP_INSTALL_DIR}/include/zstd
    cp ./zstd_ep-install/include/* ${TP_INSTALL_DIR}/include/zstd

    restore_compile_flags
}

# s2
build_s2() {
    check_if_source_exist $S2_SOURCE
    cd $TP_SOURCE_DIR/$S2_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DBUILD_SHARED_LIBS=OFF \
    -DGFLAGS_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GFLAGS=ON \
    -DGLOG_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GLOG=ON \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# bitshuffle
build_bitshuffle() {
    check_if_source_exist $BITSHUFFLE_SOURCE
    cd $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE
    PREFIX=$TP_INSTALL_DIR

    # This library has significant optimizations when built with -mavx2. However,
    # we still need to support non-AVX2-capable hardware. So, we build it twice,
    # once with the flag and once without, and use some linker tricks to
    # suffix the AVX2 symbols with '_avx2'.
    arches="default avx2 avx512"
    # Becuase aarch64 don't support avx2, disable it.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        arches="default neon"
    fi

    to_link=""
    for arch in $arches ; do
        arch_flag=""
        if [ "$arch" == "avx2" ]; then
            arch_flag="-mavx2"
        elif [ "$arch" == "avx512" ]; then
            arch_flag="-march=icelake-server"
        elif [ "$arch" == "neon" ]; then
            arch_flag="-march=armv8-a+crc"
        fi
        tmp_obj=bitshuffle_${arch}_tmp.o
        dst_obj=bitshuffle_${arch}.o
        ${CC:-gcc} $EXTRA_CFLAGS $arch_flag -std=c99 -I$PREFIX/include/lz4/ -O3 -DNDEBUG -fPIC -c \
            "src/bitshuffle_core.c" \
            "src/bitshuffle.c" \
            "src/iochain.c"
        # Merge the object files together to produce a combined .o file.
        ld -r -o $tmp_obj bitshuffle_core.o bitshuffle.o iochain.o
        # For the AVX2 symbols, suffix them.
        if [[ "$arch" == "avx2" || "$arch" == "avx512" || "$arch" == "neon" ]]; then
            # Create a mapping file with '<old_sym> <suffixed_sym>' on each line.
            nm --defined-only --extern-only $tmp_obj | while read addr type sym ; do
              echo ${sym} ${sym}_${arch}
            done > renames.txt
            objcopy --redefine-syms=renames.txt $tmp_obj $dst_obj
        else
            mv $tmp_obj $dst_obj
        fi
        to_link="$to_link $dst_obj"
    done
    rm -f libbitshuffle.a
    ar rs libbitshuffle.a $to_link
    mkdir -p $PREFIX/include/bitshuffle
    cp libbitshuffle.a $PREFIX/lib/
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle.h $PREFIX/include/bitshuffle/bitshuffle.h
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle_core.h $PREFIX/include/bitshuffle/bitshuffle_core.h
}

# croaring bitmap
# If open AVX512 default, current version will be compiled failed on some machine, so close AVX512 default,
# When this problem is solved, a switch will be added to control.
build_croaringbitmap() {
    FORCE_AVX=ON
    # avx2 is not supported by aarch64.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        FORCE_AVX=FALSE
    fi
    if [[ `cat /proc/cpuinfo |grep avx|wc -l` == "0" ]]; then
        FORCE_AVX=FALSE
    fi
    check_if_source_exist $CROARINGBITMAP_SOURCE
    cd $TP_SOURCE_DIR/$CROARINGBITMAP_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DROARING_BUILD_STATIC=ON -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DENABLE_ROARING_TESTS=OFF \
    -DROARING_DISABLE_NATIVE=ON \
    -DFORCE_AVX=$FORCE_AVX \
    -DROARING_DISABLE_AVX512=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}
#orc
build_orc() {
    check_if_source_exist $ORC_SOURCE
    cd $TP_SOURCE_DIR/$ORC_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD ../ -DBUILD_JAVA=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DPROTOBUF_HOME=$TP_INSTALL_DIR \
    -DSNAPPY_HOME=$TP_INSTALL_DIR \
    -DGTEST_HOME=$TP_INSTALL_DIR \
    -DLZ4_HOME=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DZLIB_HOME=$TP_INSTALL_DIR\
    -DBUILD_LIBHDFSPP=OFF \
    -DBUILD_CPP_TESTS=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#cctz
build_cctz() {
    check_if_source_exist $CCTZ_SOURCE
    cd $TP_SOURCE_DIR/$CCTZ_SOURCE

    make -j$PARALLEL
    PREFIX=${TP_INSTALL_DIR} make install
}

#fmt
build_fmt() {
    check_if_source_exist $FMT_SOURCE
    cd $TP_SOURCE_DIR/$FMT_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} ../ \
            -DCMAKE_INSTALL_LIBDIR=lib64 -G "${CMAKE_GENERATOR}" -DFMT_TEST=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#ryu
build_ryu() {
    check_if_source_exist $RYU_SOURCE
    cd $TP_SOURCE_DIR/$RYU_SOURCE/ryu
    make -j$PARALLEL
    make install DESTDIR=${TP_INSTALL_DIR}
    mkdir -p $TP_INSTALL_DIR/include/ryu
    mv $TP_INSTALL_DIR/include/ryu.h $TP_INSTALL_DIR/include/ryu
    # copy to 64 to compatable with current CMake
    cp -f ${TP_INSTALL_DIR}/lib/libryu.a ${TP_INSTALL_DIR}/lib64/libryu.a
}

#break_pad
build_breakpad() {
    check_if_source_exist $BREAK_PAD_SOURCE
    cd $TP_SOURCE_DIR/$BREAK_PAD_SOURCE
    mkdir -p src/third_party/lss
    cp $TP_PATCH_DIR/linux_syscall_support.h src/third_party/lss
    CFLAGS= CXXFLAGS="${CXXFLAGS} -Wno-nonnull" ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

#hadoop
build_hadoop() {
    check_if_source_exist $HADOOP_SOURCE
    cp -r $TP_SOURCE_DIR/$HADOOP_SOURCE $TP_INSTALL_DIR/hadoop
    # remove unnecessary doc and logs
    rm -rf $TP_INSTALL_DIR/hadoop/logs/* $TP_INSTALL_DIR/hadoop/share/doc/hadoop
    mkdir -p $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/include/hdfs.h $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/lib/native/libhdfs.a $TP_INSTALL_DIR/lib
}

#jdk
build_jdk() {
    check_if_source_exist $JDK_SOURCE
    rm -rf $TP_INSTALL_DIR/open_jdk && cp -r $TP_SOURCE_DIR/$JDK_SOURCE $TP_INSTALL_DIR/open_jdk
}

# ragel
# ragel-6.9+ is used by hypercan, so we build it first.
build_ragel() {
    check_if_source_exist $RAGEL_SOURCE
    cd $TP_SOURCE_DIR/$RAGEL_SOURCE
    # generage a static linked ragel, hyperscan will depend on it
    LDFLAGS=" -static-libstdc++ -static-libgcc" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

#hyperscan
build_hyperscan() {
    check_if_source_exist $HYPERSCAN_SOURCE
    cd $TP_SOURCE_DIR/$HYPERSCAN_SOURCE
    export PATH=$TP_INSTALL_DIR/bin:$PATH
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DBOOST_ROOT=$STARROCKS_THIRDPARTY/installed/include \
          -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc  -DCMAKE_INSTALL_LIBDIR=lib \
          -DBUILD_EXAMPLES=OFF -DBUILD_UNIT=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#mariadb-connector-c
build_mariadb() {
    OLD_CMAKE_GENERATOR=${CMAKE_GENERATOR}
    OLD_BUILD_SYSTEM=${BUILD_SYSTEM}

    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC ${FILE_PREFIX_MAP_OPTION}"

    # force use make build system, since ninja doesn't support install only headers
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'

    check_if_source_exist $MARIADB_SOURCE
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE
    mkdir -p build && cd build

    $CMAKE_CMD .. -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release    \
                  -DWITH_UNIT_TESTS=OFF                                 \
                  -DBUILD_SHARED_LIBS=OFF                               \
                  -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                  \
                  -DOPENSSL_USE_STATIC_LIBS=TRUE                        \
                  -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}
    # we only need build libmariadbclient and headers
    ${BUILD_SYSTEM} -j$PARALLEL mariadbclient
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/libmariadb
    mkdir -p $TP_INSTALL_DIR/lib/mariadb/
    cp libmariadbclient.a $TP_INSTALL_DIR/lib/mariadb/
    # install mariadb headers
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/include
    ${BUILD_SYSTEM} install

    restore_compile_flags
    export CMAKE_GENERATOR=$OLD_CMAKE_GENERATOR
    export BUILD_SYSTEM=$OLD_BUILD_SYSTEM
}

# jindosdk for Aliyun OSS
build_aliyun_jindosdk() {
    check_if_source_exist $JINDOSDK_SOURCE
    mkdir -p $TP_INSTALL_DIR/jindosdk
    cp -r $TP_SOURCE_DIR/$JINDOSDK_SOURCE/lib/*.jar $TP_INSTALL_DIR/jindosdk
}

build_gcs_connector() {
    check_if_source_exist $GCS_CONNECTOR_SOURCE
    mkdir -p $TP_INSTALL_DIR/gcs_connector
    cp -r $TP_SOURCE_DIR/$GCS_CONNECTOR_SOURCE/*.jar $TP_INSTALL_DIR/gcs_connector
}

build_broker_thirdparty_jars() {
    check_if_source_exist $BROKER_THIRDPARTY_JARS_SOURCE
    mkdir -p $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    cp -r $TP_SOURCE_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/* $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/hadoop-aliyun-2.7.2.jar
    # cloudfs-hadoop-with-dependencies will include aws jars, but we already support aws by official sdk, so we don't need it anymore.
    # And it will conflict with Iceberg's S3FileIO, make access S3 files failed.
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/cloudfs-hadoop-with-dependencies-1.1.21.jar
    # ensure read permission is granted for all users
    chmod -R +r $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/
}

build_aws_cpp_sdk() {
    check_if_source_exist $AWS_SDK_CPP_SOURCE
    cd $TP_SOURCE_DIR/$AWS_SDK_CPP_SOURCE
    # only build s3, s3-crt, transfer manager, identity-management and sts, you can add more components if you want.
    $CMAKE_CMD -Bbuild -DBUILD_ONLY="core;s3;s3-crt;transfer;identity-management;sts" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
               -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DENABLE_TESTING=OFF \
               -DENABLE_CURL_LOGGING=OFF \
               -G "${CMAKE_GENERATOR}" \
               -DCURL_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libcurl.a   \
               -DZLIB_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libz.a      \
               -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                     \
               -DOPENSSL_USE_STATIC_LIBS=TRUE                           \
               -Dcrypto_LIBRARY=${TP_INSTALL_DIR}/lib/libcrypto.a

    cd build
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    restore_compile_flags
}

# velocypack
build_vpack() {
    check_if_source_exist $VPACK_SOURCE
    cd $TP_SOURCE_DIR/$VPACK_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# opentelemetry
build_opentelemetry() {
    check_if_source_exist $OPENTELEMETRY_SOURCE

    cd $TP_SOURCE_DIR/$OPENTELEMETRY_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DBUILD_TESTING=OFF -DWITH_EXAMPLES=OFF \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        -DWITH_STL=OFF -DWITH_JAEGER=ON
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# jemalloc
build_jemalloc() {
    check_if_source_exist $JEMALLOC_SOURCE

    cd $TP_SOURCE_DIR/$JEMALLOC_SOURCE
    # jemalloc supports a runtime page size that's smaller or equal to the build
    # time one, but aborts on a larger one. If not defined, it falls back to the
    # the build system's _SC_PAGESIZE, which in many architectures can vary. Set
    # this to 64K (2^16) for arm architecture, and default 4K on x86 for performance.
    local addition_opts=" --with-lg-page=12"
    if [[ $MACHINE_TYPE == "aarch64" ]] ; then
        # change to 64K for arm architecture
        addition_opts=" --with-lg-page=16"
    fi
    # build jemalloc with release
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc --with-jemalloc-prefix=je --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
    # build jemalloc with debug options
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc-debug --with-jemalloc-prefix=je --enable-prof --enable-debug --enable-fill --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
}

# google benchmark
build_benchmark() {
    check_if_source_exist $BENCHMARK_SOURCE
    cd $TP_SOURCE_DIR/$BENCHMARK_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    cmake -DBENCHMARK_DOWNLOAD_DEPENDENCIES=off \
          -DBENCHMARK_ENABLE_GTEST_TESTS=off \
          -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
          -DCMAKE_INSTALL_LIBDIR=lib64 \
          -DCMAKE_BUILD_TYPE=Release ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# fast float
build_fast_float() {
    check_if_source_exist $FAST_FLOAT_SOURCE
    cd $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE
    cp -r $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE/include $TP_INSTALL_DIR
}

build_starcache() {
    check_if_source_exist $STARCACHE_SOURCE
    rm -rf $TP_INSTALL_DIR/$STARCACHE_SOURCE && mv $TP_SOURCE_DIR/$STARCACHE_SOURCE $TP_INSTALL_DIR/
}

# streamvbyte
build_streamvbyte() {
    check_if_source_exist $STREAMVBYTE_SOURCE

    cd $TP_SOURCE_DIR/$STREAMVBYTE_SOURCE/

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/

    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    $CMAKE_CMD .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=$TP_INSTALL_DIR/

    make -j$PARALLEL
    make install
}

# jansson
build_jansson() {
    check_if_source_exist $JANSSON_SOURCE
    cd $TP_SOURCE_DIR/$JANSSON_SOURCE/
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# avro-c
build_avro_c() {
    check_if_source_exist $AVRO_SOURCE
    cd $TP_SOURCE_DIR/$AVRO_SOURCE/lang/c
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    rm ${TP_INSTALL_DIR}/lib64/libavro.so*
}

# serders
build_serdes() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g"
    check_if_source_exist $SERDES_SOURCE
    cd $TP_SOURCE_DIR/$SERDES_SOURCE
    export LIBS="-lrt -lpthread -lcurl -ljansson -lrdkafka -lrdkafka++ -lavro -lssl -lcrypto -ldl"
    ./configure --prefix=${TP_INSTALL_DIR} \
                --libdir=${TP_INSTALL_DIR}/lib \
                --CFLAGS="-I ${TP_INSTALL_DIR}/include"  \
                --CXXFLAGS="-I ${TP_INSTALL_DIR}/include" \
                --LDFLAGS="-L ${TP_INSTALL_DIR}/lib -L ${TP_INSTALL_DIR}/lib64" \
                --enable-static \
                --disable-shared

    make -j$PARALLEL
    make install
    rm ${TP_INSTALL_DIR}/lib/libserdes.so*
    # these symbols also be definition in librdkafka, change these symbols to be local.
    objcopy --localize-symbol=cnd_timedwait ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=cnd_timedwait_ms ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=thrd_is_current ${TP_INSTALL_DIR}/lib/libserdes.a
    unset LIBS
    restore_compile_flags
}

# datasketches
build_datasketches() {
    check_if_source_exist $DATASKETCHES_SOURCE
    mkdir -p $TP_INSTALL_DIR/include/datasketches
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/common/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/cpc/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/fi/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/hll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/kll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/quantiles/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/req/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/sampling/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/theta/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/tuple/include/* $TP_INSTALL_DIR/include/datasketches/
}

# async-profiler
build_async_profiler() {
    check_if_source_exist $ASYNC_PROFILER_SOURCE
    mkdir -p $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/build $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/profiler.sh $TP_INSTALL_DIR/async-profiler
}

# fiu
build_fiu() {
    check_if_source_exist $FIU_SOURCE
    cd $TP_SOURCE_DIR/$FIU_SOURCE
    mkdir -p $TP_SOURCE_DIR/$FIU_SOURCE/installed
    make -j$PARALLEL
    make PREFIX=$TP_SOURCE_DIR/$FIU_SOURCE/installed install

    mkdir -p $TP_INSTALL_DIR/include/fiu
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/include/* $TP_INSTALL_DIR/include/fiu/
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/lib/libfiu.a $TP_INSTALL_DIR/lib/
}

# libdeflate
build_libdeflate() {
    check_if_source_exist $LIBDEFLATE_SOURCE
    mkdir -p $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    cd $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    $CMAKE_CMD .. -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# restore cxxflags/cppflags/cflags to default one
restore_compile_flags() {
    # c preprocessor flags
    export CPPFLAGS=$GLOBAL_CPPFLAGS
    # c flags
    export CFLAGS=$GLOBAL_CFLAGS
    # c++ flags
    export CXXFLAGS=$GLOBAL_CXXFLAGS
}

strip_binary() {
    # strip binary tools and ignore any errors
    echo "Strip binaries in $TP_INSTALL_DIR/bin/ ..."
    strip $TP_INSTALL_DIR/bin/* 2>/dev/null || true
}


# strip `$TP_SOURCE_DIR` and `$TP_INSTALL_DIR` from source code file path
export FILE_PREFIX_MAP_OPTION="-ffile-prefix-map=${TP_SOURCE_DIR}=. -ffile-prefix-map=${TP_INSTALL_DIR}=."
# set GLOBAL_C*FLAGS for easy restore in each sub build process
export GLOBAL_CPPFLAGS="-I ${TP_INCLUDE_DIR}"
# https://stackoverflow.com/questions/42597685/storage-size-of-timespec-isnt-known
export GLOBAL_CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -fPIC -g -D_POSIX_C_SOURCE=200112L -gz=zlib ${FILE_PREFIX_MAP_OPTION}"
export GLOBAL_CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess -fPIC -g -gz=zlib ${FILE_PREFIX_MAP_OPTION}"

# set those GLOBAL_*FLAGS to the CFLAGS/CXXFLAGS/CPPFLAGS
export CPPFLAGS=$GLOBAL_CPPFLAGS
export CXXFLAGS=$GLOBAL_CXXFLAGS
export CFLAGS=$GLOBAL_CFLAGS

build_libevent
build_zlib
build_lz4
build_lzo2
build_bzip
build_openssl
build_boost # must before thrift
build_protobuf
build_gflags
build_gtest
build_glog
build_rapidjson
build_simdjson
build_snappy
build_gperftools
build_curl
build_re2
build_thrift
build_leveldb
build_brpc
build_rocksdb
build_kerberos
build_sasl
build_flatbuffers
build_jemalloc
build_brotli
# must build before arrow
build_arrow
# NOTE: librdkafka depends on ZSTD which is generated by Arrow, So this SHOULD be
# built after arrow
build_librdkafka
build_pulsar
build_s2
build_bitshuffle
build_croaringbitmap
build_cctz
build_fmt
build_ryu
build_hadoop
build_jdk
build_ragel
build_hyperscan
build_mariadb
build_aliyun_jindosdk
build_gcs_connector
build_broker_thirdparty_jars
build_aws_cpp_sdk
build_vpack
build_opentelemetry
build_benchmark
build_fast_float
build_starcache
build_streamvbyte
build_jansson
build_avro_c
build_serdes
build_datasketches
build_async_profiler
build_fiu
build_llvm

if [[ "${MACHINE_TYPE}" != "aarch64" ]]; then
    build_breakpad
    build_libdeflate
fi

# strip unnecessary debug symbol for binaries in thirdparty
strip_binary

echo "Finished to build all thirdparties"

```

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

#################################################################################
# This script will
# 1. Check prerequisite libraries. Including:
#    cmake byacc flex automake libtool binutils-dev libiberty-dev bison
# 2. Compile and install all thirdparties which are downloaded
#    using *download-thirdparty.sh*.
#
# This script will run *download-thirdparty.sh* once again
# to check if all thirdparties have been downloaded, unpacked and patched.
#################################################################################
set -e

curdir=`dirname "$0"`
curdir=`cd "$curdir"; pwd`

export STARROCKS_HOME=${STARROCKS_HOME:-$curdir/..}
export TP_DIR=$curdir

# include custom environment variables
if [[ -f ${STARROCKS_HOME}/env.sh ]]; then
    . ${STARROCKS_HOME}/env.sh
fi

if [[ ! -f ${TP_DIR}/download-thirdparty.sh ]]; then
    echo "Download thirdparty script is missing".
    exit 1
fi

if [ ! -f ${TP_DIR}/vars.sh ]; then
    echo "vars.sh is missing".
    exit 1
fi
. ${TP_DIR}/vars.sh

cd $TP_DIR

# Download thirdparties.
${TP_DIR}/download-thirdparty.sh

# set COMPILER
if [[ ! -z ${STARROCKS_GCC_HOME} ]]; then
    export CC=${STARROCKS_GCC_HOME}/bin/gcc
    export CPP=${STARROCKS_GCC_HOME}/bin/cpp
    export CXX=${STARROCKS_GCC_HOME}/bin/g++
    export PATH=${STARROCKS_GCC_HOME}/bin:$PATH
else
    echo "STARROCKS_GCC_HOME environment variable is not set"
    exit 1
fi

# prepare installed prefix
mkdir -p ${TP_DIR}/installed

check_prerequest() {
    local CMD=$1
    local NAME=$2
    if ! $CMD; then
        echo $NAME is missing
        exit 1
    else
        echo $NAME is found
    fi
}

# sudo apt-get install cmake
# sudo yum install cmake
check_prerequest "${CMAKE_CMD} --version" "cmake"

# sudo apt-get install byacc
# sudo yum install byacc
check_prerequest "byacc -V" "byacc"

# sudo apt-get install flex
# sudo yum install flex
check_prerequest "flex -V" "flex"

# sudo apt-get install automake
# sudo yum install automake
check_prerequest "automake --version" "automake"

# sudo apt-get install libtool
# sudo yum install libtool
check_prerequest "libtoolize --version" "libtool"

BUILD_SYSTEM=${BUILD_SYSTEM:-make}

# sudo apt-get install binutils-dev
# sudo yum install binutils-devel
#check_prerequest "locate libbfd.a" "binutils-dev"

# sudo apt-get install libiberty-dev
# no need in centos 7.1
#check_prerequest "locate libiberty.a" "libiberty-dev"

# sudo apt-get install bison
# sudo yum install bison
#check_prerequest "bison --version" "bison"

#########################
# build all thirdparties
#########################


# Name of cmake build directory in each thirdpary project.
# Do not use `build`, because many projects contained a file named `BUILD`
# and if the filesystem is not case sensitive, `mkdir` will fail.
BUILD_DIR=starrocks_build
MACHINE_TYPE=$(uname -m)

# handle mac m1 platform, change arm64 to aarch64
if [[ "${MACHINE_TYPE}" == "arm64" ]]; then
    MACHINE_TYPE="aarch64"
fi

echo "machine type : $MACHINE_TYPE"

check_if_source_exist() {
    if [ -z $1 ]; then
        echo "dir should specified to check if exist."
        exit 1
    fi

    if [ ! -d $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
    echo "===== begin build $1"
}

check_if_archieve_exist() {
    if [ -z $1 ]; then
        echo "archieve should specified to check if exist."
        exit 1
    fi

    if [ ! -f $TP_SOURCE_DIR/$1 ];then
        echo "$TP_SOURCE_DIR/$1 does not exist."
        exit 1
    fi
}

# libevent
build_libevent() {
    check_if_source_exist $LIBEVENT_SOURCE
    cd $TP_SOURCE_DIR/$LIBEVENT_SOURCE
    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

build_openssl() {
    OPENSSL_PLATFORM="linux-x86_64"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        OPENSSL_PLATFORM="linux-aarch64"
    fi

    check_if_source_exist $OPENSSL_SOURCE
    cd $TP_SOURCE_DIR/$OPENSSL_SOURCE

    # use customized CFLAGS/CPPFLAGS/CXXFLAGS/LDFLAGS
    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC"

    LDFLAGS="-L${TP_LIB_DIR}" \
    LIBDIR="lib" \
    ./Configure --prefix=$TP_INSTALL_DIR -lz -no-shared ${OPENSSL_PLATFORM}
    make -j$PARALLEL
    make install_sw

    restore_compile_flags
}

# thrift
build_thrift() {
    check_if_source_exist $THRIFT_SOURCE
    cd $TP_SOURCE_DIR/$THRIFT_SOURCE

    if [ ! -f configure ]; then
        ./bootstrap.sh
    fi

    echo ${TP_LIB_DIR}
    ./configure LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" LIBS="-lssl -lcrypto -ldl" \
    --prefix=$TP_INSTALL_DIR --docdir=$TP_INSTALL_DIR/doc --enable-static --disable-shared --disable-tests \
    --disable-tutorial --without-qt4 --without-qt5 --without-csharp --without-erlang --without-nodejs \
    --without-lua --without-perl --without-php --without-php_extension --without-dart --without-ruby \
    --without-haskell --without-go --without-haxe --without-d --without-python -without-java --with-cpp \
    --with-libevent=$TP_INSTALL_DIR --with-boost=$TP_INSTALL_DIR --with-openssl=$TP_INSTALL_DIR

    if [ -f compiler/cpp/thrifty.hh ];then
        mv compiler/cpp/thrifty.hh compiler/cpp/thrifty.h
    fi

    make -j$PARALLEL
    make install
}

# llvm
build_llvm() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -D_POSIX_C_SOURCE=200112L ${FILE_PREFIX_MAP_OPTION}"
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess ${FILE_PREFIX_MAP_OPTION}"

    LLVM_TARGET="X86"
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        LLVM_TARGET="AArch64"
    fi

    LLVM_TARGETS_TO_BUILD=(
        "LLVMBitstreamReader"
        "LLVMRuntimeDyld" 
        "LLVMOption"
        "LLVMAsmPrinter"
        "LLVMProfileData"
        "LLVMAsmParser"
        "LLVMOrcTargetProcess"
        "LLVMExecutionEngine"
        "LLVMBinaryFormat"
        "LLVMDebugInfoDWARF"
        "LLVMObjCARCOpts"
        "LLVMCodeGen"
        "LLVMMCDisassembler"
        "LLVMSupport"
        "LLVMJITLink"
        "LLVMCFGuard"
        "LLVMInstrumentation"
        "LLVMIRReader"
        "LLVMCore"
        "LLVMTarget"
        "LLVMMC"
        "LLVMAnalysis"
        "LLVMGlobalISel"
        "LLVMScalarOpts"
        "LLVMTargetParser"
        "LLVMDemangle"
        "LLVMRemarks"
        "LLVMDebugInfoCodeView"
        "LLVMOrcShared"
        "LLVMOrcJIT"
        "LLVMTextAPI"
        "LLVMBitWriter"
        "LLVMBitReader"
        "LLVMObject"
        "LLVMTransformUtils"
        "LLVMSelectionDAG"
        "LLVMMCParser"
    )
    if [ "${LLVM_TARGET}" == "X86" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMX86Info" "LLVMX86Desc" "LLVMX86CodeGen")
    elif [ "${LLVM_TARGET}" == "AArch64" ]; then
        LLVM_TARGETS_TO_BUILD+=("LLVMAArch64Info" "LLVMAArch64Desc" "LLVMAArch64CodeGen")
    fi

    LLVM_TARGETS_TO_INSTALL=()
    for target in ${LLVM_TARGETS_TO_BUILD[@]}; do
        LLVM_TARGETS_TO_INSTALL+=("install-${target}")
    done

    check_if_source_exist $LLVM_SOURCE

    cd $TP_SOURCE_DIR
    mkdir -p llvm-build
    cd llvm-build
    rm -rf CMakeCache.txt CMakeFiles/

    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -S ../${LLVM_SOURCE}/llvm -G "${CMAKE_GENERATOR}" \
    -DLLVM_ENABLE_EH:Bool=True \
    -DLLVM_ENABLE_RTTI:Bool=True \
    -DLLVM_ENABLE_PIC:Bool=True \
    -DLLVM_ENABLE_TERMINFO:Bool=False \
    -DLLVM_TARGETS_TO_BUILD=${LLVM_TARGET} \
    -DLLVM_BUILD_LLVM_DYLIB:BOOL=False \
    -DLLVM_INCLUDE_TOOLS:BOOL=False \
    -DLLVM_BUILD_TOOLS:BOOL=False \
    -DLLVM_INCLUDE_EXAMPLES:BOOL=False \
    -DLLVM_INCLUDE_TESTS:BOOL=False \
    -DLLVM_INCLUDE_BENCHMARKS:BOOL=False \
    -DBUILD_SHARED_LIBS:BOOL=False \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}/llvm

    # TODO(yueyang): Add more targets.
    # This is a little bit hack, we need to minimize the build time and binary size.
    ${BUILD_SYSTEM} -j$PARALLEL REQUIRES_RTTI=1 ${LLVM_TARGETS_TO_BUILD[@]}
    ${BUILD_SYSTEM} install-llvm-headers
    ${BUILD_SYSTEM} ${LLVM_TARGETS_TO_INSTALL[@]}

    restore_compile_flags
}

# protobuf
build_protobuf() {
    check_if_source_exist $PROTOBUF_SOURCE
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    rm -fr gmock
    mkdir gmock
    cd gmock
    tar xf ${TP_SOURCE_DIR}/$GTEST_NAME
    mv $GTEST_SOURCE gtest
    cd $TP_SOURCE_DIR/$PROTOBUF_SOURCE
    ./autogen.sh
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc -pthread -Wl,--whole-archive -lpthread -Wl,--no-whole-archive" \
    ./configure --prefix=${TP_INSTALL_DIR} --disable-shared --enable-static --with-zlib --with-zlib-include=${TP_INSTALL_DIR}/include
    make -j$PARALLEL
    make install
}

# gflags
build_gflags() {
    check_if_source_exist $GFLAGS_SOURCE

    cd $TP_SOURCE_DIR/$GFLAGS_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# glog
build_glog() {
    check_if_source_exist $GLOG_SOURCE
    cd $TP_SOURCE_DIR/$GLOG_SOURCE

    # to generate config.guess and config.sub to support aarch64
    rm -rf config.*
    autoreconf -i

    LDFLAGS="-L${TP_LIB_DIR}" \
    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-frame-pointers --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

# gtest
build_gtest() {
    check_if_source_exist $GTEST_SOURCE

    cd $TP_SOURCE_DIR/$GTEST_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# rapidjson
build_rapidjson() {
    check_if_source_exist $RAPIDJSON_SOURCE

    rm -rf $TP_INSTALL_DIR/rapidjson
    cp -r $TP_SOURCE_DIR/$RAPIDJSON_SOURCE/include/rapidjson $TP_INCLUDE_DIR/
}

# simdjson
build_simdjson() {
    check_if_source_exist $SIMDJSON_SOURCE
    cd $TP_SOURCE_DIR/$SIMDJSON_SOURCE

    #ref: https://github.com/simdjson/simdjson/blob/master/HACKING.md
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_CXX_FLAGS="-O3" -DCMAKE_C_FLAGS="-O3" -DCMAKE_POSITION_INDEPENDENT_CODE=True -DSIMDJSON_AVX512_ALLOWED=OFF ..
    $CMAKE_CMD --build .
    mkdir -p $TP_INSTALL_DIR/lib

    cp $TP_SOURCE_DIR/$SIMDJSON_SOURCE/$BUILD_DIR/libsimdjson.a $TP_INSTALL_DIR/lib
    cp -r $TP_SOURCE_DIR/$SIMDJSON_SOURCE/include/* $TP_INCLUDE_DIR/
}

# snappy
build_snappy() {
    check_if_source_exist $SNAPPY_SOURCE
    cd $TP_SOURCE_DIR/$SNAPPY_SOURCE

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -G "${CMAKE_GENERATOR}" \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DCMAKE_POSITION_INDEPENDENT_CODE=On \
    -DCMAKE_INSTALL_INCLUDEDIR=$TP_INCLUDE_DIR/snappy \
    -DSNAPPY_BUILD_TESTS=0 ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    if [ -f $TP_INSTALL_DIR/lib64/libsnappy.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib
        cp $TP_INSTALL_DIR/lib64/libsnappy.a $TP_INSTALL_DIR/lib/libsnappy.a
    fi

    #build for libarrow.a
    cp $TP_INCLUDE_DIR/snappy/snappy-c.h  $TP_INCLUDE_DIR/snappy-c.h
    cp $TP_INCLUDE_DIR/snappy/snappy-sinksource.h  $TP_INCLUDE_DIR/snappy-sinksource.h
    cp $TP_INCLUDE_DIR/snappy/snappy-stubs-public.h  $TP_INCLUDE_DIR/snappy-stubs-public.h
    cp $TP_INCLUDE_DIR/snappy/snappy.h  $TP_INCLUDE_DIR/snappy.h
    cp $TP_INSTALL_DIR/lib/libsnappy.a $TP_INSTALL_DIR/libsnappy.a
}

# gperftools
build_gperftools() {
    check_if_source_exist $GPERFTOOLS_SOURCE
    cd $TP_SOURCE_DIR/$GPERFTOOLS_SOURCE

    if [ ! -f configure ]; then
        ./autogen.sh
    fi

    LDFLAGS="-L${TP_LIB_DIR}" \
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=$TP_INSTALL_DIR/gperftools --disable-shared --enable-static --disable-libunwind --with-pic --enable-frame-pointers
    make -j$PARALLEL
    make install
}

# zlib
build_zlib() {
    check_if_source_exist $ZLIB_SOURCE
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" \
    ./configure --prefix=$TP_INSTALL_DIR --static
    make -j$PARALLEL
    make install

    # build minizip
    cd $TP_SOURCE_DIR/$ZLIB_SOURCE/contrib/minizip
    autoreconf --force --install
    ./configure --prefix=$TP_INSTALL_DIR --enable-static=yes --enable-shared=no
    make -j$PARALLEL
    make install
}

# lz4
build_lz4() {
    check_if_source_exist $LZ4_SOURCE
    cd $TP_SOURCE_DIR/$LZ4_SOURCE

    make -C lib -j$PARALLEL install PREFIX=$TP_INSTALL_DIR \
    INCLUDEDIR=$TP_INCLUDE_DIR/lz4/ BUILD_SHARED=no
}

# lzo
build_lzo2() {
    check_if_source_exist $LZO2_SOURCE
    cd $TP_SOURCE_DIR/$LZO2_SOURCE

    CPPFLAGS="-I${TP_INCLUDE_DIR}" \
        LDFLAGS="-L${TP_LIB_DIR}" \
        ./configure --prefix="${TP_INSTALL_DIR}" --disable-shared --enable-static

    make -j "${PARALLEL}"
    make install
}

# bzip
build_bzip() {
    check_if_source_exist $BZIP_SOURCE
    cd $TP_SOURCE_DIR/$BZIP_SOURCE

    make -j$PARALLEL install PREFIX=$TP_INSTALL_DIR
}

# curl
build_curl() {
    check_if_source_exist $CURL_SOURCE
    cd $TP_SOURCE_DIR/$CURL_SOURCE

    LDFLAGS="-L${TP_LIB_DIR}" LIBS="-lssl -lcrypto -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static \
    --without-librtmp --with-ssl=${TP_INSTALL_DIR} --without-libidn2 --without-libgsasl --disable-ldap --enable-ipv6 --without-brotli
    make -j$PARALLEL
    make install
}

# re2
build_re2() {
    check_if_source_exist $RE2_SOURCE
    cd $TP_SOURCE_DIR/$RE2_SOURCE

    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release \
	    -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL install
}

# boost
build_boost() {
    check_if_source_exist $BOOST_SOURCE
    cd $TP_SOURCE_DIR/$BOOST_SOURCE

    # It is difficult to generate static linked b2, so we use LD_LIBRARY_PATH instead
    ./bootstrap.sh --prefix=$TP_INSTALL_DIR
    LD_LIBRARY_PATH=${STARROCKS_GCC_HOME}/lib:${STARROCKS_GCC_HOME}/lib64:${LD_LIBRARY_PATH} \
    ./b2 link=static runtime-link=static -j $PARALLEL --without-test --without-mpi --without-graph --without-graph_parallel --without-python cxxflags="-std=c++11 -g -fPIC -I$TP_INCLUDE_DIR -L$TP_LIB_DIR ${FILE_PREFIX_MAP_OPTION}" install
}

#leveldb
build_leveldb() {
    check_if_source_exist $LEVELDB_SOURCE
    cd $TP_SOURCE_DIR/$LEVELDB_SOURCE
    LDFLAGS="-L ${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    make -j$PARALLEL
    cp out-static/libleveldb.a $TP_LIB_DIR/libleveldb.a
    cp -r include/leveldb $TP_INCLUDE_DIR
}

# brpc
build_brpc() {
    check_if_source_exist $BRPC_SOURCE

    cd $TP_SOURCE_DIR/$BRPC_SOURCE
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    ./config_brpc.sh --headers="$TP_INSTALL_DIR/include" --libs="$TP_INSTALL_DIR/bin $TP_INSTALL_DIR/lib" --with-glog
    make -j$PARALLEL
    cp -rf output/* ${TP_INSTALL_DIR}/
    if [ -f $TP_INSTALL_DIR/lib/libbrpc.a ]; then
        mkdir -p $TP_INSTALL_DIR/lib64
        cp $TP_SOURCE_DIR/$BRPC_SOURCE/output/lib/libbrpc.a $TP_INSTALL_DIR/lib64/
    fi
}

# rocksdb
build_rocksdb() {
    check_if_source_exist $ROCKSDB_SOURCE

    cd $TP_SOURCE_DIR/$ROCKSDB_SOURCE
    make clean

    CFLAGS= \
    EXTRA_CFLAGS="-I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy -I ${TP_INCLUDE_DIR}/lz4 -L${TP_LIB_DIR} ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_CXXFLAGS="-fPIC -Wno-deprecated-copy -Wno-stringop-truncation -Wno-pessimizing-move -Wno-redundant-move -I ${TP_INCLUDE_DIR} -I ${TP_INCLUDE_DIR}/snappy -include cstdint ${FILE_PREFIX_MAP_OPTION}" \
    EXTRA_LDFLAGS="-static-libstdc++ -static-libgcc" \
    PORTABLE=1 make USE_RTTI=1 -j$PARALLEL static_lib

    cp librocksdb.a $TP_LIB_DIR/librocksdb.a
    cp -r include/rocksdb $TP_INCLUDE_DIR
}

# kerberos
build_kerberos() {
    check_if_source_exist $KRB5_SOURCE
    cd $TP_SOURCE_DIR/$KRB5_SOURCE/src
    CFLAGS="-fcommon -fPIC ${FILE_PREFIX_MAP_OPTION}" LDFLAGS="-L$TP_INSTALL_DIR/lib -pthread -ldl" \
    ./configure --prefix=$TP_INSTALL_DIR --enable-static --disable-shared --with-spake-openssl=$TP_INSTALL_DIR
    make -j$PARALLEL
    make install
}

# sasl
build_sasl() {
    check_if_source_exist $SASL_SOURCE
    cd $TP_SOURCE_DIR/$SASL_SOURCE
    CFLAGS="-fPIC" LDFLAGS="-L$TP_INSTALL_DIR/lib -lresolv -pthread -ldl" ./autogen.sh --prefix=$TP_INSTALL_DIR --enable-gssapi=yes --enable-static --disable-shared --with-openssl=$TP_INSTALL_DIR --with-gss_impl=mit
    make -j$PARALLEL
    make install
}

# librdkafka
build_librdkafka() {
    check_if_source_exist $LIBRDKAFKA_SOURCE

    cd $TP_SOURCE_DIR/$LIBRDKAFKA_SOURCE

    mkdir -p sr_build && cd sr_build
    $CMAKE_CMD -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" \
        -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include;$TP_INSTALL_DIR/include/zstd;$TP_INSTALL_DIR/include/lz4" \
        -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DRDKAFKA_BUILD_STATIC=ON -DWITH_SASL=ON -DWITH_SASL_SCRAM=ON \
        -DRDKAFKA_BUILD_EXAMPLES=OFF -DRDKAFKA_BUILD_TESTS=OFF -DWITH_SSL=ON -DWITH_ZSTD=ON -DCMAKE_INSTALL_LIBDIR=lib ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# pulsar
build_pulsar() {
    check_if_source_exist $PULSAR_SOURCE

    cd $TP_SOURCE_DIR/$PULSAR_SOURCE

    $CMAKE_CMD -DCMAKE_LIBRARY_PATH=$TP_INSTALL_DIR/lib -DCMAKE_INCLUDE_PATH=$TP_INSTALL_DIR/include \
        -DPROTOC_PATH=$TP_INSTALL_DIR/bin/protoc -DBUILD_TESTS=OFF -DBUILD_PYTHON_WRAPPER=OFF -DBUILD_DYNAMIC_LIB=OFF \
        -DOPENSSL_ROOT_DIR=$TP_INSTALL_DIR .
    ${BUILD_SYSTEM} -j$PARALLEL

    cp lib/libpulsar.a $TP_INSTALL_DIR/lib/
    cp -r include/pulsar $TP_INSTALL_DIR/include/
}

# flatbuffers
build_flatbuffers() {
  check_if_source_exist $FLATBUFFERS_SOURCE
  cd $TP_SOURCE_DIR/$FLATBUFFERS_SOURCE
  mkdir -p $BUILD_DIR
  cd $BUILD_DIR
  rm -rf CMakeCache.txt CMakeFiles/
  LDFLAGS="-static-libstdc++ -static-libgcc" \
  ${CMAKE_CMD} .. -G "${CMAKE_GENERATOR}" -DFLATBUFFERS_BUILD_TESTS=OFF
  ${BUILD_SYSTEM} -j$PARALLEL
  cp flatc  $TP_INSTALL_DIR/bin/flatc
  cp -r ../include/flatbuffers  $TP_INCLUDE_DIR/flatbuffers
  cp libflatbuffers.a $TP_LIB_DIR/libflatbuffers.a
}

build_brotli() {
    check_if_source_exist $BROTLI_SOURCE
    cd $TP_SOURCE_DIR/$BROTLI_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    ${CMAKE_CMD} .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR -DCMAKE_INSTALL_LIBDIR=lib64
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    mv -f $TP_INSTALL_DIR/lib64/libbrotlienc-static.a $TP_INSTALL_DIR/lib64/libbrotlienc.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlidec-static.a $TP_INSTALL_DIR/lib64/libbrotlidec.a
    mv -f $TP_INSTALL_DIR/lib64/libbrotlicommon-static.a $TP_INSTALL_DIR/lib64/libbrotlicommon.a
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so
    rm $TP_INSTALL_DIR/lib64/libbrotli*.so.*
}

# arrow
build_arrow() {
    export CXXFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g ${FILE_PREFIX_MAP_OPTION}"
    export CPPFLAGS=$CXXFLAGS

    check_if_source_exist $ARROW_SOURCE
    cd $TP_SOURCE_DIR/$ARROW_SOURCE/cpp
    mkdir -p release
    cd release
    export ARROW_BROTLI_URL=${TP_SOURCE_DIR}/${BROTLI_NAME}
    export ARROW_GLOG_URL=${TP_SOURCE_DIR}/${GLOG_NAME}
    export ARROW_LZ4_URL=${TP_SOURCE_DIR}/${LZ4_NAME}
    export ARROW_SNAPPY_URL=${TP_SOURCE_DIR}/${SNAPPY_NAME}
    export ARROW_ZLIB_URL=${TP_SOURCE_DIR}/${ZLIB_NAME}
    export ARROW_FLATBUFFERS_URL=${TP_SOURCE_DIR}/${FLATBUFFERS_NAME}
    export ARROW_ZSTD_URL=${TP_SOURCE_DIR}/${ZSTD_NAME}
    export LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc"

    # https://github.com/apache/arrow/blob/apache-arrow-5.0.0/cpp/src/arrow/memory_pool.cc#L286
    #
    # JemallocAllocator use mallocx and rallocx to allocate new memory, but mallocx and rallocx are Non-standard APIs,
    # and can not be hooked in BE, the memory used by arrow can not be counted by BE,
    # so disable jemalloc here and use SystemAllocator.
    #
    # Currently, the standard APIs are hooked in BE, so the jemalloc standard APIs will actually be used.
    ${CMAKE_CMD} -DARROW_PARQUET=ON -DARROW_JSON=ON -DARROW_IPC=ON -DARROW_USE_GLOG=OFF -DARROW_BUILD_STATIC=ON -DARROW_BUILD_SHARED=OFF \
    -DARROW_WITH_BROTLI=ON -DARROW_WITH_LZ4=ON -DARROW_WITH_SNAPPY=ON -DARROW_WITH_ZLIB=ON -DARROW_WITH_ZSTD=ON \
    -DARROW_WITH_UTF8PROC=OFF -DARROW_WITH_RE2=OFF \
    -DARROW_JEMALLOC=OFF -DARROW_MIMALLOC=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DARROW_BOOST_USE_SHARED=OFF -DARROW_GFLAGS_USE_SHARED=OFF -DBoost_NO_BOOST_CMAKE=ON -DBOOST_ROOT=$TP_INSTALL_DIR \
    -DJEMALLOC_HOME=$TP_INSTALL_DIR/jemalloc \
    -Dzstd_SOURCE=BUNDLED \
    -DRapidJSON_ROOT=$TP_INSTALL_DIR \
    -DARROW_SNAPPY_USE_SHARED=OFF \
    -DZLIB_ROOT=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DARROW_LZ4_USE_SHARED=OFF \
    -DBROTLI_ROOT=$TP_INSTALL_DIR \
    -DARROW_BROTLI_USE_SHARED=OFF \
    -Dgflags_ROOT=$TP_INSTALL_DIR/ \
    -DSnappy_ROOT=$TP_INSTALL_DIR/ \
    -DGLOG_ROOT=$TP_INSTALL_DIR/ \
    -DLZ4_ROOT=$TP_INSTALL_DIR/ \
    -DBoost_DIR=$TP_INSTALL_DIR \
    -DBoost_ROOT=$TP_INSTALL_DIR \
    -DARROW_BOOST_USE_SHARED=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DThrift_ROOT=$TP_INSTALL_DIR/ ..

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    if [ -f ./zstd_ep-install/lib64/libzstd.a ]; then
        cp -rf ./zstd_ep-install/lib64/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    else
        cp -rf ./zstd_ep-install/lib/libzstd.a $TP_INSTALL_DIR/lib64/libzstd.a
    fi
    # copy zstd headers
    mkdir -p ${TP_INSTALL_DIR}/include/zstd
    cp ./zstd_ep-install/include/* ${TP_INSTALL_DIR}/include/zstd

    restore_compile_flags
}

# s2
build_s2() {
    check_if_source_exist $S2_SOURCE
    cd $TP_SOURCE_DIR/$S2_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DBUILD_SHARED_LIBS=0 -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DBUILD_SHARED_LIBS=OFF \
    -DGFLAGS_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GFLAGS=ON \
    -DGLOG_ROOT_DIR="$TP_INSTALL_DIR/include" \
    -DWITH_GLOG=ON \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# bitshuffle
build_bitshuffle() {
    check_if_source_exist $BITSHUFFLE_SOURCE
    cd $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE
    PREFIX=$TP_INSTALL_DIR

    # This library has significant optimizations when built with -mavx2. However,
    # we still need to support non-AVX2-capable hardware. So, we build it twice,
    # once with the flag and once without, and use some linker tricks to
    # suffix the AVX2 symbols with '_avx2'.
    arches="default avx2 avx512"
    # Becuase aarch64 don't support avx2, disable it.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        arches="default neon"
    fi

    to_link=""
    for arch in $arches ; do
        arch_flag=""
        if [ "$arch" == "avx2" ]; then
            arch_flag="-mavx2"
        elif [ "$arch" == "avx512" ]; then
            arch_flag="-march=icelake-server"
        elif [ "$arch" == "neon" ]; then
            arch_flag="-march=armv8-a+crc"
        fi
        tmp_obj=bitshuffle_${arch}_tmp.o
        dst_obj=bitshuffle_${arch}.o
        ${CC:-gcc} $EXTRA_CFLAGS $arch_flag -std=c99 -I$PREFIX/include/lz4/ -O3 -DNDEBUG -fPIC -c \
            "src/bitshuffle_core.c" \
            "src/bitshuffle.c" \
            "src/iochain.c"
        # Merge the object files together to produce a combined .o file.
        ld -r -o $tmp_obj bitshuffle_core.o bitshuffle.o iochain.o
        # For the AVX2 symbols, suffix them.
        if [[ "$arch" == "avx2" || "$arch" == "avx512" || "$arch" == "neon" ]]; then
            # Create a mapping file with '<old_sym> <suffixed_sym>' on each line.
            nm --defined-only --extern-only $tmp_obj | while read addr type sym ; do
              echo ${sym} ${sym}_${arch}
            done > renames.txt
            objcopy --redefine-syms=renames.txt $tmp_obj $dst_obj
        else
            mv $tmp_obj $dst_obj
        fi
        to_link="$to_link $dst_obj"
    done
    rm -f libbitshuffle.a
    ar rs libbitshuffle.a $to_link
    mkdir -p $PREFIX/include/bitshuffle
    cp libbitshuffle.a $PREFIX/lib/
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle.h $PREFIX/include/bitshuffle/bitshuffle.h
    cp $TP_SOURCE_DIR/$BITSHUFFLE_SOURCE/src/bitshuffle_core.h $PREFIX/include/bitshuffle/bitshuffle_core.h
}

# croaring bitmap
# If open AVX512 default, current version will be compiled failed on some machine, so close AVX512 default,
# When this problem is solved, a switch will be added to control.
build_croaringbitmap() {
    FORCE_AVX=ON
    # avx2 is not supported by aarch64.
    if [[ "${MACHINE_TYPE}" == "aarch64" ]]; then
        FORCE_AVX=FALSE
    fi
    if [[ `cat /proc/cpuinfo |grep avx|wc -l` == "0" ]]; then
        FORCE_AVX=FALSE
    fi
    check_if_source_exist $CROARINGBITMAP_SOURCE
    cd $TP_SOURCE_DIR/$CROARINGBITMAP_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    LDFLAGS="-L${TP_LIB_DIR} -static-libstdc++ -static-libgcc" \
    $CMAKE_CMD -G "${CMAKE_GENERATOR}" -DROARING_BUILD_STATIC=ON -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
    -DCMAKE_INCLUDE_PATH="$TP_INSTALL_DIR/include" \
    -DENABLE_ROARING_TESTS=OFF \
    -DROARING_DISABLE_NATIVE=ON \
    -DFORCE_AVX=$FORCE_AVX \
    -DROARING_DISABLE_AVX512=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_LIBRARY_PATH="$TP_INSTALL_DIR/lib;$TP_INSTALL_DIR/lib64" ..
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}
#orc
build_orc() {
    check_if_source_exist $ORC_SOURCE
    cd $TP_SOURCE_DIR/$ORC_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD ../ -DBUILD_JAVA=OFF \
    -G "${CMAKE_GENERATOR}" \
    -DPROTOBUF_HOME=$TP_INSTALL_DIR \
    -DSNAPPY_HOME=$TP_INSTALL_DIR \
    -DGTEST_HOME=$TP_INSTALL_DIR \
    -DLZ4_HOME=$TP_INSTALL_DIR \
    -DLZ4_INCLUDE_DIR=$TP_INSTALL_DIR/include/lz4 \
    -DZLIB_HOME=$TP_INSTALL_DIR\
    -DBUILD_LIBHDFSPP=OFF \
    -DBUILD_CPP_TESTS=OFF \
    -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#cctz
build_cctz() {
    check_if_source_exist $CCTZ_SOURCE
    cd $TP_SOURCE_DIR/$CCTZ_SOURCE

    make -j$PARALLEL
    PREFIX=${TP_INSTALL_DIR} make install
}

#fmt
build_fmt() {
    check_if_source_exist $FMT_SOURCE
    cd $TP_SOURCE_DIR/$FMT_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} ../ \
            -DCMAKE_INSTALL_LIBDIR=lib64 -G "${CMAKE_GENERATOR}" -DFMT_TEST=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#ryu
build_ryu() {
    check_if_source_exist $RYU_SOURCE
    cd $TP_SOURCE_DIR/$RYU_SOURCE/ryu
    make -j$PARALLEL
    make install DESTDIR=${TP_INSTALL_DIR}
    mkdir -p $TP_INSTALL_DIR/include/ryu
    mv $TP_INSTALL_DIR/include/ryu.h $TP_INSTALL_DIR/include/ryu
    # copy to 64 to compatable with current CMake
    cp -f ${TP_INSTALL_DIR}/lib/libryu.a ${TP_INSTALL_DIR}/lib64/libryu.a
}

#break_pad
build_breakpad() {
    check_if_source_exist $BREAK_PAD_SOURCE
    cd $TP_SOURCE_DIR/$BREAK_PAD_SOURCE
    mkdir -p src/third_party/lss
    cp $TP_PATCH_DIR/linux_syscall_support.h src/third_party/lss
    CFLAGS= CXXFLAGS="${CXXFLAGS} -Wno-nonnull" ./configure --prefix=$TP_INSTALL_DIR --enable-shared=no --disable-samples --disable-libevent-regress
    make -j$PARALLEL
    make install
}

#hadoop
build_hadoop() {
    check_if_source_exist $HADOOP_SOURCE
    cp -r $TP_SOURCE_DIR/$HADOOP_SOURCE $TP_INSTALL_DIR/hadoop
    # remove unnecessary doc and logs
    rm -rf $TP_INSTALL_DIR/hadoop/logs/* $TP_INSTALL_DIR/hadoop/share/doc/hadoop
    mkdir -p $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/include/hdfs.h $TP_INSTALL_DIR/include/hdfs
    cp $TP_SOURCE_DIR/$HADOOP_SOURCE/lib/native/libhdfs.a $TP_INSTALL_DIR/lib
}

#jdk
build_jdk() {
    check_if_source_exist $JDK_SOURCE
    rm -rf $TP_INSTALL_DIR/open_jdk && cp -r $TP_SOURCE_DIR/$JDK_SOURCE $TP_INSTALL_DIR/open_jdk
}

# ragel
# ragel-6.9+ is used by hypercan, so we build it first.
build_ragel() {
    check_if_source_exist $RAGEL_SOURCE
    cd $TP_SOURCE_DIR/$RAGEL_SOURCE
    # generage a static linked ragel, hyperscan will depend on it
    LDFLAGS=" -static-libstdc++ -static-libgcc" \
    ./configure --prefix=$TP_INSTALL_DIR --disable-shared --enable-static
    make -j$PARALLEL
    make install
}

#hyperscan
build_hyperscan() {
    check_if_source_exist $HYPERSCAN_SOURCE
    cd $TP_SOURCE_DIR/$HYPERSCAN_SOURCE
    export PATH=$TP_INSTALL_DIR/bin:$PATH
    $CMAKE_CMD -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DBOOST_ROOT=$STARROCKS_THIRDPARTY/installed/include \
          -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc  -DCMAKE_INSTALL_LIBDIR=lib \
          -DBUILD_EXAMPLES=OFF -DBUILD_UNIT=OFF
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

#mariadb-connector-c
build_mariadb() {
    OLD_CMAKE_GENERATOR=${CMAKE_GENERATOR}
    OLD_BUILD_SYSTEM=${BUILD_SYSTEM}

    unset CXXFLAGS
    unset CPPFLAGS
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC ${FILE_PREFIX_MAP_OPTION}"

    # force use make build system, since ninja doesn't support install only headers
    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'

    check_if_source_exist $MARIADB_SOURCE
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE
    mkdir -p build && cd build

    $CMAKE_CMD .. -G "${CMAKE_GENERATOR}" -DCMAKE_BUILD_TYPE=Release    \
                  -DWITH_UNIT_TESTS=OFF                                 \
                  -DBUILD_SHARED_LIBS=OFF                               \
                  -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                  \
                  -DOPENSSL_USE_STATIC_LIBS=TRUE                        \
                  -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR}
    # we only need build libmariadbclient and headers
    ${BUILD_SYSTEM} -j$PARALLEL mariadbclient
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/libmariadb
    mkdir -p $TP_INSTALL_DIR/lib/mariadb/
    cp libmariadbclient.a $TP_INSTALL_DIR/lib/mariadb/
    # install mariadb headers
    cd $TP_SOURCE_DIR/$MARIADB_SOURCE/build/include
    ${BUILD_SYSTEM} install

    restore_compile_flags
    export CMAKE_GENERATOR=$OLD_CMAKE_GENERATOR
    export BUILD_SYSTEM=$OLD_BUILD_SYSTEM
}

# jindosdk for Aliyun OSS
build_aliyun_jindosdk() {
    check_if_source_exist $JINDOSDK_SOURCE
    mkdir -p $TP_INSTALL_DIR/jindosdk
    cp -r $TP_SOURCE_DIR/$JINDOSDK_SOURCE/lib/*.jar $TP_INSTALL_DIR/jindosdk
}

build_gcs_connector() {
    check_if_source_exist $GCS_CONNECTOR_SOURCE
    mkdir -p $TP_INSTALL_DIR/gcs_connector
    cp -r $TP_SOURCE_DIR/$GCS_CONNECTOR_SOURCE/*.jar $TP_INSTALL_DIR/gcs_connector
}

build_broker_thirdparty_jars() {
    check_if_source_exist $BROKER_THIRDPARTY_JARS_SOURCE
    mkdir -p $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    cp -r $TP_SOURCE_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/* $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/hadoop-aliyun-2.7.2.jar
    # cloudfs-hadoop-with-dependencies will include aws jars, but we already support aws by official sdk, so we don't need it anymore.
    # And it will conflict with Iceberg's S3FileIO, make access S3 files failed.
    rm $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/cloudfs-hadoop-with-dependencies-1.1.21.jar
    # ensure read permission is granted for all users
    chmod -R +r $TP_INSTALL_DIR/$BROKER_THIRDPARTY_JARS_SOURCE/
}

build_aws_cpp_sdk() {
    check_if_source_exist $AWS_SDK_CPP_SOURCE
    cd $TP_SOURCE_DIR/$AWS_SDK_CPP_SOURCE
    # only build s3, s3-crt, transfer manager, identity-management and sts, you can add more components if you want.
    $CMAKE_CMD -Bbuild -DBUILD_ONLY="core;s3;s3-crt;transfer;identity-management;sts" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
               -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DENABLE_TESTING=OFF \
               -DENABLE_CURL_LOGGING=OFF \
               -G "${CMAKE_GENERATOR}" \
               -DCURL_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libcurl.a   \
               -DZLIB_LIBRARY_RELEASE=${TP_INSTALL_DIR}/lib/libz.a      \
               -DOPENSSL_ROOT_DIR=${TP_INSTALL_DIR}                     \
               -DOPENSSL_USE_STATIC_LIBS=TRUE                           \
               -Dcrypto_LIBRARY=${TP_INSTALL_DIR}/lib/libcrypto.a

    cd build
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install

    restore_compile_flags
}

# velocypack
build_vpack() {
    check_if_source_exist $VPACK_SOURCE
    cd $TP_SOURCE_DIR/$VPACK_SOURCE
    mkdir -p build
    cd build
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DCMAKE_CXX_COMPILER=$STARROCKS_GCC_HOME/bin/g++ -DCMAKE_C_COMPILER=$STARROCKS_GCC_HOME/bin/gcc

    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# opentelemetry
build_opentelemetry() {
    check_if_source_exist $OPENTELEMETRY_SOURCE

    cd $TP_SOURCE_DIR/$OPENTELEMETRY_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    $CMAKE_CMD .. \
        -DCMAKE_CXX_STANDARD="17" \
        -G "${CMAKE_GENERATOR}" \
        -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} \
        -DBUILD_TESTING=OFF -DWITH_EXAMPLES=OFF \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        -DWITH_STL=OFF -DWITH_JAEGER=ON
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# jemalloc
build_jemalloc() {
    check_if_source_exist $JEMALLOC_SOURCE

    cd $TP_SOURCE_DIR/$JEMALLOC_SOURCE
    # jemalloc supports a runtime page size that's smaller or equal to the build
    # time one, but aborts on a larger one. If not defined, it falls back to the
    # the build system's _SC_PAGESIZE, which in many architectures can vary. Set
    # this to 64K (2^16) for arm architecture, and default 4K on x86 for performance.
    local addition_opts=" --with-lg-page=12"
    if [[ $MACHINE_TYPE == "aarch64" ]] ; then
        # change to 64K for arm architecture
        addition_opts=" --with-lg-page=16"
    fi
    # build jemalloc with release
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc --with-jemalloc-prefix=je --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
    # build jemalloc with debug options
    CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g" \
    ./configure --prefix=${TP_INSTALL_DIR}/jemalloc-debug --with-jemalloc-prefix=je --enable-prof --enable-debug --enable-fill --enable-prof --disable-cxx --disable-libdl --disable-shared $addition_opts
    make -j$PARALLEL
    make install
}

# google benchmark
build_benchmark() {
    check_if_source_exist $BENCHMARK_SOURCE
    cd $TP_SOURCE_DIR/$BENCHMARK_SOURCE
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/
    cmake -DBENCHMARK_DOWNLOAD_DEPENDENCIES=off \
          -DBENCHMARK_ENABLE_GTEST_TESTS=off \
          -DCMAKE_INSTALL_PREFIX=$TP_INSTALL_DIR \
          -DCMAKE_INSTALL_LIBDIR=lib64 \
          -DCMAKE_BUILD_TYPE=Release ../
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# fast float
build_fast_float() {
    check_if_source_exist $FAST_FLOAT_SOURCE
    cd $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE
    cp -r $TP_SOURCE_DIR/$FAST_FLOAT_SOURCE/include $TP_INSTALL_DIR
}

build_starcache() {
    check_if_source_exist $STARCACHE_SOURCE
    rm -rf $TP_INSTALL_DIR/$STARCACHE_SOURCE && mv $TP_SOURCE_DIR/$STARCACHE_SOURCE $TP_INSTALL_DIR/
}

# streamvbyte
build_streamvbyte() {
    check_if_source_exist $STREAMVBYTE_SOURCE

    cd $TP_SOURCE_DIR/$STREAMVBYTE_SOURCE/

    mkdir -p $BUILD_DIR
    cd $BUILD_DIR
    rm -rf CMakeCache.txt CMakeFiles/

    CMAKE_GENERATOR="Unix Makefiles"
    BUILD_SYSTEM='make'
    $CMAKE_CMD .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX:PATH=$TP_INSTALL_DIR/

    make -j$PARALLEL
    make install
}

# jansson
build_jansson() {
    check_if_source_exist $JANSSON_SOURCE
    cd $TP_SOURCE_DIR/$JANSSON_SOURCE/
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# avro-c
build_avro_c() {
    check_if_source_exist $AVRO_SOURCE
    cd $TP_SOURCE_DIR/$AVRO_SOURCE/lang/c
    mkdir -p build
    cd build
    $CMAKE_CMD .. -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
    rm ${TP_INSTALL_DIR}/lib64/libavro.so*
}

# serders
build_serdes() {
    export CFLAGS="-O3 -fno-omit-frame-pointer -fPIC -g"
    check_if_source_exist $SERDES_SOURCE
    cd $TP_SOURCE_DIR/$SERDES_SOURCE
    export LIBS="-lrt -lpthread -lcurl -ljansson -lrdkafka -lrdkafka++ -lavro -lssl -lcrypto -ldl"
    ./configure --prefix=${TP_INSTALL_DIR} \
                --libdir=${TP_INSTALL_DIR}/lib \
                --CFLAGS="-I ${TP_INSTALL_DIR}/include"  \
                --CXXFLAGS="-I ${TP_INSTALL_DIR}/include" \
                --LDFLAGS="-L ${TP_INSTALL_DIR}/lib -L ${TP_INSTALL_DIR}/lib64" \
                --enable-static \
                --disable-shared

    make -j$PARALLEL
    make install
    rm ${TP_INSTALL_DIR}/lib/libserdes.so*
    # these symbols also be definition in librdkafka, change these symbols to be local.
    objcopy --localize-symbol=cnd_timedwait ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=cnd_timedwait_ms ${TP_INSTALL_DIR}/lib/libserdes.a
    objcopy --localize-symbol=thrd_is_current ${TP_INSTALL_DIR}/lib/libserdes.a
    unset LIBS
    restore_compile_flags
}

# datasketches
build_datasketches() {
    check_if_source_exist $DATASKETCHES_SOURCE
    mkdir -p $TP_INSTALL_DIR/include/datasketches
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/common/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/cpc/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/fi/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/hll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/kll/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/quantiles/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/req/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/sampling/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/theta/include/* $TP_INSTALL_DIR/include/datasketches/
    cp -r $TP_SOURCE_DIR/$DATASKETCHES_SOURCE/tuple/include/* $TP_INSTALL_DIR/include/datasketches/
}

# async-profiler
build_async_profiler() {
    check_if_source_exist $ASYNC_PROFILER_SOURCE
    mkdir -p $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/build $TP_INSTALL_DIR/async-profiler
    cp -r $TP_SOURCE_DIR/$ASYNC_PROFILER_SOURCE/profiler.sh $TP_INSTALL_DIR/async-profiler
}

# fiu
build_fiu() {
    check_if_source_exist $FIU_SOURCE
    cd $TP_SOURCE_DIR/$FIU_SOURCE
    mkdir -p $TP_SOURCE_DIR/$FIU_SOURCE/installed
    make -j$PARALLEL
    make PREFIX=$TP_SOURCE_DIR/$FIU_SOURCE/installed install

    mkdir -p $TP_INSTALL_DIR/include/fiu
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/include/* $TP_INSTALL_DIR/include/fiu/
    cp $TP_SOURCE_DIR/$FIU_SOURCE/installed/lib/libfiu.a $TP_INSTALL_DIR/lib/
}

# libdeflate
build_libdeflate() {
    check_if_source_exist $LIBDEFLATE_SOURCE
    mkdir -p $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    cd $TP_SOURCE_DIR/$LIBDEFLATE_SOURCE/build
    $CMAKE_CMD .. -DCMAKE_INSTALL_LIBDIR=lib64 -DCMAKE_INSTALL_PREFIX=${TP_INSTALL_DIR} -DCMAKE_BUILD_TYPE=Release
    ${BUILD_SYSTEM} -j$PARALLEL
    ${BUILD_SYSTEM} install
}

# restore cxxflags/cppflags/cflags to default one
restore_compile_flags() {
    # c preprocessor flags
    export CPPFLAGS=$GLOBAL_CPPFLAGS
    # c flags
    export CFLAGS=$GLOBAL_CFLAGS
    # c++ flags
    export CXXFLAGS=$GLOBAL_CXXFLAGS
}

strip_binary() {
    # strip binary tools and ignore any errors
    echo "Strip binaries in $TP_INSTALL_DIR/bin/ ..."
    strip $TP_INSTALL_DIR/bin/* 2>/dev/null || true
}


# strip `$TP_SOURCE_DIR` and `$TP_INSTALL_DIR` from source code file path
export FILE_PREFIX_MAP_OPTION="-ffile-prefix-map=${TP_SOURCE_DIR}=. -ffile-prefix-map=${TP_INSTALL_DIR}=."
# set GLOBAL_C*FLAGS for easy restore in each sub build process
export GLOBAL_CPPFLAGS="-I ${TP_INCLUDE_DIR}"
# https://stackoverflow.com/questions/42597685/storage-size-of-timespec-isnt-known
export GLOBAL_CFLAGS="-O3 -fno-omit-frame-pointer -std=c99 -fPIC -g -D_POSIX_C_SOURCE=200112L -gz=zlib ${FILE_PREFIX_MAP_OPTION}"
export GLOBAL_CXXFLAGS="-O3 -fno-omit-frame-pointer -Wno-class-memaccess -fPIC -g -gz=zlib ${FILE_PREFIX_MAP_OPTION}"

# set those GLOBAL_*FLAGS to the CFLAGS/CXXFLAGS/CPPFLAGS
export CPPFLAGS=$GLOBAL_CPPFLAGS
export CXXFLAGS=$GLOBAL_CXXFLAGS
export CFLAGS=$GLOBAL_CFLAGS

build_libevent
build_zlib
build_lz4
build_lzo2
build_bzip
build_openssl
build_boost # must before thrift
build_protobuf
build_gflags
build_gtest
build_glog
build_rapidjson
build_simdjson
build_snappy
build_gperftools
build_curl
build_re2
build_thrift
build_leveldb
build_brpc
build_rocksdb
build_kerberos
build_sasl
build_flatbuffers
build_jemalloc
build_brotli
# must build before arrow
build_arrow
# NOTE: librdkafka depends on ZSTD which is generated by Arrow, So this SHOULD be
# built after arrow
build_librdkafka
build_pulsar
build_s2
build_bitshuffle
build_croaringbitmap
build_cctz
build_fmt
build_ryu
build_hadoop
build_jdk
build_ragel
build_hyperscan
build_mariadb
build_aliyun_jindosdk
build_gcs_connector
build_broker_thirdparty_jars
build_aws_cpp_sdk
build_vpack
build_opentelemetry
build_benchmark
build_fast_float
build_starcache
build_streamvbyte
build_jansson
build_avro_c
build_serdes
build_datasketches
build_async_profiler
build_fiu
build_llvm

if [[ "${MACHINE_TYPE}" != "aarch64" ]]; then
    build_breakpad
    build_libdeflate
fi

# strip unnecessary debug symbol for binaries in thirdparty
strip_binary

echo "Finished to build all thirdparties"

```

### 修改 2：`be/CMakeLists.txt`（添加 `-lsframe`）

我看到文件中已经有了上次的修改（`-lbfd -lsframe`），说明这个修改你已经接受了且还保留着。确认一下：

`be/CMakeLists.txt` 已经是修改后的状态，不需要再改了。

### 修改 3：文档 — 重写"安装编译依赖"章节，新增"基础准备"章节

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
processors=8
```

修改后在 PowerShell 执行 `wsl --shutdown`，再重新进入 WSL 使配置生效。可在 WSL 中用 `free -h` 验证。

### 0.2 下载源码

```bash
git clone https://github.com/StarRocks/starrocks.git
cd starrocks
git checkout branch-3.2.16-learning   # 切换到目标分支
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
- **BE 启动时 SIGABRT（DataCache 相关）**：在 `output/be/conf/be.conf` 中加一行 `datacache_enable = false`。

---

## 九、推荐 Debug 组合

| 组件 | 启动方式 | 调试方式 |
|------|----------|----------|
| FE | `start_fe.sh --daemon --debug` | Windows IDEA → Remote JVM Debug → `localhost:5005` |
| BE | `start_be.sh --daemon`（Debug 构建） | Windows CLion（WSL Toolchain）→ Attach to Process |

**完整链路**：MySQL 连 `localhost:9030` 执行 SQL → FE 在 Java 断点停住看解析/规划 → BE 在 C++ 断点停住看执行/存储，完整跟踪一条 SQL 从头到尾的源码路径。

```

全部 3 个文件修改完成！来确认一下每个修改：

---

**✅ 文件 1：`thirdparty/build-thirdparty.sh`（4 处修改）**

1. **RocksDB**（`build_rocksdb` 函数）— 添加 `-Wno-redundant-move` 和 `-include cstdint`
2. **Breakpad**（`build_breakpad` 函数）— 添加 `CXXFLAGS="${CXXFLAGS} -Wno-nonnull"`
3. **Pulsar**（`build_pulsar` 函数）— 添加 `-DOPENSSL_ROOT_DIR=$TP_INSTALL_DIR`
4. **LLVM**（`build_llvm` 函数）— 删除末尾多余的 `../${LLVM_SOURCE}`

**✅ 文件 2：`be/CMakeLists.txt`（已是修改后状态，无需再改）**

- `-lbfd` 后面已有 `-lsframe`

**✅ 文件 3：`docs/zh/learning/在wsl2上进行starrocks编译启动源码debug总结.md`**

- 标题改为「WSL2 上编译、启动、Debug StarRocks（3.2 版本）」
- 新增「零、基础准备」章节（安装 WSL2 + 内存配置建议、下载源码、Cursor 使用注意、CLion 安装）
- 「一、安装编译依赖」拆分为 4 个子章节：基础工具、安装 GCC 10（⚠️ 重点强调）、安装 JDK 17、验证
- 详细说明了为什么不建议用 GCC 13+，以及 Ubuntu 24.04 上如何安装 GCC 10

---

建议你现在用 `git diff` 确认所有改动，然后 `git stash` 或 `git add -A && git commit` 备份一下！

