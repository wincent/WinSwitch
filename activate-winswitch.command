#!/bin/sh
#
# Activate WinSwitch.command
# Script to activate WinSwitch in current user account
# $Id$

tool="/Library/Menu Extras/WinSwitch.menu/Contents/Resources/menu-extra-tool"
 
# deactivate Apple's menu extra, MenuCracker and WinSwitch
"${tool}"                                       \
  -r com.apple.menuextra.appleuser              \
  -r net.sourceforge.menucracker                \
  -r com.wincent.WinSwitch
  
/bin/sleep 3

# must kill SystemUIServer to force it to reload the new WinSwitch bundle
/usr/bin/killall -SIGHUP SystemUIServer
  
# open MenuCracker; will relaunch SystemUIServer if it did not respawn already
/usr/bin/open \
  "/Library/Menu Extras/WinSwitch.menu/Contents/Resources/MenuCracker.menu"
  
# allow time for SystemUIServer to relaunch
/bin/sleep 5
  
# activate WinSwitch, adding to right-hand end of menu bar
"${tool}"                                       \
  -a "/Library/Menu Extras/WinSwitch.menu"      \
  -p -1

# retry if error reported on first try (system under heavy load may take longer to respawn SystemUIServer)
if [ $? -ne 0 ]; then
  /bin/sleep 5
  "${tool}" -a "/Library/Menu Extras/WinSwitch.menu" -p -1
fi

# don't check the exit status (spurious errors reported due to conflict with Unsanity MEE?)
exit 0
