#!/usr/bin/env bash

ask() {
  local prompt="$1" default="${2:-}" reply
  if [[ -n "${default}" ]]; then
    read -r -p "${prompt} [${default}]: " reply || true
    echo "${reply:-$default}"
  else
    read -r -p "${prompt}: " reply || true
    echo "${reply}"
  fi
}

ask_yn() {
  local prompt="$1" default="${2:-y}" reply
  read -r -p "${prompt} [${default}]: " reply || true
  reply="$(echo "${reply:-$default}" | tr '[:upper:]' '[:lower:]')"
  [[ "${reply}" == "y" || "${reply}" == "yes" ]]
}

ask_secret() {
  local reply
  read -r -s -p "$1: " reply || true
  echo >&2
  echo "${reply}"
}

tfvar_get() {
  local file="$1" key="$2"
  [[ -f "${file}" ]] || { echo ""; return 0; }
  python3 - "$file" "$key" <<'PY'
import re, sys
path, key = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
lines = []
for line in text.splitlines():
    if "#" in line:
        line = line.split("#", 1)[0]
    lines.append(line)
text = "\n".join(lines)
pat = re.compile(
    rf'(?m)^\s*{re.escape(key)}\s*=\s*('
    r'"(?:\\.|[^"\\])*"'
    r"|'(?:\\.|[^'\\])*'"
    r"|true|false"
    r"|-?\d+(?:\.\d+)?"
    r"|\[[^\]]*\]"
    r")\s*$"
)
m = pat.search(text)
if not m:
    sys.exit(0)
raw = m.group(1).strip()
if raw.startswith("[") and raw.endswith("]"):
    inner = raw[1:-1].strip()
    if not inner:
        print("")
        sys.exit(0)
    parts = re.findall(r'"((?:\\.|[^"\\])*)"', inner)
    print(",".join(p.replace('\\"', '"') for p in parts))
    sys.exit(0)
if (raw.startswith('"') and raw.endswith('"')) or (raw.startswith("'") and raw.endswith("'")):
    print(raw[1:-1].encode("utf-8").decode("unicode_escape") if "\\" in raw else raw[1:-1])
    sys.exit(0)
print(raw)
PY
}

tfvar_has() {
  local file="$1" key="$2"
  [[ -f "${file}" ]] || return 1
  python3 - "$file" "$key" <<'PY'
import re, sys
path, key = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
lines = []
for line in text.splitlines():
    if "#" in line:
        line = line.split("#", 1)[0]
    lines.append(line)
text = "\n".join(lines)
pat = re.compile(rf'(?m)^\s*{re.escape(key)}\s*=')
sys.exit(0 if pat.search(text) else 1)
PY
}

_get_var() {
  eval "printf '%s' \"\${$1}\""
}

_set_var() {
  eval "$1=\"\$2\""
}

resolve_str() {
  local var_name="$1" prompt="$2" default="${3:-}" tf_key="${4:-}" tf_path="${5:-}"
  local current
  current="$(_get_var "${var_name}")"
  if [[ -n "${current}" ]]; then
    return 0
  fi
  if [[ -n "${tf_key}" && -n "${tf_path}" ]] && tfvar_has "${tf_path}" "${tf_key}"; then
    current="$(tfvar_get "${tf_path}" "${tf_key}")"
    _set_var "${var_name}" "${current}"
    echo "  ${var_name}=${current} (from terraform.tfvars)" >&2
    return 0
  fi
  if [[ "${NONINTERACTIVE:-false}" == "true" ]]; then
    _set_var "${var_name}" "${default}"
    return 0
  fi
  current="$(ask "${prompt}" "${default}")"
  _set_var "${var_name}" "${current}"
}

resolve_bool() {
  local var_name="$1" prompt="$2" default="${3:-false}" tf_key="${4:-}" tf_path="${5:-}"
  local current yn_default normalized
  _normalize_bool() {
    local v
    v="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
    case "${v}" in
      true|1|yes|y) echo true ;;
      false|0|no|n|"") echo false ;;
      *) echo "$1" ;;
    esac
  }
  current="$(_get_var "${var_name}")"
  if [[ -n "${current}" ]]; then
    _set_var "${var_name}" "$(_normalize_bool "${current}")"
    return 0
  fi
  if [[ -n "${tf_key}" && -n "${tf_path}" ]] && tfvar_has "${tf_path}" "${tf_key}"; then
    current="$(tfvar_get "${tf_path}" "${tf_key}")"
    normalized="$(_normalize_bool "${current}")"
    _set_var "${var_name}" "${normalized}"
    echo "  ${var_name}=${normalized} (from terraform.tfvars)" >&2
    return 0
  fi
  if [[ "${NONINTERACTIVE:-false}" == "true" ]]; then
    _set_var "${var_name}" "$(_normalize_bool "${default}")"
    return 0
  fi
  yn_default="n"
  [[ "$(_normalize_bool "${default}")" == "true" ]] && yn_default="y"
  if ask_yn "${prompt}" "${yn_default}"; then
    _set_var "${var_name}" "true"
  else
    _set_var "${var_name}" "false"
  fi
}

hcl_list() {
  local raw="${1:-}" item first=true
  local -a parts=()
  echo -n "["
  if [[ -n "${raw}" ]]; then
    IFS=',' read -r -a parts <<<"${raw}" || true
  fi
  for item in "${parts[@]+"${parts[@]}"}"; do
    item="$(echo "${item}" | xargs)"
    [[ -z "${item}" ]] && continue
    if [[ "${first}" == "true" ]]; then
      first=false
    else
      echo -n ", "
    fi
    echo -n "\"${item}\""
  done
  echo "]"
}
