#!/bin/sh
# (lab container) push-app.sh <branch> <message>
rm -rf /lab/xfer/scripts/.x; vmlab scp-to forge /lab/xfer/scripts/sync-push.sh /home/ubuntu/scripts/ >/dev/null
vmlab ssh forge "rm -rf ~/xfer-hello" && vmlab scp-to forge /lab/xfer/hello /home/ubuntu/xfer-hello && vmlab ssh forge "bash ~/scripts/sync-push.sh '$1' '$2'"
