about-alias 'profile config'
alias zc='z -c'      # 严格匹配当前路径的子路径
alias zz='z -i'      # 使用交互式选择模式
alias zf='z -I'      # 使用 fzf 对多个结果进行选择
alias zb='z -b'      # 快速回到父目录

alias cp='cp -i'
alias d='cd /home'


tail() {
  if [ -t 1 ]; then
    command tail "$@" | sed \
      -e "s/\b\(ERROR\|FAIL\|FATAL\|CRITICAL\|FAILURE\)\b/\x1b[1;31m&\x1b[0m/g" \
      -e "s/\b\(WARN\|WARNING\|ISSUE\|RETRY\)\b/\x1b[1;33m&\x1b[0m/g" \
      -e "s/\b\(INFO\|NOTICE\|SUCCESS\|OK\|DONE\|PASS\)\b/\x1b[32m&\x1b[0m/g" \
      -e "s/\b\(DEBUG\|TRACE\|VERBOSE\)\b/\x1b[34m&\x1b[0m/g" \
      -e "s/\[[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\]/\x1b[90m&\x1b[0m/g" \
      -e "s/0x[0-9a-fA-F]\{6,8\}/\x1b[36m&\x1b[0m/g" \
      -e "s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\(:[0-9]\{1,5\}\)\?/\x1b[35m&\x1b[0m/g" \
      -e "s/\b\(GET\|POST\|PUT\|DELETE\|PATCH\|HEAD\)\b/\x1b[1;34m&\x1b[0m/g" \
      -e "s|\"\(/[^\"]*\)\"|\"\x1b[32m\1\x1b[0m\"|g" \
      -e "s/\b\(password\|secret\|token\|key\)=\([^ ]*\)/\1=\x1b[41m***\x1b[0m/g"
  else
    command tail "$@"
  fi
}

# 将 Ctrl-N 映射为 <Ctrl + w> <Shift + N>

alias bd='bashdb --debug'

l_tree() {
	lsd -lh --date +%Y年%m月%d"日"%H:%M:%S $1
}
alias l=l_tree
alias lt='lsd --tree'
alias gitui='gitui -l'

alias cc='clear & clear'

make_jobs() {
    nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
}

make_timestamp() {
    date '+%F %T'
}

make_clean_logs() {
    {
        echo "Build started: $(make_timestamp)"
        echo "Working dir: $PWD"
        echo "Jobs: $(make_jobs)"
        echo
    } > out.log

    > err.log
}

make_print_cmd() {
    printf 'Command:'
    printf ' %q' "$@"
    printf '\n'
}

make_log_step_start() {
    local title="$1"
    shift

    {
        echo
        echo "===== $(make_timestamp) | $title ====="
        echo "Working dir: $PWD"
        make_print_cmd "$@"
    } >> out.log
}

make_log_step_end() {
    local title="$1"
    local status="$2"
    local duration="$3"

    {
        echo "Status: $status"
        echo "Duration: ${duration}s"
        echo "===== $(make_timestamp) | $title done ====="
    } >> out.log

    if [ "$status" -ne 0 ]; then
        {
            echo
            echo "===== $(make_timestamp) | $title failed ====="
            echo "Status: $status"
            echo "Duration: ${duration}s"
        } >> err.log
    fi
}

make_run_logged() {
    local title="$1"
    shift
    local start_time
    local end_time
    local status

    make_log_step_start "$title" "$@"
    start_time=$(date +%s)
    "$@" >> out.log 2>> err.log
    status=$?
    end_time=$(date +%s)
    make_log_step_end "$title" "$status" "$((end_time - start_time))"

    return "$status"
}

make_section() {
    echo "----------------------------------------"
    echo "$1"
}

make_show_summary() {
    local out_lines="${1:-10}"
    local err_lines="${2:-10}"

    echo "---------------"
    echo "Build Log Summary (Last ${out_lines} lines):"
    if [ -s out.log ]; then
        tail -n "$out_lines" out.log
    else
        echo "out.log is empty."
    fi
    echo "---------------"
    echo "Build Err Summary (Last ${err_lines} lines):"
    if [ -s err.log ]; then
        tail -n "$err_lines" err.log
    else
        echo "err.log is empty."
    fi
}

make_check_target() {
    local target="${1:-}"

    if [ -n "$target" ] && [ ! -e "$target" ]; then
        echo "Build target not found: $target"
        return 1
    fi
}

