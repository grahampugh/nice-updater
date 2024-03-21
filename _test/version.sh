#!/bin/bash

get_system_version() {
    system_version=$( /usr/bin/sw_vers -productVersion )
    return "${system_version:0:2}"
}

system_major_version=$(get_system_version)
if [[ $system_major_version -eq 10 ]]; then
    writelog "ERROR: system too old, quitting"
elif  [[ $system_major_version -ge 13 ]]; then
    /usr/bin/open -W open x-apple.systempreferences:com.apple.Software-Update-Settings.extension &
else
    /usr/bin/open -W /System/Library/PreferencePanes/SoftwareUpdate.prefPane &
fi
