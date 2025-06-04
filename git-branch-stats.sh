#!/bin/bash

# Default main branch
main_branch="main"

# Function to show usage
show_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -m, --main-branch BRANCH    Specify the main branch (default: main)"
  echo "  -h, --help                  Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0                          # Use default 'main' branch"
  echo "  $0 -m master                # Use 'master' as main branch"
  echo "  $0 --main-branch develop    # Use 'develop' as main branch"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -m|--main-branch)
      main_branch="$2"
      shift 2
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
  esac
done

# Validate that the specified main branch exists
if ! git show-ref --verify --quiet "refs/heads/$main_branch"; then
  echo "Error: Branch '$main_branch' does not exist in this repository."
  echo "Available branches:"
  git branch --format="  %(refname:short)"
  exit 1
fi

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print headers
print_headers() {
  printf "%-30s | %-20s | %-12s | %-10s | %-20s\n" "Branch" "Last Commit" "Merged Status" "Behind/Ahead" "Additions/Deletions"
  printf "%s\n" "--------------------------------------------------------------------------------------------------------------------"
}

# Header
print_headers

# Iterate over all local branches sorted by last commit date (oldest to newest)
for branch in $(git for-each-ref --sort=committerdate --format='%(refname:short)' refs/heads/); do
  # Skip the main branch
  if [ "$branch" == "$main_branch" ]; then
    continue
  fi

  # Truncate branch name to 30 characters
  if [ ${#branch} -gt 30 ]; then
    display_branch="${branch:0:27}..."
  else
    display_branch="$branch"
  fi

  # Get the date of the last commit in relative format
  last_commit=$(git log -1 --format="%cr" "$branch" 2>/dev/null)

  # Get the number of commits the branch is behind and ahead of main
  ahead_behind=$(git rev-list --left-right --count "$main_branch...$branch" 2>/dev/null)
  behind=$(echo "$ahead_behind" | awk '{print $1}')
  ahead=$(echo "$ahead_behind" | awk '{print $2}')
  
  # Set defaults if no matches found or if values are empty
  behind=${behind:-0}
  ahead=${ahead:-0}
  
  # Validate that behind and ahead are integers
  if ! [[ "$behind" =~ ^[0-9]+$ ]]; then
    behind=0
  fi
  if ! [[ "$ahead" =~ ^[0-9]+$ ]]; then
    ahead=0
  fi

  # Get the number of additions and deletions compared to main
  diff_stats=$(git diff --shortstat "$main_branch...$branch" 2>/dev/null)
  additions=$(echo "$diff_stats" | sed -n 's/.* \([0-9][0-9]*\) insertion.*/\1/p')
  deletions=$(echo "$diff_stats" | sed -n 's/.* \([0-9][0-9]*\) deletion.*/\1/p')
  
  # Set defaults if no matches found
  additions=${additions:-0}
  deletions=${deletions:-0}

  # Check merge status
  if git merge-base --is-ancestor "$branch" "$main_branch" 2>/dev/null; then
    if [ "$ahead" -eq 0 ]; then
      merge_status="Merged"
      merge_color="${GREEN}"
    else
      merge_status="Diverged"
      merge_color="${YELLOW}"
    fi
  else
    merge_status="Unmerged"
    merge_color="${RED}"
  fi

  # Color coding for behind count
  if [ "$behind" -gt 20 ]; then
    behind_color="${RED}"
  elif [ "$behind" -gt 10 ]; then
    behind_color="${YELLOW}"
  else
    behind_color="${GREEN}"
  fi

  # Color coding for ahead count
  if [ "$ahead" -gt 0 ]; then
    ahead_color="${CYAN}"
  else
    ahead_color="${NC}"
  fi

  # Color coding for additions
  if [ "$additions" -gt 1000 ]; then
    additions_color="${MAGENTA}"
  elif [ "$additions" -gt 100 ]; then
    additions_color="${BLUE}"
  elif [ "$additions" -gt 0 ]; then
    additions_color="${GREEN}"
  else
    additions_color="${NC}"
  fi

  # Color coding for deletions
  if [ "$deletions" -gt 1000 ]; then
    deletions_color="${RED}"
  elif [ "$deletions" -gt 100 ]; then
    deletions_color="${YELLOW}"
  elif [ "$deletions" -gt 0 ]; then
    deletions_color="${MAGENTA}"
  else
    deletions_color="${NC}"
  fi

  # Output the information with colors using echo -e (reordered columns)
  echo -e "$(printf "%-30s | %-20s | " "$display_branch" "$last_commit")${merge_color}$(printf "%-12s" "$merge_status")${NC} | ${behind_color}$(printf "%5s" "$behind")${NC}/${ahead_color}$(printf "%-5s" "$ahead")${NC} | ${additions_color}$(printf "%7s" "$additions")${NC}/${deletions_color}$(printf "%-12s" "$deletions")${NC}"
done

# Footer headers for reference when output is long
echo ""
print_headers