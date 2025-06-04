#!/bin/bash

# Git Branch Cleanup Tool
# Based on git-branch-stats.sh, this tool helps clean up merged branches safely

set -e

# Default configuration
main_branch="main"
dry_run=true  # Now defaults to dry-run (preview mode)
interactive=true
force=false
age_days=""
verbose=false
include_ancestors=false
include_diverged=false
include_unmerged=false

# Protected branches that require explicit confirmation
# These branches will ALWAYS require manual confirmation, even in force mode
PROTECTED_BRANCHES=(
    "main"
    "master" 
    "develop"
    "development"
    "dev"
    "staging"
    "stage"
    "test"
    "testing"
    "qa"
    "uat"
    "production"
    "prod"
    "release"
    "hotfix"
    "beta"
    "alpha"
    "stable"
    "live"
    "demo"
    "preview"
    "gh-pages"
    "pages"
    "docs"
    "documentation"
)

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Usage function
usage() {
    cat << EOF
Git Branch Cleanup Tool

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -m, --main BRANCH       Specify main branch (default: main)
    -e, --execute           Actually delete branches (default is preview mode)
    -f, --force             Skip interactive confirmation (use with caution)
    -a, --age DAYS          Only delete branches older than DAYS days
    -v, --verbose           Show detailed information
    --merged-only           Only clean up actually merged branches (default behavior)
    --include-diverged      Also clean up diverged branches (branches that have been rebased)
    --include-ancestors     Include ancestor branches (potential false positives - use with caution)
    --include-unmerged      Also clean up unmerged branches (branches that contain commits not in main branch)
    --list-protected        List all protected branch names and exit

BRANCH STATUS DETECTION:
    ACTUALLY MERGED     - Branch was properly merged via merge commit or PR
    ANCESTOR ONLY      - Branch is ancestor of main but NOT actually merged (potential false positive)
    DIVERGED           - Branch was merged but has additional commits (rebased after merge)
    UNMERGED           - Branch contains commits not in main branch

EXAMPLES:
    $0                              # Preview cleanup of actually merged branches (safe default)
    $0 --execute                    # Actually delete merged branches after confirmation
    $0 --execute --force --age 30   # Auto-delete actually merged branches older than 30 days
    $0 --include-ancestors --verbose # Preview potential false positives (ancestor branches)
    $0 --include-unmerged --age 90  # Preview unmerged branches older than 90 days
    $0 --execute --main develop     # Actually delete branches using 'develop' as main branch

SAFETY FEATURES:
    - PREVIEW MODE BY DEFAULT (no deletions unless --execute is used)
    - Interactive mode by default (requires confirmation for each branch)
    - Never deletes the current branch or main branch
    - Distinguishes between actually merged vs ancestor-only branches
    - Shows detailed branch information before deletion
    - Warns about potential false positives
    - Protected branches require explicit name confirmation (even in force mode)
    - Unmerged branches show commits that would be lost and require name confirmation

PROTECTED BRANCHES:
    The following branches are considered protected and require typing the exact
    branch name to confirm deletion (even with --force):
    
    main, master, develop, development, dev, staging, stage, test, testing,
    qa, uat, production, prod, release, hotfix, beta, alpha, stable, live,
    demo, preview, gh-pages, pages, docs, documentation

UNMERGED BRANCH SAFETY:
    When --include-unmerged is used, the tool will:
    - Show all commits that would be permanently lost
    - Display a prominent data loss warning
    - Require typing the exact branch name to confirm
    - Work even in force mode (always requires confirmation)
    - Recommend using --age filter for safer automated cleanup

EOF
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_verbose() {
    if [ "$verbose" = true ]; then
        echo -e "${CYAN}[VERBOSE]${NC} $1"
    fi
}

# Validation functions
validate_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not a git repository"
        exit 1
    fi
}

validate_main_branch() {
    if ! git show-ref --verify --quiet "refs/heads/$main_branch"; then
        log_error "Main branch '$main_branch' does not exist"
        exit 1
    fi
}

get_current_branch() {
    git branch --show-current
}

