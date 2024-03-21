#!/bin/bash

# These variables will be automagically updated if you run build.sh, no need to modify them
mainDaemonPlist="/Library/LaunchDaemons/com.grahamrpugh.nice_updater.plist"
mainOnDemandDaemonPlist="/Library/LaunchDaemons/com.grahamrpugh.nice_updater_on_demand.plist"
preferenceFileFullPath="/Library/Preferences/com.grahamrpugh.nice_updater.prefs.plist"

DIR=$(dirname "$0")

# install swiftDialog
if /usr/sbin/installer -tgt / -pkg "$DIR/dialog.pkg"; then
    echo "swiftDialog successfully installed"
else
    echo "ERROR: swiftDialog was not installed"
    exit 1
fi

# Set permissions on LaunchDaemon and Script
chown root:wheel "$mainDaemonPlist"
chmod 644 "$mainDaemonPlist"
chown root:wheel "$preferenceFileFullPath"
chmod 644 "$preferenceFileFullPath"
chown root:wheel /Library/Scripts/nice_updater.sh
chmod 755 /Library/Scripts/nice_updater.sh
chown root:wheel /Library/Scripts/nice_updater_uninstall.sh
chmod 755 /Library/Scripts/nice_updater_uninstall.sh
if [[ -f /Library/Scripts/nice_updater_custom_icon.png ]]; then
    chown root:wheel /Library/Scripts/nice_updater_custom_icon.png
    chmod 644 /Library/Scripts/nice_updater_custom_icon.png
fi

# Start our LaunchDaemons
/bin/launchctl load -w "$mainDaemonPlist"
/bin/launchctl load -w "$mainOnDemandDaemonPlist"

/bin/launchctl start com.grahamrpugh.nice_updater
