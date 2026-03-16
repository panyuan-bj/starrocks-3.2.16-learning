#!/usr/bin/env bash
#
# 自动扫描 learning/ 目录结构并生成 README.md
# 用法: cd learning/ && bash generate_readme.sh
#       或: bash docs/zh/learning/generate_readme.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
README="$SCRIPT_DIR/README.md"

# ── 生成目录树（排除 README.md 和本脚本自身）──
generate_tree() {
    local base="$SCRIPT_DIR"
    local prefix="${1:-}"

    local entries=()
    while IFS= read -r entry; do
        entries+=("$entry")
    done < <(ls -1 "$base/$prefix" 2>/dev/null | sort)

    local count=${#entries[@]}
    local i=0

    for entry in "${entries[@]}"; do
        i=$((i + 1))
        local rel_path="${prefix:+$prefix/}$entry"
        local full_path="$base/$rel_path"

        # 跳过 README.md 和脚本自身
        [[ "$entry" == "README.md" ]] && continue
        [[ "$entry" == "generate_readme.sh" ]] && continue

        local connector="├──"
        [[ $i -eq $count ]] && connector="└──"

        if [[ -d "$full_path" ]]; then
            echo "${prefix:+│   }$connector $entry/"
        else
            local title=""
            # 尝试从 .md 文件中提取第一个 # 标题
            if [[ "$entry" == *.md ]]; then
                title=$(grep -m1 '^#\s' "$full_path" 2>/dev/null | sed 's/^#\+\s*//' || true)
            fi
            if [[ -n "$title" ]]; then
                echo "${prefix:+│   }$connector $entry  — $title"
            else
                echo "${prefix:+│   }$connector $entry"
            fi
        fi
    done
}

# ── 递归生成完整树 ──
generate_full_tree() {
    local base="$SCRIPT_DIR"
    local indent="$1"
    local dir="$2"

    local entries=()
    while IFS= read -r entry; do
        entries+=("$entry")
    done < <(ls -1 "$base/$dir" 2>/dev/null | sort)

    local total=${#entries[@]}
    local idx=0

    for entry in "${entries[@]}"; do
        idx=$((idx + 1))
        local rel="${dir:+$dir/}$entry"
        local full="$base/$rel"

        [[ "$entry" == "README.md" && "$dir" == "" ]] && continue
        [[ "$entry" == "generate_readme.sh" ]] && continue

        local is_last=false
        [[ $idx -eq $total ]] && is_last=true

        local branch="├── "
        local sub_indent="${indent}│   "
        if $is_last; then
            branch="└── "
            sub_indent="${indent}    "
        fi

        if [[ -d "$full" ]]; then
            echo "${indent}${branch}${entry}/"
            generate_full_tree "$sub_indent" "$rel"
        else
            local title=""
            if [[ "$entry" == *.md ]]; then
                title=$(grep -m1 '^#\s' "$full" 2>/dev/null | sed 's/^#\+\s*//' || true)
            fi
            if [[ -n "$title" ]]; then
                echo "${indent}${branch}${entry}"
            else
                echo "${indent}${branch}${entry}"
            fi
        fi
    done
}

# ── 生成文件列表表格 ──
generate_file_table() {
    local base="$SCRIPT_DIR"

    while IFS= read -r -d '' file; do
        local rel="${file#$base/}"

        [[ "$rel" == "README.md" ]] && continue
        [[ "$rel" == "generate_readme.sh" ]] && continue

        local title=""
        if [[ "$file" == *.md ]]; then
            title=$(grep -m1 '^#\s' "$file" 2>/dev/null | sed 's/^#\+\s*//' || true)
        fi
        [[ -z "$title" ]] && title="（无标题）"

        echo "| \`$rel\` | $title |"
    done < <(find "$base" -type f -name '*.md' ! -name 'README.md' -print0 | sort -z)
}

# ── 统计信息 ──
total_files=$(find "$SCRIPT_DIR" -type f -name '*.md' ! -name 'README.md' | wc -l)
total_dirs=$(find "$SCRIPT_DIR" -type d ! -path "$SCRIPT_DIR" | wc -l)

# ── 写入 README.md ──
cat > "$README" << 'HEADER'
# StarRocks 源码学习笔记

## 一、本目录的目的

`learning/` 目录是我在深入学习 [StarRocks](https://github.com/StarRocks/starrocks) 源码过程中，逐步积累的个人学习笔记与分析文档。

StarRocks 是一款高性能、实时的分析型数据库，其底层 BE（Backend）由 C++ 编写，代码量庞大、模块众多、架构精巧。对于习惯了 Java 生态的工程师来说，直接阅读 C++ 源码往往面临语言壁垒、构建体系差异、模块划分不明等多重挑战。因此，我在阅读过程中将自己的理解、踩过的坑、模块间的关联关系等整理成文档，希望达到以下几个目的：

- **降低入门门槛**：以 Java 工程师的视角，用类比的方式解释 C++ 代码中的概念，让更多后端工程师能快速建立对 StarRocks 源码的全局认知。
- **建立知识地图**：将庞大的代码库按层次进行梳理，从基础设施、工具服务、存储引擎、查询执行到表达式求值，形成一张系统性的「源码导览图」。
- **记录实践经验**：包括如何在不同环境下（Docker、WSL2）编译、启动、调试 StarRocks，减少重复踩坑的时间成本。
- **沉淀学习成果**：将碎片化的阅读过程转化为结构化的文档，方便日后回顾，也便于和社区同学交流讨论。

---

## 二、目录结构

HEADER

# 写入树
echo '```' >> "$README"
echo 'learning/' >> "$README"
echo "├── README.md" >> "$README"
generate_full_tree "" "" >> "$README"
echo '```' >> "$README"

# 写入文件表格
cat >> "$README" << 'TABLE_HEADER'

### 各文件简介

| 文件路径 | 标题/简介 |
|----------|-----------|
TABLE_HEADER

generate_file_table >> "$README"

# 写入统计与鼓励
cat >> "$README" << FOOTER

> 共 **$total_dirs** 个子目录，**$total_files** 篇文档。

---

## 三、共勉

源码阅读从来不是一件轻松的事——面对数十万行代码、陌生的语言和复杂的架构，迷茫和挫败感在所难免。但请记住：**每一次深入理解一个函数、一段逻辑、一条数据流转路径，都是在为自己的技术功底添砖加瓦。**

> **有志者，事竟成。**
>
> 不积跬步，无以至千里。坚持下去，你终将拥有看透系统全貌的能力。

---

*本文件由 \`generate_readme.sh\` 脚本自动生成于 $(date '+%Y-%m-%d %H:%M:%S')，当 \`learning/\` 目录结构发生变化时，请重新执行：*

\`\`\`bash
bash docs/zh/learning/generate_readme.sh
\`\`\`
FOOTER

echo "✅ README.md 已生成：$README"
echo "   共扫描 $total_dirs 个目录，$total_files 篇文档。"
