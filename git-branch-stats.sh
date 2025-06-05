#!/bin/bash

# Default main branch
main_branch="main"
debug_mode=false

# Function to show usage
show_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -m, --main-branch BRANCH    Specify the main branch (default: main)"
  echo "  -d, --debug                 Show debug information including terminal width"
  echo "  -h, --help                  Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0                          # Use default 'main' branch"
  echo "  $0 -m master                # Use 'master' as main branch"
  echo "  $0 --main-branch develop    # Use 'develop' as main branch"
  echo "  $0 --debug                  # Show terminal width calculation"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -m|--main-branch)
      main_branch="$2"
      shift 2
      ;;
    -d|--debug)
      debug_mode=true
      shift
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
ORANGE='\033[0;33m\033[38;5;214m'  # Orange color
NC='\033[0m' # No Color

# Get terminal width - try multiple methods
# First try the COLUMNS environment variable (most reliable in scripts)
TERM_WIDTH=${COLUMNS:-}

# If COLUMNS is not set, try stty size (most reliable)
if [ -z "$TERM_WIDTH" ]; then
  TERM_WIDTH=$(stty size 2>/dev/null | awk '{print $2}')
fi

# If stty failed, try tput
if [ -z "$TERM_WIDTH" ] || [ "$TERM_WIDTH" -eq 0 ]; then
  TERM_WIDTH=$(tput cols 2>/dev/null)
fi

# Default to 120 if we couldn't get terminal width
TERM_WIDTH=${TERM_WIDTH:-120}

# Subtract 2 from terminal width to prevent line wrapping
TERM_WIDTH=$((TERM_WIDTH - 10))

# Calculate available width for branch name
# Format: Branch | 12 chars | 8 chars | 11 chars | 15 chars
# Total fixed: 12 + 8 + 11 + 15 = 46 chars for data columns
# Plus 4 separators of 3 chars each = 12 chars
# Total fixed width = 58 chars
FIXED_WIDTH=58
BRANCH_WIDTH=$((TERM_WIDTH - FIXED_WIDTH))

# Ensure minimum branch width
if [ "$BRANCH_WIDTH" -lt 20 ]; then
  BRANCH_WIDTH=20
fi

# Show debug information if requested
if [ "$debug_mode" = true ]; then
  echo "=== Debug Information ==="
  echo "Terminal width detected: $TERM_WIDTH"
  echo "Fixed columns width: $FIXED_WIDTH"
  echo "Branch column width: $BRANCH_WIDTH"
  echo "COLUMNS env variable: ${COLUMNS:-not set}"
  echo "tput cols output: $(tput cols 2>/dev/null || echo 'failed')"
  echo "stty size output: $(stty size 2>/dev/null || echo 'failed')"
  echo "========================"
  echo ""
fi

# Function to print headers
print_headers() {
  printf "%-${BRANCH_WIDTH}s | %12s | %8s | %11s | %15s\n" "Branch" "Last Commit" "Status" "Behind/Ahead" "Add/Del"
  printf "%${TERM_WIDTH}s\n" "" | tr ' ' '-'
}

# Header
print_headers

# Iterate over all local branches sorted by last commit date (oldest to newest)
for branch in $(git for-each-ref --sort=committerdate --format='%(refname:short)' refs/heads/); do
  # Skip the main branch
  if [ "$branch" == "$main_branch" ]; then
    continue
  fi

  # Truncate branch name if needed
  if [ ${#branch} -gt "$BRANCH_WIDTH" ]; then
    display_branch="${branch:0:$((BRANCH_WIDTH-3))}..."
  else
    display_branch="$branch"
  fi

  # Get the date of the last commit in relative format
  last_commit=$(git log -1 --format="%cr" "$branch" 2>/dev/null)
  
  # Truncate last_commit to 12 chars if needed
  if [ ${#last_commit} -gt 12 ]; then
    last_commit="${last_commit:0:12}"
  fi

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

  # Check merge status - works with both merge and rebase workflows
  # First check if branch is ancestor (traditional merge)
  if git merge-base --is-ancestor "$branch" "$main_branch" 2>/dev/null; then
    if [ "$ahead" -eq 0 ]; then
      merge_status="Merged"
      merge_color="${GREEN}"
    else
      merge_status="Diverged"
      merge_color="${YELLOW}"
    fi
  else
    # Use git cherry to detect if commits have been rebased into main
    # The --cherry flag marks commits that have equivalent changes in main with '='
    cherry_output=$(git log --cherry --oneline "$main_branch...$branch" 2>/dev/null)
    
    # Count commits that are unique to the branch (not prefixed with '=')
    unique_commits=$(echo "$cherry_output" | grep -v "^=" | wc -l | tr -d ' ')
    
    # Count commits that have been cherry-picked/rebased (prefixed with '=')
    rebased_commits=$(echo "$cherry_output" | grep "^=" | wc -l | tr -d ' ')
    
    # Check if there are any actual file differences
    has_differences=$(git diff --quiet "$main_branch...$branch" 2>/dev/null; echo $?)
    
    if [ "$unique_commits" -eq 0 ] && [ "$rebased_commits" -gt 0 ]; then
      # All commits have been rebased into main
      merge_status="Rebased"
      merge_color="${ORANGE}"
    elif [ "$unique_commits" -eq 0 ] && [ "$ahead" -eq 0 ]; then
      # No commits ahead, likely merged
      merge_status="Merged"
      merge_color="${GREEN}"
    elif [ "$rebased_commits" -gt 0 ] && [ "$unique_commits" -gt 0 ]; then
      # Some commits rebased, some not
      merge_status="Partial"
      merge_color="${YELLOW}"
    elif [ "$additions" -eq 0 ] && [ "$deletions" -eq 0 ] && [ "$ahead" -gt 0 ]; then
      # Branch has commits but no actual changes
      merge_status="Empty"
      merge_color="${BLUE}"
    else
      merge_status="Unmerged"
      merge_color="${RED}"
    fi
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

  # Output the information with properly formatted columns
  printf "%-${BRANCH_WIDTH}s | %12s | ${merge_color}%8s${NC} | " \
    "$display_branch" \
    "$last_commit" \
    "$merge_status"
  
  # Format behind/ahead with compact spacing
  printf "${behind_color}%5s${NC}/${ahead_color}%-5s${NC} | " "$behind" "$ahead"
  
  # Format additions/deletions with compact spacing  
  printf "${additions_color}%7s${NC}/${deletions_color}%-7s${NC}\n" "$additions" "$deletions"
done

# Footer headers for reference when output is long
echo ""
print_headers