# Protected branch functions
is_protected_branch() {
    local branch="$1"
    local protected_branch
    
    for protected_branch in "${PROTECTED_BRANCHES[@]}"; do
        if [ "$branch" = "$protected_branch" ]; then
            return 0
        fi
    done
    return 1
}

confirm_protected_branch_deletion() {
    local branch="$1"
    local user_input
    
    echo
    echo -e "${BOLD}${RED}████████████████████████████████████████████████████████████████${NC}"
    echo -e "${BOLD}${RED}█                                                              █${NC}"
    echo -e "${BOLD}${RED}█                 ⚠️  PROTECTED BRANCH WARNING ⚠️               █${NC}"
    echo -e "${BOLD}${RED}█                                                              █${NC}"
    echo -e "${BOLD}${RED}████████████████████████████████████████████████████████████████${NC}"
    echo
    echo -e "${BOLD}${RED}🚨 DANGER: You are about to delete a PROTECTED branch: ${CYAN}$branch${NC}"
    echo
    echo -e "${YELLOW}Protected branches are typically critical infrastructure branches like:${NC}"
    echo -e "  • Main development branches (main, master, develop)"
    echo -e "  • Environment branches (staging, production, test)"
    echo -e "  • Release branches (release, hotfix)"
    echo -e "  • Documentation branches (gh-pages, docs)"
    echo
    echo -e "${BOLD}${RED}⚠️  This action is EXTREMELY DANGEROUS and could disrupt your entire team!${NC}"
    echo
    get_branch_info "$branch"
    echo
    echo -e "${BOLD}${RED}To confirm this dangerous action, type the EXACT branch name: ${CYAN}$branch${NC}"
    echo -e "${BOLD}${YELLOW}Or type 'abort' to cancel, or 'quit' to exit the program${NC}"
    echo
    
    while true; do
        read -p "Type branch name to confirm deletion: " user_input
        case "$user_input" in
            "$branch")
                echo -e "${RED}⚠️  CONFIRMED: Proceeding with deletion of protected branch '$branch'${NC}"
                return 0
                ;;
            "abort"|"cancel"|"no"|"n")
                echo -e "${GREEN}✓ Aborted deletion of protected branch '$branch'${NC}"
                return 1
                ;;
            "quit"|"exit"|"q")
                echo -e "${YELLOW}Exiting program as requested${NC}"
                exit 0
                ;;
            "")
                echo -e "${RED}Empty input. Please type the exact branch name '$branch' to confirm, or 'abort' to cancel.${NC}"
                ;;
            *)
                echo -e "${RED}Input '$user_input' does not match branch name '$branch'.${NC}"
                echo -e "${YELLOW}Please type the exact branch name '$branch' to confirm, or 'abort' to cancel.${NC}"
                ;;
        esac
    done
}

