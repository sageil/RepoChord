#!/usr/bin/env bash

set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
temporary_root="$(mktemp -d /private/tmp/repochord-completion-test.XXXXXX)"

cleanup() {
  rm -rf -- "$temporary_root"
}

trap cleanup EXIT

orders_repository="$temporary_root/orders"
storefront_repository="$temporary_root/storefront"
worker_repository="$temporary_root/worker"
coordinate_repository="$temporary_root/coordinate"
test_home="$temporary_root/home"
command_bin="$temporary_root/commands"
bash_completion="$temporary_root/repochord.bash"
zsh_completion="$temporary_root/_rchord"

for repository_path in "$orders_repository" "$storefront_repository" "$worker_repository"; do
  git init -q "$repository_path"
  git -C "$repository_path" config user.name "Completion Test"
  git -C "$repository_path" config user.email "completion-test@example.com"
  printf '# product\n' > "$repository_path/README.md"
  git -C "$repository_path" add README.md
  git -C "$repository_path" commit -m "test: initialize product" >/dev/null
done

mkdir -p "$test_home"
export HOME="$test_home"
export XDG_CONFIG_HOME="$test_home/.config"
unset XDG_BIN_HOME XDG_DATA_HOME REPOCHORD_CONFIG_HOME REPOCHORD_DATA_HOME

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

rchord_command="$command_bin/rchord"

HOME="$test_home" \
"$rchord_command" init \
  --project acme-commerce \
  --coordinate "$coordinate_repository" \
  --create-coordinate \
  --repository "orders-api=$orders_repository" \
  --repository "storefront=$storefront_repository" \
  --repository "_worker=$worker_repository" \
  >/dev/null

mkdir -p "$coordinate_repository/.repochord/results/ORDER-123-run-a1b2c3"
printf '{}\n' > "$coordinate_repository/.repochord/results/ORDER-123-run-a1b2c3/.manifest.json"
mkdir -p "$coordinate_repository/.repochord/results/.hidden-run"
printf '{}\n' > "$coordinate_repository/.repochord/results/.hidden-run/.manifest.json"

test "$(HOME="$test_home" "$rchord_command" __complete projects)" = "acme-commerce"
test "$({ HOME="$test_home" "$rchord_command" __complete repositories acme-commerce; } | tr '\n' ' ')" = "orders-api storefront _worker "
test "$({ HOME="$test_home" "$rchord_command" __complete runs acme-commerce; } | tr '\n' ' ')" = ".hidden-run ORDER-123-run-a1b2c3 "

empty_home="$temporary_root/empty-home"
mkdir -p "$empty_home"
test -z "$(HOME="$empty_home" XDG_CONFIG_HOME="$empty_home/.config" "$rchord_command" __complete projects)"

HOME="$test_home" "$rchord_command" completion bash > "$bash_completion"
HOME="$test_home" "$rchord_command" completion zsh > "$zsh_completion"

/bin/bash -n "$bash_completion"
zsh -n "$zsh_completion"

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  complete -p rchord >/dev/null
  COMP_WORDS=(rchord start --project acme)
  COMP_CWORD=3
  _rchord
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx acme-commerce

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(rchord cleanup --project acme-commerce --repository ord)
  COMP_CWORD=5
  _rchord
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx orders-api

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(rchord cleanup --a)
  COMP_CWORD=2
  _rchord
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx -- --all

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(rchord resume --project acme-commerce --run ORDER)
  COMP_CWORD=5
  _rchord
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx ORDER-123-run-a1b2c3

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(rchord resume --project acme-commerce --retry-blocked ord)
  COMP_CWORD=5
  _rchord
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx orders-api

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(rchord resume --m)
  COMP_CWORD=2
  _rchord
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx -- --max-attempts

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(rchord res)
  COMP_CWORD=1
  _rchord
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx resume

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(rchord integrate --project acme-commerce --run ORDER)
  COMP_CWORD=5
  _rchord
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx ORDER-123-run-a1b2c3

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(rchord integrate --show)
  COMP_CWORD=2
  _rchord
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx -- --show-diffs

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(rchord report --project acme-commerce --run ORDER)
  COMP_CWORD=5
  _rchord
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx ORDER-123-run-a1b2c3

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(rchord rep)
  COMP_CWORD=1
  _rchord
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx report

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(rchord up)
  COMP_CWORD=1
  _rchord
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx upgrade

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(rchord upgrade --)
  COMP_CWORD=2
  _rchord
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  > "$temporary_root/bash-upgrade-options.txt"

