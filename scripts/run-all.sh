#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script will find all git repositories within the specified 'FOLDER' (defaults to current dir) filtered by 'FILTER' (defaults to empty string; accepts regex) and for a minimum depth of 'MINDEPTH' (optional; defaults to 1) and a maximum depth of 'MAXDEPTH' (optional; defaults to 4); and then runs the specified commands in each of those git repos. This script is not limited to only running 'git' commands!

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail

# Re-source guard is inside .shellrc itself — safe to call unconditionally.
source "${HOME}/.shellrc"

usage() {
  cat <<EOF
  $(red 'Usage'): $(yellow "${${(%):-%x}##*/}") <any-unix-command>
This script will find all git repositories within the specified 'FOLDER' (defaults to current dir) filtered by 'FILTER' (defaults to empty string; accepts regex) and for a minimum depth of 'MINDEPTH' (optional; defaults to 1) and a maximum depth of 'MAXDEPTH' (optional; defaults to 4); and then runs the specified commands in each of those git repos. This script is not limited to only running 'git' commands!

For eg:
FOLDER=dev MINDEPTH=2 $(yellow "${${(%):-%x}##*/}") git status
FOLDER=dev MINDEPTH=2 $(yellow "${${(%):-%x}##*/}") git branch -vv
FOLDER=dev MINDEPTH=2 $(yellow "${${(%):-%x}##*/}") ls -l
FILTER=oss $(yellow "${${(%):-%x}##*/}") ls -l
FILTER='oss|zsh|omz' $(yellow "${${(%):-%x}##*/}") git fo
EOF
  exit 1
}

main() {
  while getopts ":h:" opt; do
    case ${opt} in
      h)
        usage
        ;;
      :)
        echo "Invalid option: -${OPTARG} requires an argument" >&2
        usage
        ;;
    esac
  done
  shift $((OPTIND - 1))

  # if there are no arguments, print usage and exit
  [[ $# -eq 0 ]] && usage

  section_header "$(yellow 'Running commands in git repositories')"

  # script_start_time is passed explicitly to print_script_duration below.
  # This script does not call step_start/step_end so there is no need to push
  # onto SCRIPT_START_TIMES.  If step_start/step_end are ever added here,
  # this local must also be pushed onto SCRIPT_START_TIMES so step_end can
  # compute total elapsed correctly (see design note in .shellrc).
  local script_start_time
  script_start_time="${EPOCHSECONDS}"
  print_script_start

  local mindepth maxdepth folder filter
  mindepth="${MINDEPTH:-1}"
  maxdepth="${MAXDEPTH:-4}"
  folder="${FOLDER:-.}"
  filter="${FILTER:-}"
  local total_count count dir repo

  echo "$(yellow "Finding git repos starting in folder '$(cyan "${folder}")' for a min depth of $(cyan "${mindepth}") and max depth of $(cyan "${maxdepth}")")"
  [[ "${filter}" != '' ]] && echo "$(yellow "Filtering with: $(cyan "${filter}")")"

  # Find all .git directories; use :h modifier for dirname, assoc array for sort -u dedup.
  local -A _seen=()
  local -a dir_array=()
  while IFS= read -r git_dir; do
    local d="${git_dir:h}"
    [[ -n "${filter}" && ! "${d}" =~ ${filter} ]] && continue
    if (( ! ${+_seen[${d}]} )); then
      _seen[${d}]=1
      dir_array+=("${d}")
    fi
  done < <(find "${folder}" -mindepth "${mindepth}" -maxdepth "${maxdepth}" -type d -name '.git' 2>/dev/null)
  unset _seen

  total_count=${#dir_array[@]}

  # Track failures
  local -a failed_repos=()
  local -a successful_repos=()

  count=1
  for dir in "${dir_array[@]}"; do
    if is_directory "${dir}" && ! is_symbolic_link "${dir}"; then
      info "[${count} of ${total_count}] '$(yellow "$*")' in '$(cyan "${dir}")'"
      if (cd "${dir}" && eval "$@"); then
        successful_repos+=("${dir}")
      else
        failed_repos+=("${dir}")
        warn "Command failed in: $(red "${dir}")"
      fi
      ((count++))
    fi
  done

  # Report summary
  echo ""
  info "$(yellow 'Summary')"
  echo "  Total repositories: ${total_count}"
  echo "  Successful: $(green ${#successful_repos[@]})"
  if [[ ${#failed_repos[@]} -gt 0 ]]; then
    echo "Failed: $(red ${#failed_repos[@]})"
    echo "$(red 'Failed repositories:')"
    for repo in "${failed_repos[@]}"; do
      echo "  - $(red "${repo}")"
    done
  fi

  print_script_duration "${script_start_time}"

  # Exit with error if any repos failed
  [[ ${#failed_repos[@]} -gt 0 ]] && exit 1
  exit 0
}

main "$@"
