#!/bin/bash

# Detect optimal number of jobs (number of CPU cores + 1 for I/O operations)
if command -v nproc >/dev/null 2>&1; then
    DEFAULT_JOBS=$(($(nproc) + 1))
else
    # Fallback to 8 jobs if nproc is not available
    DEFAULT_JOBS=8
fi

# Default values
MAX_CONCURRENT_JOBS=$DEFAULT_JOBS
VERBOSE=false
FETCH_ONLY=false

# Parse command line options
while getopts "j:vfh" opt; do
    case $opt in
        j) MAX_CONCURRENT_JOBS=$OPTARG ;;
        v) VERBOSE=true ;;
        f) FETCH_ONLY=true ;;
        h)
            echo "Usage: $0 [-j jobs] [-v] [-f] [-h]"
            echo "  -j N  Maximum number of concurrent jobs (default: auto-detected based on CPU cores)"
            echo "  -v    Verbose output"
            echo "  -f    Fetch only (don't merge)"
            echo "  -h    Show this help message"
            exit 0
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

# Temporary file to hold repositories where errors occurred
failed_repos_file=$(mktemp) || {
    echo "Failed to create temporary file"
    exit 1
}

# Ensure cleanup on script exit
trap 'rm -f "$failed_repos_file"' EXIT

# Functions to print messages
print_error() {
    printf '\n\033[0;31m[ERROR] %s\033[0m\n' "$1" >&2
}
export -f print_error

print_info() {
    printf '\033[0;32m[INFO] %s\033[0m\n' "$1"
}
export -f print_info

print_debug() {
    if [ "$VERBOSE" = true ]; then
        printf '\033[0;34m[DEBUG] %s\033[0m\n' "$1"
    fi
}
export -f print_debug

# Function to pull changes in Git repository
perform_git_operations() {
    local repo_dir=$1
    local original_dir=$(pwd)
    local repo_output=""

    cd "$repo_dir" || { repo_output+=$(print_error "Cannot change to directory: $repo_dir"); echo "$repo_dir" >> "$2"; return 1; }

    repo_output+=$(print_info "Processing repository in directory: $repo_dir")
    
    if [ "$VERBOSE" = true ]; then
        repo_output+=$(print_debug "Current branch: $(git branch --show-current)")
    fi

    if [ "$FETCH_ONLY" = true ]; then
        git fetch --all --prune
        local status=$?
        [ "$VERBOSE" = true ] && repo_output+=$(print_debug "Fetch completed with status: $status")
    else
        git pull
        local status=$?
        [ "$VERBOSE" = true ] && repo_output+=$(print_debug "Pull completed with status: $status")
    fi

    if [ $status -ne 0 ]; then
        repo_output+=$(print_error "Git operation failed in repository: $repo_dir")
        echo "$repo_dir" >> "$2"
        printf "%b" "$repo_output\n"
        cd "$original_dir"
        return 1
    fi

    printf "%b" "$repo_output\n"
    cd "$original_dir"
}

# Export function and variables so they're available in the subshell
export -f perform_git_operations
export VERBOSE
export FETCH_ONLY

# Print starting message with configuration
print_info "Script started with configuration:"
print_info "- Max concurrent jobs: $MAX_CONCURRENT_JOBS"
print_info "- Verbose mode: $VERBOSE"
print_info "- Fetch only mode: $FETCH_ONLY"

# Find git repositories and process them concurrently
find . -type d -name ".git" -print0 | \
    xargs -0 -n1 -I{} -P"$MAX_CONCURRENT_JOBS" \
    bash -c 'dir=$(dirname "$1"); perform_git_operations "$dir" "'"$failed_repos_file"'"' _ {}

# Print ending message
print_info "Script finished."

# Print repositories where errors occurred
if [ ! -s "$failed_repos_file" ]; then
    print_info "All repositories processed successfully."
else
    print_error "Errors occurred in the following repositories:"
    while IFS= read -r repo; do
        print_error "- $repo"
    done < "$failed_repos_file"
fi