confirm_unmerged_branch_deletion() {
    local branch="$1"
    local user_input
    local commit_count
    local ahead_behind
    local ahead
    
    # Get commit count that would be lost
    ahead_behind=$(git rev-list --left-right --count "$main_branch...$branch" 2>/dev/null)
    ahead=$(echo "$ahead_behind" | awk '{print $2}')
    
    echo
    echo -e "${BOLD}${RED}████████████████████████████████████████████████████████████████${NC}"
    echo -e "${BOLD}${RED}█                                                              █${NC}"
    echo -e "${BOLD}${RED}█                ⚠️  UNMERGED BRANCH WARNING ⚠️                █${NC}"
    echo -e "${BOLD}${RED}█                                                              █${NC}"
    echo -e "${BOLD}${RED}████████████████████████████████████████████████████████████████${NC}"
    echo
    echo -e "${BOLD}${RED}🚨 DATA LOSS WARNING: You are about to delete an UNMERGED branch: ${CYAN}$branch${NC}"
    echo
    echo -e "${BOLD}${YELLOW}This branch contains ${RED}$ahead commits${YELLOW} that are NOT in the main branch!${NC}"
    echo -e "${YELLOW}These commits will be PERMANENTLY LOST if you proceed:${NC}"
    echo
    
    # Show the commits that would be lost
    echo -e "${BOLD}${RED}Commits that will be lost:${NC}"
    git log --oneline --color=always "$main_branch..$branch" | head -10 | sed 's/^/  📝 /'
    if [ "$ahead" -gt 10 ]; then
        echo -e "  ${YELLOW}... and $((ahead - 10)) more commits${NC}"
    fi
    echo
    
    # Show branch details
    get_branch_info "$branch"
    echo
    
    echo -e "${BOLD}${RED}⚠️  This action will PERMANENTLY DELETE $ahead commits of work!${NC}"
    echo -e "${BOLD}${RED}⚠️  This action CANNOT be undone!${NC}"
    echo
    echo -e "${BOLD}${RED}To confirm this dangerous action, type the EXACT branch name: ${CYAN}$branch${NC}"
    echo -e "${BOLD}${YELLOW}Or type 'abort' to cancel, or 'quit' to exit the program${NC}"
    echo
    
    while true; do
        read -p "Type branch name to confirm deletion: " user_input
        case "$user_input" in
            "$branch")
                echo -e "${RED}⚠️  CONFIRMED: Proceeding with deletion of unmerged branch '$branch' (losing $ahead commits)${NC}"
                return 0
                ;;
            "abort"|"cancel"|"no"|"n")
                echo -e "${GREEN}✓ Aborted deletion of unmerged branch '$branch' (preserved $ahead commits)${NC}"
                return 1
                ;;
            "quit"|"exit"|"q")
                echo -e "${YELLOW}Exiting program as requested${NC}"
                exit 0
                ;;
            "")
                echo -e "${RED}Empty input. Please type the exact branch name '$branch' to confirm, or 'abort' to cancel.${NC}"
                ;;
            *)
                echo -e "${RED}Input '$user_input' does not match branch name '$branch'.${NC}"
                echo -e "${YELLOW}Please type the exact branch name '$branch' to confirm, or 'abort' to cancel.${NC}"
                ;;
        esac
    done
}

# Core functions
is_branch_merged() {
    local branch="$1"
    git merge-base --is-ancestor "$branch" "$main_branch" 2>/dev/null
}

was_branch_actually_merged() {
    local branch="$1"
    local branch_tip
    local merge_commits
    
    branch_tip=$(git rev-parse "$branch" 2>/dev/null)
    
    # Look for merge commits in main that include this branch's tip commit
    # This checks if there's a merge commit in main's history that has this branch as a parent
    merge_commits=$(git rev-list --merges "$main_branch" --grep="Merge.*$branch" 2>/dev/null || true)
    
    if [ -n "$merge_commits" ]; then
        return 0
    fi
    
    # Alternative: check if branch tip appears in main's first-parent history
    # This catches squash merges or direct merges
    if git merge-base --is-ancestor "$branch_tip" "$main_branch" 2>/dev/null; then
        # Check if the branch tip commit appears in main's history
        if git rev-list --first-parent "$main_branch" | grep -q "^$branch_tip$" 2>/dev/null; then
            return 0
        fi
    fi
    
    return 1
}

is_branch_fully_merged() {
    local branch="$1"
    local ahead_behind
    local ahead
    
    ahead_behind=$(git rev-list --left-right --count "$main_branch...$branch" 2>/dev/null)
    ahead=$(echo "$ahead_behind" | awk '{print $2}')
    
    # A branch is "fully merged" if:
    # 1. It has no commits ahead of main (ahead = 0)
    # 2. AND it was actually merged (not just an ancestor)
    if [ "$ahead" -eq 0 ] && is_branch_merged "$branch"; then
        if was_branch_actually_merged "$branch"; then
            return 0
        else
            # This is likely a false positive - branch became ancestor but wasn't merged
            return 1
        fi
    fi
    
    return 1
}

get_branch_age_days() {
    local branch="$1"
    local last_commit_timestamp
    local current_timestamp
    local age_seconds
    
    last_commit_timestamp=$(git log -1 --format="%ct" "$branch" 2>/dev/null)
    current_timestamp=$(date +%s)
    age_seconds=$((current_timestamp - last_commit_timestamp))
    echo $((age_seconds / 86400))
}

