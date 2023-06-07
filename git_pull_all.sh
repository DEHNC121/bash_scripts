#!/bin/bash

function git_pull {
  # Check if the directory has a .git folder
  if [ -d ".git" ]; then
    echo "Updating $PWD"
    git pull
  fi

  # Recursively call the git_pull function for all subdirectories
  for dir in */; do
    if [ -d "$dir" ]; then
      cd "$dir" || exit
      git_pull
      cd ..
    fi
  done
}

# Call the git_pull function from the current directory
git_pull

