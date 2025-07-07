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
MAX_RETRIES=20
RETRY_DELAY=0.5
CONFIG_DIR="$HOME/.config/erp_telnet"
LAYOUT_FILE="$CONFIG_DIR/layout"

# Create config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Default layout (2x2 grid)
DEFAULT_LAYOUT=(
    "split-window -v -p 50"
    "split-window -h -p 50"
    "select-pane -t 0"
    "split-window -h -p 50"
    "select-layout tiled"
)

# Cleanup function
cleanup() {
    local exit_code=$?
    echo "Cleaning up..."
    # Kill monitoring process if it exists
    if [ -n "$MONITOR_PID" ] && kill -0 $MONITOR_PID 2>/dev/null; then
        echo "Stopping connection monitor..."
        kill $MONITOR_PID 2>/dev/null
    fi
    # Save layout before exit
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        echo "Saving current layout..."
        save_layout
    fi
    exit $exit_code
}

# Set up trap for multiple signals
trap cleanup EXIT SIGINT SIGTERM SIGHUP

# Function to save current layout
save_layout() {
    tmux list-windows -F "#{window_layout}" -t "$SESSION_NAME" > "$LAYOUT_FILE"
    echo "Layout saved to $LAYOUT_FILE"
}

# Function to load saved layout
load_layout() {
    if [ -f "$LAYOUT_FILE" ]; then
        local layout=$(cat "$LAYOUT_FILE")
        tmux select-layout -t "$SESSION_NAME" "$layout"
        return 0
    fi
    return 1
}

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

# Function to check if a pane is healthy
check_pane_health() {
    local pane=$1
    local port=${PORTS[$pane]}
    if ! tmux capture-pane -t "$SESSION_NAME:0.$pane" -p | grep -q "\[xg118pro-csh.*\] #"; then
        echo "Pane $pane (port $port) appears disconnected. Reconnecting..."
        setup_telnet "$pane"
        return 1
    fi
    return 0
}

# Function to monitor all connections
monitor_connections() {
    while true; do
        for i in {0..3}; do
            check_pane_health "$i" &
        done
        wait
        sleep 30
    done
}

# Function to wait for telnet connection
wait_for_connection() {
    local pane=$1
    local retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        if tmux capture-pane -t "$SESSION_NAME:0.$pane" -p | grep -q "\[xg118pro-csh:~\] #"; then
            sleep 1  # Give an extra second for the connection to stabilize
            return 0
        fi
        sleep $RETRY_DELAY
        ((retries++))
    done
    return 1
}

# Function to setup telnet connection in a pane
setup_telnet() {
    local pane=$1
    local port=${PORTS[$pane]}
    local display_name=${DISPLAY_NAMES[$pane]}
    
    # Connect to telnet
    tmux send-keys -t "$SESSION_NAME:0.$pane" "telnet $HOST $port" C-m
    
    # Wait for connection
    if wait_for_connection "$pane"; then
        # Clear any pending input
        tmux send-keys -t "$SESSION_NAME:0.$pane" C-m
        # Set custom prompt with multiple attempts
        for attempt in {1..3}; do
            tmux send-keys -t "$SESSION_NAME:0.$pane" "PS1='[xg118pro-csh-$display_name:~] # '" C-m
            sleep 0.5
        done
        return 0
    fi
    echo "Failed to setup telnet in pane $pane"
    return 1
}

# Function to check and recover session
check_session() {
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        echo "Found existing session. Checking health..."
        local unhealthy=0
        for i in {0..3}; do
            if ! check_pane_health "$i"; then
                unhealthy=1
            fi
        done
        if [ $unhealthy -eq 0 ]; then
            echo "Existing session is healthy. Reusing it."
            return 0
        else
            echo "Session needs recovery. Recreating..."
            tmux kill-session -t "$SESSION_NAME"
            return 1
        fi
    fi
    return 1
}

# Main script
echo "Starting ERP telnet session setup..."

# Check dependencies
check_dependencies

# Check host connectivity
check_host

# Check if we're already inside a tmux session
if [ -n "$TMUX" ]; then
    echo "Detected running inside tmux. Detaching current session..."
    tmux detach-client
fi

# Check existing session
if ! check_session; then
    # Create new tmux session
    echo "Creating new tmux session..."
    tmux new-session -d -s "$SESSION_NAME"
    
    # Apply layout
    echo "Applying layout..."
    if ! load_layout; then
        echo "No saved layout found. Using default 2x2 grid..."
        for cmd in "${DEFAULT_LAYOUT[@]}"; do
            tmux "$cmd" -t "$SESSION_NAME"
        done
    fi

    # Start all telnet connections in parallel
    echo "Establishing telnet connections..."
    for i in {0..3}; do
        setup_telnet $i &
    done

    # Wait for all background processes to complete
    wait

    # Final prompt setup to ensure changes took effect
    for i in {0..3}; do
        tmux send-keys -t "$SESSION_NAME:0.$i" C-m
        tmux send-keys -t "$SESSION_NAME:0.$i" "PS1='[xg118pro-csh-${DISPLAY_NAMES[$i]}:~] # '" C-m
        tmux send-keys -t "$SESSION_NAME:0.$i" C-m
    done
fi

# Start connection monitoring in the background
monitor_connections &
MONITOR_PID=$!

# Save current layout
save_layout

echo "Setup complete. Attaching to session..."
# Attach to the session
exec tmux attach-session -t "$SESSION_NAME"
