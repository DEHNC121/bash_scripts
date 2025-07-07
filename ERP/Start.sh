#!/bin/bash

# Script to create a tmux session with 4 panes and connect to telnet sessions
# Author: DEHNC121
# Last modified: 2025-07-07

# Exit on any error
set -e

# Configuration
HOST="10.12.0.17"
PORTS=(6008 6009 6010 6011)
DISPLAY_NAMES=(158 159 160 161)
SESSION_NAME="telnet_session"

# Function to check dependencies
check_dependencies() {
    if ! command -v tmux &> /dev/null; then
        echo "Error: tmux is not installed. Please install it first."
        exit 1
    fi
    if ! command -v telnet &> /dev/null; then
        echo "Error: telnet is not installed. Please install it first."
        exit 1
    fi
}

# Function to check host connectivity
check_host() {
    if ! ping -c 1 -W 1 "$HOST" &> /dev/null; then
        echo "Warning: Host $HOST might be unreachable"
        read -p "Do you want to continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Main script
echo "Starting ERP telnet session setup..."

# Check dependencies
check_dependencies

# Check host connectivity
check_host

# Check if we're already inside a tmux session
if [ -n "$TMUX" ]; then
    # We're inside tmux, detach first
    echo "Detected running inside tmux. Detaching current session..."
    tmux detach-client
fi

# Kill existing session if it exists
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Found existing session. Terminating..."
    tmux kill-session -t "$SESSION_NAME"
fi

# Create new tmux session
echo "Creating new tmux session..."
tmux new-session -d -s "$SESSION_NAME"

# Split the window into four panes (2x2 grid)
echo "Creating 2x2 grid layout..."
# First, split vertically
tmux split-window -v -t "$SESSION_NAME:0.0" -p 50
# Then split each pane horizontally
tmux split-window -h -t "$SESSION_NAME:0.0" -p 50
tmux split-window -h -t "$SESSION_NAME:0.1" -p 50

# Send telnet commands to each pane and set prompt
for i in {0..3}; do
    echo "Connecting to $HOST:${PORTS[$i]} in pane $i..."
    # Connect to telnet
    tmux send-keys -t "$SESSION_NAME:0.$i" "telnet $HOST ${PORTS[$i]}" C-m
    # Wait for telnet to connect and show prompt
    sleep 3
    # Send Enter to ensure we have a fresh prompt
    tmux send-keys -t "$SESSION_NAME:0.$i" C-m
    # Set custom prompt with display number
    tmux send-keys -t "$SESSION_NAME:0.$i" "PS1='[xg118pro-csh-${DISPLAY_NAMES[$i]}:~] # '" C-m
    # Send Enter again to show the new prompt
    tmux send-keys -t "$SESSION_NAME:0.$i" C-m
done

# Set tiled layout to ensure equal sizes
tmux select-layout -t "$SESSION_NAME" tiled

echo "Setup complete. Attaching to session..."
# Attach to the session (use exec to replace the current shell)
exec tmux attach-session -t "$SESSION_NAME"
