if [[ "${#incomplete_repositories[@]}" -eq 0 ]]; then
  overall_status="completed"
else
  overall_status="incomplete"
fi

if [[ "${#integrated_repositories[@]}" -eq 0 ]]; then
  integrated_list="none"
else
  integrated_list=""

  for repository_key in "${integrated_repositories[@]}"; do
    if [[ -n "$integrated_list" ]]; then
      integrated_list+=", "
    fi

    integrated_list+="$repository_key"
  done
fi

if [[ "$overall_status" == "completed" ]]; then
  incomplete_list="none"
else
  incomplete_list=""

  for repository_key in "${incomplete_repositories[@]}"; do
    if [[ -n "$incomplete_list" ]]; then
      incomplete_list+=", "
    fi

    incomplete_list+="$repository_key"
  done
fi
