# AMD64 (x86_64) 汇编参考手册

> 本手册仅涉及 AMD64 (x86_64) 架构，使用 Intel 汇编语法。
> 关于 x86_64 vs ARM 架构对比、Intel 语法 vs AT&T 语法对照等内容，请参阅同目录下的 [CPU指令集.md](CPU指令集.md)。

---

## 一、环境信息

| 项目 | 值 |
|------|------|
| CPU | AMD Ryzen 9 8940HX |
| 架构 | x86_64（也叫 AMD64，64 位） |
| 指令集 | x86-64 + SSE/AVX/AVX-512 等扩展 |
| 编译器 | GCC 10.5.0 |
| 汇编语法 | Intel 语法（通过 `-masm=intel` 指定） |
| 操作系统 | Windows WSL2 (Ubuntu) |
| 调用约定 | System V AMD64 ABI |

---

## 二、寄存器大全

### 2.1 通用寄存器（16 个）

x86_64 有 16 个 64 位通用寄存器。每个 64 位寄存器都可以通过不同名称访问其低位部分：

#### 经典 8 个寄存器（从 8086 时代继承）

| 64 位 | 32 位 | 16 位 | 8 位（低） | 8 位（高） | 主要用途 |
|-------|-------|-------|-----------|-----------|---------|
| **RAX** | EAX | AX | AL | AH | 累加器，**函数返回值** |
| **RBX** | EBX | BX | BL | BH | 基址寄存器，**被调用者保存** |
| **RCX** | ECX | CX | CL | CH | 计数器，函数第 **4** 个参数 |
| **RDX** | EDX | DX | DL | DH | 数据寄存器，函数第 **3** 个参数 |
| **RSI** | ESI | SI | SIL | — | 源变址，函数第 **2** 个参数 |
| **RDI** | EDI | DI | DIL | — | 目标变址，函数第 **1** 个参数（C++ 中也是 `this`） |
| **RBP** | EBP | BP | BPL | — | 基址指针（栈帧锚点），**被调用者保存** |
| **RSP** | ESP | SP | SPL | — | 栈指针（始终指向栈顶） |

> 注意：SIL、DIL、BPL、SPL 这 4 个 8 位寄存器是 x86_64 新增的，在 32 位模式下不存在。

#### 子寄存器嵌套关系图（以 RAX 为例）

```
RAX（64 位，8 字节）
├── EAX（低 32 位，4 字节）
│   ├── AX（低 16 位，2 字节）
│   │   ├── AL（低 8 位，1 字节）
│   │   └── AH（高 8 位，即 AX 的 bit 8~15）
│   └── EAX 的高 16 位（无独立名称）
└── RAX 的高 32 位（无独立名称）

位编号：
63        32 31        16 15     8 7      0
[  高32位   ] [  高16位   ] [  AH  ] [  AL  ]
|<-------------- RAX (64位) -------------->|
              |<------- EAX (32位) ------->|
                           |<---- AX ----->|
```

> **重要规则**：在 x86_64 中，**写 32 位寄存器（如 `mov eax, 0`）会自动将高 32 位清零**。但写 8 位或 16 位寄存器不会影响高位。

#### x86_64 新增的 8 个寄存器（R8~R15）

| 64 位 | 32 位 | 16 位 | 8 位（低） | 主要用途 |
|-------|-------|-------|-----------|---------|
| **R8** | R8D | R8W | R8B | 函数第 **5** 个参数 |
| **R9** | R9D | R9W | R9B | 函数第 **6** 个参数 |
| **R10** | R10D | R10W | R10B | 调用者保存，临时 |
| **R11** | R11D | R11W | R11B | 调用者保存，临时 |
| **R12** | R12D | R12W | R12B | **被调用者保存** |
| **R13** | R13D | R13W | R13B | **被调用者保存** |
| **R14** | R14D | R14W | R14B | **被调用者保存** |
| **R15** | R15D | R15W | R15B | **被调用者保存** |

> R8~R15 没有 AH 那样的"高 8 位"子寄存器——只有 D（Doubleword，32位）、W（Word，16位）、B（Byte，8位）。

### 2.2 段寄存器（6 个）

段寄存器是 x86 架构从 16 位时代遗留下来的。在 64 位模式下，大多数段寄存器已无原始用途，但 FS 和 GS 仍然被操作系统使用。

| 寄存器 | 全称 | 64 位模式下的用途 |
|--------|------|-----------------|
| **CS** | Code Segment | 代码段，CPU 自动管理，程序员不直接操作 |
| **DS** | Data Segment | 数据段，64 位下基址固定为 0，可忽略 |
| **ES** | Extra Segment | 附加段，64 位下基址固定为 0，可忽略 |
| **SS** | Stack Segment | 栈段，64 位下基址固定为 0，可忽略 |
| **FS** | （无标准全称） | **Linux**：指向线程控制块（TCB），用于线程局部存储（TLS）。`fs:40` 就是 Stack Canary 的位置 |
| **GS** | （无标准全称） | **Linux 内核**：指向 per-CPU 数据区。用户态一般不直接使用 |

### 2.3 指令指针寄存器

| 寄存器 | 大小 | 说明 |
|--------|------|------|
| **RIP** | 64 位 | 指令指针（Instruction Pointer），也叫程序计数器（PC）。始终指向**下一条要执行的指令的地址**。不能直接用 `mov` 修改，只能通过 `jmp`、`call`、`ret` 等控制流指令间接修改。 |

