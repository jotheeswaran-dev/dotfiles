#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to cleanup browser profiles folders (delete cache, session and other files that will anyways be recreated when you restart that browser). It can be safely invoked even if that browser is running (in which case it will skip processing after printing a warning to quit that application)

# set -euo pipefail is intentionally omitted: some cleanup steps (find, rm on
# missing files) return non-zero in normal operation and must not abort the script.

# Re-source guard is inside .aliases itself — safe to call unconditionally.
# Sourcing .aliases also brings in .shellrc (which .aliases sources internally).
source "${HOME}/.aliases"

# Vacuums SQLite databases larger than 10 MB and deletes known cache/session files from a
# browser's profile folder. Skips processing if the browser process is running. Supports
# dry-run mode (pass 1 as the third argument) and optional statistics output (pass 1 as the
# fourth argument).
# Usage: vacuum_browser_profile_folder <browser-name> <profile-folder> <dry-run> <show-stats>
vacuum_browser_profile_folder() {
  local browser_name="${1}"   # Passed browser name
  local profile_folder="${2}" # Profile folder path
  local dry_run="${3:-0}"        # Dry-run flag (1 = dry-run)
  local show_stats="${4:-0}"     # Show statistics flag (1 = show stats)

  # Read pattern files from DOTFILES_DIR
  local -a file_patterns dir_patterns
  local file_patterns_file="${DOTFILES_DIR}/scripts/data/cleanup-browser-files.txt"
  local dir_patterns_file="${DOTFILES_DIR}/scripts/data/cleanup-browser-dirs.txt"
  if is_file "${file_patterns_file}"; then
    # while+read replaces $("${(@f)$(grep -vE ...)}"): no grep subprocess fork.
    # =~ regex test skips comment lines; ${_line//[[:space:]]/} blank-line check.
    local _line
    while IFS= read -r _line; do
      [[ "${_line}" =~ '^[[:space:]]*#' || -z "${_line//[[:space:]]/}" ]] && continue
      file_patterns+=("${_line}")
    done < "${file_patterns_file}"
  fi
  if is_file "${dir_patterns_file}"; then
    local _line
    while IFS= read -r _line; do
      [[ "${_line}" =~ '^[[:space:]]*#' || -z "${_line//[[:space:]]/}" ]] && continue
      dir_patterns+=("${_line}")
    done < "${dir_patterns_file}"
  fi

  if pgrep -i -f -q "${browser_name}"; then
    warn "Shutdown '$(yellow "${browser_name}")' first!; skipping processing of files for ${browser_name}"
    return 0 # Success, nothing to do
  fi

  if ! is_directory "${profile_folder}"; then
    warn "Skipping processing of '$(yellow "${profile_folder}")' since it doesn't exist"
    return 0 # Success, nothing to do
  fi

  section_header "$(yellow 'Vacuuming') '$(purple "${browser_name}")' in '$(yellow "${profile_folder}")'..."

  # du output is "<size>\t<path>"; capture once, strip path with %% — no cut fork.
  local _du_out size_before
  _du_out=$(du -sk "${profile_folder}" 2>/dev/null)
  size_before="${_du_out%%$'\t'*}"
  echo "--> Size before: $(folder_size "${profile_folder}")"

  if command_exists sqlite3; then
    local vacuum_failed=0
    local db_count=0
    local vacuumed_count=0

    while IFS= read -r -d '' db_file; do
      ((db_count++))
      local db_size=$(stat -f%z "${db_file}" 2>/dev/null || echo 0)
      # Only vacuum if > 10MB to save time
      if [[ ${db_size} -gt 10485760 ]]; then
        if [[ ${dry_run} -eq 1 ]]; then
          echo "[DRY-RUN] Would vacuum: $(replace_home_with_tilde "${db_file}") ($(numfmt --to=iec ${db_size} 2>/dev/null || echo "${db_size} bytes"))"
        else
          echo "Vacuuming: $(replace_home_with_tilde "${db_file}")"
          if ! sqlite3 "${db_file}" 'PRAGMA journal_mode=WAL; VACUUM; REINDEX;'; then
            warn "sqlite3 failed for '$(yellow "${db_file}")'"
            vacuum_failed=1
          else
            ((vacuumed_count++))
          fi
        fi
      fi
    done < <(find "${profile_folder}" -type f -iname '*.sqlite' -print0)

    [[ ${show_stats} -eq 1 ]] && echo "  -> Processed ${vacuumed_count} of ${db_count} SQLite databases"

    if [[ ${vacuum_failed} -ne 0 ]]; then
      warn "One or more sqlite vacuum/reindex operations failed in '$(yellow "${profile_folder}")'"
      return 1
    fi
  fi

  # --- Combined Deletion Logic ---
  # Build find arguments for files
  local file_find_args=()
  if [[ ${#file_patterns[@]} -gt 0 ]]; then
    for pattern in "${file_patterns[@]}"; do
      [[ ${#file_find_args[@]} -gt 0 ]] && file_find_args+=('-o')
      file_find_args+=('-iname' "${pattern}")
    done
  fi

  # Build find arguments for directories
  local dir_find_args=()
  if [[ ${#dir_patterns[@]} -gt 0 ]]; then
    for pattern in "${dir_patterns[@]}"; do
      [[ ${#dir_find_args[@]} -gt 0 ]] && dir_find_args+=('-o')
      dir_find_args+=('-iname' "${pattern}")
    done
  fi

  # Construct and execute the combined find command if patterns exist
  local combined_find_cmd=('find' "${profile_folder}" '-mindepth' '1')
  local has_conditions=0 # Flag to track if any conditions were added

  if [[ ${#file_find_args[@]} -gt 0 ]]; then
    combined_find_cmd+=('\(' '-type' 'f' '\(' "${file_find_args[@]}" '\)' '\)')
    has_conditions=1
  fi
  if [[ ${#dir_find_args[@]} -gt 0 ]]; then
    # Add '-o' separator if file conditions were already added
    [[ $has_conditions -eq 1 ]] && combined_find_cmd+=('-o')
    combined_find_cmd+=('\(' '-type' 'd' '-depth' '\(' "${dir_find_args[@]}" '\)' '\)')
    has_conditions=1 # Ensure flag is set even if only dir patterns exist
  fi

  # Add -delete action and execute only if conditions were specified
  if [[ ${has_conditions} -eq 1 ]]; then
    if [[ ${dry_run} -eq 1 ]]; then
      # Capture find output into an array; ${#_items} replaces `wc -l` subprocess.
      local -a _items=("${(@f)$("${combined_find_cmd[@]}" -print 2>/dev/null)}")
      local total_count=${#_items}
      echo '[DRY-RUN] Would delete the following files and directories:'
      print -l "${_items[@]}" | head -20
      [[ ${total_count} -gt 20 ]] && echo "  ... and $((total_count - 20)) more items"
    else
      echo 'Deleting files and directories matching patterns...'
      local -a _items=("${(@f)$("${combined_find_cmd[@]}" -print 2>/dev/null)}")
      local deleted_count=${#_items}
      if ! "${combined_find_cmd[@]}" -delete; then
        warn "Combined find/delete operation failed (code: $?) in '$(yellow "${profile_folder}")'.";
      else
        [[ ${show_stats} -eq 1 ]] && echo "  -> Deleted ${deleted_count} items"
      fi
    fi
  fi

  _du_out=$(du -sk "${profile_folder}" 2>/dev/null)
  local size_after="${_du_out%%$'\t'*}"
  echo "--> Size after: $(folder_size "${profile_folder}")"

  if [[ ${show_stats} -eq 1 ]] && [[ ${dry_run} -eq 0 ]]; then
    local space_saved=$((size_before - size_after))
    echo "  -> Space saved: $(numfmt --to=iec $((space_saved * 1024)) 2>/dev/null || echo "${space_saved}K")"
  fi

  success "Successfully processed profile folder for '$(yellow "${browser_name}")'"
}

main() {
  # Parse command line options
  local dry_run=0
  local show_stats=0
  while getopts ":ns" opt; do
    case ${opt} in
      n)
        dry_run=1
        ;;
      s)
        show_stats=1
        ;;
      \?)
        echo "$(red "Usage"): $(yellow "${${(%):-%x}##*/}") [-n] [-s]"
        echo "  -n  Dry-run mode (show what would be done without doing it)"
        echo "  -s  Show detailed statistics"
        exit 2
        ;;
    esac
  done
  shift $((OPTIND - 1))

  [[ ${dry_run} -eq 1 ]] && warn "Running in DRY-RUN mode - no changes will be made"

  # script_start_time is passed explicitly to print_script_duration below.
  # This script does not call step_start/step_end so there is no need to push
  # onto SCRIPT_START_TIMES.  If step_start/step_end are ever added here,
  # this local must also be pushed onto SCRIPT_START_TIMES so step_end can
  # compute total elapsed correctly (see design note in .shellrc).
  local script_start_time="${EPOCHSECONDS}"
  print_script_start

  # Define browsers and their profile folders
  # Key: Browser name (used for process check)
  # Value: Absolute path to the profile folder
  typeset -A browser_profiles
  browser_profiles=(
    brave       "${PERSONAL_PROFILES_DIR}/BraveProfile"
    chrome      "${PERSONAL_PROFILES_DIR}/ChromeProfile"
    firefox     "${PERSONAL_PROFILES_DIR}/FirefoxProfile"
    thunderbird "${PERSONAL_PROFILES_DIR}/ThunderbirdProfile"
    zen         "${PERSONAL_PROFILES_DIR}/ZenProfile"
  )

  # Loop through defined browsers and process them
  local browser_name profile_folder
  for browser_name profile_folder in "${(@kv)browser_profiles}"; do
    vacuum_browser_profile_folder "${browser_name}" "${profile_folder}" "${dry_run}" "${show_stats}"
  done

  print_script_duration "${script_start_time}"
}

main "$@"