get_merge_status() {
    local branch="$1"
    local ahead_behind
    local behind
    local ahead
    
    ahead_behind=$(git rev-list --left-right --count "$main_branch...$branch" 2>/dev/null)
    behind=$(echo "$ahead_behind" | awk '{print $1}')
    ahead=$(echo "$ahead_behind" | awk '{print $2}')
    
    if [ "$ahead" -eq 0 ]; then
        # Branch has no commits ahead of main
        if is_branch_merged "$branch"; then
            if was_branch_actually_merged "$branch"; then
                echo "MERGED"
            else
                echo "ANCESTOR"  # New status for false positives
            fi
        else
            echo "UNMERGED"
        fi
    else
        # Branch has commits ahead of main
        if is_branch_merged "$branch"; then
            echo "DIVERGED"
        else
            echo "UNMERGED"
        fi
    fi
}

display_merge_status_banner() {
    local status="$1"
    local branch="$2"
    
    case $status in
        "MERGED")
            echo -e "${BOLD}${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${BOLD}${WHITE}║${NC} ${BOLD}${GREEN}✓ ACTUALLY MERGED${NC} ${BOLD}${WHITE}- Safe to delete                         ║${NC}"
            echo -e "${BOLD}${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
            ;;
        "ANCESTOR")
            echo -e "${BOLD}${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${BOLD}${WHITE}║${NC} ${BOLD}${RED}⚠ ANCESTOR ONLY${NC} ${BOLD}${WHITE}- NOT actually merged, just older!        ║${NC}"
            echo -e "${BOLD}${WHITE}║${NC} ${BOLD}${YELLOW}  This branch may contain unmerged work - review carefully!${NC}   ${BOLD}${WHITE}║${NC}"
            echo -e "${BOLD}${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
            ;;
        "DIVERGED")
            echo -e "${BOLD}${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${BOLD}${WHITE}║${NC} ${BOLD}${YELLOW}⚠ DIVERGED${NC} ${BOLD}${WHITE}- Merged but has additional commits            ║${NC}"
            echo -e "${BOLD}${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
            ;;
        "UNMERGED")
            echo -e "${BOLD}${WHITE}╔════════════════════════════════════════════════════════════════╗${NC}"
            echo -e "${BOLD}${WHITE}║${NC} ${BOLD}${RED}✗ UNMERGED${NC} ${BOLD}${WHITE}- Contains commits not in main branch          ║${NC}"
            echo -e "${BOLD}${WHITE}╚════════════════════════════════════════════════════════════════╝${NC}"
            ;;
    esac
}

get_branch_info() {
    local branch="$1"
    local last_commit
    local ahead_behind
    local behind
    local ahead
    local age_days
    local merge_status
    
    last_commit=$(git log -1 --format="%cr" "$branch" 2>/dev/null)
    ahead_behind=$(git rev-list --left-right --count "$main_branch...$branch" 2>/dev/null)
    behind=$(echo "$ahead_behind" | awk '{print $1}')
    ahead=$(echo "$ahead_behind" | awk '{print $2}')
    age_days=$(get_branch_age_days "$branch")
    merge_status=$(get_merge_status "$branch")
    
    # Display the prominent merge status banner
    display_merge_status_banner "$merge_status" "$branch"
    echo
    
    # Display detailed branch information
    echo -e "${BOLD}Branch Details:${NC}"
    echo -e "  ${CYAN}Name:${NC} $branch"
    echo -e "  ${CYAN}Last commit:${NC} $last_commit ($age_days days ago)"
    echo -e "  ${CYAN}Behind main:${NC} $behind commits"
    echo -e "  ${CYAN}Ahead of main:${NC} $ahead commits"
    
    # Show additional warning for ANCESTOR status
    if [ "$merge_status" = "ANCESTOR" ]; then
        echo
        echo -e "  ${BOLD}${RED}⚠ WARNING:${NC} This branch appears to be an ancestor of main but was not"
        echo -e "     actually merged. This often happens when:"
        echo -e "     • Main branch moved forward independently"
        echo -e "     • Branch was created from an old commit"
        echo -e "     • Work was manually copied to main without proper merging"
        echo -e "  ${BOLD}${YELLOW}👀 Please review the branch content before deleting!${NC}"
    fi
    
    # Show commit summary if branch has commits
    if [ "$ahead" -gt 0 ]; then
        echo -e "  ${CYAN}Recent commits:${NC}"
        git log --oneline "$main_branch..$branch" | head -3 | sed 's/^/    /'
        if [ "$ahead" -gt 3 ]; then
            echo "    ... and $((ahead - 3)) more commits"
        fi
    fi
}

