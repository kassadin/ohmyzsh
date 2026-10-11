# If ZSH is not defined, use the current script's directory.
[[ -n "$ZSH" ]] || export ZSH="${${(%):-%x}:a:h}"

# Set ZSH_CUSTOM to the path where your custom config files
# and plugins exists, or else we will use the default custom/
[[ -n "$ZSH_CUSTOM" ]] || ZSH_CUSTOM="$ZSH/custom"

# Set ZSH_CACHE_DIR to the path where cache files should be created
# or else we will use the default cache/
[[ -n "$ZSH_CACHE_DIR" ]] || ZSH_CACHE_DIR="$ZSH/cache"

# Make sure $ZSH_CACHE_DIR is writable, otherwise use a directory in $HOME
if [[ ! -w "$ZSH_CACHE_DIR" ]]; then
  ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh"
fi

# Create cache and completions dir and add to $fpath
[[ -d "$ZSH_CACHE_DIR/completions" ]] || mkdir -p "$ZSH_CACHE_DIR/completions"
(( ${fpath[(Ie)$ZSH_CACHE_DIR/completions]} )) || fpath=("$ZSH_CACHE_DIR/completions" $fpath)

# Initializes Oh My Zsh

# Load all stock functions (from $fpath files) called below.
autoload -U compaudit compinit zrecompile

# Figure out the SHORT hostname
if [[ "$OSTYPE" = darwin* ]]; then
  # macOS's $HOST changes with dhcp, etc. Use LocalHostName if possible.
  # scutil costs a fork on every start, so remember its answer for a day
  # (like lib/grep.zsh) and re-check sooner if $HOST changes.
  __omz_host_cache="$ZSH_CACHE_DIR/localhostname"
  __omz_host_cached=("$__omz_host_cache"(Nm-1))
  __omz_host_key=
  SHORT_HOST=
  if [[ -n "$__omz_host_cached" ]]; then
    if ! { read -r __omz_host_key && read -r SHORT_HOST } < "$__omz_host_cache"; then
      __omz_host_key=
      SHORT_HOST=
    fi
  fi
  if [[ "$__omz_host_key" != "$HOST" || -z "$SHORT_HOST" ]]; then
    # only cache what scutil actually answered, so a transient failure
    # doesn't pin the fallback name for a day
    if SHORT_HOST=$(scutil --get LocalHostName 2>/dev/null) && [[ -n "$SHORT_HOST" ]]; then
      [[ ! -w "$ZSH_CACHE_DIR" ]] || print -rl -- "$HOST" "$SHORT_HOST" >| "$__omz_host_cache"
    else
      SHORT_HOST="${HOST/.*/}"
    fi
  fi
  unset __omz_host_cache __omz_host_cached __omz_host_key
else
  SHORT_HOST="${HOST/.*/}"
fi

# Save the location of the current completion dump file.
if [[ -z "$ZSH_COMPDUMP" ]]; then
  ZSH_COMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump-${SHORT_HOST}-${ZSH_VERSION}"
fi

