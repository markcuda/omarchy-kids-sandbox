# shellcheck shell=bash
# lib/session-manifest.sh -- one root-owned, schema-versioned session input.
# It snapshots effective profile data and the launcher map so later session
# surfaces consume one document instead of rebuilding state in a kid session.

SESSION_MANIFEST_SCHEMA=1

session_manifest_dir() { printf '%s/sessions\n' "$ETC"; }
session_manifest_path() { printf '%s/%s.json\n' "$(session_manifest_dir)" "$1"; }

session_manifest_error() {
  echo "session-manifest: $*" >&2
  return 1
}

session_manifest_valid_account() {
  [[ "$1" =~ ^kid-[a-z0-9]+(-[0-9]+)?$ ]]
}

session_manifest_profile_value() {
  local account="$1" key="$2" value
  value="$("$CONF_BIN" get "$account" "$key" 2>/dev/null)" || {
    session_manifest_error "cannot resolve '$key' for '$account'"
    return 1
  }
  [[ -n "$value" ]] || {
    session_manifest_error "profile '$account' has an empty '$key'"
    return 1
  }
  printf '%s\n' "$value"
}

session_manifest_validate_profile() {
  local account="$1" profile="$KIDS_DIR/$1.conf" value band avatar
  session_manifest_valid_account "$account" || {
    session_manifest_error "invalid kid account '$account'"
    return 1
  }
  [[ -f "$profile" && ! -L "$profile" ]] || {
    session_manifest_error "profile '$account' is missing or linked"
    return 1
  }

  value="$(session_manifest_profile_value "$account" name)" || return 1
  [[ "$value" != *$'\n'* ]] || {
    session_manifest_error "profile '$account' has an invalid name"
    return 1
  }
  avatar="$(session_manifest_profile_value "$account" avatar)" || return 1
  [[ "$avatar" =~ ^[a-z0-9][a-z0-9-]*$ ]] || {
    session_manifest_error "profile '$account' has an invalid avatar"
    return 1
  }
  [[ -f "$SHARE/avatars/$avatar.svg" && ! -L "$SHARE/avatars/$avatar.svg" ]] || {
    session_manifest_error "profile '$account' has no package avatar '$avatar'"
    return 1
  }
  band="$(session_manifest_profile_value "$account" band)" || return 1
  is_valid_band "$band" || {
    session_manifest_error "profile '$account' has an invalid band '$band'"
    return 1
  }

  value="$(session_manifest_profile_value "$account" level)" || return 1
  [[ "$value" =~ ^[123]$ ]] || {
    session_manifest_error "profile '$account' has an invalid level '$value'"
    return 1
  }
  value="$(session_manifest_profile_value "$account" theme)" || return 1
  [[ "$value" =~ ^[a-z0-9][a-z0-9-]*$ ]] || {
    session_manifest_error "profile '$account' has an invalid theme"
    return 1
  }
  value="$(session_manifest_profile_value "$account" web)" || return 1
  is_in "$value" garden filtered none || {
    session_manifest_error "profile '$account' has an invalid web mode '$value'"
    return 1
  }
  return 0
}