> 在 x86_64 中，RIP 还可以用于**RIP 相对寻址**（RIP-relative addressing），这是 64 位模式新增的寻址方式，常见于访问全局变量和字符串常量。

### 2.4 标志寄存器（RFLAGS）

RFLAGS 是一个 64 位寄存器，其中每个二进制位（bit）是一个**标志位（Flag）**，记录 CPU 运算的状态。大多数标志位由算术/逻辑指令自动设置，控制流指令（如 `je`、`jg`）根据标志位决定是否跳转。

#### 常用标志位

| 标志位 | 全称 | 位置 | 含义 | 设置时机 |
|--------|------|------|------|---------|
| **ZF** | Zero Flag | bit 6 | 运算结果为 0 时置 1 | `add`/`sub`/`cmp`/`test`/`and`/`or`/`xor` 等 |
| **SF** | Sign Flag | bit 7 | 运算结果为负数（最高位为 1）时置 1 | 同上 |
| **CF** | Carry Flag | bit 0 | 无符号运算产生进位/借位时置 1 | `add`/`sub`/`cmp`/移位指令 |
| **OF** | Overflow Flag | bit 11 | 有符号运算溢出时置 1 | `add`/`sub`/`cmp` |
| **PF** | Parity Flag | bit 2 | 结果最低字节中 1 的个数为偶数时置 1 | 算术/逻辑指令 |
| **AF** | Auxiliary Carry Flag | bit 4 | BCD 运算辅助进位 | 很少使用 |

#### 控制标志位

| 标志位 | 全称 | 位置 | 含义 |
|--------|------|------|------|
| **DF** | Direction Flag | bit 10 | 字符串操作的方向。0=递增（前向），1=递减（后向）。用 `cld`/`std` 设置 |
| **IF** | Interrupt Flag | bit 9 | 中断允许标志。1=允许外部中断，0=禁止。仅内核可修改 |
| **TF** | Trap Flag | bit 8 | 单步调试标志。1=每执行一条指令就触发调试异常 |

#### 条件跳转指令与标志位的对应

| 跳转指令 | 含义 | 检查的标志位 |
|---------|------|------------|
| `je` / `jz` | 等于 / 为零 | ZF = 1 |
| `jne` / `jnz` | 不等于 / 非零 | ZF = 0 |
| `jg` / `jnle` | 大于（有符号） | ZF = 0 且 SF = OF |
| `jge` / `jnl` | 大于等于（有符号） | SF = OF |
| `jl` / `jnge` | 小于（有符号） | SF ≠ OF |
| `jle` / `jng` | 小于等于（有符号） | ZF = 1 或 SF ≠ OF |
| `ja` / `jnbe` | 高于（无符号） | CF = 0 且 ZF = 0 |
| `jae` / `jnb` / `jnc` | 高于等于（无符号） | CF = 0 |
| `jb` / `jnae` / `jc` | 低于（无符号） | CF = 1 |
| `jbe` / `jna` | 低于等于（无符号） | CF = 1 或 ZF = 1 |
| `js` | 负数 | SF = 1 |
| `jns` | 非负数 | SF = 0 |
| `jo` | 溢出 | OF = 1 |
| `jno` | 未溢出 | OF = 0 |

### 2.5 浮点 / SIMD 寄存器

#### x87 FPU 寄存器（历史遗留，现代代码较少直接使用）

| 寄存器 | 大小 | 说明 |
|--------|------|------|
| ST(0) ~ ST(7) | 80 位 | x87 浮点单元的寄存器栈，8 个。以栈结构组织（ST(0) 是栈顶）。主要用于传统浮点运算，现代编译器更倾向使用 SSE/AVX |

#### MMX 寄存器（过时，了解即可）

| 寄存器 | 大小 | 说明 |
|--------|------|------|
| MM0 ~ MM7 | 64 位 | 多媒体扩展。与 x87 ST 寄存器共享物理空间，不能同时使用。已被 SSE 取代 |

#### SSE 寄存器

| 寄存器 | 大小 | 说明 |
|--------|------|------|
| XMM0 ~ XMM15 | 128 位 | SSE（Streaming SIMD Extensions）寄存器。现代代码中用于浮点运算和 SIMD 并行计算 |

在 System V AMD64 ABI 中：
- **XMM0 ~ XMM7**：传递浮点参数（前 8 个 float/double 参数）
- **XMM0**：浮点返回值

#### AVX 寄存器

| 寄存器 | 大小 | 说明 |
|--------|------|------|
| YMM0 ~ YMM15 | 256 位 | AVX（Advanced Vector Extensions）寄存器。XMM 寄存器是 YMM 寄存器的低 128 位 |

```
YMM0（256 位）
├── XMM0（低 128 位）
└── YMM0 的高 128 位
```

#### AVX-512 寄存器（简要了解）

| 寄存器 | 大小 | 说明 |
|--------|------|------|
| ZMM0 ~ ZMM31 | 512 位 | AVX-512 寄存器。YMM 是 ZMM 的低 256 位。数量从 16 个扩展到 32 个 |
| K0 ~ K7 | 64 位 | 掩码寄存器（Opmask），用于 AVX-512 的条件执行 |

> AMD Ryzen 9 8940HX 支持 AVX-512，但日常学习汇编时很少直接接触 AVX-512 指令。

### 2.6 控制 / 调试寄存器（了解即可）

这些寄存器只能在内核态（Ring 0）访问，用户态程序不能直接使用。

#### 控制寄存器

