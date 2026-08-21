
if [[ "$#" -gt 0 ]]; then
  case "$1" in
    -h|--help|help)
      usage
      exit 0
      ;;
  esac
fi

initialize_locations

if [[ "$#" -eq 0 ]]; then
  run_start
  exit
fi

case "$1" in
  init)
    shift
    run_init "$@"
    ;;
  config)
    shift
    run_config "$@"
    ;;
  list)
    shift
    run_list "$@"
    ;;
  upgrade)
    shift
    run_upgrade "$@"
    ;;
  validate)
    shift
    run_validate "$@"
    ;;
  report)
    shift
    run_report "$@"
    ;;
  cleanup)
    shift
    run_cleanup "$@"
    ;;
  integrate)
    shift
    run_integrate "$@"
    ;;
  resume)
    shift
    run_resume "$@"
    ;;
  completion)
    shift
    run_completion "$@"
    ;;
  __complete)
    shift
    run_completion_candidates "$@"
    ;;
  start)
    shift
    run_start "$@"
    ;;
  *)
    run_start "$@"
    ;;
esac
