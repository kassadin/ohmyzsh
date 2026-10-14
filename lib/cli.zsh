#!/usr/bin/env zsh

# The `omz` command, reduced to `omz reload` and `omz update`.

function omz {
  setopt localoptions noksharrays
  [[ $# -gt 0 ]] || {
    _omz::help
    return 1
  }

  local command="$1"
  shift

  # Subcommand functions start with _ so that they don't
  # appear as completion entries when looking for `omz`
  (( ${+functions[_omz::$command]} )) || {
    _omz::help
    return 1
  }

  _omz::$command "$@"
}

function _omz {
  local -a cmds
  cmds=(
    'help:Usage information'
    'reload:Reload the current zsh session'
    'update:Update Oh My Zsh'
  )

  if (( CURRENT == 2 )); then
    _describe 'command' cmds
  fi

  return 0
}

# If run from a script, do not set the completion function
if (( ${+functions[compdef]} )); then
  compdef _omz omz
fi

## Utility functions

function _omz::log {
  # if promptsubst is set, a message with `` or $()
  # will be run even if quoted due to `print -P`
  setopt localoptions nopromptsubst

  # $1 = info|warn|error
  # $2 = text

  # Choose coloring based on log type
  case "$1" in
    info) print -P "%F{green}omz%f: $2" ;;
    warn) print -P "%S%F{yellow}omz%f%s: $2" ;;
    error) print -P "%S%F{red}omz%f%s: $2" ;;
  esac >&2
}

## User-facing commands

function _omz::help {
  cat >&2 <<EOF
Usage: omz <command> [options]

Available commands:

  help                Print this help message
  reload              Reload the current zsh session
  update              Update Oh My Zsh

EOF
}

function _omz::reload {
  # Delete current completion cache
  command rm -f $_comp_dumpfile $ZSH_COMPDUMP

  # Old zsh versions don't have ZSH_ARGZERO
  local zsh="${ZSH_ARGZERO:-${functrace[-1]%:*}}"
  # ZSH_ARGZERO is how zsh was invoked, not the path to it, so re-resolve
  # anything that is not absolute via $PATH at exec time (see #13919)
  [[ "${zsh#-}" != /* ]] && (( $+commands[zsh] )) && zsh="zsh"
  # Check whether to run a login shell
  [[ "$zsh" = -* || -o login ]] && exec -l "${zsh#-}" || exec "$zsh"
}

function _omz::update {
  # Check if git command is available
  (( $+commands[git] )) || {
    _omz::log error "git is not installed. Aborting..."
    return 1
  }

  # Check that $ZSH is a git repository and save the current HEAD
  local last_commit
  last_commit=$(builtin cd -q "$ZSH" 2>/dev/null && command git rev-parse HEAD 2>/dev/null) || {
    _omz::log error "\`$ZSH\` is not a git repository. Aborting..."
    return 1
  }

  _omz::log info "updating Oh My Zsh..."
  (builtin cd -q "$ZSH" && command git pull --rebase --autostash) || {
    _omz::log error "there was an error updating. Resolve it and try again..."
    return 1
  }

  # Restart the zsh session if there were changes
  if [[ "$(builtin cd -q "$ZSH"; command git rev-parse HEAD)" != "$last_commit" ]]; then
    _omz::log info "updated successfully. Reloading zsh session..."
    _omz::reload
  else
    _omz::log info "Oh My Zsh is already up to date."
  fi
}