| 寄存器 | 主要用途 |
|--------|---------|
| **CR0** | 控制 CPU 模式：保护模式开关、分页开关、缓存控制 |
| **CR2** | 存储最近一次**缺页异常**（Page Fault）的线性地址 |
| **CR3** | 存储**页目录基地址**，用于虚拟内存地址转换 |
| **CR4** | 扩展控制：SSE 支持、大页面、SMEP 等 |

#### 调试寄存器

| 寄存器 | 用途 |
|--------|------|
| **DR0 ~ DR3** | 存储最多 4 个**硬件断点**的地址 |
| **DR6** | 调试状态寄存器（哪个断点被触发了） |
| **DR7** | 调试控制寄存器（断点的启用/类型/长度配置） |

---

## 三、寄存器命名历史与记忆技巧

### 3.1 从 8086 到 AMD64 的演进

x86 架构的寄存器命名经历了三个时代：

```
1978 年 - Intel 8086（16 位 CPU）
    AX, BX, CX, DX, SI, DI, BP, SP（8 个 16 位寄存器）

1985 年 - Intel 386（32 位 CPU）
    在前面加 E（Extended）：EAX, EBX, ECX, EDX, ESI, EDI, EBP, ESP

2003 年 - AMD64 / x86_64（64 位 CPU）
    在前面加 R（Register）：RAX, RBX, RCX, RDX, RSI, RDI, RBP, RSP
    新增 8 个：R8, R9, R10, R11, R12, R13, R14, R15
```

### 3.2 每个寄存器名字的由来

| 寄存器 | 缩写来源 | 全称 | 历史用途（8086 时代） | 记忆口诀 |
|--------|---------|------|---------------------|---------|
| **RAX** | **A**ccumulator | 累加器 | 算术运算的默认操作数和结果存放处。`mul`/`div` 指令强制使用 AX | **A**累加器 → 函数**A**nswer（返回值） |
| **RBX** | **B**ase | 基址寄存器 | 8086 时代用于存放数据段的基地址 | **B**ase → **B**ackup（被调用者保存，常被当"安全"存储） |
| **RCX** | **C**ounter | 计数器 | `loop` 指令用 CX 做循环计数，`rep` 前缀也用 CX | **C**ounter → **C**ount loops（数循环次数） |
| **RDX** | **D**ata | 数据寄存器 | 与 AX 配合做乘除法（`mul`→ DX:AX 存放 32 位结果） | **D**ata → 和 **A** 搭档的 **D**ata |
| **RSI** | **S**ource **I**ndex | 源变址寄存器 | 字符串操作（`movs`/`cmps`）的源地址指针 | **S**ource → 数据从**S**ource（源）来 |
| **RDI** | **D**estination **I**ndex | 目标变址寄存器 | 字符串操作的目标地址指针 | **D**estination → 数据到**D**estination（目的地）去 |
| **RBP** | **B**ase **P**ointer | 基址指针 | 指向当前函数栈帧的底部（锚点） | **B**ase **P**ointer → 栈帧的**B**ottom**P**oint（底部锚点） |
| **RSP** | **S**tack **P**ointer | 栈指针 | 始终指向栈顶，`push`/`pop` 自动修改 | **S**tack **P**ointer → **S**tack 的**P**eak（栈顶） |

### 3.3 前缀字母的含义

| 前缀 | 含义 | 时代 | 示例 |
|------|------|------|------|
| （无） | 原始的 16 位寄存器名 | 8086 (1978) | AX, BX, SI, BP |
| **E** | **E**xtended（扩展到 32 位） | 386 (1985) | **E**AX, **E**SI, **E**BP |
| **R** | **R**egister（扩展到 64 位） | AMD64 (2003) | **R**AX, **R**SI, **R**BP |

### 3.4 子寄存器后缀的含义

| 后缀 | 含义 | 示例 | 大小 |
|------|------|------|------|
| **L** | **L**ow byte（低 8 位） | AL, BL, CL, DL, SIL, R8B | 8 位 |
| **H** | **H**igh byte（AX 的高 8 位） | AH, BH, CH, DH（仅传统 4 个有） | 8 位 |
| **X** | e**X**tended（16 位，相对于 8 位的扩展） | AX, BX, CX, DX | 16 位 |
| **D** | **D**oubleword（32 位） | R8D, R9D, ..., R15D | 32 位 |
| **W** | **W**ord（16 位） | R8W, R9W, ..., R15W | 16 位 |
| **B** | **B**yte（8 位） | R8B, R9B, ..., R15B | 8 位 |

### 3.5 R8~R15 为什么是纯数字

因为到了 AMD64 时代，8 个经典寄存器的"有意义名字"已经用完了（ABCD + SI/DI/BP/SP），AMD 就直接用编号 R8~R15。它们没有特殊的历史含义，就是"第 8 号 ~ 第 15 号寄存器"。

### 3.6 System V ABI 参数传递的记忆口诀

```
参数顺序：RDI, RSI, RDX, RCX, R8, R9
记忆：     D    S    D    C    8   9

口诀：Diane's Silk Dress Cost $89
      Di     Si   Dx   Cx  8  9
```

> 这个口诀在国外汇编学习社区很流行。你也可以简单记成：**前两个是 DI/SI（目标/源），然后是 DX/CX（数据/计数），最后两个是 R8/R9（新增的）**。

---

## 四、AMD64 CPU 指令大全

