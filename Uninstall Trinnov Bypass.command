#!/bin/bash
# Removes Trinnov Bypass (the command, the four apps and the four Quick Actions).
rm -rf "$HOME/Library/Application Support/TrinnovBypass" "$HOME/Applications/Trinnov Bypass"
for n in "Trinnov Bypass Toggle" "Trinnov Bypass On" "Trinnov Bypass Off" "Trinnov Bypass Status"; do
  rm -rf "$HOME/Library/Services/$n.workflow"
done
/System/Library/CoreServices/pbs -update >/dev/null 2>&1 || true
echo "Trinnov Bypass removed."
