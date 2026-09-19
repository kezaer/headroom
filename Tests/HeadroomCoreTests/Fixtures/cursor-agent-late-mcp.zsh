#!/bin/zsh
if [[ "$1" == status ]]; then
  print -n '{"isAuthenticated":true}'
  exit 0
fi
stty raw -echo
print -n $'Cursor Agent\r\nAsk (shift+tab to cycle)\r\nAuto\r\n'
sleep 0.3
print -n $'MCP Server Approval Required\r\nCursor Agent found configured external tools.\r\nReview these servers before continuing.\r\n'
buffer=''
while read -k 1 character; do
  buffer+="$character"
  if [[ "$character" == a || "$buffer" == */usage ]]; then
    print -r -- "$buffer" > "$PWD/unexpected-input"
    break
  fi
done