should_delete_branch() {
    local branch="$1"
    local current_branch="$2"
    local include_diverged="$3"
    local include_ancestors="$4"
    local include_unmerged="$5"
    local merge_status
    
    # Never delete current branch or main branch
    if [ "$branch" = "$current_branch" ] || [ "$branch" = "$main_branch" ]; then
        return 1
    fi
    
    # Never auto-delete protected branches - they always require explicit confirmation
    if is_protected_branch "$branch"; then
        log_verbose "Skipping protected branch $branch: requires explicit confirmation"
        return 1
    fi
    
    # Check age filter if specified
    if [ -n "$age_days" ]; then
        local branch_age
        branch_age=$(get_branch_age_days "$branch")
        if [ "$branch_age" -lt "$age_days" ]; then
            log_verbose "Skipping $branch: only $branch_age days old (required: $age_days+ days)"
            return 1
        fi
    fi
    
    # Get the merge status to make informed decisions
    merge_status=$(get_merge_status "$branch")
    
    # Check merge status
    case $merge_status in
        "MERGED")
            log_verbose "Branch $branch is actually merged - safe to delete"
            return 0
            ;;
        "ANCESTOR")
            if [ "$include_ancestors" = true ]; then
                log_verbose "Branch $branch is only an ancestor (potential false positive) - including due to --include-ancestors"
                return 0
            else
                log_verbose "Branch $branch is only an ancestor (potential false positive) - requiring manual review"
                return 1  # Don't auto-delete these - require manual confirmation
            fi
            ;;
        "DIVERGED")
            if [ "$include_diverged" = true ]; then
                log_verbose "Branch $branch is merged but diverged (rebased) - including due to --include-diverged"
                return 0
            else
                log_verbose "Skipping $branch: diverged (use --include-diverged to include)"
                return 1
            fi
            ;;
        "UNMERGED")
            if [ "$include_unmerged" = true ]; then
                log_verbose "Branch $branch is unmerged - including due to --include-unmerged"
                return 0
            else
                log_verbose "Skipping $branch: not merged"
                return 1
            fi
            ;;
        *)
            log_verbose "Skipping $branch: unknown merge status"
            return 1
            ;;
    esac
}

confirm_deletion() {
    local branch="$1"
    local merge_status
    
    if [ "$force" = true ]; then
        # Even in force mode, protected branches require explicit confirmation
        if is_protected_branch "$branch"; then
            log_warning "Protected branch '$branch' requires explicit confirmation even in force mode"
            confirm_protected_branch_deletion "$branch"
            return $?
        fi
        
        # Even in force mode, unmerged branches require explicit confirmation
        merge_status=$(get_merge_status "$branch")
        if [ "$merge_status" = "UNMERGED" ]; then
            log_warning "Unmerged branch '$branch' requires explicit confirmation even in force mode"
            confirm_unmerged_branch_deletion "$branch"
            return $?
        fi
        
        return 0
    fi
    
    # Use special confirmation for protected branches
    if is_protected_branch "$branch"; then
        confirm_protected_branch_deletion "$branch"
        return $?
    fi
    
    # Use special confirmation for unmerged branches
    merge_status=$(get_merge_status "$branch")
    if [ "$merge_status" = "UNMERGED" ]; then
        confirm_unmerged_branch_deletion "$branch"
        return $?
    fi
    
    # Standard confirmation for non-protected, non-unmerged branches
    echo
    echo -e "${BOLD}${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${YELLOW}                        BRANCH DELETION CONFIRMATION${NC}"
    echo -e "${BOLD}${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    echo
    get_branch_info "$branch"
    echo
    echo -e "${BOLD}${RED}⚠ WARNING: This action cannot be undone!${NC}"
    echo -e "${BOLD}${BLUE}ℹ️  After confirmation, all branches will be deleted automatically${NC}"
    echo -e "${BOLD}${BLUE}   (except protected branches which still require individual confirmation)${NC}"
    echo
    
    while true; do
        echo -e "${BOLD}Delete branch '${CYAN}$branch${NC}${BOLD}'?${NC}"
        read -p "  [y] Yes, delete it  [N] No, skip  [q] Quit: " choice
        case $choice in
            [Yy]* ) 
                echo -e "${GREEN}✓ Confirmed deletion of $branch${NC}"
                return 0;;
            [Qq]* ) 
                echo -e "${RED}Aborted by user${NC}"
                exit 0;;
            * ) 
                echo -e "${YELLOW}Skipping $branch${NC}"
                return 1;;
        esac
    done
}

