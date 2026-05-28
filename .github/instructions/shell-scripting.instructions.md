---
applyTo: "**/*.sh,**/.shellrc,**/.aliases,**/.envrc,**/.zsh*,**/files/--HOME--/*,**/files/--ZDOTDIR--/*"
---

# Shell Script Instructions

Apply these rules when writing or editing any shell script in this repository.

Syntax choices follow the decision-making priority defined in
`copilot-instructions.md` (startup speed + maintainability first; POSIX and
zsh built-ins where they do not conflict with those). Document the tradeoff in
a comment when they conflict.

## Script Skeleton

```zsh
#!/usr/bin/env zsh
# shellcheck shell=zsh
# file location: <describe where this file is symlinked/used>
#
# <One-line description of the script>
#
# Usage: <script-name> [options]

set -euo pipefail

# ---------------------------------------------------------------------------
# Re-source guard is inside .shellrc itself — safe to call unconditionally.
source "${HOME}/.shellrc"

# ---------------------------------------------------------------------------
# Constants / Config
readonly SCRIPT_NAME="${0:t}"

# ---------------------------------------------------------------------------
# Usage

usage() {
  cat <<EOF
$(yellow "Usage:") $(cyan "${SCRIPT_NAME}") [options]

  Description of what this script does.

$(yellow "Options:")
  $(yellow "-f") <file>   Description of -f
  $(yellow "-h")          Show this help
EOF
}

# ---------------------------------------------------------------------------
# Private helpers

_helper_function() {
  # ...
}

# ---------------------------------------------------------------------------
# Main

main() {
  local flag=""

  while getopts ":fh" opt; do
    case "${opt}" in
      f) flag=true ;;
      h) usage; return 0 ;;
      :) warn "Option -${OPTARG} requires an argument."; usage; return 1 ;;
      ?) warn "Unknown option: -${OPTARG}"; usage; return 1 ;;
    esac
  done
  shift $(( OPTIND - 1 ))

  # ... main logic ...
}

main "$@"
```

## Quoting and Variable References

### Always Quote Variables

Always quote variables to prevent word-splitting and glob expansion when the
value is used in a context where it could contain spaces:

```zsh
# Good — quoted, safe if value contains spaces
cp "${src_file}" "${dest_dir}/"
[[ -f "${config_path}" ]]
info "Processing ${filename}"

# BAD — unquoted, breaks if value contains spaces
cp $src_file $dest_dir/
[[ -f $config_path ]]
info "Processing $filename"
```

### Single Quotes vs Double Quotes

Prefer **single quotes** for static strings that contain no variable references
or command substitutions. Use **double quotes** when the string contains a
variable reference or needs escape interpretation:

```zsh
# Good — single quotes for static strings
local sep='------'
grep -q 'pattern'
error 'File not found'

# Good — double quotes when expanding variables
local msg="Processing ${repo_name}"
source "${HOME}/.shellrc"
info "Done: ${count} files processed"

# BAD — double quotes on strings with no variable expansion (unnecessary)
local sep="------"
grep -q "pattern"   # fine if no special chars, but prefer single quotes
```

### `${var}` Brace Notation

Always use `${var}` brace notation (not bare `$var`) to unambiguously delimit
the variable name. This prevents accidental concatenation bugs and makes the
boundary of the variable name visually clear:

```zsh
# Good
echo "${HOME}/.config"
local path="${DOTFILES_DIR}/scripts"
info "Repo: ${repo_name}_backup"   # without braces, _backup would be part of name

# BAD
echo "$HOME/.config"
local path="$DOTFILES_DIR/scripts"
```

Exception: `$?`, `$#`, `$@`, `$*`, `$$`, `$!`, `$-` — the single-character
special parameters do not need braces.

## Positional Parameters

Always guard positional parameters with a default to avoid `unbound variable`
errors under `set -u`:

```zsh
local arg="${1:-}"   # Good
local arg="$1"       # BAD under set -u if $1 not provided
```

## Pipelines with `grep`

`grep -q` in a pipeline under `set -o pipefail` causes SIGPIPE:

```zsh
# BAD
some_command | grep -q "pattern"

# Good
some_command | grep -q "pattern" || true
# Or better, capture output first
output=$(some_command)
is_non_zero_string "${output}" && echo "${output}" | grep -q "pattern"
```

## Function Visibility

Internal helpers not called by external scripts must be prefixed with `_`:

```zsh
_internal_helper() { ... }   # private
public_function() { ... }    # public (no prefix)
```

## `source` vs `load_file_if_exists`

`load_file_if_exists` is defined in `.shellrc` and is only available **after**
`.shellrc` has been downloaded and sourced. The rule is:

- **Before `.shellrc` is sourced** (e.g., early boot of `fresh-install` on a
  vanilla OS): use plain `source` with an explicit existence check, or accept
  that the file must be present.
- **After `.shellrc` is sourced**: always prefer `load_file_if_exists` over
  `source` for any file that may not exist on all machines or in all scenarios.

```zsh
# Early boot — .shellrc not yet available, use source with guard
[[ -f "${HOME}/.shellrc" ]] && source "${HOME}/.shellrc"

# After .shellrc is sourced — use load_file_if_exists
load_file_if_exists "${ZDOTDIR}/.some-optional-file"
```

## Array Operations

```zsh
# Declare associative arrays explicitly to avoid parameter-not-set errors
typeset -A my_assoc_array

# Check empty/non-empty
is_empty_array my_arr       # instead of [[ ${#my_arr[@]} -eq 0 ]]
is_non_empty_array my_arr   # instead of [[ ${#my_arr[@]} -gt 0 ]]

# Join
result=$(join_array ", " "${my_arr[@]}")
```

## `.envrc` Special Rules

`.envrc` files run in a **bash** subshell via direnv. They must:
- Use POSIX syntax only (no `(( $+functions[...] ))`, no `${(j::)arr}`)
- Source `.shellrc` unconditionally — do NOT guard with `type is_shellrc_sourced`
- Add comment: `# direnv runs this in a bash subshell — source unconditionally`

## Comment Format

```zsh
################################################################################
# file-header.sh
# Purpose: ...
################################################################################

# ---------------------------------------------------------------------------
# Section Name

# Individual function comments use plain #
function_name() {
  # Implementation detail comment
}
```

## Formatting After Every Edit

After every edit to a shell script, reformat with `shfmt`:

```zsh
shfmt -w <file>
```

**shfmt has no inline per-line or per-block ignore directive.** Whole files can
be excluded via `.shfmtignore`, but only for two valid reasons:

1. The file contains zsh-only syntax that shfmt cannot parse (e.g. `${^array}`,
   `for key value in "${(@kv)assoc}"`).
2. The file hits a shfmt bug where one-liners inside loop or push bodies are
   forcibly expanded into unreadable multi-line form with no way to suppress it.

Do not add files to `.shfmtignore` for any other reason.
