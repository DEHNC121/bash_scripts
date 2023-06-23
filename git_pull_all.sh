#!/bin/bash

# An array to hold repositories where errors occurred
declare -a failed_repos=()

# Functions to print messages
print_error() {
    printf '\033[0;31mError: %s\033[0m\n' "$1"
}
export -f print_error

print_info() {
    printf '\033[0;32mInfo: %s\033[0m\n' "$1"
}
export -f print_info

# Function to pull changes in Git repository
perform_git_operations() {
    local repo_dir=$1
    local original_dir=$(pwd)
    local repo_output=""  # to hold output for this repository

    # Ensure we always return to the original directory
    trap 'cd "$original_dir"' RETURN

    cd "$repo_dir" || { repo_output+=$(print_error "Cannot change to directory: $repo_dir"); failed_repos+=("$repo_dir"); return 1; }

    repo_output+=$(print_info "Processing repository in directory: $repo_dir")

    # git pull &>/dev/null
    git pull
    if [ $? -ne 0 ]; then
        repo_output+=$(print_error "Cannot pull latest changes in repository: $repo_dir")
        failed_repos+=("$repo_dir")
        printf "%b" "$repo_output\n"
        return 1
    fi

    printf "%b" "$repo_output\n"
}

# Export function so it's available in the subshell used by xargs
export -f perform_git_operations

# Print starting message
print_info "Script started..."

# Find git repositories and process them concurrently
find . -type d -name ".git" -print0 | xargs -0 -n1 -I{} -P8 bash -c 'dir=$(dirname "$1"); perform_git_operations "$dir"' _ {}

# Print ending message
print_info "Script finished."

# Print repositories where errors occurred
if [ ${#failed_repos[@]} -eq 0 ]; then
    print_info "No errors occurred in any repositories."
else
    print_error "Errors occurred in the following repositories:"
    for repo in "${failed_repos[@]}"; do
        echo "$repo"
    done
fi