make_stop_process() {
    local process_name="${MAKE_STOP_PROCESS-emanager}"

    [ -n "$process_name" ] || return 0

    pkill "$process_name" 2>/dev/null
    sleep 1
    pkill -9 "$process_name" 2>/dev/null
}

make_run_post_install() {
    local script_path="${MAKE_POST_INSTALL_SCRIPT-$HOME/emanager-cron.sh}"

    [ -n "$script_path" ] || return 0
    [ -f "$script_path" ] || return 0

    make_run_logged "post install script" sh "$script_path"
}

make_install_step() {
    [ "${MAKE_SKIP_INSTALL:-0}" != "1" ] || return 0

    make_section "Install: make install"
    make_stop_process

    make_run_logged "make install" env MAKEFLAGS= make install
    if [ $? -ne 0 ]; then
        echo "Install failed! Check err.log for details."
        return 1
    fi

    make_run_post_install
}

mmake() {
    local build_args=("$@")

    [ ${#build_args[@]} -gt 0 ] || build_args=(mtype=debug)

    make_clean_logs
    make_section "1. Clean: make clean"
    make_run_logged "make clean" env MAKEFLAGS= make clean
    if [ $? -ne 0 ]; then
        echo "make clean failed! Check err.log."
        make_show_summary 10 15
        return 1
    fi

    make_section "2. Build: make ${build_args[*]} -j$(make_jobs)"
    make_run_logged "make build" env MAKEFLAGS= make "${build_args[@]}" -j"$(make_jobs)"
    if [ $? -ne 0 ]; then
        echo "3、Build failed! Check err.log for details."
        make_show_summary 10 15
        return 1
    fi

    if ! make_check_target "$MAKE_BUILD_TARGET"; then
        make_show_summary 10 15
        return 1
    fi

    make_section "3. Build completed"
    make_show_summary 10 10

    if ! make_install_step; then
        make_show_summary 10 15
        return 1
    fi

    echo "----------------------------------------"
    echo "5、Install completed. "
}
alias mm=mmake
bbmake() {
    local build_args=("$@")

    make_clean_logs

    make_section "1. Clean: make clean"
    make_run_logged "make clean" env MAKEFLAGS= make clean
    if [ $? -ne 0 ]; then
        echo "make clean failed! Check err.log."
        make_show_summary 10 15
        return 1
    fi

    make_section "2. Build with Bear: make ${build_args[*]} -j$(make_jobs)"
    local start_time=$(date +%s)

    make_run_logged "bear make build" env MAKEFLAGS= /usr/local/bin/bear -- make "${build_args[@]}" -j"$(make_jobs)"

    local build_status=$?

    if [ $build_status -ne 0 ]; then
        echo "2.1、Build failed!"
        echo "Note: err.log may contain Bear logs; search upward for the real compiler error."
        make_show_summary 10 15
        return 1
    fi

    if ! make_check_target "$MAKE_BUILD_TARGET"; then
        make_show_summary 10 15
        return 1
    fi

    local end_time=$(date +%s)
    make_section "3. Build completed in $((end_time - start_time)) seconds"
    make_show_summary 10 10

    if ! make_install_step; then
        make_show_summary 10 15
        return 1
    fi

    echo "----------------------------------------"
    echo "5、Install completed successfully!"
}
# 在你的 .bashrc 或 .zshrc 中修改别名定义
alias bb=bbmake

mimake(){
    local build_args=("$@")

    [ ${#build_args[@]} -gt 0 ] || build_args=(mtype=debug)

    make_clean_logs
    make_section "1. Build: make ${build_args[*]} -j$(make_jobs)"
    make_run_logged "make build" env MAKEFLAGS= make "${build_args[@]}" -j"$(make_jobs)"
    if [ $? -ne 0 ]; then
        echo "2、Build failed! Check err.log for details."
        make_show_summary 10 15
        return 1
    fi

    if ! make_check_target "$MAKE_BUILD_TARGET"; then
        make_show_summary 10 15
        return 1
    fi

    make_section "2. Build completed"
    make_show_summary 10 10

    if ! make_install_step; then
        make_show_summary 10 15
        return 1
    fi

    echo "----------------------------------------"
    echo "4、Install completed. "
}
alias mi=mimake

alias pg='ps aux |grep -i'

# tcpreplay -i lo -M 100 -K
alias tplay=treplay
    function treplay(){
        if [ -z "$1" ]; then
            echo "Usage: treplay <pcap-file>"
            return 1
        fi
        sudo tcpreplay -i lo -M 100 -K "$1"
    }

alias rf='find ./ -maxdepth 7 -type f -delete'
  # Useful unarchiver!
  function extract () {
	  if [ -f $1 ] ; then
		  case $1 in
			  *.tar.bz2)        tar xjf $1                ;;
			  *.tar.gz)        tar xzf $1                ;;
			  *.bz2)                bunzip2 $1                ;;
			  *.rar)                rar x $1                ;;
			  *.gz)                gunzip $1                ;;
			  *.tar)                tar xf $1                ;;
			  *.tbz2)                tar xjf $1                ;;
			  *.tgz)                tar xzf $1                ;;
			  *.zip)                unzip $1                ;;
			  *.Z)                uncompress $1        ;;
			  *)                        echo "'$1' cannot be extracted via extract()" ;;
		  esac
	  else
		  echo "'$1' is not a valid file"
	  fi
  }