> 按功能分类。每条指令标注常用程度：★★★ 常用（阅读汇编经常遇到）、★★ 较常用、★ 不常见（了解即可）。
> 所有示例均使用 Intel 语法。

### 4.1 数据传输指令

| 指令 | 常用度 | 格式 | 说明 | 示例 |
|------|-------|------|------|------|
| **MOV** | ★★★ | `mov dst, src` | 将 src 的值复制到 dst。最基本的数据传输指令 | `mov rax, rbx` — rax = rbx |
| **LEA** | ★★★ | `lea dst, [addr]` | 将地址表达式的**地址本身**（而非地址处的值）加载到 dst | `lea rax, [rbp-8]` — rax = rbp-8 |
| **PUSH** | ★★★ | `push src` | 将 src 压入栈：rsp -= 8，然后 [rsp] = src | `push rbp` |
| **POP** | ★★★ | `pop dst` | 从栈顶弹出到 dst：dst = [rsp]，然后 rsp += 8 | `pop rbp` |
| **XCHG** | ★★ | `xchg a, b` | 交换 a 和 b 的值 | `xchg rax, rbx` |
| **MOVZX** | ★★★ | `movzx dst, src` | **零扩展**传送：将较小的 src 扩展为较大的 dst，高位填 0 | `movzx eax, al` — 将 8 位扩展为 32 位 |
| **MOVSX** | ★★★ | `movsx dst, src` | **符号扩展**传送：将较小的 src 扩展为较大的 dst，高位填符号位 | `movsx rax, eax` — 将 32 位扩展为 64 位 |
| **MOVSXD** | ★★ | `movsxd dst, src` | 专门用于将 32 位**有符号**值符号扩展到 64 位 | `movsxd rax, edx` |
| **CMOVcc** | ★★ | `cmovcc dst, src` | 条件传送：根据标志位决定是否执行 mov。cc 与 Jcc 相同 | `cmove rax, rbx` — 若 ZF=1，rax=rbx |
| **CDQ** | ★★ | `cdq` | 将 EAX 的符号位扩展到 EDX:EAX（用于 `idiv` 之前） | `cdq` — 32 位有符号除法准备 |
| **CQO** | ★★ | `cqo` | 将 RAX 的符号位扩展到 RDX:RAX（用于 64 位 `idiv` 之前） | `cqo` |
| **CBW/CWDE/CDQE** | ★ | `cbw`/`cwde`/`cdqe` | 在 AX/EAX/RAX 内部做符号扩展 | `cdqe` — EAX 符号扩展到 RAX |
| **BSWAP** | ★ | `bswap reg` | 字节序反转（大端/小端转换） | `bswap eax` — 反转 EAX 中 4 个字节的顺序 |

### 4.2 算术运算指令

| 指令 | 常用度 | 格式 | 说明 | 示例 |
|------|-------|------|------|------|
| **ADD** | ★★★ | `add dst, src` | dst = dst + src，设置标志位 | `add rax, 8` |
| **SUB** | ★★★ | `sub dst, src` | dst = dst - src，设置标志位 | `sub rsp, 32` |
| **INC** | ★★ | `inc dst` | dst = dst + 1（不影响 CF） | `inc ecx` |
| **DEC** | ★★ | `dec dst` | dst = dst - 1（不影响 CF） | `dec ecx` |
| **NEG** | ★★ | `neg dst` | dst = -dst（取补码/取反） | `neg eax` |
| **CMP** | ★★★ | `cmp a, b` | 计算 a - b，**只设置标志位，不存结果**。用于后续的 Jcc 判断 | `cmp eax, 0` |
| **IMUL** | ★★★ | `imul dst, src` | 有符号乘法。两操作数形式：dst = dst * src | `imul eax, ebx` |
| | | `imul dst, src, imm` | 三操作数形式：dst = src * imm | `imul eax, ebx, 4` |
| **MUL** | ★★ | `mul src` | 无符号乘法。隐含使用 RAX：RDX:RAX = RAX * src | `mul rbx` |
| **IDIV** | ★★ | `idiv src` | 有符号除法。RDX:RAX / src → 商在 RAX，余数在 RDX | `idiv ecx` |
| **DIV** | ★★ | `div src` | 无符号除法。同 IDIV 但无符号 | `div ecx` |
| **ADC** | ★ | `adc dst, src` | 带进位加法：dst = dst + src + CF | `adc rax, rbx` |
| **SBB** | ★ | `sbb dst, src` | 带借位减法：dst = dst - src - CF | `sbb rax, rbx` |

### 4.3 逻辑运算指令

| 指令 | 常用度 | 格式 | 说明 | 示例 |
|------|-------|------|------|------|
| **AND** | ★★★ | `and dst, src` | dst = dst & src（按位与），设置标志位 | `and eax, 0xFF` — 取低 8 位 |
| **OR** | ★★★ | `or dst, src` | dst = dst \| src（按位或），设置标志位 | `or eax, 1` — 设置最低位 |
| **XOR** | ★★★ | `xor dst, src` | dst = dst ^ src（按位异或），设置标志位 | `xor eax, eax` — 清零（高效写法） |
| **NOT** | ★★ | `not dst` | dst = ~dst（按位取反），**不影响标志位** | `not eax` |
| **TEST** | ★★★ | `test a, b` | 计算 a & b，**只设置标志位，不存结果**。常用于判断是否为 0 | `test al, al` — 判断 al 是否为 0 |

### 4.4 移位与旋转指令

