#!/bin/sh

arguments_file="${0}.args"
stdin_file="${0}.stdin"
printf '%s\n' "$@" > "$arguments_file"

case "$0" in
  *-no-stdin)
    exec 0<&-
    trap 'printf "%s\n" terminated > "${0}.terminated"; exit 0' TERM INT
    while :; do :; done
    ;;
esac

cat > "$stdin_file"

case "$0" in
  *-slow)
    trap 'exit 0' TERM INT
    while :; do sleep 1; done
    ;;
  *-exit)
    printf '%s\n' 'PRIVATE_STDERR_MARKER' >&2
    exit 7
    ;;
  *-malformed)
    printf '%s\n' 'not json'
    exit 0
    ;;
  *)
    printf '%s\n' '{"type":"thread.started","thread_id":"fixture-thread"}'
    printf '%s\n' '{"type":"item.completed","item":{"type":"reasoning","text":"Private reasoning"}}'
    printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"Fixture answer"}}'
    ;;
esac
