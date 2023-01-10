#!/bin/bash

status="/Library/Scripts/nice_updater_status.txt"

if [ -f "$status" ]; then
  result=$(cat "$status")
else
  result="Unknown"
fi

echo "<result>$result</result>"