| 指令 | 常用度 | 格式 | 说明 | 示例 |
|------|-------|------|------|------|
| **SHL** | ★★★ | `shl dst, count` | 逻辑左移。高位移出丢弃，低位补 0。等价于乘以 2^count | `shl eax, 2` — eax *= 4 |
| **SHR** | ★★★ | `shr dst, count` | 逻辑右移。低位移出丢弃，高位补 0。等价于无符号除以 2^count | `shr eax, 1` — eax /= 2（无符号） |
| **SAL** | ★★ | `sal dst, count` | 算术左移。与 SHL 完全相同（机器码也一样） | `sal eax, 3` |
| **SAR** | ★★★ | `sar dst, count` | 算术右移。低位移出丢弃，高位补**符号位**。有符号除以 2^count | `sar eax, 1` — eax /= 2（有符号） |
| **ROL** | ★ | `rol dst, count` | 循环左移。移出的位从另一端进入 | `rol eax, 4` |
| **ROR** | ★ | `ror dst, count` | 循环右移 | `ror eax, 4` |
| **RCL** | ★ | `rcl dst, count` | 带进位循环左移（CF 参与） | `rcl eax, 1` |
| **RCR** | ★ | `rcr dst, count` | 带进位循环右移 | `rcr eax, 1` |

### 4.5 控制流指令

| 指令 | 常用度 | 格式 | 说明 | 示例 |
|------|-------|------|------|------|
| **JMP** | ★★★ | `jmp label` | 无条件跳转到 label 地址 | `jmp .L8` |
| **Jcc** | ★★★ | `jcc label` | 条件跳转。cc 是条件码，参见标志位章节的条件跳转表 | `je .L8` — 若相等（ZF=1）则跳转 |
| **CALL** | ★★★ | `call label` | 函数调用：push 返回地址，然后 jmp 到 label | `call _Z12do_somethingv` |
| **RET** | ★★★ | `ret` | 函数返回：pop 返回地址到 RIP | `ret` |
| **NOP** | ★★★ | `nop` | 空操作，什么都不做。用于对齐或占位 | `nop` |
| **LOOP** | ★ | `loop label` | ECX -= 1，若 ECX ≠ 0 则跳转到 label。现代代码很少使用 | `loop .L1` |
| **INT** | ★ | `int n` | 触发软中断。`int 3` 是调试断点，`int 0x80` 是旧式 Linux 系统调用 | `int 3` — 断点 |
| **SYSCALL** | ★★ | `syscall` | x86_64 Linux 的系统调用指令（替代旧的 `int 0x80`） | `syscall` |
| **ENDBR64** | ★★ | `endbr64` | Intel CET 安全特性，标记合法的间接跳转目标。可忽略 | `endbr64` |
| **UD2** | ★ | `ud2` | 未定义指令，强制触发异常。编译器用于标记"不可达代码" | `ud2` |

### 4.6 栈操作指令

| 指令 | 常用度 | 格式 | 说明 | 示例 |
|------|-------|------|------|------|
| **PUSH** | ★★★ | `push src` | 压栈：RSP -= 8，[RSP] = src | `push rbp` |
| **POP** | ★★★ | `pop dst` | 弹栈：dst = [RSP]，RSP += 8 | `pop rbp` |
| **ENTER** | ★ | `enter size, level` | 建立栈帧（等价于 push rbp + mov rbp,rsp + sub rsp,size）。很少使用，太慢 | `enter 32, 0` |
| **LEAVE** | ★★★ | `leave` | 撤销栈帧：mov rsp, rbp; pop rbp。函数尾声常见 | `leave` |

### 4.7 字符串 / 内存块操作指令

这些指令操作的是 RSI（源）和 RDI（目标）指向的内存，每次操作后自动递增/递减指针（由 DF 标志位控制方向）。通常配合 `REP` 前缀使用。

| 指令 | 常用度 | 说明 |
|------|-------|------|
| **MOVS** / **MOVSB/W/D/Q** | ★★ | 内存复制：[RDI] = [RSI]，然后 RSI/RDI 自动递增 |
| **CMPS** / **CMPSB/W/D/Q** | ★ | 内存比较：比较 [RSI] 和 [RDI]，设置标志位 |
| **SCAS** / **SCASB/W/D/Q** | ★ | 扫描：比较 AL/AX/EAX/RAX 和 [RDI] |
| **STOS** / **STOSB/W/D/Q** | ★★ | 存储填充：[RDI] = AL/AX/EAX/RAX，RDI 自动递增。`rep stosb` 相当于 `memset` |
| **LODS** / **LODSB/W/D/Q** | ★ | 加载：AL/AX/EAX/RAX = [RSI]，RSI 自动递增 |

#### REP 前缀

| 前缀 | 常用度 | 说明 |
|------|-------|------|
| **REP** | ★★ | 重复执行后面的指令 RCX 次。常见：`rep movsb`（memcpy）、`rep stosb`（memset） |
| **REPE** / **REPZ** | ★ | 重复执行，直到 RCX=0 或 ZF=0 |
| **REPNE** / **REPNZ** | ★ | 重复执行，直到 RCX=0 或 ZF=1 |

### 4.8 标志位操作指令

