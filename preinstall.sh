#!/bin/bash

# These variables will be automagically updated if you run build.sh, no need to modify them
mainDaemonPlist="/Library/LaunchDaemons/com.grahamrpugh.nice_updater.plist"
mainOnDemandDaemonPlist="/Library/LaunchDaemons/com.grahamrpugh.nice_updater_on_demand.plist"

# Stop our LaunchDaemons
/bin/launchctl unload -w "$mainOnDemandDaemonPlist"
/bin/launchctl unload -w "$mainDaemonPlist"

# Old ones also need to be removed
oldDaemonPlist="/Library/LaunchDaemons/com.github.grahampugh.nice_updater.plist"
oldOnDemandDaemonPlist="/Library/LaunchDaemons/grahampugh.nice_updater_on_demand.plist"

# Stop our LaunchDaemons
/bin/launchctl unload -w "$oldOnDemandDaemonPlist"
/bin/launchctl unload -w "$oldDaemonPlist"

exit 0
