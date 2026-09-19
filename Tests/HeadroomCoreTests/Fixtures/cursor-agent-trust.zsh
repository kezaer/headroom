#!/bin/zsh
if [[ "$1" == status ]]; then
  print -n '{"isAuthenticated":true}'
  exit 0
fi
stty raw -echo
print -n $'/!\\ Workspace Trust Required\r\nCursor Agent can execute code and access files in this directory.\r\n[a] Trust this workspace\r\n[q] Quit\r\n'
buffer=''
while read -k 1 character; do
  buffer+="$character"
  if [[ "$character" == a || "$buffer" == */usage ]]; then
    print -r -- "$buffer" > "$PWD/unexpected-input"
    break
  fi
done