delete_branch() {
    local branch="$1"
    
    if [ "$dry_run" = true ]; then
        log_info "PREVIEW: Would delete branch: $branch"
        get_branch_info "$branch"
        return 0
    fi
    
    if git branch -d "$branch" 2>/dev/null; then
        log_success "Deleted branch: $branch"
        return 0
    else
        log_warning "Could not delete branch '$branch' (may have unmerged commits)"
        if [ "$force" = true ]; then
            log_warning "Force deleting branch: $branch"
            git branch -D "$branch"
            log_success "Force deleted branch: $branch"
        else
            echo "Use --force to force delete unmerged branches"
            return 1
        fi
    fi
}

# Main cleanup function
cleanup_branches() {
    local current_branch
    local deleted_count=0
    local skipped_count=0
    local branches_to_delete=()
    local bulk_confirmed=false
    
    current_branch=$(get_current_branch)
    log_info "Current branch: $current_branch"
    log_info "Main branch: $main_branch"
    
    if [ "$dry_run" = true ]; then
        log_warning "PREVIEW MODE - No branches will actually be deleted (use --execute to delete)"
    else
        log_warning "EXECUTE MODE - Branches will be permanently deleted!"
    fi
    
    echo
    
    # First pass: collect all branches that would be deleted
    for branch in $(git for-each-ref --sort=committerdate --format='%(refname:short)' refs/heads/); do
        if should_delete_branch "$branch" "$current_branch" "$include_diverged" "$include_ancestors" "$include_unmerged"; then
            branches_to_delete+=("$branch")
        else
            ((skipped_count++))
        fi
    done
    
    # If we have branches to delete, show summary and get confirmation
    if [ ${#branches_to_delete[@]} -gt 0 ]; then
        if [ "$dry_run" = true ]; then
            echo -e "${BOLD}${BLUE}Preview: Found ${#branches_to_delete[@]} branches that would be deleted${NC}"
            echo
            
            # Show table header
            print_headers
            
            # Show each branch in table format
            for branch in "${branches_to_delete[@]}"; do
                get_branch_table_info "$branch"
            done
            
            # Show footer for reference
            echo
            print_headers
            
            deleted_count=${#branches_to_delete[@]}
        else
            # In execute mode, show summary and get bulk confirmation
            if [ "$force" = false ]; then
                if confirm_bulk_deletion "${branches_to_delete[@]}"; then
                    bulk_confirmed=true
                    echo -e "${GREEN}✓ Bulk confirmation received - proceeding with deletions${NC}"
                else
                    echo -e "${YELLOW}Bulk deletion cancelled by user${NC}"
                    return
                fi
            else
                bulk_confirmed=true
            fi
            
            echo
            log_info "Proceeding with deletion of ${#branches_to_delete[@]} branches..."
            echo
            
            # Second pass: actually delete the branches
            for branch in "${branches_to_delete[@]}"; do
                # Only require individual confirmation for protected branches
                # Unmerged branches were already covered in bulk confirmation
                if is_protected_branch "$branch"; then
                    if ! confirm_deletion "$branch"; then
                        ((skipped_count++))
                        continue
                    fi
                fi
                
                if delete_branch "$branch"; then
                    ((deleted_count++))
                else
                    ((skipped_count++))
                fi
            done
        fi
    else
        log_info "No branches found matching the specified criteria"
    fi
    
    echo
    if [ "$dry_run" = true ]; then
        log_info "Summary (PREVIEW): $deleted_count branches would be deleted, $skipped_count branches skipped"
        echo
        log_info "Use --execute to actually perform the deletions"
    else
        log_info "Summary: $deleted_count branches deleted, $skipped_count branches skipped"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -m|--main)
            main_branch="$2"
            shift 2
            ;;
        -e|--execute)
            dry_run=false
            shift
            ;;
        -f|--force)
            force=true
            interactive=false
            shift
            ;;
        -a|--age)
            age_days="$2"
            # Validate that age_days is a non-negative integer
            if ! [[ "$age_days" =~ ^[0-9]+$ ]]; then
                log_error "Invalid age value: '$age_days'. Must be a non-negative integer (number of days)."
                echo "Example: --age 30 (for branches older than 30 days), --age 0 (for any age)"
                exit 1
            fi
            shift 2
            ;;
        -v|--verbose)
            verbose=true
            shift
            ;;
        --merged-only)
            # This is the default behavior
            shift
            ;;
        --include-diverged)
            include_diverged=true
            shift
            ;;
        --include-ancestors)
            include_ancestors=true
            shift
            ;;
        --include-unmerged)
            include_unmerged=true
            shift
            ;;
        --list-protected)
            echo "Protected branches that require explicit confirmation:"
            printf "  %s\n" "${PROTECTED_BRANCHES[@]}"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Function to print headers (borrowed from git-branch-stats.sh)