grep -Fqx -- --help "$temporary_root/bash-upgrade-options.txt"

if grep -Eq -- '^(--project|--coordinate|-p|-c)$' "$temporary_root/bash-upgrade-options.txt"; then
  echo "Bash completion offered a project selector for upgrade." >&2
  exit 1
fi

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(rchord list --d)
  COMP_CWORD=2
  _rchord
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx -- --details

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  whence -w _rchord >/dev/null
  whence -w _rchord_projects >/dev/null
' completion-test "$zsh_completion" "$temporary_root/zcompdump"

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(rchord cleanup --project acme-commerce --repository ord)
  CURRENT=6
  _rchord
' completion-test "$zsh_completion" "$temporary_root/zcompdump-behavior" \
  | grep -Fqx orders-api

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(rchord cleanup --a)
  CURRENT=3
  _rchord
' completion-test "$zsh_completion" "$temporary_root/zcompdump-cleanup-all" \
  | grep -Fqx -- --all

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(rchord resume --project acme-commerce --run ORDER)
  CURRENT=6
  _rchord
' completion-test "$zsh_completion" "$temporary_root/zcompdump-resume-run" \
  | grep -Fqx ORDER-123-run-a1b2c3

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(rchord resume --project acme-commerce --retry-blocked ord)
  CURRENT=6
  _rchord
' completion-test "$zsh_completion" "$temporary_root/zcompdump-resume-repository" \
  | grep -Fqx orders-api

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(rchord resume --m)
  CURRENT=3
  _rchord
' completion-test "$zsh_completion" "$temporary_root/zcompdump-resume-options" \
  | grep -Fqx -- --max-attempts

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(rchord res)
  CURRENT=2
  _rchord
' completion-test "$zsh_completion" "$temporary_root/zcompdump-resume-command" \
  | grep -Fqx resume

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(rchord integrate --project acme-commerce --run ORDER)
  CURRENT=6
  _rchord
' completion-test "$zsh_completion" "$temporary_root/zcompdump-run" \
  | grep -Fqx ORDER-123-run-a1b2c3

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(rchord integrate --show)
  CURRENT=3
  _rchord
' completion-test "$zsh_completion" "$temporary_root/zcompdump-show-diffs" \
  | grep -Fqx -- --show-diffs

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(rchord report --project acme-commerce --run ORDER)
  CURRENT=6
  _rchord
' completion-test "$zsh_completion" "$temporary_root/zcompdump-report-run" \
  | grep -Fqx ORDER-123-run-a1b2c3

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(rchord rep)
  CURRENT=2
  _rchord
' completion-test "$zsh_completion" "$temporary_root/zcompdump-report-command" \
  | grep -Fqx report

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(rchord up)
  CURRENT=2
  _rchord
' completion-test "$zsh_completion" "$temporary_root/zcompdump-upgrade-command" \
  | grep -Fqx upgrade

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(rchord upgrade --)
  CURRENT=3
  _rchord
' completion-test "$zsh_completion" "$temporary_root/zcompdump-upgrade-options" \
  > "$temporary_root/zsh-upgrade-options.txt"

grep -Fqx -- --help "$temporary_root/zsh-upgrade-options.txt"

if grep -Eq -- '^(--project|--coordinate|-p|-c)$' "$temporary_root/zsh-upgrade-options.txt"; then
  echo "Zsh completion offered a project selector for upgrade." >&2
  exit 1
fi

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(rchord list --d)
  CURRENT=3
  _rchord
' completion-test "$zsh_completion" "$temporary_root/zcompdump-list" \
  | grep -Fqx -- --details

if HOME="$test_home" "$rchord_command" completion fish >/dev/null 2>&1; then
  echo "RepoChord unexpectedly generated a completion for an unsupported shell." >&2
  exit 1
fi

echo "Completion tests passed."
