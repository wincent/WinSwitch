#!/bin/sh

# script to activate WinSwitch in current user account

tool="/Library/Menu Extras/WinSwitch.menu/Contents/Resources/menu-extra-tool"
 
# deactivate Apple's menu extra, MenuCracker and WinSwitch
"${tool}"                                       \
  -r com.apple.menuextra.appleuser              \
  -r net.sourceforge.menucracker                \
  -r com.wincent.WinSwitch
  
/bin/sleep 3

#Êmust kill SystemUIServer to force it to reload the new WinSwitch bundle
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

exit 0