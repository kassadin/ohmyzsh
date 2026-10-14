# If ZSH is not defined, use the current script's directory.
[[ -n "$ZSH" ]] || export ZSH="${${(%):-%x}:a:h}"

# Set ZSH_CUSTOM to the path where your own scripts live
# (.zsh files are sourced automatically), or else custom/
[[ -n "$ZSH_CUSTOM" ]] || ZSH_CUSTOM="$ZSH/custom"

# Set ZSH_CACHE_DIR to the path where cache files should be created
# or else we will use the default cache/
[[ -n "$ZSH_CACHE_DIR" ]] || ZSH_CACHE_DIR="$ZSH/cache"

# Make sure $ZSH_CACHE_DIR is writable, otherwise use a directory in $HOME
if [[ ! -w "$ZSH_CACHE_DIR" ]]; then
  ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh"
fi

# Initializes Oh My Zsh

# Load all stock functions (from $fpath files) called below.
autoload -U compaudit compinit zrecompile

is_plugin() {
  local base_dir=$1
  local name=$2
  builtin test -f $base_dir/plugins/$name/$name.plugin.zsh \
    || builtin test -f $base_dir/plugins/$name/_$name
}

# Add all defined plugins to fpath. This must be done before running
# compinit, so plugin completions are found and included in the dump check.
for plugin ($plugins); do
  if is_plugin "$ZSH_CUSTOM" "$plugin"; then
    fpath=("$ZSH_CUSTOM/plugins/$plugin" $fpath)
  elif is_plugin "$ZSH" "$plugin"; then
    fpath=("$ZSH/plugins/$plugin" $fpath)
  else
    echo "[oh-my-zsh] plugin '$plugin' not found"
  fi
done

# Save the location of the current completion dump file.
if [[ -z "$ZSH_COMPDUMP" ]]; then
  ZSH_COMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump-${ZSH_VERSION}"
fi

# compinit reuses an existing dump file as-is, so it never notices that $fpath
# changed (e.g. a plugin adding its own completions). Record the fpath in the
# dump and force a rebuild whenever it differs.
zcompdump_fpath="#omz fpath: $fpath"
zcompdump_refresh=0
if [[ ! -r "$ZSH_COMPDUMP" ]] || ! command grep -Fxq "$zcompdump_fpath" "$ZSH_COMPDUMP"; then
  command rm -f "$ZSH_COMPDUMP"
  zcompdump_refresh=1
fi

# Load completions, excluding insecure directories (compaudit lists them if needed)
compinit -i -d "$ZSH_COMPDUMP"

# Append the fpath marker if it is missing (compinit may have regenerated the dump).
# Use `tee` in case the $ZSH_COMPDUMP filename is invalid, to silence the error.
if (( zcompdump_refresh )); then
  tee -a "$ZSH_COMPDUMP" &>/dev/null <<EOF

$zcompdump_fpath
EOF
fi
unset zcompdump_fpath zcompdump_refresh

# zcompile the completion dump file if the .zwc is older or missing.
# Test that first so the lock directory and zrecompile are skipped when it's fresh.
if [[ ! "${ZSH_COMPDUMP}.zwc" -nt "$ZSH_COMPDUMP" ]] \
   && command mkdir "${ZSH_COMPDUMP}.lock" 2>/dev/null; then
  zrecompile -q -p "$ZSH_COMPDUMP"
  command rm -rf "$ZSH_COMPDUMP.zwc.old" "${ZSH_COMPDUMP}.lock"
fi

# Load all of the lib files in $ZSH/lib
for lib_file ("$ZSH"/lib/*.zsh); do
  source "$lib_file"
done
unset lib_file

# Load your own scripts from $ZSH_CUSTOM (files ending in .zsh),
# after the lib files so they can use and override what they define
for config_file ("$ZSH_CUSTOM"/*.zsh(N)); do
  source "$config_file"
done
unset config_file

# Source the plugins defined in $plugins. Plugin dirs were already added to
# fpath above; completion-only plugins (a dir with just a _name file) need
# no sourcing. Custom plugins win over built-ins with the same name.
for plugin ($plugins); do
  if [[ -f "$ZSH_CUSTOM/plugins/$plugin/$plugin.plugin.zsh" ]]; then
    source "$ZSH_CUSTOM/plugins/$plugin/$plugin.plugin.zsh"
  elif [[ -f "$ZSH/plugins/$plugin/$plugin.plugin.zsh" ]]; then
    source "$ZSH/plugins/$plugin/$plugin.plugin.zsh"
  fi
done
unset plugin is_plugin

# set completion colors to be the same as `ls`
[[ -z "$LS_COLORS" ]] || zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
