#!/usr/bin/env zsh

# vim:filetype=zsh syntax=zsh tabstop=2 shiftwidth=2 softtabstop=2 expandtab autoindent fileencoding=utf-8

# This script is idempotent and will restore your local setup to the same state even if run multiple times.
# In most cases, the script will provide warning messages if skipping certain steps. Each such message will be useful to give you a hint about what to do to force rerunning of that step.

# file location: <anywhere; but advisable in the PATH>

# TODO: Need to figure out the scriptable commands for the following settings:
# 1. Auto-adjust Brightness
# 2. Brightness on battery
# 3. Keyboard brightness

# Exit immediately if a command exits with a non-zero status.
set -e

# Error trap cleanup and exit
_cleanup_and_exit() {
  local message='Installation failed. Check for error messages above.'
  # (( $+functions[...] )) is a no-subshell zsh builtin check, faster than 'type ... &>/dev/null'
  if (( $+functions[error] )); then
    error "${message}"
  else
    echo "ERROR: ${message}" >&2
  fi

  # Restore cron from the backup taken at the start of main(); CRON_BACKUP_FILE is set there.
  # (( $+functions[...] )) is a no-subshell zsh builtin check, faster than 'type ... &>/dev/null'
  if (( $+functions[resume_cron] )); then
    resume_cron
  elif [[ -s "${CRON_BACKUP_FILE:-}" ]]; then
    # Fallback: shellrc not yet loaded, restore directly
    if crontab "${CRON_BACKUP_FILE}"; then
      echo 'SUCCESS: Restored crontab from backup.'
    else
      echo 'ERROR: Failed to restore crontab.' >&2
    fi
    rm -f "${CRON_BACKUP_FILE}"
  fi

  exit 1
}

