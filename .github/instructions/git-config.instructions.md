---
applyTo: "**/.gitconfig,**/custom.gitattributes,**/add-upstream-git-config.sh"
---

# Git Configuration Instructions

## `~/.gitconfig` Aliases

Aliases that use shell commands must use `!sh -c '...' -` to properly handle
the `-C <dir>` flag:

```ini
# BAD — does not honour -C
my-alias = !git some-command

# Good — honours -C via $1 defaulting to current dir
my-alias = !sh -c 'git -C "${1:-.}" some-command' -
```

For aliases that accept additional arguments, pass them through with `"$@"`:

```ini
pull-unshallow = !sh -c 'cd "${1:-.}" && shift && git fetch --unshallow "$@" && git pull "$@"' -
```

## Shallow Clone Aliases

- `git fetch-unshallow`: fetch and unshallow if repo is shallow. Guards against
  `--unshallow` on already-complete repos (which fails).
- `git pull-unshallow`: pull and unshallow in one step.

```ini
fetch-unshallow = !sh -c 'git -C "${1:-.}" rev-parse --is-shallow-repository | grep -q true && git -C "${1:-.}" fetch --unshallow || git -C "${1:-.}" fetch' -
```

## `git sci` (Stage + Commit Interactive)

Must check for diverged state before attempting `--amend`:

```ini
sci = !sh -c 'git status --porcelain | grep -q . && git add -p && \
  git status --short && git log --oneline -1 && \
  git diff --cached --stat && \
  git diff @{u}..HEAD --name-only 2>/dev/null | grep -q . \
    && git commit || git commit --amend' -
```

## `git size`

Use three subshell invocations for clarity (human-triggered, not in startup):

```ini
size = !sh -c 'echo "Working tree: $(du -sh . | cut -f1)"; echo "Git objects: $(git count-objects -vH | grep size-pack | cut -d: -f2)"; echo "Largest objects: $(git rev-list --all --objects | sort -k2 | uniq -f1 | sort -rn | head -5)"' -
```

## Aliases and `!` Functions

For complex logic, prefer the named function pattern for readability:

```ini
[alias]
  my-cmd = "!f() { git -C \"${1:-.}\" command; }; f"
```

Simpler single-command aliases can use `!git` directly:

```ini
  st = status --short --branch
```

## `.gitattributes`

`install-dotfiles.rb` copies `custom.gitattributes` to `.gitattributes` in the
appropriate directory. Always edit `custom.gitattributes`, not `.gitattributes`
directly.

Binary file types must be marked binary:

```gitattributes
*.defaults  binary
*.zwc       binary
```
