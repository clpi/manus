#!/bin/sh
# coord/cron/healthcheck.sh — monitor critical Idol infrastructure
# and alert via ntfy when something flaps.
#
# Checks three things every 60 seconds:
#   1. Self reachability: can this host reach r16.idol.id over HTTPS?
#   2. Grok-box tunnel: is the Tailscale path to grok-box alive?
#   3. OpenRouter API: is the openrouter dispatch path reachable?
#
# On transition (up→down OR down→up) the script publishes a state-change
# notification to ntfy. Steady-state (still up OR still down) is silent.
#
# The cron entry is in coord/cron/healthcheck.cron — installs at
# */1 * * * * so a flap surfaces within a minute.

set -u

CHANNEL="${NTFY_HOME_CHANNEL:-idol-health}"
NTFY_SERVER="${NTFY_SERVER_URL:-https://ntfy.sh}"
STATE_DIR=/tmp/idol-health-state
mkdir -p "$STATE_DIR"

notify() {
  local title="$1" body="$2" priority="${3:-default}"
  curl -sm 10 \
    -H "Title: $title" \
    -H "Priority: $priority" \
    -H "Tags: warning,idol" \
    -d "$body" \
    "${NTFY_SERVER}/${CHANNEL}" >/dev/null 2>&1 || true
}

check_up() {
  local name="$1" current="$2"
  local prev_file="$STATE_DIR/$name.prev"
  local prev=""
  [ -f "$prev_file" ] && prev=$(cat "$prev_file")
  if [ "$current" != "$prev" ]; then
    printf '%s\n' "$current" > "$prev_file"
    if [ "$current" = "down" ]; then
      notify "idol/$name DOWN" "down at $(date -Iseconds) on $(hostname)" "high"
      printf 'idol/healthcheck: %s DOWN at %s\n' "$name" "$(date -Iseconds)" >&2
    else
      notify "idol/$name UP" "recovered at $(date -Iseconds) on $(hostname)" "default"
      printf 'idol/healthcheck: %s UP at %s\n' "$name" "$(date -Iseconds)" >&2
    fi
  fi
}

# 1. self reachability: HTTPS to api.idol.id (any 2xx/3xx = up, 5xx = up
# but degraded, 000 = down)
status=$(curl -sm 5 -o /dev/null -w "%{http_code}" \
  https://api.idol.id/__idol/version 2>/dev/null)
case "$status" in
  2*|3*|404) check_up r16idol_api up ;;
  000)       check_up r16idol_api down ;;
  *)         check_up r16idol_api "degraded:$status" ;;
esac

# 2. grok-box tunnel: tailscale ping returns 0 when reachable.
#    Also probe via the grok-box IP directly as a fallback so the
#    Tailscale relay flap doesn't mask a real outage (or vice-versa).
groks_box_tailscale=down
groks_box_ip=down
if tailscale ping -c 1 --timeout 5s grok-box >/dev/null 2>&1; then
  groks_box_tailscale=up
fi
# Resolve grok-box IP via tailscale status (no DNS dependency)
groks_box_ip=$(tailscale status --json 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); \
print(d.get('Peer',{}).get('grok-box',{}).get('TailscaleIPs',[''])[0])" 2>/dev/null)
if [ -n "$groks_box_ip" ]; then
  if timeout 3 nc -z "$groks_box_ip" 22 2>/dev/null; then
    groks_box_ip=up
  fi
fi
# Combine: grokbox is up if EITHER the Tailscale path OR the direct
# IP is reachable. (Either path alone is sufficient for the user's
# mental model of "I can reach grok-box".)
case "$groks_box_tailscale:$groks_box_ip" in
  up:*)      check_up grokbox up ;;
  *:up)      check_up grokbox up ;;
  up:up)     check_up grokbox up ;;
  *)         check_up grokbox down ;;
esac

# 3. openrouter: a chat completion request as health probe
status=$(curl -sm 5 -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${OPENROUTER_API_KEY:-no-key}" \
  -H "Content-Type: application/json" \
  -d '{"model":"meta-llama/llama-3.1-8b-instruct","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' \
  https://openrouter.ai/api/v1/chat/completions 2>/dev/null)
case "$status" in
  200) check_up openrouter up ;;
  401|402|429) check_up openrouter "auth:$status" ;;
  000) check_up openrouter down ;;
  *) check_up openrouter "degraded:$status" ;;
esac

# 4. grok/XAI API: a chat completion request as billing/path probe.
#    This is the path that "went down" per user report — the actual
#    failure was credits (HTTP 403), not network. Probing here lets
#    the ntfy alert name the actual cause.
status=$(curl -sm 5 -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${XAI_API_KEY:-no-key}" \
  -H "Content-Type: application/json" \
  -d '{"model":"grok-3-fast","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' \
  https://api.x.ai/v1/chat/completions 2>/dev/null)
case "$status" in
  200) check_up xai up ;;
  401) check_up xai "auth:401" ;;
  403) check_up xai "no_credits" ;;
  429) check_up xai "rate_limited" ;;
  000) check_up xai down ;;
  *) check_up xai "degraded:$status" ;;
esac

exit 0
