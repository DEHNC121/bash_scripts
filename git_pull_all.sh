#!/bin/bash

# Temporary file to hold repositories where errors occurred
failed_repos_file=$(mktemp)

# Functions to print messages
print_error() {
    printf '\n\033[0;31mError: %s\033[0m\n' "$1"
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

    cd "$repo_dir" || { repo_output+=$(print_error "Cannot change to directory: $repo_dir"); echo "$repo_dir" >> "$2"; return 1; }

    repo_output+=$(print_info "Processing repository in directory: $repo_dir")

    git pull
    if [ $? -ne 0 ]; then
        repo_output+=$(print_error "Cannot pull latest changes in repository: $repo_dir")
        echo "$repo_dir" >> "$2"
        printf "%b" "$repo_output\n"
        cd "$original_dir"
        return 1
    fi

    printf "%b" "$repo_output\n"
    cd "$original_dir"
}

# Export function so it's available in the subshell used by xargs
export -f perform_git_operations

# Print starting message
print_info "Script started..."

# Find git repositories and process them concurrently
find . -type d -name ".git" -print0 | xargs -0 -n1 -I{} -P8 bash -c 'dir=$(dirname "$1"); perform_git_operations "$dir" "'"$failed_repos_file"'"' _ {}

# Print ending message
print_info "Script finished."

# Print repositories where errors occurred
if [ ! -s "$failed_repos_file" ]; then
    print_info "No errors occurred in any repositories."
else
    print_error "Errors occurred in the following repositories:"
    cat "$failed_repos_file"
fi

# Clean up temporary file
rm -f "$failed_repos_file"
