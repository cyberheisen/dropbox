#!/bin/bash
# log_gen.sh
LOG="/tmp/demo_access.log"
METHODS=("GET" "POST" "PUT" "DELETE")
PATHS=("/login" "/admin" "/../etc/passwd" "/wp-admin" "/api/token" "/.env" "/shell.php")
IPS=("10.10.10.1" "192.168.1.55" "172.16.0.4" "45.33.32.156" "8.8.8.8")
CODES=("200" "200" "200" "403" "404" "500" "301" "401")

while true; do
  METHOD=${METHODS[$RANDOM % ${#METHODS[@]}]}
  PATH=${PATHS[$RANDOM % ${#PATHS[@]}]}
  IP=${IPS[$RANDOM % ${#IPS[@]}]}
  CODE=${CODES[$RANDOM % ${#CODES[@]}]}
  TS=$(date '+%d/%b/%Y:%H:%M:%S %z')
  echo "$IP - - [$TS] \"$METHOD $PATH HTTP/1.1\" $CODE $((RANDOM % 4096))" >> "$LOG"
  sleep $((RANDOM % 3 + 1))
done
