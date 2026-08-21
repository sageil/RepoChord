run_completion() {
  if [[ "$#" -ne 1 ]]; then
    usage
    exit 2
  fi

  case "$1" in
    bash)
      print_bash_completion
      ;;
    zsh)
      print_zsh_completion
      ;;
    *)
      fail "Unsupported completion shell: $1" 2
      ;;
  esac
}