alias sr=safe_rm
export TRASH_DIR=/tmp/.__trash
safe_rm () {
	local d t f s
	[ -z "$PS1" ] && (/bin/rm "$@"; return)
	d="${TRASH_DIR}/`date +%W`"
	t=`date +%F_%H-%M-%S`
	[ -e "$d" ] || mkdir -p "$d" || return
	for f do
		[ -e "$f" ] || continue
		s=`basename "$f"`
		/bin/mv "$f" "$d/${t}_$s" || break
	done
	echo -e "[$? $t `whoami` `pwd`]$@\n" >> "$d/00rmlog.txt"
}
# alias tail='tspin'
alias mans='tldr '
alias gp='grep -Rn --exclude="tags" --exclude="my.viminfo" --exclude="*.a" --exclude="*.o" --exclude="*.so"'
# alias gp='rg -n --glob="!tags" --glob="!my.viminfo" '
alias xml='xmllint --format '

gitu() {
	key="${1:-$HOME/.ssh/id_rsa}"
	eval "$(ssh-agent)" \
		&& ssh-add "$key" \
		&& gitui "${@:2}" \
		&& eval "$(ssh-agent -k)"
	}


alias gmt='git mergetool --no-prompt'
alias gmtv='git mergetool --no-prompt --tool=vimdiff'
alias gmtgv='git mergetool --no-prompt --tool=gvimdiff'
alias gmtmv='git mergetool --no-prompt --tool=mvimdiff'
alias gmtk='git mergetool -y --tool=Kaleidoscope'



