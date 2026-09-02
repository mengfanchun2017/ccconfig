#!/bin/bash
cd /home/francis/git/ccconfig
echo "=== by-day line count ==="
bash option-usage/token-usage.sh --by-day 2>/dev/null | wc -l
echo "=== stats output ==="
bash option-usage/token-usage.sh --stats 2>/dev/null
echo "=== done ==="