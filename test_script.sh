#!/bin/bash

# Kolorowe warianty
declare -r GREEN='\033[0;32m'
declare -r RED='\033[0;31m'
declare -r YELLOW='\033[0;33m'
declare -r BLUE='\033[0;34m'
declare -r NC='\033[0m' # Zresetowanie kolorów

# Funkcje do wyświetlania komunikatów
print_error() {
  printf "${RED}Błąd: %s${NC}\n" "$1"
}

print_info() {
  printf "${BLUE}Info: %s${NC}\n" "$1"
}

# Funkcja do wykonywania operacji na repozytorium Git
perform_git_operations() {
  local repository_dir=$1

  cd "$repository_dir" || { print_error "Nie można przejść do katalogu: $repository_dir"; return 1; }

  printf "${GREEN}Praca w repozytorium: %s${NC}\n" "$repository_dir"

  if git rev-parse --verify "stash@{0}" >/dev/null 2>&1; then
    git stash apply || { print_error "Nie można przywrócić zmian z operacji stash w repozytorium: $repository_dir"; return 1; }
  else
    printf "${YELLOW}Brak zapisanych zmian w operacji stash w repozytorium: %s${NC}\n" "$repository_dir"
  fi

  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)

  git switch master || { print_error "Nie można przełączyć na gałąź master w repozytorium: $repository_dir"; return 1; }

  git pull || { print_error "Nie można pobrać zmian z zdalnego repozytorium w repozytorium: $repository_dir"; return 1; }

  git switch "$current_branch" || { print_error "Nie można przełączyć na pierwotną gałąź w repozytorium: $repository_dir"; return 1; }

  git rebase origin/master || { print_error "Nie można wykonać operacji rebase w repozytorium: $repository_dir"; return 1; }

  printf "${GREEN}Zadanie zakończone dla repozytorium: %s${NC}\n" "$repository_dir"
}

# Sprawdź czy dostarczono ścieżkę jako argument
if [ $# -eq 0 ]; then
  print_error "Brak podanej ścieżki. Użycie: $0 /ścieżka/do/katalogu"
  exit 1
fi

# Wprowadź ścieżkę do określonego katalogu
directory="$1"

if [ ! -d "$directory" ]; then
  print_error "Katalog $directory nie istnieje."
  exit 1
fi

# Wydruk powiadomienia o rozpoczęciu skryptu
print_info "Rozpoczynam skrypt..."

# Przejście przez foldery w określonym katalogu
find "$directory" -type d -name ".git" | while read -r git_dir; do
  repository_dir=$(dirname "$git_dir")

  if [[ -d "$repository_dir/.git" ]]; then
    perform_git_operations "$repository_dir" || continue
  fi
done

# Wydruk powiadomienia o zakończeniu skryptu
print_info "Skrypt zakończony."

#directory="$HOME/aos/sdk/master/workspace"