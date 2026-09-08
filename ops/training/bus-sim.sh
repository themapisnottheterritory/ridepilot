#!/usr/bin/env bash
# Start (or restart) the simulated bus feed on the training host.
# Cron on the training box: @reboot /home/philz/rptest/ridepilot/ops/training/bus-sim.sh
DIR=$(cd "$(dirname "$0")" && pwd)
LOG=/home/philz/bus-sim.log
pkill -f "python3 $DIR/bus-sim.py" 2>/dev/null
sleep 1
nohup python3 "$DIR/bus-sim.py" >> "$LOG" 2>&1 &
echo "bus-sim started (pid $!), log $LOG"
