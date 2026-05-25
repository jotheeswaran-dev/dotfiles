#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

################################################################################
# This file is sourced only for login shells. It should contain commands that
# should be executed only in login shells. It should be used to set the terminal
# type and run a series of external commands (fortune, msgs, from, etc.)
# Note that using zprofile and zlogin, you are able to run commands for login
# shells before and after zshrc.
#
# file location: ${ZDOTDIR}/.zlogin
# load order: .zshenv [.shellrc], .zshrc [.shellrc, .aliases [.shellrc]], .zlogin
################################################################################

# execute 'DEBUG=true zsh' to debug the load order of the custom zsh configuration files
[[ -n "${DEBUG+1}" ]] && echo "loading ${0}"

# Faster than 'type is_shellrc_sourced &>/dev/null': no subshell, pure zsh builtin check.
(( $+functions[is_shellrc_sourced] )) || source "${HOME}/.shellrc"

recompile_zsh_scripts() {
  if is_non_empty_file "${1}" && (! is_file "${1}.zwc" || [[ "${1}" -nt "${1}.zwc" ]]); then
    # Bare echo — not routed through a color function, so tilde sub must be explicit.
    # Inline ${1//${HOME}/~} rather than replace_home_with_tilde: this function is
    # defined in .zlogin before the guard-source on line 20 runs; keeping the inline
    # form avoids any dependency on .shellrc load order within this file.
    [[ -n "${DEBUG+1}" ]] && echo "recompiling '${1//${HOME}/~}'"
    # Remove any stale .zwc.old left by a previously failed zrecompile run before
    # attempting recompilation. zrecompile writes .zwc files read-only; if zcompile
    # fails mid-write the .zwc.old backup is left behind — clean it up unconditionally.
    rm -f "${1}.zwc.old"
    zrecompile -pq "${1}" &>/dev/null
    # Remove .zwc.old again in case this run moved the old file there before failing.
    rm -f "${1}.zwc.old"
  fi
}

recompile_zsh_autoload_dir() {
  # Compile extensionless zsh autoload function files (files with no suffix).
  # find_in_folder_and_recompile only picks up *.sh / *.zsh; autoloaded functions
  # under e.g. XDG_CONFIG_HOME/zsh/ have no extension and would be missed without
  # this dedicated helper.
  # NOTE: Do NOT replace this call with find_in_folder_and_recompile — that function
  # matches only '*.sh' and '*.zsh' patterns, so it would silently skip every
  # extensionless autoload file (cc, count, pull, push, st, etc.) in this directory.
  local dir_to_scan="${1}"

  if ! is_directory "${dir_to_scan}"; then
    warn "Directory '$(yellow "${dir_to_scan}")' not found for zsh autoload recompilation." >&2
    return
  fi

  local f
  for f in "${dir_to_scan}"/*(N.); do
    # Skip files that already have an extension — those are handled elsewhere.
    [[ "${f:e}" == "" ]] && recompile_zsh_scripts "${f}"
  done
}

find_in_folder_and_recompile() {
  local dir_to_scan="${1}"
  local f # Loop variable

  if ! is_directory "${dir_to_scan}"; then
    warn "Directory '$(yellow "${dir_to_scan}")' not found for zsh script recompilation." >&2
    return
  fi

  # Mtime sentinel: skip the expensive find scan if nothing in the directory has
  # changed since the last recompilation run.  The sentinel file is stored under
  # XDG_CACHE_HOME, keyed by a sanitised form of the directory path.
  # The sentinel is touched after a successful scan so the next login is free.
  local sentinel="${XDG_CACHE_HOME}/zwc-sentinel-${dir_to_scan//\//-}"
  if is_file "${sentinel}" && [[ "${sentinel}" -nt "${dir_to_scan}" ]]; then
    # Bare echo — same reasoning as above: inline to avoid .shellrc load-order dependency.
    [[ -n "${DEBUG+1}" ]] && echo "skipping recompile scan (unchanged): '${dir_to_scan//${HOME}/~}'"
    return
  fi

  find "${dir_to_scan}" -maxdepth 5 \
    \( \( -name 'node_modules' -o -name '.pnpm' \) -type d -prune \) -o \
    \( \( -name '*.sh' -o -name '*.zsh' \) -type f -print0 \) |
    while IFS= read -r -d $'\0' f; do
    recompile_zsh_scripts "${f}"
  done

  touch "${sentinel}"
}

# <https://github.com/zimfw/zimfw/blob/master/login_init.zsh>
autoload -Uz zrecompile

# zsh config files can be compiled to improve performance
# Based from: https://github.com/romkatv/zsh-bench/blob/master/configs/ohmyzsh%2B/setup
recompile_zsh_scripts "${ZDOTDIR}/.zshenv"
recompile_zsh_scripts "${ZDOTDIR}/.zshrc"
recompile_zsh_scripts "${ZDOTDIR}/.zlogin"

find_in_folder_and_recompile "${ZSH}"

# omz doesn't know about these files, and so we don't depend on 'ZDOTDIR'
recompile_zsh_scripts "${HOME}/.aliases"
recompile_zsh_scripts "${HOME}/.shellrc"

# Compile third-party completion scripts that are sourced directly at startup.
# Without a .zwc these are parsed from source on every shell start.
# These live outside DOTFILES_DIR / XDG_CACHE_HOME / ANTIDOTE_HOME, so they are
# not covered by the find_in_folder_and_recompile calls below. Add any new
# third-party sourced completions here rather than extending those scans.
recompile_zsh_scripts "${HOMEBREW_PREFIX}/opt/git-extras/share/git-extras/git-extras-completion.zsh"

# Compile extensionless autoload function files under XDG_CONFIG_HOME/zsh/.
# These are not *.sh / *.zsh so find_in_folder_and_recompile misses them.
recompile_zsh_autoload_dir "${XDG_CONFIG_HOME}/zsh"

# Compile all *.zsh cache files under XDG_CACHE_HOME (brew shellenv, starship init,
# repo aliases, fast-syntax-highlighting theme, etc.).  A directory scan is used
# rather than listing individual files so any new cache files added in future are
# picked up automatically without needing to update this file.
find_in_folder_and_recompile "${XDG_CACHE_HOME}"

# Recompile large directories in the background (&!) so they don't block the first
# prompt on login shells.  Each call is individually guarded by a mtime sentinel
# inside find_in_folder_and_recompile, so unchanged dirs are skipped immediately.
# '&!' disowns the job — it won't appear in job control or produce a "Done" message.
{
  find_in_folder_and_recompile "${DOTFILES_DIR}"
  find_in_folder_and_recompile "${PERSONAL_BIN_DIR}"
  find_in_folder_and_recompile "${PROJECTS_BASE_DIR}"
  # explicitly use both intel and arm install locations of homebrew
  find_in_folder_and_recompile /opt/homebrew
  find_in_folder_and_recompile /usr/local
} &!

[[ -n "${DEBUG+1}" ]] && echo "Finished recompiling zsh scripts."
