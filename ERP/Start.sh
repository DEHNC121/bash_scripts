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

# Function to create the default layout
create_default_layout() {
    # Start with a single pane
    tmux new-session -d -s "$SESSION_NAME"
    
    # Split into four panes
    tmux split-window -v -t "$SESSION_NAME:0.0"
    tmux split-window -h -t "$SESSION_NAME:0.0"
    tmux split-window -h -t "$SESSION_NAME:0.2"
    
    # Select tiled layout
    tmux select-layout -t "$SESSION_NAME:0" tiled
    
    # Give tmux a moment to stabilize
    sleep 1
}

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
    
    if ! tmux capture-pane -t "$SESSION_NAME:0.$pane" -p 2>/dev/null | grep -q "\[xg118pro-csh.*\] #"; then
        return 1
    fi
    return 0
}

# Function to wait for telnet connection
wait_for_connection() {
    local pane=$1
    local retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        # Check for successful connection message or any prompt
        if tmux capture-pane -t "$SESSION_NAME:0.$pane" -p | grep -q -E "Connected to.*Escape character is|>|\$|#|\[xg118pro-csh"; then
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
    
    # Verify pane exists before proceeding
    if ! tmux list-panes -t "$SESSION_NAME:0" | grep -q "^$pane:"; then
        echo "Error: Pane $pane does not exist"
        return 1
    fi
    
    echo "Connecting to $HOST:$port in pane $pane..."
    # Connect to telnet
    tmux send-keys -t "$SESSION_NAME:0.$pane" "telnet $HOST $port" C-m
    
    # Wait for connection
    if wait_for_connection "$pane"; then
        echo "Connection established in pane $pane"
        # Send a carriage return to potentially trigger prompt
        tmux send-keys -t "$SESSION_NAME:0.$pane" C-m
        sleep 1
        
        # Try to set custom prompt but don't fail if it doesn't work
        echo "Attempting to set custom prompt for pane $pane..."
        for attempt in {1..3}; do
            tmux send-keys -t "$SESSION_NAME:0.$pane" "PS1='[xg118pro-csh-$display_name:~] # '" C-m
            sleep 1
            
            # Check if custom prompt was set
            if tmux capture-pane -t "$SESSION_NAME:0.$pane" -p | grep -q "\[xg118pro-csh-$display_name:~\] #"; then
                echo "Custom prompt set successfully for pane $pane"
                return 0
            fi
        done
        
        echo "Warning: Could not set custom prompt for pane $pane, but connection is established"
        return 0
    fi
    
    echo "Failed to setup telnet in pane $pane"
    return 1
}

# Function to check and recover session
check_session() {
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        echo "Found existing session. Attempting to attach..."
        return 0
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

# Check existing session or create new one
if check_session; then
    echo "Reusing existing session..."
else
    # Create new tmux session with layout
    echo "Creating new tmux session..."
    create_default_layout
    
    # Start telnet connections sequentially
    echo "Establishing telnet connections..."
    connection_failures=0
    for i in {0..3}; do
        if ! setup_telnet $i; then
            echo "Warning: Failed to setup telnet connection in pane $i"
            ((connection_failures++))
        else
            echo "Successfully connected telnet in pane $i"
        fi
    done

    # Only exit if all connections failed
    if [ $connection_failures -eq 4 ]; then
        echo "Error: All telnet connections failed"
        tmux kill-session -t "$SESSION_NAME"
        exit 1
    elif [ $connection_failures -gt 0 ]; then
        echo "Warning: Some telnet connections failed but continuing with working ones"
    fi

    # Final prompt refresh - only try if initial setup worked
    echo "Refreshing prompts..."
    for i in {0..3}; do
        tmux send-keys -t "$SESSION_NAME:0.$i" C-m
    done
fi

# Save current layout
save_layout

echo "Setup complete. Attaching to session..."
# Attach to the session
exec tmux attach-session -t "$SESSION_NAME"
