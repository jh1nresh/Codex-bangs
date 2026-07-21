#!/bin/sh

if [ "${1-}" = "--version" ]; then
  printf '%s\n' 'codex-cli fixture'
  exit 0
fi

stop_marker="${0}.stopped"
trap 'printf "%s\n" stopped > "$stop_marker"' 0

printf 'fixture diagnostic\n' >&2

while IFS= read -r request; do
  case "$request" in
    *'"method":"initialize"'*)
      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
      ;;
    *rateLimits*read*)
      case "$0" in
        *rate-error*)
          printf '%s\n' '{"jsonrpc":"2.0","id":2,"error":{"code":-32000,"message":"PRIVATE_RATE_MARKER"}}'
          ;;
        *)
          printf '%s\n' 'not-json'
          printf '%0550d' 0
          sleep 0.1
          printf '%050d\n' 0
          printf '%s\n' '{"jsonrpc":"2.0","method":"thread/status/changed","params":{"threadId":"fixture-thread","status":{"type":"active","activeFlags":["waitingOnApproval"]}}}'
          printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tool/requestUserInput","params":{}}'
          printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25}}}}'
          ;;
      esac
      ;;
    *thread*list*)
      case "$0" in
        *task-error*)
          printf '%s\n' '{"jsonrpc":"2.0","id":3,"error":{"code":-32000,"message":"PRIVATE_TASK_MARKER"}}'
          ;;
        *sort-fallback*)
          case "$request" in
            *recency_at*)
              printf '%s\n' '{"jsonrpc":"2.0","id":3,"error":{"code":-32600,"message":"PRIVATE_SORT_MARKER"}}'
              ;;
            *updated_at*)
              printf '%s\n' '{"jsonrpc":"2.0","id":4,"result":{"data":[{"id":"fixture-thread","name":"Fixture","preview":"","cwd":"","ephemeral":false,"updatedAt":10,"status":{"type":"active","activeFlags":["waitingOnApproval"]}}]}}'
              ;;
          esac
          ;;
        *not-loaded*)
          printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"data":[{"id":"fixture-thread","name":"Fixture","preview":"","cwd":"","ephemeral":false,"recencyAt":99,"updatedAt":10,"status":{"type":"notLoaded","activeFlags":[]}}]}}'
          ;;
        *)
          printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"data":[{"id":"fixture-thread","name":"Fixture","preview":"","cwd":"","ephemeral":false,"updatedAt":10,"status":{"type":"active","activeFlags":["waitingOnApproval"]}}]}}'
          ;;
      esac
      ;;
    *test*error*)
      printf '%s\n' '{"jsonrpc":"2.0","id":4,"error":{"code":-32000,"message":"PRIVATE_MARKER"}}'
      ;;
    *test*exit*)
      exit 0
      ;;
  esac
done