# Set DNS to 8.8.8.8 if on Jio ISP (GitHub may otherwise not resolve)
setup_jio_dns() {
  local _org
  # Capture curl output into a variable first; then test with a glob match.
  # Previously: curl ... | grep -qi 'jio' — two processes + pipe.
  # Now: single curl fork, pure-zsh lowercase expansion (:l) + glob match.
  _org=$(curl -fsS https://ipinfo.io/org 2>/dev/null)
  if [[ "${_org:l}" == *jio* ]]; then
    echo '==> Setting DNS for WiFi from Jio ISP'
    networksetup -setdnsservers Wi-Fi 8.8.8.8 || echo 'Warning: Failed to set DNS for Wi-Fi'
  fi
}

# Download and source .shellrc from GitHub (before dotfiles are cloned)
download_and_source_shellrc() {
  echo "==> Download the '~/.shellrc' for loading the utility functions"
  # force the download for FIRST_INSTALL
  # (( $+functions[...] )) is a no-subshell zsh builtin check, faster than 'type ... &>/dev/null'
  [[ -n "${FIRST_INSTALL}" ]] && (( $+functions[is_shellrc_sourced] )) && unfunction is_shellrc_sourced

  # Check for one key function defined in .shellrc to see if sourcing is needed
  if ! (( $+functions[is_shellrc_sourced] )); then
    [[ ! -f "${HOME}/.shellrc" ]] && curl --retry 3 --retry-delay 5 -fsSL "https://raw.githubusercontent.com/${GH_USERNAME}/dotfiles/refs/heads/${DOTFILES_BRANCH}/files/--HOME--/.shellrc" -o "${HOME}/.shellrc"
    DEBUG=true source "${HOME}/.shellrc"
  else
    warn "Skipping downloading and sourcing '$(yellow "${HOME}/.shellrc")' since its already loaded"
  fi
}

# Enable Touch ID for sudo command when running on the terminal
approve_fingerprint_sudo() {
  step_start
  section_header "$(yellow 'Setting up touchId for sudo access in terminal shells')"

  if ! ioreg -c AppleBiometricSensor | \grep -q AppleBiometricSensor; then
    warn 'Touch ID hardware is not detected. Skipping configuration.'
    step_end
    return 0  # Exit successfully as no action is needed
  fi

  local template_file='/etc/pam.d/sudo_local.template'
  if ! is_file "${template_file}"; then
    warn "Template file '$(yellow "${template_file}")' not found! Skipping!"
    step_end
    return
  fi

  local target_file='/etc/pam.d/sudo_local'
  if ! is_file "${target_file}"; then
    if sudo sh -c "sed 's/^#auth/auth/' '${template_file}' > '${target_file}'"; then
      success "Created new file: '$(yellow "${target_file}")'"
    else
      error "Failed to create '${target_file}'"
    fi
  else
    warn "'$(yellow "${target_file}")' is already present - not creating again"
  fi
  step_end
}

# Verify FileVault disk encryption is active
ensure_filevault_is_on() {
  step_start
  section_header "$(yellow 'Verifying FileVault status')"
  if [[ "$(fdesetup isactive)" != 'true' ]]; then
    error 'FileVault is not turned on. Please encrypt your hard disk!'
    exit 1
  fi
  step_end
}

# Install Xcode Command Line Tools via non-interactive, non-gui softwareupdate
install_xcode_command_line_tools() {
  step_start
  section_header "$(yellow 'Installing xcode command-line tools')"
  if ! xcode-select -p &>/dev/null; then
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    sudo softwareupdate -ia --agree-to-license --force || warn 'softwareupdate encountered errors'
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    if ! xcode-select -p 2>/dev/null; then
      error "Couldn't install xcode command-line tools; Aborting"
      exit 1
    fi

    success 'Successfully installed xcode command-line tools'
  else
    warn 'Skipping installation of xcode command-line tools since its already present'
  fi
  # Note: Duplicate the cleanup if the installation was cancelled and continued via the gui
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  step_end
}

# Create all directories referenced by env vars as a pre-emptive safety step
ensure_directories_exist() {
  step_start
  section_header "$(yellow 'Creating directories defined by various env vars')"
  local -a folders=("${DOTFILES_DIR}" "${PROJECTS_BASE_DIR}" "${PERSONAL_BIN_DIR}" "${PERSONAL_CONFIGS_DIR}" "${PERSONAL_PROFILES_DIR}" "${XDG_CACHE_HOME}" "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}" "${XDG_STATE_HOME}")
  for folder in "${folders[@]}"; do
    ensure_dir_exists "${folder}"
  done
  step_end
}

# Clone an OMZ plugin from GitHub if not already present
clone_omz_plugin_if_not_present() {
  local last_segment
  last_segment="$(extract_last_segment "${1}")"
  clone_repo_into "${1}" "${ZSH_CUSTOM}/plugins/${last_segment}" || warn "Failed to install '$(yellow "${last_segment}")'"
}

# Install Oh My Zsh and custom plugins
install_oh_my_zsh_and_custom_plugins() {
  step_start
  section_header "$(yellow 'Installing oh-my-zsh') into '$(purple "${ZSH}")'"
  if ! is_directory "${ZSH}"; then
    sh -c "$(ZSH= curl --retry 3 --retry-delay 5 -fsSL https://install.ohmyz.sh/)" "" --unattended
    success "Successfully installed oh-my-zsh into '$(yellow "${ZSH}")'"
  else
    warn "Skipping installation of oh-my-zsh since '$(yellow "${ZSH}")' is already present"
  fi
  step_end

  # Note: Some of these are available via brew, but enabling them will take an additional step and the only other benefit (of keeping them up-to-date using brew can still be achieved by updating the git repos directly using git commands)
  # These repos can be alternatively tracked using git submodules, but by doing so, any new change in the submodule, will show up as a new commit in the main (home) repo. To avoid this "noise", I prefer to decouple them
  step_start
  section_header2 "$(yellow 'Installing custom omz plugins')"
  # Note: These are not installed using homebrew since sourcing of the files needs to be explicit in .zshrc
  # Also, the order of these being referenced in the zsh session startup (for vanilla OS) will cause a warning to be printed though the rest of the shell startup sequence is still being performed. Ultimately, until they become included by default into omz, keep them here as custom plugins
  local -a omz_plugins=(
    'zdharma-continuum/fast-syntax-highlighting'
    'zsh-users/zsh-autosuggestions'
    'zsh-users/zsh-completions'
  )
  for plugin_url in "${omz_plugins[@]}"; do
    clone_omz_plugin_if_not_present "https://github.com/${plugin_url}"
  done
  step_end
}

# Clone the dotfiles repo and configure upstream
clone_dot_files_repo() {
  step_start
  section_header "$(yellow 'Installing dotfiles') into '$(purple "${DOTFILES_DIR}")'"
  rm -rfv "${ZDOTDIR}/.zshrc.pre-oh-my-zsh"
  if is_non_zero_string "${DOTFILES_DIR}" && ! is_git_repo "${DOTFILES_DIR}"; then
    # Delete the auto-generated .zshrc since that needs to be replaced by the one in the DOTFILES_DIR repo
    rm -rf "${ZDOTDIR}/.zshrc"

    # Note: Cloning with https since the ssh keys will not be present at this time
    if clone_repo_into "https://github.com/${GH_USERNAME}/dotfiles" "${DOTFILES_DIR}" "${DOTFILES_BRANCH}"; then
      # Use the https protocol for pull, but use ssh/git for push (only configure if not already set)
      if ! git -C "${DOTFILES_DIR}" config --get url.ssh://git@github.com/.pushInsteadOf &>/dev/null; then
        git -C "${DOTFILES_DIR}" config url.ssh://git@github.com/.pushInsteadOf https://github.com/
      fi
      append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"
      # Setup the DOTFILES_DIR repo's upstream if it doesn't already point to UPSTREAM_GH_USERNAME's repo
      add-upstream-git-config.sh -d "${DOTFILES_DIR}" -u "${UPSTREAM_GH_USERNAME}" || warn 'Failed to add upstream git config for dotfiles repo'
    else
      error 'Failed to clone dotfiles repo'
      exit 1
    fi
  else
    warn "Skipping cloning the dotfiles repo since '$(yellow "${DOTFILES_DIR}")' is either not defined or is already a git repo"
  fi
  step_end
}

# Install homebrew, tap repos, and run brew bundle
install_homebrew() {
  step_start
  section_header "$(yellow 'Installing homebrew') into '$(yellow "${HOMEBREW_PREFIX}")'"
  if is_zero_string "${HOMEBREW_PREFIX}"; then
    error "'HOMEBREW_PREFIX' env var is not set; something is wrong. Please correct before retrying!"
    exit 1  # Irrecoverable failure
  fi

  if ! command_exists brew; then
    # Prep for installing homebrew
    sudo mkdir -p "${HOMEBREW_PREFIX}/tmp" "${HOMEBREW_PREFIX}/repository" "${HOMEBREW_PREFIX}/plugins" "${HOMEBREW_PREFIX}/bin"
    sudo chown -fR "${USER}":admin "${HOMEBREW_PREFIX}"
    chmod u+w "${HOMEBREW_PREFIX}"

    local install_script_file
    install_script_file="$(mktemp)"
    if curl --retry 3 --retry-delay 5 -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "${install_script_file}"; then
      NONINTERACTIVE=1 bash "${install_script_file}" || {
        rm -f "${install_script_file}"
        error 'Homebrew installation failed'
        exit 1
      }
      rm -f "${install_script_file}"
      success 'Successfully installed homebrew'
    else
      rm -f "${install_script_file}"
      error 'Failed to download Homebrew installation script'
      exit 1
    fi
  else
    warn "Skipping installation of $(yellow 'homebrew') since it's already installed"
  fi

  # Note: ensure that homebrew's environment variables are set correctly for this session (even if homebrew was not installed in this session)
  eval_shellenv "${HOMEBREW_PREFIX}/bin/brew" shellenv

  # Note: Temporarily disable the ERR trap since brew commands may fail on a vanilla OS (e.g. rate limits, missing deps).
  if is_non_zero_string "${FIRST_INSTALL}"; then
    trap - ERR
  fi

  # Since we have moved away from any taps in the FIRST_INSTALL, this logic is no longer required.
  # TODO: Cleanup once this has been tested on a vanilla OS
  # \grep -E "^tap " "${HOMEBREW_BUNDLE_FILE}" | awk '{print $2}' | tr -d "'\"" | while read -r tap_name; do
  #   brew tap "${tap_name}" || true
  # done

  # Note: Do not set the 'FIRST_INSTALL' in this script - since its supposed to run idempotently. Also, don't run the cleanup of pre-installed brews/casks (for the same reason)
  # Run brew bundle install if check fails. Let brew handle idempotency. Continue script even if bundle fails.
  # Note: Split into taps, formulae and casks separately so that curl doesnt timeout, and failures are isolated and reported clearly.
  # Note: Each pass includes the Brewfile preamble (non tap/brew/cask lines) to preserve Ruby DSL context (e.g. cask_args, is_arm).
  # Note: For FIRST_INSTALL, only process lines up to the first 'FIRST_INSTALL' guard in the Brewfile (which marks the end of the base install section).
  if is_non_zero_string "${FIRST_INSTALL}"; then
    local brewfile_content
    brewfile_content="$(sed "/^[^#].*FIRST_INSTALL/q" "${HOMEBREW_BUNDLE_FILE}")"
    brewfile_content="${brewfile_content%$'\n'*FIRST_INSTALL*}"  # strip the FIRST_INSTALL guard line itself
    if brew bundle check || brew bundle --file=- <<< "${brewfile_content}"; then
      success 'Successfully installed cmd-line and gui apps using homebrew'
    else
      warn 'Homebrew bundle install encountered errors; continuing...'
    fi
  else
    if brew bundle check || brew bundle; then
      success 'Successfully installed cmd-line and gui apps using homebrew'
    else
      warn 'Homebrew bundle install encountered errors; continuing...'
    fi
  fi

  # Note: load all zsh config files for the 2nd time for PATH and other env vars to take effect (due to defensive programming)
  load_zsh_configs
  # Note: run the post-brew-install script once more (in case it wasn't run by the brew lifecycle due to any error)
  # Note: When running with FIRST_INSTALL, some errors might come on a vanilla OS - warn and continue instead of failing.
  post-brew-install.sh || { is_non_zero_string "${FIRST_INSTALL}" && warn 'post-brew-install encountered errors; continuing...'; }

  if is_non_zero_string "${FIRST_INSTALL}"; then
    trap _cleanup_and_exit ERR
  fi

  # TODO: Commented out to avoid the second touchId popup. Need to investigate how to solve this.
  # is_arm && sudo rm -rf /usr/local/bin/keybase /usr/local/bin/git-remote-keybase || true
  step_end
}

# Clone the Keybase home repo (private configs)
clone_home_repo() {
  step_start
  section_header "$(yellow 'Cloning') $(purple 'home') repo"
  if is_non_zero_string "${KEYBASE_HOME_REPO_NAME}"; then
    if clone_repo_into "$(build_keybase_repo_url "${KEYBASE_HOME_REPO_NAME}")" "${HOME}"; then
      # Reset ssh keys' permissions so that git doesn't complain when using them
      set_ssh_folder_permissions

      # Fix /etc/hosts file to block facebook
      is_file "${PERSONAL_CONFIGS_DIR}/etc.hosts" && sudo cp "${PERSONAL_CONFIGS_DIR}/etc.hosts" /etc/hosts
    else
      warn 'Failed to clone home repo'
    fi
  else
    warn "Skipping cloning of home repo since the '$(yellow 'KEYBASE_HOME_REPO_NAME')' env var hasn't been set"
  fi
  step_end
}

# Clone the Keybase profiles repo (browser profiles)
clone_profiles_repo() {
  step_start
  section_header "$(yellow 'Cloning') $(purple 'profiles') repo"
  if is_non_zero_string "${KEYBASE_PROFILES_REPO_NAME}" && is_non_zero_string "${PERSONAL_PROFILES_DIR}"; then
    if ! clone_repo_into "$(build_keybase_repo_url "${KEYBASE_PROFILES_REPO_NAME}")" "${PERSONAL_PROFILES_DIR}"; then
      warn 'Failed to clone profiles repo'
    fi
  else
    warn "Skipping cloning of profiles repo since either the '$(yellow 'KEYBASE_PROFILES_REPO_NAME')' or the '$(yellow 'PERSONAL_PROFILES_DIR')' env var hasn't been set"
  fi
  step_end
}

main() {
  # Suspend cron early (shellrc not yet available at this point).
  # CRON_BACKUP_FILE, suspend_cron and resume_cron live in .shellrc (section 1g) so they are
  # guaranteed present the moment .shellrc is sourced, even before the dotfiles repo is cloned.
  export CRON_BACKUP_FILE="${TMPDIR:-/tmp}/crontab_backup"
  crontab -l > "${CRON_BACKUP_FILE}" 2>/dev/null || : > "${CRON_BACKUP_FILE}"
  crontab -r &>/dev/null || true

  trap _cleanup_and_exit ERR
  trap 'rm -f "${CRON_BACKUP_FILE}"' EXIT

  export ZDOTDIR="${ZDOTDIR:-"${HOME}"}"
  export ZSH="${ZSH:-"${ZDOTDIR}/.oh-my-zsh"}"
  export ZSH_CUSTOM="${ZSH_CUSTOM:-"${ZSH}/custom"}"

  # Note: Cannot load from shellrc since that file won't be present in a new machine (vanilla OS)
  # $EPOCHSECONDS is provided by the zsh/datetime built-in module — always available, no fork.
  # Capture start epoch into both a local variable and SCRIPT_START_TIMES.
  # The local is passed explicitly to print_script_duration at the end of main.
  # SCRIPT_START_TIMES is used by step_end (called throughout this script) to
  # compute the "total elapsed" column independently of the local variable.
  # Both are required; see the design note above step_timing_init in .shellrc.
  local script_start_time
  zmodload zsh/datetime
  script_start_time="${EPOCHSECONDS}"
  SCRIPT_START_TIMES+=("${script_start_time}")
  # strftime -s writes directly into a separate variable — preserves the epoch integer in script_start_time.
  local script_start_time_human
  strftime -s script_start_time_human '%Y-%m-%d %H:%M:%S' "${EPOCHSECONDS}"
  echo "==> Script started at: ${script_start_time_human}"

  ###############################
  # Do not allow rootless login #
  ###############################
  # Note: Commented out since I am not sure if we need to do this on the office MBP or not
  # section_header "$(yellow 'Verifying rootless login enabled status')"
  # if [[ "$(/usr/bin/csrutil status | awk '/status/ {print $5}' | sed 's/\.$//')" == "enabled" ]]; then
  #   error "rootless login is enabled. Please disable in boot screen and run again"
  #   exit 1 # Irrecoverable failure
  # fi

  ############################
  # Disable macos gatekeeper #
  ############################
  # section_header "$(yellow 'Disabling macos gatekeeper')"
  # sudo spectl --master-disable

  setup_jio_dns

  download_and_source_shellrc

  keep_sudo_alive

  approve_fingerprint_sudo

  ensure_filevault_is_on

  install_xcode_command_line_tools

  set_ssh_folder_permissions

  ensure_directories_exist

  install_oh_my_zsh_and_custom_plugins

  clone_dot_files_repo

  # run this outside of the clone function, since it needs to be run irrespective of whether the dotfiles repo was pre-existing or not
  append_to_path_if_dir_exists "${DOTFILES_DIR}/scripts"
  install-dotfiles.rb

  # Load all zsh config files for PATH and other env vars to take effect
  DEBUG=true load_zsh_configs

  install_homebrew

  if is_non_zero_string "${KEYBASE_USERNAME}"; then
    if ! command_exists keybase; then
      error 'Keybase not found in the PATH. Aborting!!!'
      exit 1 # Irrecoverable failure
    fi

    ######################
    # Login into keybase #
    ######################
    step_start
    debug "$(yellow 'Logging into keybase')"
    if keybase status --json 2>/dev/null | \grep -q '"logged_in":true'; then
      warn "Skipping keybase login since '$(yellow "${KEYBASE_USERNAME}")' is already logged in"
    elif ! keybase login; then
      error 'Could not login into keybase. Retry after logging in.'
      exit 1 # Irrecoverable failure
    fi
    step_end

    clone_home_repo

    clone_profiles_repo
  else
    warn "Skipping cloning of any keybase repo since '$(yellow 'KEYBASE_USERNAME')' has not been set"
  fi

  is_file "${SSH_CONFIGS_DIR}/known_hosts.old" && rm -f "${SSH_CONFIGS_DIR}/known_hosts.old"

  ###################################################################
  # Restore the preferences from the older machine into the new one #
  ###################################################################
  step_start
  section_header "$(yellow 'Restore preferences')"
  if command_exists 'osx-defaults.sh'; then
    osx-defaults.sh -s
    success 'Successfully baselines preferences'
  else
    warn "Skipping baselining of preferences since '$(yellow 'osx-defaults.sh')' couldn't be found in the PATH; Please baseline manually and follow it up with re-import of the backed-up preferences"
  fi

  if command_exists 'capture-prefs.sh'; then
    capture-prefs.sh -i
    success 'Successfully restored preferences from backup'
  else
    warn "Skipping importing of preferences since '$(yellow 'capture-prefs.sh')' couldn't be found in the PATH; Please set it up manually"
  fi

  if is_directory '/Applications/Sol.app' && ! pgrep -x 'Sol' &>/dev/null; then
    open /Applications/Sol.app
  fi
  step_end

  ################################
  # Recreate the zsh completions #
  ################################
  step_start
  section_header "$(yellow 'Recreate zsh completions')"
  rm -rf "${XDG_CACHE_HOME}/zcompdump"* &>/dev/null  || true
  autoload -Uz compinit && compinit -C -d "${XDG_CACHE_HOME}/zcompdump" &>/dev/null  || true
  step_end

  ###################
  # Setup cron jobs #
  ###################
  step_start
  section_header "$(yellow 'Setup cron jobs')"
  if command_exists recron; then
    # Remove the backup before calling recron so that if any subsequent step fails the EXIT trap
    # finds nothing to restore, preventing a stale backup file from persisting across runs.
    rm -f "${CRON_BACKUP_FILE}"
    recron
  else
    warn "Skipping setting up of cron jobs since '$(yellow 'recron')' couldn't be found; Please set it up manually"
  fi
  step_end

  ###########################
  # Resurrect tracked repos #
  ###########################
  # For now, to save time while re-imaging/setting up the laptop, we'll skip resurrecting all the tracked repos
  # resurrect_tracked_repos

  if command_exists allow_all_direnv_configs; then
    # HACKTAG: Can take a long time on FIRST_INSTALL (same as install_mise_versions). Running in background to be non-blocking
    allow_all_direnv_configs &!
  else
    warn "Skipping registering all direnv configs since '$(yellow 'allow_all_direnv_configs')' couldn't be found in the PATH; Please run it manually"
  fi

  if command_exists install_mise_versions; then
    # HACKTAG: For some reason this exits with an error code and can also take a long time on FIRST_INSTALL. Need to investigate a better fix
    install_mise_versions &!
  else
    warn "Skipping installation of languages since '$(yellow 'install_mise_versions')' couldn't be found in the PATH; Please run it manually"
  fi

  # To install the latest versions of the hex, rebar and phoenix packages
  # mix local.hex --force && mix local.rebar --force
  # mix archive.install hex phx_new 1.4.1

  # To install the native-image tool after graalvm is installed
  # gu install native-image

  # vagrant plugin install vagrant-vbguest

  # if installing jhipster for dot-net-core
  # TODO: Use the next line since the released version is only for .net 2.2:
  # npm i -g generator-jhipster-dotnetcore
  # Note: '-g' didnt work. Had to do 'npm init' and then use '--save-dev' to install and link as a local dependency
  # npm i -g jhipster/jhipster-dotnetcore
  # npm link generator-jhipster-dotnetcore
  # jhipster -d --blueprints dotnetcore

  # Default tooling for dotnet projects
  # dotnet tool install -g dotnet-sonarscanner
  # dotnet tool install -g dotnet-format

  success '** Finished auto installation process: Remember to do the following steps! **'
  warn "1. Run the 'bupc' alias to finish setting up all other applications managed by homebrew"
  warn "2. MANUALLY QUIT AND RESTART iTerm2 and Terminal apps"

  print_script_duration "${script_start_time}"
}

main "$@"
