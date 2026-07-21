#!/bin/sh

printf 'fixture diagnostic\n' >&2

while IFS= read -r request; do
  case "$request" in
    *'"method":"initialize"'*)
      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
      ;;
    *rateLimits*read*)
      printf '%s\n' 'not-json'
      printf '%0550d' 0
      sleep 0.1
      printf '%050d\n' 0
      printf '%s\n' '{"jsonrpc":"2.0","method":"thread/status/changed","params":{"threadId":"fixture-thread","status":{"type":"active","activeFlags":["waitingOnApproval"]}}}'
      printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tool/requestUserInput","params":{}}'
      printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":25}}}}'
      ;;
    *thread*list*)
      printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"data":[{"id":"fixture-thread","name":"Fixture","preview":"","cwd":"","ephemeral":false,"updatedAt":10,"status":{"type":"active","activeFlags":["waitingOnApproval"]}}]}}'
      ;;
    *test*error*)
      printf '%s\n' '{"jsonrpc":"2.0","id":4,"error":{"code":-32000,"message":"PRIVATE_MARKER"}}'
      ;;
    *test*exit*)
      exit 0
      ;;
  esac
done
