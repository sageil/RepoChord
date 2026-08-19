#!/usr/bin/env bash

set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repository_directory="$(cd -- "$test_directory/.." && pwd -P)"
temporary_root="$(mktemp -d /private/tmp/repomux-completion-test.XXXXXX)"

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
bash_completion="$temporary_root/repomux.bash"
zsh_completion="$temporary_root/_repomux"

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
unset XDG_BIN_HOME XDG_DATA_HOME REPOMUX_CONFIG_HOME REPOMUX_DATA_HOME

HOME="$test_home" \
"$repository_directory/install.sh" \
  --bin-dir "$command_bin" \
  >/dev/null

repomux_command="$command_bin/repomux"

HOME="$test_home" \
"$repomux_command" init \
  --project acme-commerce \
  --coordinate "$coordinate_repository" \
  --create-coordinate \
  --repository "orders-api=$orders_repository" \
  --repository "storefront=$storefront_repository" \
  --repository "_worker=$worker_repository" \
  >/dev/null

mkdir -p "$coordinate_repository/.repomux/results/ORDER-123-run-a1b2c3"
printf '{}\n' > "$coordinate_repository/.repomux/results/ORDER-123-run-a1b2c3/.manifest.json"
mkdir -p "$coordinate_repository/.repomux/results/.hidden-run"
printf '{}\n' > "$coordinate_repository/.repomux/results/.hidden-run/.manifest.json"

test "$(HOME="$test_home" "$repomux_command" __complete projects)" = "acme-commerce"
test "$({ HOME="$test_home" "$repomux_command" __complete repositories acme-commerce; } | tr '\n' ' ')" = "orders-api storefront _worker "
test "$({ HOME="$test_home" "$repomux_command" __complete runs acme-commerce; } | tr '\n' ' ')" = ".hidden-run ORDER-123-run-a1b2c3 "

empty_home="$temporary_root/empty-home"
mkdir -p "$empty_home"
test -z "$(HOME="$empty_home" XDG_CONFIG_HOME="$empty_home/.config" "$repomux_command" __complete projects)"

HOME="$test_home" "$repomux_command" completion bash > "$bash_completion"
HOME="$test_home" "$repomux_command" completion zsh > "$zsh_completion"

/bin/bash -n "$bash_completion"
zsh -n "$zsh_completion"

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  complete -p repomux >/dev/null
  COMP_WORDS=(repomux start --project acme)
  COMP_CWORD=3
  _repomux
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx acme-commerce

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(repomux cleanup --project acme-commerce --repository ord)
  COMP_CWORD=5
  _repomux
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx orders-api

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(repomux integrate --project acme-commerce --run ORDER)
  COMP_CWORD=5
  _repomux
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx ORDER-123-run-a1b2c3

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(repomux report --project acme-commerce --run ORDER)
  COMP_CWORD=5
  _repomux
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx ORDER-123-run-a1b2c3

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(repomux rep)
  COMP_CWORD=1
  _repomux
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx report

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(repomux up)
  COMP_CWORD=1
  _repomux
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx upgrade

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(repomux upgrade --)
  COMP_CWORD=2
  _repomux
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
  COMP_WORDS=(repomux list --d)
  COMP_CWORD=2
  _repomux
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx -- --details

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(repomux start --agent-output q)
  COMP_CWORD=3
  _repomux
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx quiet

HOME="$test_home" \
PATH="$command_bin:$PATH" \
/bin/bash -c '
  source "$1"
  COMP_WORDS=(repomux config set agent-output p)
  COMP_CWORD=4
  _repomux
  printf "%s\n" "${COMPREPLY[@]}"
' completion-test "$bash_completion" \
  | grep -Fqx progress

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  whence -w _repomux >/dev/null
  whence -w _repomux_projects >/dev/null
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
  words=(repomux cleanup --project acme-commerce --repository ord)
  CURRENT=6
  _repomux
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
  words=(repomux integrate --project acme-commerce --run ORDER)
  CURRENT=6
  _repomux
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
  words=(repomux report --project acme-commerce --run ORDER)
  CURRENT=6
  _repomux
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
  words=(repomux rep)
  CURRENT=2
  _repomux
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
  words=(repomux up)
  CURRENT=2
  _repomux
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
  words=(repomux upgrade --)
  CURRENT=3
  _repomux
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
  words=(repomux list --d)
  CURRENT=3
  _repomux
' completion-test "$zsh_completion" "$temporary_root/zcompdump-list" \
  | grep -Fqx -- --details

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(repomux start --agent-output q)
  CURRENT=4
  _repomux
' completion-test "$zsh_completion" "$temporary_root/zcompdump-agent-output" \
  | grep -Fqx quiet

HOME="$test_home" \
PATH="$command_bin:$PATH" \
zsh -fc '
  autoload -Uz compinit
  compinit -d "$2"
  source "$1"
  compadd() {
    print -l -- "$@"
  }
  words=(repomux config set agent-output p)
  CURRENT=5
  _repomux
' completion-test "$zsh_completion" "$temporary_root/zcompdump-config-agent-output" \
  | grep -Fqx progress

if HOME="$test_home" "$repomux_command" completion fish >/dev/null 2>&1; then
  echo "RepoMux unexpectedly generated a completion for an unsupported shell." >&2
  exit 1
fi

echo "Completion tests passed."
