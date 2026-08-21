scaffolder="$coordinate_repository/.agents/skills/repochord/scripts/scaffold-feature.sh"
packet_fixture="$test_directory/fixtures/complete-scaffolded-packet.sh"

"$scaffolder" PROJECT-123 api web >/dev/null

test ! -e "$coordinate_repository/requests/PROJECT-123.md"
test ! -e "$coordinate_repository/tasks/PROJECT-123/api.md"
test ! -e "$coordinate_repository/tasks/PROJECT-123/web.md"
test -f "$coordinate_repository/tasks/PROJECT-123/assignments.txt"

"$scaffolder" editable-shipping-address api web >/dev/null
existing_request="$coordinate_repository/requests/editable-shipping-address.md"
existing_assignments="$coordinate_repository/tasks/editable-shipping-address/assignments.txt"
existing_assignments_hash="$(git hash-object "$existing_assignments")"
resolved_output="$("$scaffolder" --title "Editable shipping address" api web)"
resolved_request_path="${resolved_output%%$'\n'*}"
resolved_assignment_path="${resolved_output#*$'\n'}"
resolved_assignment_path="${resolved_assignment_path%%$'\n'*}"
case_variant_output="$("$scaffolder" EDITABLE-SHIPPING-ADDRESS api web)"
case_variant_request_path="${case_variant_output%%$'\n'*}"
case_variant_assignment_path="${case_variant_output#*$'\n'}"
case_variant_assignment_path="${case_variant_assignment_path%%$'\n'*}"

test "$resolved_request_path" = "$existing_request"
test "$resolved_assignment_path" = "$existing_assignments"
test "$case_variant_request_path" = "$existing_request"
test "$case_variant_assignment_path" = "$existing_assignments"
test ! -e "$existing_request"
test "$existing_assignments_hash" = "$(git hash-object "$existing_assignments")"

if find "$coordinate_repository/tasks" -maxdepth 1 -name 'editable-shipping-address-*' -print -quit | grep -q .; then
  echo "Scaffolder created a duplicate for an existing normalized feature title." >&2
  exit 1
fi

generated_output="$("$scaffolder" --title "Customer order cancellation" api web)"
generated_request_path="${generated_output%%$'\n'*}"
generated_assignment_path="${generated_output#*$'\n'}"
generated_assignment_path="${generated_assignment_path%%$'\n'*}"
generated_feature_filename="$(basename -- "$generated_request_path")"
generated_feature_id="${generated_feature_filename%.md}"
generated_feature_prefix="customer-order-cancellation-"
generated_feature_suffix="${generated_feature_id#"$generated_feature_prefix"}"

if [[ "$generated_feature_id" != "$generated_feature_prefix"* || \
  ! "$generated_feature_suffix" =~ ^[a-z0-9]+$ || \
  "${#generated_feature_suffix}" -ne 6 ]]
then
  echo "Scaffolder returned an invalid generated feature ID: $generated_feature_id" >&2
  exit 1
fi

test "$generated_assignment_path" = "$coordinate_repository/tasks/$generated_feature_id/assignments.txt"
test ! -e "$generated_request_path"
test ! -e "$coordinate_repository/tasks/$generated_feature_id/api.md"
test ! -e "$coordinate_repository/tasks/$generated_feature_id/web.md"

second_generated_output="$("$scaffolder" --title "Customer order cancellation" api web)"
second_generated_request_path="${second_generated_output%%$'\n'*}"
second_generated_feature_filename="$(basename -- "$second_generated_request_path")"
second_generated_feature_id="${second_generated_feature_filename%.md}"

if [[ "$second_generated_feature_id" == "$generated_feature_id" ]]; then
  echo "Scaffolder generated a duplicate feature ID." >&2
  exit 1
fi

if [[ -n "$(find "$coordinate_repository" -maxdepth 1 -name '.repochord-feature-id.*' -print -quit)" ]]; then
  echo "Scaffolder left an identifier reservation behind." >&2
  exit 1
fi

"$packet_fixture" "$coordinate_repository" PROJECT-123

touch "$api_repository/preflight-dirty.tmp"
runner="$coordinate_repository/.agents/skills/repochord/scripts/run-repository-agents.sh"

if "$runner" \
  PROJECT-123-preflight \
  "$coordinate_repository/tasks/PROJECT-123/assignments.txt" \
  >/dev/null 2>&1
then
  echo "Runner unexpectedly accepted a dirty product repository." >&2
  exit 1
fi

test ! -e "$coordinate_repository/.repochord/results/PROJECT-123-preflight"
rm -f -- "$api_repository/preflight-dirty.tmp"

existing_explicit_output="$("$scaffolder" PROJECT-123 api web)"
existing_explicit_request="${existing_explicit_output%%$'\n'*}"
existing_explicit_assignments="${existing_explicit_output#*$'\n'}"
existing_explicit_assignments="${existing_explicit_assignments%%$'\n'*}"
test "$existing_explicit_request" = "$coordinate_repository/requests/PROJECT-123.md"
test "$existing_explicit_assignments" = "$coordinate_repository/tasks/PROJECT-123/assignments.txt"

printf '\nlocal change\n' >> "$coordinate_repository/.agents/skills/repochord/SKILL.md"
printf 'obsolete project runtime file\n' > "$coordinate_repository/.agents/skills/repochord/obsolete.txt"

HOME="$test_home" "$rchord_command" init \
  --project acme-commerce \
  --coordinate "$coordinate_repository" \
  --repository "api=$api_repository" \
  --repository "web=$web_repository" \
  >/dev/null

diff -qr "$installed_data/skill" "$coordinate_repository/.agents/skills/repochord" >/dev/null
diff -qr "$installed_data/task-skill" "$coordinate_repository/.agents/skills/create-repochord-task" >/dev/null
test ! -e "$coordinate_repository/.agents/skills/repochord/obsolete.txt"

echo "Installer tests passed."