print_headers() {
    printf "%-30s | %-20s | %-12s | %-10s | %-20s\n" "Branch" "Last Commit" "Merged Status" "Behind/Ahead" "Additions/Deletions"
    printf "%s\n" "--------------------------------------------------------------------------------------------------------------------"
}

# Function to get branch display info for table
get_branch_table_info() {
    local branch="$1"
    local display_branch
    local last_commit
    local merge_status
    local ahead_behind
    local behind
    local ahead
    local diff_stats
    local additions
    local deletions
    local merge_color
    local behind_color
    local ahead_color
    
    # Truncate branch name to 30 characters
    if [ ${#branch} -gt 30 ]; then
        display_branch="${branch:0:27}..."
    else
        display_branch="$branch"
    fi
    
    # Get the date of the last commit in relative format
    last_commit=$(git log -1 --format="%cr" "$branch" 2>/dev/null)
    
    # Get merge status
    merge_status=$(get_merge_status "$branch")
    
    # Get the number of commits the branch is behind and ahead of main
    ahead_behind=$(git rev-list --left-right --count "$main_branch...$branch" 2>/dev/null)
    behind=$(echo "$ahead_behind" | awk '{print $1}')
    ahead=$(echo "$ahead_behind" | awk '{print $2}')
    
    # Get the number of additions and deletions compared to main
    diff_stats=$(git diff --shortstat "$main_branch...$branch" 2>/dev/null)
    additions=$(echo "$diff_stats" | sed -n 's/.* \([0-9][0-9]*\) insertion.*/\1/p')
    deletions=$(echo "$diff_stats" | sed -n 's/.* \([0-9][0-9]*\) deletion.*/\1/p')
    
    # Set defaults if no matches found
    additions=${additions:-0}
    deletions=${deletions:-0}
    
    # Color coding for merge status
    case $merge_status in
        "MERGED")
            merge_color="${GREEN}"
            ;;
        "ANCESTOR")
            merge_color="${YELLOW}"
            ;;
        "DIVERGED")
            merge_color="${CYAN}"
            ;;
        "UNMERGED")
            merge_color="${RED}"
            ;;
        *)
            merge_color="${NC}"
            ;;
    esac
    
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
    
    # Output the information with colors
    echo -e "$(printf "%-30s | %-20s | " "$display_branch" "$last_commit")${merge_color}$(printf "%-12s" "$merge_status")${NC} | ${behind_color}$(printf "%5s" "$behind")${NC}/${ahead_color}$(printf "%-5s" "$ahead")${NC} | $(printf "%7s" "$additions")/$(printf "%-12s" "$deletions")"
}