session_manifest_validate_time() {
  local account="$1" key value
  for key in budget_min budget_min_weekend; do
    value="$(session_manifest_profile_value "$account" "$key")" || return 1
    [[ "$value" =~ ^[0-9]+$ ]] && ((10#$value >= 1 && 10#$value <= 1440)) || {
      session_manifest_error "profile '$account' has an invalid '$key'"
      return 1
    }
  done
  for key in lights_out lights_out_weekend; do
    value="$(session_manifest_profile_value "$account" "$key")" || return 1
    [[ "$value" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || {
      session_manifest_error "profile '$account' has an invalid '$key'"
      return 1
    }
  done
}

session_manifest_allowlist_json() {
  local account="$1" apps_bin allowlist id
  local -a ids
  apps_bin="$(kids_bin apps "$DIR")"
  allowlist="$(OMARCHY_KIDS_ETC="$ETC" OMARCHY_KIDS_SHARE="$SHARE" \
    "$apps_bin" allowlist "$account" 2>/dev/null)" || {
    session_manifest_error "cannot resolve launcher allowlist for '$account'"
    return 1
  }
  IFS=',' read -ra ids <<<"$allowlist"
  for id in "${ids[@]+${ids[@]}}"; do
    [[ -z "$id" || "$id" =~ ^[a-z0-9_-]+$ ]] || {
      session_manifest_error "profile '$account' has an invalid launcher id '$id'"
      return 1
    }
  done
  jq -Rn --arg allowlist "$allowlist" '$allowlist | split(",") | map(select(length > 0))'
}

session_manifest_map_is_valid() {
  local map="$1"
  jq -e '
    type == "object" and (.tiles | type == "array") and
    all(.tiles[];
      (.id | type == "string") and
      (.label | type == "string") and
      (.icon | type == "string") and
      (.installed | type == "boolean") and
      (.argv | type == "array") and
      ((.installed == false and (.argv | length) == 0) or
       (.installed == true and (.argv | length) > 0)) and
      (.installed == false or (.argv[0] | type == "string" and startswith("/"))))
  ' "$map" >/dev/null
}

session_manifest_render() {
  local account="$1" output="$2" map name avatar band level theme web policy_id
  local budget_min budget_min_weekend lights_out lights_out_weekend allowlist
  map="$(mktemp)"
  if ! launcher_map_render "$account" "$map"; then
    rm -f "$map"
    return 1
  fi
  if ! session_manifest_map_is_valid "$map"; then
    rm -f "$map"
    session_manifest_error "launcher map for '$account' is invalid"
    return 1
  fi

  name="$(session_manifest_profile_value "$account" name)" || {
    rm -f "$map"
    return 1
  }
  avatar="$(session_manifest_profile_value "$account" avatar)" || {
    rm -f "$map"
    return 1
  }
  band="$(session_manifest_profile_value "$account" band)" || {
    rm -f "$map"
    return 1
  }
  level="$(session_manifest_profile_value "$account" level)" || {
    rm -f "$map"
    return 1
  }
  theme="$(session_manifest_profile_value "$account" theme)" || {
    rm -f "$map"
    return 1
  }
  web="$(session_manifest_profile_value "$account" web)" || {
    rm -f "$map"
    return 1
  }
  budget_min="$(session_manifest_profile_value "$account" budget_min)" || {
    rm -f "$map"
    return 1
  }
  budget_min_weekend="$(session_manifest_profile_value "$account" budget_min_weekend)" || {
    rm -f "$map"
    return 1
  }
  lights_out="$(session_manifest_profile_value "$account" lights_out)" || {
    rm -f "$map"
    return 1
  }
  lights_out_weekend="$(session_manifest_profile_value "$account" lights_out_weekend)" || {
    rm -f "$map"
    return 1
  }
  allowlist="$(session_manifest_allowlist_json "$account")" || {
    rm -f "$map"
    return 1
  }
  policy_id="omarchy-kids-$band"

  jq -n --arg account "$account" --arg name "$name" --arg avatar "$avatar" \
    --arg band "$band" --argjson level "$level" --arg theme "$theme" \
    --argjson allowlist "$allowlist" --arg web "$web" --arg policy_id "$policy_id" \
    --argjson budget_min "$budget_min" --argjson budget_min_weekend "$budget_min_weekend" \
    --arg lights_out "$lights_out" --arg lights_out_weekend "$lights_out_weekend" \
    --argjson tiles "$(jq '[.tiles[] | {id, label, icon, installed, argv}]' "$map")" \
    '{schema_version: 1, account: $account, name: $name, avatar: $avatar,
      band: $band, level: $level, theme: $theme, allowlist: $allowlist,
      web: $web, policy_id: $policy_id, budget_min: $budget_min,
      budget_min_weekend: $budget_min_weekend, lights_out: $lights_out,
      lights_out_weekend: $lights_out_weekend, tiles: $tiles}' >"$output"
  rm -f "$map"
}

session_manifest_json_is_valid() {
  local account="$1" file="$2"
  jq -e --arg account "$account" --argjson schema "$SESSION_MANIFEST_SCHEMA" '
    type == "object" and .schema_version == $schema and .account == $account and
    (.name | type == "string" and length > 0) and
    (.avatar | type == "string" and test("^[a-z0-9][a-z0-9-]*$")) and
    (.band | type == "string") and (.level | type == "number" and . >= 1 and . <= 3) and
    (.theme | type == "string" and length > 0) and
    (.allowlist | type == "array" and all(.[]; type == "string")) and
    (.web | type == "string" and (IN("garden", "filtered", "none"))) and
    (.policy_id | type == "string" and length > 0) and
    (.budget_min | type == "number" and . >= 1 and . <= 1440) and
    (.budget_min_weekend | type == "number" and . >= 1 and . <= 1440) and
    (.lights_out | type == "string" and test("^([01][0-9]|2[0-3]):[0-5][0-9]$")) and
    (.lights_out_weekend | type == "string" and test("^([01][0-9]|2[0-3]):[0-5][0-9]$")) and
    (.tiles | type == "array") and
    all(.tiles[];
      (.id | type == "string") and (.label | type == "string") and
      (.icon | type == "string") and (.installed | type == "boolean") and
      (.argv | type == "array") and all(.argv[]; type == "string") and
      ((.installed == false and (.argv | length) == 0) or
       (.installed == true and (.argv | length) > 0)) and
      (.installed == false or (.argv[0] | type == "string" and startswith("/")))) and
    (keys | length == 15) and
    all(keys[]; IN("schema_version", "account", "name", "avatar", "band", "level", "theme",
      "allowlist", "web", "policy_id", "budget_min", "budget_min_weekend", "lights_out",
      "lights_out_weekend", "tiles"))
  ' "$file" >/dev/null
}

session_manifest_owner_ok() {
  local account="$1" file dir
  file="$(session_manifest_path "$account")"
  dir="$(session_manifest_dir)"
  is_root || return 0
  [[ "$(file_stat u "$file")" == 0 && "$(file_stat G "$file")" == root ]] || {
    session_manifest_error "manifest '$account' is not root:root"
    return 1
  }
  [[ "$(file_stat u "$dir")" == 0 && "$(file_stat G "$dir")" == omarchy-kids ]] || {
    session_manifest_error "sessions directory is not root:omarchy-kids"
    return 1
  }
}

session_manifest_build() {
  local account="$1" dir stage target
  session_manifest_valid_account "$account" || {
    session_manifest_error "invalid kid account '$account'"
    return 1
  }
  session_manifest_validate_profile "$account" || return 1
  session_manifest_validate_time "$account" || return 1
  dir="$(session_manifest_dir)"
  [[ ! -L "$dir" && (! -e "$dir" || -d "$dir") ]] || {
    session_manifest_error "sessions path '$dir' is not a directory"
    return 1
  }
  install -d -m 0750 "$dir" || {
    session_manifest_error "cannot create '$dir'"
    return 1
  }
  chmod 0750 "$dir" || {
    session_manifest_error "cannot set mode on '$dir'"
    return 1
  }
  if is_root; then
    chown root:omarchy-kids "$dir" || {
      session_manifest_error "cannot set '$dir' to root:omarchy-kids"
      return 1
    }
  else
    chown root:omarchy-kids "$dir" >/dev/null 2>&1 || true
  fi
  target="$(session_manifest_path "$account")"
  stage="$(mktemp "$dir/.$account.XXXXXX")" || {
    session_manifest_error "cannot stage '$target'"
    return 1
  }
  if ! session_manifest_render "$account" "$stage" || ! session_manifest_json_is_valid "$account" "$stage"; then
    rm -f "$stage"
    session_manifest_error "build failed for '$account'; existing manifest was preserved"
    return 1
  fi
  chmod 0644 "$stage" || {
    rm -f "$stage"
    session_manifest_error "cannot set mode on '$target'"
    return 1
  }
  if is_root; then
    chown root:root "$stage" || {
      rm -f "$stage"
      session_manifest_error "cannot set '$target' to root:root"
      return 1
    }
  else
    chown root:root "$stage" >/dev/null 2>&1 || true
  fi
  mv -f "$stage" "$target" || {
    rm -f "$stage"
    session_manifest_error "cannot replace '$target'"
    return 1
  }
}

session_manifest_check() {
  local account="$1" file expected
  session_manifest_valid_account "$account" || {
    session_manifest_error "invalid kid account '$account'"
    return 1
  }
  file="$(session_manifest_path "$account")"
  [[ -f "$file" && ! -L "$file" ]] || {
    session_manifest_error "manifest '$account' is missing or linked"
    return 1
  }
  [[ "$(file_stat a "$file")" == 644 ]] || {
    session_manifest_error "manifest '$account' has the wrong mode"
    return 1
  }
  session_manifest_owner_ok "$account" || return 1
  if ! session_manifest_json_is_valid "$account" "$file"; then
    session_manifest_error "manifest '$account' is malformed or has the wrong schema"
    return 1
  fi
  expected="$(mktemp)"
  if ! session_manifest_validate_profile "$account" || ! session_manifest_validate_time "$account" ||
    ! session_manifest_render "$account" "$expected"; then
    rm -f "$expected"
    session_manifest_error "current source data for '$account' is invalid"
    return 1
  fi
  if ! cmp -s "$file" "$expected"; then
    rm -f "$expected"
    session_manifest_error "manifest '$account' is stale"
    return 1
  fi
  rm -f "$expected"
}

session_manifest_remove() { rm -f "$(session_manifest_path "$1")"; }

session_manifest() {
  [[ $# -eq 2 ]] || {
    session_manifest_error "usage: session_manifest <build|check> <kid>"
    return 1
  }
  case "$1" in
    build) session_manifest_build "$2" ;;
    check) session_manifest_check "$2" ;;
    *) session_manifest_error "unknown verb '$1' (want build or check)" ;;
  esac
}