| 指令 | 常用度 | 说明 |
|------|-------|------|
| **CLC** | ★ | 清除进位标志：CF = 0 |
| **STC** | ★ | 设置进位标志：CF = 1 |
| **CMC** | ★ | 取反进位标志：CF = !CF |
| **CLD** | ★★ | 清除方向标志：DF = 0（字符串操作向前） |
| **STD** | ★ | 设置方向标志：DF = 1（字符串操作向后） |
| **CLI** | ★ | 禁止中断：IF = 0（仅内核态） |
| **STI** | ★ | 允许中断：IF = 1（仅内核态） |
| **LAHF** | ★ | 将标志位低 8 位加载到 AH |
| **SAHF** | ★ | 将 AH 存储到标志位低 8 位 |

### 4.9 位操作指令

| 指令 | 常用度 | 格式 | 说明 |
|------|-------|------|------|
| **BT** | ★ | `bt src, n` | 测试 src 的第 n 位，结果放入 CF |
| **BTS** | ★ | `bts dst, n` | 测试并设置第 n 位（置 1） |
| **BTR** | ★ | `btr dst, n` | 测试并清除第 n 位（置 0） |
| **BTC** | ★ | `btc dst, n` | 测试并取反第 n 位 |
| **BSF** | ★ | `bsf dst, src` | 从低位到高位扫描第一个为 1 的位（Bit Scan Forward） |
| **BSR** | ★ | `bsr dst, src` | 从高位到低位扫描第一个为 1 的位（Bit Scan Reverse） |
| **POPCNT** | ★★ | `popcnt dst, src` | 统计 src 中 1 的个数（Population Count） |
| **LZCNT** | ★ | `lzcnt dst, src` | 统计前导零个数（Leading Zero Count） |
| **TZCNT** | ★ | `tzcnt dst, src` | 统计末尾零个数（Trailing Zero Count） |

### 4.10 条件设置指令（SETcc）

根据标志位设置一个字节为 0 或 1。cc 条件与 Jcc 完全相同。

| 指令 | 常用度 | 说明 | 示例 |
|------|-------|------|------|
| **SETcc** | ★★★ | 如果条件 cc 满足，dst = 1；否则 dst = 0 | `sete al` — 若 ZF=1，al=1；否则 al=0 |

常见变体：`sete`/`setne`/`setg`/`setge`/`setl`/`setle`/`seta`/`setb` 等，与 Jcc 一一对应。

### 4.11 浮点 / SIMD 指令（SSE/AVX 常用子集）

> SSE/AVX 指令非常多（上千条），这里只列出最常见的标量浮点操作。

#### 标量浮点运算（单个 float/double）

| 指令 | 常用度 | 说明 |
|------|-------|------|
| **MOVSS** | ★★★ | 传送单精度浮点数（32 位） |
| **MOVSD** | ★★★ | 传送双精度浮点数（64 位） |
| **ADDSS** / **ADDSD** | ★★★ | 单精度 / 双精度加法 |
| **SUBSS** / **SUBSD** | ★★★ | 单精度 / 双精度减法 |
| **MULSS** / **MULSD** | ★★★ | 单精度 / 双精度乘法 |
| **DIVSS** / **DIVSD** | ★★★ | 单精度 / 双精度除法 |
| **SQRTSS** / **SQRTSD** | ★★ | 平方根 |
| **UCOMISS** / **UCOMISD** | ★★★ | 浮点比较，设置标志位（类似整数的 CMP） |
| **CVTSI2SS** | ★★ | 整数转单精度浮点 |
| **CVTSI2SD** | ★★ | 整数转双精度浮点 |
| **CVTSS2SD** | ★★ | 单精度转双精度 |
| **CVTSD2SS** | ★★ | 双精度转单精度 |
| **CVTTSS2SI** | ★★ | 单精度转整数（截断） |
| **CVTTSD2SI** | ★★ | 双精度转整数（截断） |

> 指令命名规则：`SS` = Scalar Single（标量单精度），`SD` = Scalar Double（标量双精度），`PS` = Packed Single（打包单精度，SIMD），`PD` = Packed Double（打包双精度，SIMD）。

#### 打包 SIMD 运算（了解即可）

| 指令 | 说明 |
|------|------|
| **MOVAPS** / **MOVAPD** | 传送对齐的打包浮点（128 位） |
| **MOVUPS** / **MOVUPD** | 传送未对齐的打包浮点（128 位） |
| **ADDPS** / **ADDPD** | 同时对 4 个 float / 2 个 double 做加法 |
| **PADDD** / **PADDQ** | 打包整数加法（4×32位 / 2×64位） |
| **PXOR** | 128 位异或（常用于清零 XMM 寄存器：`pxor xmm0, xmm0`） |

### 4.12 系统指令

| 指令 | 常用度 | 说明 |
|------|-------|------|
| **CPUID** | ★ | 查询 CPU 功能信息。输入 EAX 功能号，输出到 EAX/EBX/ECX/EDX |
| **RDTSC** | ★ | 读取时间戳计数器（Time Stamp Counter），结果在 EDX:EAX |
| **RDTSCP** | ★ | 同 RDTSC，但序列化（更精确） |
| **PAUSE** | ★★ | 自旋锁等待提示。告诉 CPU "我在忙等"，降低功耗和资源争用 |
| **HLT** | ★ | 停止 CPU 执行，等待中断。仅内核态使用 |
| **ENDBR64** | ★★ | CET 间接跳转目标标记（安全特性），可忽略 |

### 4.13 内存屏障与原子操作

