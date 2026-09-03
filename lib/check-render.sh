# shellcheck shell=bash
# lib/check-render.sh — omarchy-kids-check's two report renderers
# (human, --json), reading the RESULTS/SECTION_ORDER the reporting
# helpers and every section above filled in. Sourced by the dispatcher;
# not meant to be executed directly.

# --- render: human -----------------------------------------------------

render_human() {
    local sec entry section id status detail badge
    for sec in "${SECTION_ORDER[@]}"; do
        printf '\n== %s ==\n' "$sec"
        for entry in "${RESULTS[@]}"; do
            IFS=$'\x1f' read -r section id status detail <<<"$entry"
            [[ "$section" == "$sec" ]] || continue
            case "$status" in
                pass) badge="${G}PASS${N}" ;;
                warn) badge="${Y}WARN${N}" ;;
                fail) badge="${R}FAIL${N}" ;;
                *)    badge="SKIP" ;;
            esac
            printf '  %b  %-34s %s\n' "$badge" "$id" "$detail"
        done
    done
    printf '\n'
    case "$VERDICT" in
        pass) printf '%b\n' "${G}All checks pass. Safe to hand over.${N}" ;;
        warn) printf '%b\n' "${Y}Passing, with warnings above — review them, then hand over.${N}" ;;
        fail) printf '%b\n' "${R}Not ready — fix the FAIL lines above before handing over.${N}" ;;
    esac
}

# --- render: json --------------------------------------------------------

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

render_json() {
    local sec entry section id status detail first_sec=1 first_chk
    printf '{\n'
    printf '  "generated_at": "%s",\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')"
    printf '  "verdict": "%s",\n' "$VERDICT"
    printf '  "exit_code": %s,\n' "$EXIT_CODE"
    printf '  "sections": [\n'
    for sec in "${SECTION_ORDER[@]}"; do
        [[ "$first_sec" == 1 ]] || printf ',\n'
        first_sec=0
        printf '    {\n      "name": "%s",\n      "checks": [\n' "$(json_escape "$sec")"
        first_chk=1
        for entry in "${RESULTS[@]}"; do
            IFS=$'\x1f' read -r section id status detail <<<"$entry"
            [[ "$section" == "$sec" ]] || continue
            [[ "$first_chk" == 1 ]] || printf ',\n'
            first_chk=0
            printf '        {"id": "%s", "status": "%s", "detail": "%s"}' \
                "$(json_escape "$id")" "$status" "$(json_escape "$detail")"
        done
        printf '\n      ]\n    }'
    done
    printf '\n  ]\n}\n'
}