function gsd-sync-mem() {
    local NMEM_BIN
    NMEM_BIN="$(type -P nmem 2>/dev/null)"
    local PLANNING_DIR=".planning/codebase"

    if [ ! -x "$NMEM_BIN" ]; then
        echo "❌ 未找到可执行的 nmem，请确认 Nowledge Mem CLI 已安装并在 PATH 中"
        return 1
    fi

    if [ ! -d "$PLANNING_DIR" ]; then
        echo "❌ 未发现 $PLANNING_DIR 目录，请先运行 gsd-map-codebase"
        return 1
    fi

    echo "🧠 正在将项目全量规划文档同步至 nmem 长期记忆..."

    for file in "$PLANNING_DIR"/*.md; do
        [ -e "$file" ] || continue
        local filename
        filename=$(basename "$file" .md)
        echo " -> 正在处理: $filename"
        "$NMEM_BIN" m add "项目架构文档 [$filename]: $(cat "$file")" --temp > /dev/null 2>&1
    done

    echo "✅ 同步完成！Codex 现在可以通过 nmem 检索到完整的项目上下文。"
}

function codex_smart() {
    local NMEM_BIN=""
    local CODEX_BIN=""
    local CYMBAL_BIN=""
    local SESSION_LOG="/tmp/codex_$(date +%s).log"
    local CYMBAL_INDEX_LOG="/tmp/codex_cymbal_index_$$.log"
    local START_TIME=$(date +%s)
    local CURRENT_DIR="${PWD##*/}"
    local SESSION_NOTE_DIR=".planning/codebase"
    local SESSION_NOTE_FILE=""
    local LAUNCH_DIR="$PWD"
    local ROOT_AGENTS_FILE="$PWD/AGENTS.md"
    local ROOT_AGENTS_BACKUP=""
    local GENERATED_ROOT_AGENTS=0

    export ELECTRON_DISABLE_SANDBOX=1
    export CODEX_DISABLE_SANDBOX=1
    export NO_SANDBOX=1
    export TMPDIR=/tmp
    export XDG_RUNTIME_DIR=/tmp
    export HOME=/root
    export PATH="/usr/local/bin:$PATH"

    mkdir -p "$SESSION_NOTE_DIR" 2>/dev/null

    NMEM_BIN="$(type -P nmem 2>/dev/null)"
    CODEX_BIN="$(type -P codex 2>/dev/null)"

    load_planning_knowledge() {
        local knowledge=""
        local file
        while IFS= read -r -d '' file; do
            local title
            title=$(basename "$file")
            knowledge+="### $title"$'\n'
            knowledge+='```text'$'\n'
            knowledge+="$(cat "$file")"$'\n'
            knowledge+='```'$'\n\n'
        done < <(find "$SESSION_NOTE_DIR" -maxdepth 1 -type f ! -name 'AGENTS.md' -print0 | sort -z)

        printf '%s' "$knowledge"
    }

    has_cymbal_source_files() {
        [ -n "$(find "$PWD" -maxdepth 3 -type f \( \
            -name '*.c' -o -name '*.cc' -o -name '*.cpp' -o -name '*.cxx' -o -name '*.h' -o -name '*.hpp' -o \
            -name '*.go' -o -name '*.rs' -o -name '*.py' -o -name '*.js' -o -name '*.jsx' -o \
            -name '*.ts' -o -name '*.tsx' -o -name '*.mjs' -o -name '*.cjs' -o \
            -name '*.java' -o -name '*.kt' -o -name '*.swift' -o -name '*.rb' -o -name '*.php' \
        \) -print -quit 2>/dev/null)" ]
    }

    cymbal_startup_index() {
        CYMBAL_BIN="$(type -P cymbal 2>/dev/null)"
        [ -n "$CYMBAL_BIN" ] || return 0

        if ! git -C "$PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1 && ! has_cymbal_source_files; then
            return 0
        fi

        echo "📡 Cymbal: 正在预热语义索引..."
        if command -v timeout >/dev/null 2>&1; then
            timeout 8 "$CYMBAL_BIN" index "$PWD" > "$CYMBAL_INDEX_LOG" 2>&1
        else
            "$CYMBAL_BIN" index "$PWD" > "$CYMBAL_INDEX_LOG" 2>&1
        fi

        local status=$?
        if [ "$status" -eq 0 ]; then
            local summary
            summary=$(tail -n 1 "$CYMBAL_INDEX_LOG" 2>/dev/null)
            echo "✅ Cymbal: ${summary:-索引已就绪}"
        elif [ "$status" -eq 124 ]; then
            echo "⚠️ Cymbal: 索引超过 8s，已跳过本次启动预热。Codex 内仍可手动运行: rtk cymbal index ."
        else
            echo "⚠️ Cymbal: 预热失败，Codex 内仍可使用 rg/sed 或手动运行: rtk cymbal index ."
            tail -n 2 "$CYMBAL_INDEX_LOG" 2>/dev/null
        fi
    }

    print_cymbal_agents_section() {
        cat <<'EOF'
## Code Navigation

Use `rtk cymbal` as the preferred tool for semantic code navigation.

Use Cymbal when you need to:
- understand a function, class, method, type, or exported variable
- find definitions, callers, references, or importers
- inspect impact before editing code
- trace what a symbol calls
- read source for a known symbol

Primary commands:

```bash
rtk cymbal index .
rtk cymbal investigate <symbol>
rtk cymbal refs <symbol>
rtk cymbal show <symbol>
rtk cymbal context <symbol>
rtk cymbal impact <symbol>
rtk cymbal trace <symbol>
rtk cymbal search <query>
rtk cymbal outline <file>
rtk cymbal structure
```

For non-git directories or shared config/workspace directories, prefer an explicit database:

```bash
rtk cymbal -d /tmp/cymbal.db index <path>
rtk cymbal -d /tmp/cymbal.db investigate <symbol>
```

Cymbal is preferred for semantic navigation. Use `rg`, `rg --files`, `sed`, and direct file reads for file discovery, literal text search, config files, Markdown, logs, generated files, or when Cymbal returns no useful result.

EOF
    }

    save_session_context() {
        local duration="$1"
        local summary_file="/tmp/codex_session_summary_$$.md"
        local git_state=""

        {
            echo "## Codex 会话总结"
            echo "- 项目目录: $PWD"
            echo "- 会话时长: ${duration}s"
            echo "- 结束时间: $(date '+%F %T')"
            echo
            echo "## 修改概览"
            if git -C "$PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                git_state=$(git -C "$PWD" status --short)
                if [ -n "$git_state" ]; then
                    printf '%s\n' "$git_state"
                else
                    echo "未检测到未提交的工作区修改。"
                fi
                echo
                echo "### Diff Stat"
                git -C "$PWD" diff --stat
            else
                echo "未检测到 git 仓库，无法自动列出修改文件。"
            fi
            echo
            echo "## 会话日志摘录"
            sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\x1b\[?2004[hl]//g' "$SESSION_LOG" | tail -n 120
        } > "$summary_file"

        if [ -n "$NMEM_BIN" ] && [ -x "$NMEM_BIN" ]; then
            local summary_snippet
            summary_snippet=$(sed -n '1,80p' "$summary_file" | tr '\n' ' ')
            "$NMEM_BIN" m add "[$PWD] $summary_snippet" --temp > /dev/null 2>&1
            "$NMEM_BIN" --json t save --from codex -p "$PWD" -s "[$PWD] 已将本次修改和学习内容保存到 .planning/codebase 与 nmem" > /dev/null 2>&1
        fi

        rm -f "$summary_file"
    }

    local PLANNING_KNOWLEDGE=""
    if [ -d "$SESSION_NOTE_DIR" ]; then
        PLANNING_KNOWLEDGE=$(load_planning_knowledge)
        if [ -n "$PLANNING_KNOWLEDGE" ]; then
            {
                echo "# Codex Planning Context"
                echo
                echo "This file is generated from all files under .planning/codebase."
                echo
                print_cymbal_agents_section
                printf '%s' "$PLANNING_KNOWLEDGE"
            } > "$SESSION_NOTE_DIR/AGENTS.md"
            if [ -e "$ROOT_AGENTS_FILE" ]; then
                ROOT_AGENTS_BACKUP="/tmp/codex_root_agents_$$"
                cp "$ROOT_AGENTS_FILE" "$ROOT_AGENTS_BACKUP"
            fi
            ln -sfn "$PWD/$SESSION_NOTE_DIR/AGENTS.md" "$ROOT_AGENTS_FILE"
            GENERATED_ROOT_AGENTS=1
            echo "✨ 已根据 .planning/codebase 构建 Codex 启动上下文。"
        fi
    fi

    on_codex_exit() {
        trap - EXIT INT TERM
        local DURATION=$(( $(date +%s) - START_TIME ))

        if [ -s "$SESSION_LOG" ]; then
            echo
            echo "[System] 会话结束，正在同步增量记忆 (${DURATION}s)..."
            save_session_context "$DURATION"
        fi

        rm -f "$SESSION_LOG"
        rm -f "$CYMBAL_INDEX_LOG"
        if [ "$GENERATED_ROOT_AGENTS" -eq 1 ]; then
            if [ -n "$ROOT_AGENTS_BACKUP" ] && [ -f "$ROOT_AGENTS_BACKUP" ]; then
                mv -f "$ROOT_AGENTS_BACKUP" "$ROOT_AGENTS_FILE"
            else
                rm -f "$ROOT_AGENTS_FILE"
            fi
        fi
        unalias bwrap 2>/dev/null
    }
    trap on_codex_exit INT TERM

    if [ -z "$CODEX_BIN" ] || [ ! -x "$CODEX_BIN" ]; then
        echo "❌ 未找到可执行的 codex: $CODEX_BIN"
        return 1
    fi

    if ! command -v script >/dev/null 2>&1; then
        echo "❌ 未找到 script 命令，无法捕获交互会话日志"
        return 1
    fi

    cymbal_startup_index

    echo "🚀 Codex 引擎已就绪 (GSD 增强版)"
    echo "💡 常用 GSD: gsd-progress (进度) | gsd-do (意图) | gsd-note (笔记)"
    echo "💡 语义导航: rtk cymbal investigate <symbol> | rtk cymbal refs <symbol>"
    echo "💡 提示：退出时建议执行 [/save-brain] 将核心逻辑更新至 AGENTS.md"
    echo "----------------------------------------------------------------"

    local CODEX_CMD
    printf -v CODEX_CMD '%q ' "$CODEX_BIN" "$@"
    script -q -e -c "cd \"$LAUNCH_DIR\" && $CODEX_CMD" "$SESSION_LOG"

    on_codex_exit
}
alias codex=codex_smart