| 指令 | 常用度 | 说明 |
|------|-------|------|
| **LOCK** 前缀 | ★★ | 加在指令前面，保证该指令原子执行。如 `lock add [rax], 1` |
| **MFENCE** | ★★ | 全内存屏障：保证屏障之前的所有读写操作在屏障之后可见 |
| **LFENCE** | ★ | 加载屏障：保证之前的读操作完成 |
| **SFENCE** | ★ | 存储屏障：保证之前的写操作完成 |
| **XADD** | ★ | 原子交换并加法：`lock xadd [mem], reg` — 原子地 tmp=*mem; *mem=tmp+reg; reg=tmp |
| **CMPXCHG** | ★★ | 比较并交换（CAS）：`lock cmpxchg [mem], reg` — 若 *mem == RAX，则 *mem = reg；否则 RAX = *mem |
| **CMPXCHG8B/16B** | ★ | 8 字节 / 16 字节的 CAS 操作 |

---

## 五、补充内容

### 5.1 函数调用约定（System V AMD64 ABI）

#### 参数传递

| 参数序号 | 整数/指针参数 | 浮点参数 |
|---------|-------------|---------|
| 第 1 个 | **RDI** | XMM0 |
| 第 2 个 | **RSI** | XMM1 |
| 第 3 个 | **RDX** | XMM2 |
| 第 4 个 | **RCX** | XMM3 |
| 第 5 个 | **R8** | XMM4 |
| 第 6 个 | **R9** | XMM5 |
| 第 7 个 | XMM6 | XMM6 |
| 第 8 个 | XMM7 | XMM7 |
| 更多 | **栈传递**（从右到左压栈） | **栈传递** |

> C++ 成员函数有一个隐含的 `this` 指针，作为**第 1 个参数**放在 RDI 中。

#### 返回值

| 类型 | 寄存器 |
|------|-------|
| 整数/指针 | **RAX**（如果超过 64 位，高 64 位在 RDX） |
| 浮点 | **XMM0** |

#### 寄存器保存责任

| 类别 | 寄存器 | 含义 |
|------|-------|------|
| **调用者保存**（Caller-saved / Volatile） | RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11 | 函数调用可能破坏这些寄存器。如果调用者还需要其中的值，必须在 `call` 前自己保存到栈上 |
| **被调用者保存**（Callee-saved / Non-volatile） | **RBX, RBP, R12, R13, R14, R15** | 被调用函数如果要使用这些寄存器，必须先 `push` 保存，函数返回前 `pop` 恢复 |
| **栈指针** | RSP | 特殊——由 `call`/`ret`/`push`/`pop` 隐式修改，函数返回时必须恢复到调用前的值 |

#### 栈对齐要求

在执行 `call` 指令**之前**，RSP 必须是 **16 字节对齐**的。`call` 指令本身会压入 8 字节返回地址，所以进入被调用函数时 RSP 是 16n+8 对齐的。函数序言中的 `push rbp`（又减 8 字节）恢复了 16 字节对齐。

### 5.2 内存寻址模式

x86_64 支持丰富的内存寻址模式，通用公式为：

```
[base + index * scale + displacement]

其中：
- base:         任意通用寄存器（可选）
- index:        除 RSP 外的任意通用寄存器（可选）
- scale:        1、2、4 或 8（与 index 配合，可选）
- displacement: 8 位或 32 位立即数（可选）
```

#### 各寻址模式示例

| 寻址模式 | Intel 语法示例 | 含义 |
|---------|---------------|------|
| 立即数（Immediate） | `mov eax, 42` | 操作数就是常数 42 |
| 寄存器（Register） | `mov eax, ebx` | 操作数在寄存器中 |
| 直接寻址（Direct） | `mov eax, [0x601040]` | 从固定内存地址读取 |
| 寄存器间接（Register Indirect） | `mov eax, [rbx]` | 从 rbx 指向的地址读取 |
| 基址 + 偏移（Base + Displacement） | `mov eax, [rbp-8]` | 从 rbp-8 地址读取。**最常见**，用于访问局部变量 |
| 基址 + 变址（Base + Index） | `mov eax, [rbx+rcx]` | 从 rbx+rcx 地址读取 |
| 基址 + 变址 × 比例因子 + 偏移（SIB） | `mov eax, [rbx+rcx*4+8]` | 从 rbx + rcx×4 + 8 读取。典型用于数组访问：`array[i]` |
| RIP 相对寻址 | `mov eax, [rip+0x200abc]` | 相对于当前指令地址的偏移。用于访问全局变量和常量。x86_64 新增 |

#### SIB 寻址的典型场景

```c
int arr[100];
int x = arr[i];  // i 在 rcx 中
```

对应汇编：

```asm
mov  eax, DWORD PTR [rbx+rcx*4]
;    rbx = arr 的基地址
;    rcx = 下标 i
;    *4  = sizeof(int)，每个元素 4 字节
;    结果：读取 arr + i*4 处的 4 字节
```

### 5.3 数据大小限定符

当汇编指令中有内存操作数时，CPU 需要知道读写多少字节。使用 `PTR` 限定符指定：

| 限定符 | 全称 | 大小 | 等价 C 类型 | 示例 |
|--------|------|------|-----------|------|
| **BYTE PTR** | Byte Pointer | 1 字节（8 位） | `char` / `int8_t` | `mov BYTE PTR [rbp-1], 0` |
| **WORD PTR** | Word Pointer | 2 字节（16 位） | `short` / `int16_t` | `mov WORD PTR [rbp-2], 0` |
| **DWORD PTR** | Double Word Pointer | 4 字节（32 位） | `int` / `int32_t` / `float` | `mov DWORD PTR [rbp-4], 42` |
| **QWORD PTR** | Quad Word Pointer | 8 字节（64 位） | `long` / `int64_t` / `double` / 指针 | `mov QWORD PTR [rbp-8], rax` |
| **XMMWORD PTR** | XMM Word | 16 字节（128 位） | SSE 向量 | `movaps XMMWORD PTR [rsp], xmm0` |
| **YMMWORD PTR** | YMM Word | 32 字节（256 位） | AVX 向量 | `vmovaps YMMWORD PTR [rsp], ymm0` |