# Resolve the commit $ZSH is checked out at into $REPLY by reading the git
# directory, so that no git process is forked on every startup.
# Handles .git files (worktrees, submodules), worktree common dirs, detached
# HEADs and packed refs. Returns 1 if anything is unexpected.
_omz_git_head() {
  local gitdir="$ZSH/.git" common head ref
  local -a lines
  REPLY=

  # .git may be a file pointing at the real git dir
  if [[ -f "$gitdir" ]]; then
    read -r head 2>/dev/null < "$gitdir" || return 1
    [[ "$head" = "gitdir: "* ]] || return 1
    gitdir="${head#gitdir: }"
    [[ -n "$gitdir" ]] || return 1
    [[ "$gitdir" = /* ]] || gitdir="$ZSH/$gitdir"
  fi

  # worktrees keep their refs in the common git dir
  common="$gitdir"
  if [[ -f "$gitdir/commondir" ]]; then
    read -r common 2>/dev/null < "$gitdir/commondir" || return 1
    [[ "$common" = /* ]] || common="$gitdir/$common"
  fi

  [[ -r "$gitdir/HEAD" ]] || return 1
  read -r head 2>/dev/null < "$gitdir/HEAD" || return 1

  if [[ "$head" = ref:\ * ]]; then
    ref="${head#ref: }"

    # Only use well-formed full ref names as paths. Besides matching Git's ref
    # rules, this prevents a malformed HEAD from escaping the git directory.
    [[ "$ref" = refs/?* \
      && "$ref" != *..* \
      && "$ref" != *//* \
      && "$ref" != */ \
      && "$ref" != */.* \
      && "$ref" != *.lock \
      && "$ref" != *.lock/* \
      && "$ref" != *. \
      && "$ref" != *'@{'* \
      && "$ref" != *[[:cntrl:]\ \~\^\:\?\*\[\\]* \
    ]] || return 1

    case "$ref" in
      # These namespaces are private to each worktree and are never resolved
      # from the common directory or its packed-refs file.
      refs/bisect/*|refs/worktree/*|refs/rewritten/*)
        [[ -r "$gitdir/$ref" ]] || return 1
        read -r REPLY 2>/dev/null < "$gitdir/$ref" || return 1
        ;;
      *)
        if [[ -r "$common/$ref" ]]; then
          read -r REPLY 2>/dev/null < "$common/$ref" || return 1
        elif [[ -r "$common/packed-refs" ]]; then
          lines=("${(@f)$(<"$common/packed-refs")}")
          REPLY="${lines[(r)* ${(b)ref}]%% *}"
        else
          return 1
        fi
        ;;
    esac
  else
    # detached HEAD: the file holds the commit itself
    REPLY="$head"
  fi

  # only an object ID is a usable answer: a symbolic ref, a malformed file or
  # a missed packed entry all fall through to the git fallback instead
  [[ -n "$REPLY" && -z "${REPLY//[0-9a-f]/}" ]] \
    && (( ${#REPLY} == 40 || ${#REPLY} == 64 ))
}

# Construct zcompdump OMZ metadata. The helper reports through $REPLY, so
# call it in a scope that keeps that out of the global namespace.
() {
  local REPLY
  _omz_git_head || REPLY="$(builtin cd -q "$ZSH"; git rev-parse HEAD 2>/dev/null)"
  typeset -g zcompdump_revision="#omz revision: $REPLY"
}
zcompdump_fpath="#omz fpath: $fpath"
unset -f _omz_git_head

# Check whether the zcompdump file carries the current OMZ metadata lines
_omz_compdump_has_metadata() {
  local -a lines
  [[ -r "$ZSH_COMPDUMP" ]] || return 1
  lines=("${(@f)$(<"$ZSH_COMPDUMP")}")
  (( ${lines[(Ie)$zcompdump_revision]} && ${lines[(Ie)$zcompdump_fpath]} ))
}

# Delete the zcompdump file if OMZ zcompdump metadata changed
zcompdump_refresh=0
if ! _omz_compdump_has_metadata; then
  command rm -f "$ZSH_COMPDUMP"
  zcompdump_refresh=1
fi

# Load completions, excluding insecure directories (compaudit lists them if needed)
compinit -i -d "$ZSH_COMPDUMP"

# Append zcompdump metadata if missing (compinit may have regenerated the file)
if (( zcompdump_refresh )) || ! _omz_compdump_has_metadata; then
  # Use `tee` in case the $ZSH_COMPDUMP filename is invalid, to silence the error
  # See https://github.com/ohmyzsh/ohmyzsh/commit/dd1a7269#commitcomment-39003489
  tee -a "$ZSH_COMPDUMP" &>/dev/null <<EOF

$zcompdump_revision
$zcompdump_fpath
EOF
fi
unset zcompdump_revision zcompdump_fpath zcompdump_refresh
unset -f _omz_compdump_has_metadata

# zcompile the completion dump file if the .zwc is older or missing.
# Test that first so the lock directory and zrecompile are skipped when it's fresh.
if [[ ! "${ZSH_COMPDUMP}.zwc" -nt "$ZSH_COMPDUMP" ]] \
   && command mkdir "${ZSH_COMPDUMP}.lock" 2>/dev/null; then
  zrecompile -q -p "$ZSH_COMPDUMP"
  command rm -rf "$ZSH_COMPDUMP.zwc.old" "${ZSH_COMPDUMP}.lock"
fi

_omz_source() {
  local context filepath="$1"

  # Construct zstyle context based on path
  context="lib:${filepath:t:r}" # :t = lib_name.zsh, :r = lib_name

  local disable_aliases=0
  zstyle -T ":omz:${context}" aliases || disable_aliases=1

  # Back up alias names prior to sourcing
  local -A aliases_pre galiases_pre
  if (( disable_aliases )); then
    aliases_pre=("${(@kv)aliases}")
    galiases_pre=("${(@kv)galiases}")
  fi

  # Source file from $ZSH_CUSTOM if it exists, otherwise from $ZSH
  if [[ -f "$ZSH_CUSTOM/$filepath" ]]; then
    source "$ZSH_CUSTOM/$filepath"
  elif [[ -f "$ZSH/$filepath" ]]; then
    source "$ZSH/$filepath"
  fi

  # Unset all aliases that don't appear in the backed up list of aliases
  if (( disable_aliases )); then
    if (( #aliases_pre )); then
      aliases=("${(@kv)aliases_pre}")
    else
      (( #aliases )) && unalias "${(@k)aliases}"
    fi
    if (( #galiases_pre )); then
      galiases=("${(@kv)galiases_pre}")
    else
      (( #galiases )) && unalias "${(@k)galiases}"
    fi
  fi
}

# Load all of the lib files in ~/.oh-my-zsh/lib that end in .zsh
# TIP: Add files you don't want in git to .gitignore
for lib_file ("$ZSH"/lib/*.zsh); do
  _omz_source "lib/${lib_file:t}"
done
unset lib_file

# set completion colors to be the same as `ls`
[[ -z "$LS_COLORS" ]] || zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
