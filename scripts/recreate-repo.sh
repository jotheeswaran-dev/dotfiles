#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is used to recreate the git repos in the home and profiles folders. This is useful to remove dangling & orphaned commits from the remote git repo so that fresh cloning is fast.
# It assumes that a pre-existing repo on local is present - so that it can capture the relevant remote details.
# It will force removal of history if the `-f` flag is given. (The history of the profiles repo will always get deleted).

# Exit immediately if a command exits with a non-zero status.
set -e

# Source shell helpers if they aren't already loaded
# Faster than 'type is_shellrc_sourced &>/dev/null': no subshell, pure zsh builtin check.
(( $+functions[is_shellrc_sourced] )) || source "${HOME}/.shellrc"

usage() {
  echo "$(red 'Usage'): $(yellow "${${(%):-%x}##*/}") [-f] -d <repo-folder>"
  echo " $(yellow '-f')               --> (optional) force squashing into a single commit (profiles repo will automatically/always be forced anyways)"
  echo " $(yellow '-d <repo-folder>') --> (mandatory) The folder which has to be processed"
  echo "    eg: $(cyan "-f -d \${HOME}")                (will push to $(yellow "$(build_keybase_repo_url "${KEYBASE_HOME_REPO_NAME}")"))"
  echo "    eg: $(cyan "-d \${PERSONAL_PROFILES_DIR}")  (will push to $(yellow "$(build_keybase_repo_url "${KEYBASE_PROFILES_REPO_NAME}")"))"
  exit 1
}

# Extract the specified git config value from the git repo in the specified folder
extract_git_config_value() {
  git -C "${1}" config --get "${2}" || error "Failed to get git config value '${2}' for folder '${1}'"
}

# Trap handler: on any exit, restore cron from backup if CRON_BACKUP_FILE is present.
# On the success path, CRON_BACKUP_FILE is removed before recron runs, so resume_cron becomes a no-op here.
# On the failure path, resume_cron restores from the backup saved by suspend_cron.
_cleanup_recreate() {
  local exit_code=$?
  [[ ${exit_code} -ne 0 ]] && warn "Script exited with error code ${exit_code}."
  resume_cron
}

main() {
  local force=N
  local folder
  while getopts ":fd:" opt; do
    case ${opt} in
      f)
        force=Y
        ;;
      d)
        folder="${OPTARG}"
        ;;
      \?)
        usage
        ;;
      :)
        echo "Invalid option: -${OPTARG} requires an argument" 1>&2
        usage
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if is_zero_string "${folder}"; then
    usage
  fi

  # Remove trailing slash if present
  folder="$(strip_trailing_slash "${folder}")"

  # For the profiles repo alone, I don't care about retaining the history
  [[ "$(extract_last_segment "${folder}")" == "${KEYBASE_PROFILES_REPO_NAME}" ]] && force=Y

  ! is_git_repo "${folder}" && error "'${folder}' is not a git repo. Please specify the root of a git repo to proceed. Aborting!!!"

  section_header "$(yellow 'Processing folder'): '$(cyan "${folder}")'"
  info "$(yellow 'Squash commits (will lose history!)'): '$(cyan "${force}")'"

  # Suspend cron while this script is running; the trap restores it on failure, recron regenerates it on success.
  suspend_cron
  trap _cleanup_recreate EXIT

  # Capture information from pre-existing git repo
  local git_url
  local git_user_name
  local git_user_email
  local git_branch_name
  git_url="$(extract_git_config_value "${folder}" remote.origin.url)"
  git_user_name="$(extract_git_config_value "${folder}" user.name)"
  git_user_email="$(extract_git_config_value "${folder}" user.email)"
  git_branch_name="$(git -C "${folder}" branch --show-current)"
  is_zero_string "${git_branch_name}" && error 'Failed to determine current branch name'

  info "$(yellow 'Repo url'): '$(cyan "${git_url}")'"
  info "$(yellow 'User name'): '$(cyan "${git_user_name}")'"
  info "$(yellow 'User email'): '$(cyan "${git_user_email}")'"

  # Before deleting the current git information, ensure that keybase is installed and logged in (if the remote url is a keybase url). This is to avoid a scenario where we delete the git history and then fail to push to the remote due to authentication issues.
  if [[ "${git_url}" =~ 'keybase' ]]; then
    if ! command_exists keybase; then
      error "'keybase' command not found in the PATH. Aborting!!!"
      exit 1 # Irrecoverable failure
    fi

    debug "$(yellow 'Logging into keybase')"
    if keybase status --json 2>/dev/null | \grep -q '"logged_in":true'; then
      warn "Skipping keybase login since '$(yellow "${KEYBASE_USERNAME}")' is already logged in"
    elif ! keybase login; then
      error 'Could not login into keybase. Retry after logging in.'
      exit 1 # Irrecoverable failure
    fi
  fi

  git -C "${folder}" size || true
  if [[ "${force}" == 'Y' ]]; then
    rm -rf "${folder}/.git"

    git -C "${folder}" init --ref-format=reftable .

    git -C "${folder}" remote add origin "${git_url}"
    git -C "${folder}" config user.name "${git_user_name}"
    git -C "${folder}" config user.email "${git_user_email}"

    rm -f "${folder}/.git/index.lock"
    git -C "${folder}" add -A .
    git -C "${folder}" commit -qm "Initial commit: $(strftime '%Y-%m-%d %H:%M:%S' ${EPOCHSECONDS})"  # strftime — no $(date) fork
  fi

  # Retry the commit in case it failed the first time
  rm -f "${folder}/.git/index.lock"
  git -C "${folder}" add -A .
  git -C "${folder}" amq

  debug "Compressing '$(yellow "${folder}")'"
  git -C "${folder}" rfc
  SKIP_SIZE_BEFORE=1 git -C "${folder}" cc

  if [[ "${git_url}" =~ 'keybase' ]]; then
    debug "$(blue 'Recreating') '$(yellow "${git_url}")'"

    local git_remote_repo_name
    # ${${git_url%/}##*/} strips trailing slash then everything up to the last slash —
    # pure-zsh equivalent of basename, no extract_last_segment subshell call.
    git_remote_repo_name="${${git_url%\/}##*/}"
    keybase git delete -f "${git_remote_repo_name}" || warn "Failed to delete keybase repo '${git_remote_repo_name}' (it might not exist)"
    keybase git create "${git_remote_repo_name}" || error "Failed to create keybase repo '${git_remote_repo_name}'"
  fi

  debug "$(blue 'Pushing') from $(yellow "${folder}") to $(yellow "${git_url}")"
  git -C "${folder}" push --progress -fu origin "${git_branch_name}"

  rm -f "${folder}/.git/index.lock"

  success "The git repo in '$(yellow "${folder}")' recreated and pushed successfully to '$(yellow "${git_url}")'"

  # Regenerate crontab after this script finishes.
  # Clear the backup first so the EXIT trap (_cleanup_recreate -> resume_cron) becomes a no-op.
  load_zsh_configs
  rm -f "${CRON_BACKUP_FILE}"
  recron
}

main "$@"