> 为什么叫 "Word" 是 2 字节？因为 Intel 在 8086 时代定义了 Word = 16 位（当时 CPU 是 16 位的），后面 Double Word = 32 位，Quad Word = 64 位，一直沿用至今。

> 当两个操作数中有一个是寄存器时，CPU 可以根据寄存器大小推断，此时 PTR 限定符可以省略。例如 `mov eax, [rbp-4]` 不需要写 `DWORD PTR`，因为 `eax` 本身就是 32 位的。

### 5.4 函数序言与尾声模板

几乎每个函数的汇编代码都以标准的序言（Prologue）开始，以标准的尾声（Epilogue）结束。阅读汇编时可以快速跳过这些固定模式，直接看中间的核心逻辑。

#### 序言（Prologue）

```asm
endbr64                    ; CET 安全标记（可忽略）
push   rbp                 ; 保存调用者的栈帧基址
mov    rbp, rsp             ; 建立当前函数的栈帧锚点
sub    rsp, N               ; 为局部变量分配 N 字节栈空间

; [可选] 栈保护（Stack Canary）
mov    rax, QWORD PTR fs:40 ; 读取 canary 随机值
mov    QWORD PTR [rbp-8], rax ; 存到栈上作为警戒
xor    eax, eax             ; 清除寄存器中的 canary 残留

; [可选] 保存被调用者保存寄存器
push   rbx                  ; 如果函数要用 rbx，先保存
push   r12                  ; 如果函数要用 r12，先保存
```

#### 尾声（Epilogue）

```asm
; [可选] 恢复被调用者保存寄存器
pop    r12
pop    rbx

; [可选] 栈保护检查
mov    rdx, QWORD PTR [rbp-8]  ; 读回 canary
sub    rdx, QWORD PTR fs:40    ; 与原始值比较
je     .Lok                    ; 相等 → 安全
call   __stack_chk_fail@PLT    ; 不相等 → 栈被破坏，终止
.Lok:

; 恢复栈帧
leave                       ; 等价于 mov rsp, rbp; pop rbp
ret                         ; 返回调用者
```

#### 函数序言做的三件事（一句话总结）

```
push rbp       → 备份调用者的栈帧锚点
mov rbp, rsp   → 建立自己的栈帧锚点
sub rsp, N     → 在栈上为局部变量分配空间
```

### 5.5 C++ Name Mangling 规则

C++ 编译器会将函数名"编码"（mangling）为一个包含类名、参数类型等信息的字符串，以支持函数重载。

#### 编码规则（GCC / Itanium ABI）

```
_Z  <名称长度> <函数名>  <参数类型编码>

例：_Z15scenario_rvaluev
    _Z          → C++ mangled name 前缀
    15          → 函数名长度 15 个字符
    scenario_rvalue → 函数名
    v           → void（无参数）

例：_ZN6StatusC1Ei
    _Z          → C++ mangled name 前缀
    N           → 嵌套名称开始（Nested）
    6Status     → 类名 "Status"（长度6）
    C1          → 构造函数（C1 = complete constructor）
    E           → 嵌套名称结束
    i           → int 参数
```

#### 常见类型编码

| 编码 | C++ 类型 |
|------|---------|
| `v` | void |
| `b` | bool |
| `c` | char |
| `i` | int |
| `l` | long |
| `x` | long long |
| `f` | float |
| `d` | double |
| `P` | 指针（后跟指向的类型） |
| `R` | 引用（后跟引用的类型） |
| `K` | const |

#### 还原 Mangled 名称

使用 `c++filt` 命令：

```bash
$ echo "_ZN6StatusC1Ei" | c++filt
Status::Status(int)

$ echo "_ZNK6Status2okEv" | c++filt
Status::ok() const
```

### 5.6 常用 GCC 汇编生成命令

#### 生成汇编代码

```bash
# 生成 Intel 语法汇编（推荐），无优化（看最真实的逻辑）
g++ -S -masm=intel -O0 file.cpp -o file.s

# 生成 Intel 语法汇编，O2 优化（看编译器实际会怎么做）
g++ -S -masm=intel -O2 file.cpp -o file.s

# 生成 AT&T 语法汇编（GCC 默认）
g++ -S -O0 file.cpp -o file.s
```

#### 反汇编已编译的程序

```bash
# 反汇编，Intel 语法
objdump -d -M intel a.out

# 反汇编，只看某个函数（配合 grep）
objdump -d -M intel a.out | grep -A 30 "<_Z12do_somethingv>:"

# 反汇编，显示源代码交错（需要 -g 编译）
objdump -d -M intel -S a.out
```

#### 还原 Mangled 名称

```bash
# 单个名称
echo "_ZN6StatusC1Ei" | c++filt

# 对 objdump 输出整体还原
objdump -d -M intel a.out | c++filt

# 直接用 objdump 的 -C 选项
objdump -d -M intel -C a.out
```

#### 查看预处理后的宏展开

```bash
# 只做预处理，不编译（看宏展开后的代码）
g++ -E file.cpp -o file.i
```