# Function to show summary table and get bulk confirmation
confirm_bulk_deletion() {
    local branches_to_delete=("$@")
    local branch_count=${#branches_to_delete[@]}
    local user_input
    
    if [ "$branch_count" -eq 0 ]; then
        return 0
    fi
    
    echo
    echo -e "${BOLD}${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${YELLOW}                    BULK DELETION CONFIRMATION${NC}"
    echo -e "${BOLD}${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${BOLD}The following ${RED}$branch_count branches${NC}${BOLD} will be deleted:${NC}"
    echo
    
    # Show table header
    print_headers
    
    # Show each branch in table format
    for branch in "${branches_to_delete[@]}"; do
        get_branch_table_info "$branch"
    done
    
    # Show footer for reference
    echo
    print_headers
    echo
    
    # Show summary by status
    local merged_count=0
    local ancestor_count=0
    local diverged_count=0
    local unmerged_count=0
    
    for branch in "${branches_to_delete[@]}"; do
        local status=$(get_merge_status "$branch")
        case $status in
            "MERGED") ((merged_count++)) ;;
            "ANCESTOR") ((ancestor_count++)) ;;
            "DIVERGED") ((diverged_count++)) ;;
            "UNMERGED") ((unmerged_count++)) ;;
        esac
    done
    
    echo -e "${BOLD}Summary by Status:${NC}"
    [ "$merged_count" -gt 0 ] && echo -e "  ${GREEN}✓ Actually Merged:${NC} $merged_count branches"
    [ "$ancestor_count" -gt 0 ] && echo -e "  ${YELLOW}⚠ Ancestor Only:${NC} $ancestor_count branches (potential false positives)"
    [ "$diverged_count" -gt 0 ] && echo -e "  ${CYAN}🔄 Diverged:${NC} $diverged_count branches (rebased)"
    [ "$unmerged_count" -gt 0 ] && echo -e "  ${RED}❌ Unmerged:${NC} $unmerged_count branches (will lose commits!)"
    echo
    
    if [ "$unmerged_count" -gt 0 ]; then
        echo -e "${BOLD}${RED}⚠️  WARNING: $unmerged_count unmerged branches will lose commits permanently!${NC}"
    fi
    if [ "$ancestor_count" -gt 0 ]; then
        echo -e "${BOLD}${YELLOW}⚠️  WARNING: $ancestor_count ancestor-only branches may contain unmerged work!${NC}"
    fi
    
    echo
    echo -e "${BOLD}${RED}⚠️  This action cannot be undone!${NC}"
    echo -e "${BOLD}${BLUE}ℹ️  After confirmation, all branches will be deleted automatically${NC}"
    echo -e "${BOLD}${BLUE}   (except protected branches which still require individual confirmation)${NC}"
    echo
    
    while true; do
        echo -e "${BOLD}Type '${CYAN}I understand I am deleting $branch_count branches${NC}${BOLD}' to confirm:${NC}"
        read -p "> " user_input
        case "$user_input" in
            "I understand I am deleting $branch_count branches")
                echo -e "${GREEN}✓ Confirmed bulk deletion of $branch_count branches${NC}"
                return 0
                ;;
            "abort"|"cancel"|"no"|"n")
                echo -e "${GREEN}✓ Aborted bulk deletion${NC}"
                return 1
                ;;
            "quit"|"exit"|"q")
                echo -e "${YELLOW}Exiting program as requested${NC}"
                exit 0
                ;;
            "")
                echo -e "${RED}Empty input. Please type the exact confirmation phrase.${NC}"
                ;;
            *)
                echo -e "${RED}Input does not match required phrase.${NC}"
                echo -e "${YELLOW}Please type exactly: 'I understand I am deleting $branch_count branches'${NC}"
                ;;
        esac
    done
}

# Main execution
main() {
    log_info "Git Branch Cleanup Tool (Safe Preview Mode by Default)"
    
    # Validate environment
    validate_git_repo
    validate_main_branch
    
    # Update remote tracking branches
    log_info "Updating remote tracking information..."
    git fetch --prune 2>/dev/null || log_warning "Could not fetch from remote"
    
    # Start cleanup
    cleanup_branches
    
    if [ "$dry_run" = true ]; then
        log_success "Branch cleanup preview completed - use --execute to perform deletions"
    else
        log_success "Branch cleanup completed"
    fi
}

# Run main function
main "$@"
