# Git Branch Management Tools

## Installation

1. **Clone the repository**

   ```bash
   git clone https://github.com/yourusername/git-branch-management-tools.git
   cd git-branch-management-tools
   ```

2. **Make the scripts executable**

   ```bash
   chmod +x git-branch-stats.sh clean-up-branches.sh
   ```

3. **(Optional) Install the scripts globally as `branches` and `prune-branches`**

   To use the tools as simple commands from anywhere, copy them to a directory in your `PATH` and rename:

   ```bash
   sudo cp git-branch-stats.sh /usr/local/bin/branches
   sudo cp clean-up-branches.sh /usr/local/bin/prune-branches
   ```

   > **Tip:** You can use any directory in your `PATH` (e.g., `~/.local/bin` for user installs).

4. **(Alternative) Add aliases to your shell profile**

   If you prefer not to copy the scripts, add these aliases to your `~/.bashrc`, `~/.zshrc`, or equivalent:

   ```bash
   alias branches="$PWD/git-branch-stats.sh"
   alias prune-branches="$PWD/clean-up-branches.sh"
   ```

   Then reload your shell configuration:

   ```bash
   source ~/.bashrc   # or source ~/.zshrc
   ```

5. **Verify installation**

   Run the following commands to ensure the tools are accessible:

   ```bash
   branches --help
   prune-branches --help
   ```

**Requirements:**

- A Unix-like environment (Linux, macOS, WSL)
- Bash shell
- Git installed
- Standard Unix tools (`awk`, `sed`, `date`)

For more details and usage examples, see the sections below.

This repository contains two complementary bash scripts for managing git branches effectively:

1. **`git-branch-stats.sh`** - Analyze and display detailed statistics about all local branches
2. **`clean-up-branches.sh`** - Safely clean up merged branches with various filtering options

## TL;DR Basic Examples:

```sh
# Show what would be deleted (safe preview mode)
./clean-up-branches.sh

# Actually delete merged branches (requires --execute)
./clean-up-branches.sh --execute

# Only delete branches merged into a custom main branch (e.g., develop)
./clean-up-branches.sh --main develop --execute

# Include branches that are diverged (rebased/force-pushed) from main
./clean-up-branches.sh --include-diverged --execute

# Include ancestor-only branches (appear merged but weren't actually merged)
./clean-up-branches.sh --include-ancestors --execute

# Include unmerged branches (dangerous: will show data loss warning and require confirmation)
./clean-up-branches.sh --include-unmerged --execute

# Only delete branches older than 30 days
./clean-up-branches.sh --age 30 --execute

# Force delete without interactive confirmation (except protected/unmerged branches)
./clean-up-branches.sh --force --execute

# Combine options: delete merged or diverged branches older than 14 days, non-interactively
./clean-up-branches.sh --include-diverged --age 14 --force --execute

```

## git-branch-stats.sh

A comprehensive tool that displays detailed information about all local git branches in a formatted table.

### Features

- **Branch Information**: Shows branch name, last commit date, merge status, and commit differences
- **Color Coding**: Visual indicators for merge status, branch age, and change volume
- **Sorting**: Branches sorted by last commit date (oldest to newest)
- **Detailed Metrics**: Displays behind/ahead commit counts and additions/deletions

### Usage

```bash
./git-branch-stats.sh
```

### Output Example

```
Branch                         | Last Commit          | Merged Status | Behind/Ahead | Additions/Deletions
--------------------------------------------------------------------------------------------------------------------
feature/old-feature           | 2 months ago        | Merged       |     0/0      |       0/0
feature/bugfix-123            | 3 weeks ago         | Unmerged     |    15/8      |     245/67
hotfix/critical-fix           | 1 week ago          | Diverged     |     5/2      |      89/12
```

## clean-up-branches.sh

A safe and interactive tool for cleaning up merged git branches with multiple safety features and **advanced merge detection** to prevent false positives.

### Key Features

- **Safe Preview Mode by Default**: Shows what would be deleted without actually deleting
- **Enhanced Summary Tables**: Displays branches in git-branch-stats.sh format before deletion
- **Bulk Confirmation**: Single confirmation for multiple branches with detailed breakdown
- **Smart Merge Detection**: Distinguishes between actually merged branches vs. branches that are just ancestors
- **False Positive Prevention**: Warns about branches that appear merged but weren't actually merged
- **Protected Branches**: Extra safety for critical branches (main, master, staging, etc.)
- **Interactive Mode**: Confirms each deletion by default
- **Explicit Execution**: Requires `--execute` flag to actually delete branches
- **Input Validation**: Validates command line arguments to prevent errors
- **Age Filtering**: Only delete branches older than specified days
- **Multiple Branch Types**: Handles merged, diverged, ancestor-only, and unmerged branches
- **Safety Checks**: Never deletes current branch or main branch
- **Force Mode**: Batch deletion for automation
- **Verbose Logging**: Detailed information about processing decisions

### Branch Status Detection

The tool now provides accurate branch status detection:

| Status              | Description                                            | Action                                     |
| ------------------- | ------------------------------------------------------ | ------------------------------------------ |
| **ACTUALLY MERGED** | Branch was properly merged via merge commit or PR      | ✅ Safe to delete                          |
| **ANCESTOR ONLY**   | Branch is ancestor of main but NOT actually merged     | ⚠️ Requires manual review                  |
| **DIVERGED**        | Branch was merged but has additional commits (rebased) | 🔄 Optional deletion                       |
| **UNMERGED**        | Branch contains commits not in main branch             | ❌ Not deleted (unless --include-unmerged) |

### Usage

```bash
# Safe preview mode (default) - shows what would be deleted
./clean-up-branches.sh

# Actually delete merged branches after confirmation
./clean-up-branches.sh --execute

# Preview potential false positives (ancestor branches) with caution
./clean-up-branches.sh --include-ancestors --verbose

# Auto-delete actually merged branches older than 30 days
./clean-up-branches.sh --execute --force --age 30

# Include diverged branches (rebased branches)
./clean-up-branches.sh --include-diverged

# Include unmerged branches (shows commits that would be lost)
./clean-up-branches.sh --include-unmerged --age 90

# Use different main branch with verbose output
./clean-up-branches.sh --main develop --verbose

# Show help
./clean-up-branches.sh --help
```

### Command Line Options

| Option                | Description                                                  |
| --------------------- | ------------------------------------------------------------ |
| `-h, --help`          | Show help message                                            |
| `-m, --main BRANCH`   | Specify main branch (default: main)                          |
| `-e, --execute`       | Actually delete branches (default is preview mode)           |
| `-f, --force`         | Skip interactive confirmation                                |
| `-a, --age DAYS`      | Only delete branches older than DAYS days                    |
| `-v, --verbose`       | Show detailed processing information                         |
| `--merged-only`       | Only clean up actually merged branches (default)             |
| `--include-diverged`  | Also clean up diverged branches (rebased)                    |
| `--include-ancestors` | Include ancestor branches (potential false positives)        |
| `--include-unmerged`  | Include unmerged branches (shows commits that would be lost) |
| `--list-protected`    | List all protected branch names and exit                     |

### Protected Branches

For extra safety, certain critical branches are **always protected** and require explicit confirmation, even in force mode:

**Infrastructure Branches:**

- `main`, `master`, `develop`, `development`, `dev`

**Environment Branches:**

- `staging`, `stage`, `production`, `prod`, `test`, `testing`, `qa`, `uat`

**Release Branches:**

- `release`, `hotfix`, `beta`, `alpha`, `stable`

**Deployment Branches:**

- `live`, `demo`, `preview`

**Documentation Branches:**

- `gh-pages`, `pages`, `docs`, `documentation`

#### Protected Branch Confirmation

When attempting to delete a protected branch, users see a prominent warning and must type the exact branch name:

```
████████████████████████████████████████████████████████████████
█                                                              █
█                 ⚠️  PROTECTED BRANCH WARNING ⚠️               █
█                                                              █
████████████████████████████████████████████████████████████████

🚨 DANGER: You are about to delete a PROTECTED branch: staging

Protected branches are typically critical infrastructure branches like:
  • Main development branches (main, master, develop)
  • Environment branches (staging, production, test)
  • Release branches (release, hotfix)
  • Documentation branches (gh-pages, docs)

⚠️  This action is EXTREMELY DANGEROUS and could disrupt your entire team!

To confirm this dangerous action, type the EXACT branch name: staging
Or type 'abort' to cancel, or 'quit' to exit the program

Type branch name to confirm deletion: _
```

### Enhanced User Experience

#### Summary Table Preview

Before deletion, the tool shows a comprehensive table (similar to `git-branch-stats.sh`) of all branches that would be deleted:

```
Branch                         | Last Commit          | Merged Status | Behind/Ahead | Additions/Deletions
--------------------------------------------------------------------------------------------------------------------
feature/old-implementation    | 2 months ago        | MERGED       |     45/0     |       0/0
fix/legacy-bug               | 6 weeks ago         | ANCESTOR     |    120/0     |      23/45
hotfix/security-patch        | 3 weeks ago         | DIVERGED     |     12/3     |       8/2
feature/experimental         | 1 month ago         | UNMERGED     |     67/15    |     156/89
--------------------------------------------------------------------------------------------------------------------

Summary by Status:
  ✓ Actually Merged: 1 branches
  ⚠ Ancestor Only: 1 branches (potential false positives)
  🔄 Diverged: 1 branches (rebased)
  ❌ Unmerged: 1 branches (will lose commits!)

⚠️  WARNING: 1 unmerged branches will lose commits permanently!
⚠️  WARNING: 1 ancestor-only branches may contain unmerged work!

⚠️  This action cannot be undone!

Type 'I understand I am deleting 4 branches' to confirm:
>
```

#### Bulk Confirmation

Instead of confirming each branch individually, users get:

1. **Summary table** showing all branches with their status
2. **Status breakdown** with counts and warnings
3. **Single confirmation** requiring exact phrase: `I understand I am deleting X branches`
4. **Individual confirmation** still required for protected/unmerged branches

#### Input Validation

The tool now validates command line arguments and provides helpful error messages:

```bash
$ ./clean-up-branches.sh --age 3-
[ERROR] Invalid age value: '3-'. Must be a positive integer (number of days).
Example: --age 30 (for branches older than 30 days)
```

### Unmerged Branch Handling

By default, unmerged branches (containing commits not in main) are skipped to prevent data loss. However, with `--include-unmerged`, you can clean up unmerged branches with enhanced safety warnings.

#### Unmerged Branch Warning

When attempting to delete an unmerged branch, users see a prominent data loss warning:

```
████████████████████████████████████████████████████████████████
█                                                              █
█                ⚠️  UNMERGED BRANCH WARNING ⚠️                █
█                                                              █
████████████████████████████████████████████████████████████████

🚨 DATA LOSS WARNING: You are about to delete an UNMERGED branch: feature-xyz

This branch contains 5 commits that are NOT in the main branch!
These commits will be PERMANENTLY LOST if you proceed:

Commits that will be lost:
  📝 abc1234 Add new feature implementation
  📝 def5678 Fix bug in feature logic
  📝 ghi9012 Update documentation
  📝 jkl3456 Add unit tests
  📝 mno7890 Final cleanup

⚠️  This action will PERMANENTLY DELETE 5 commits of work!
⚠️  This action CANNOT be undone!

To confirm this dangerous action, type the EXACT branch name: feature-xyz
```

#### Recommended Usage for Unmerged Branches

```bash
# Safe approach: Review old unmerged branches first
./git-branch-stats.sh

# Preview unmerged branches that would be deleted (90+ days old)
./clean-up-branches.sh --include-unmerged --age 90

# Actually clean up old unmerged branches after review
./clean-up-branches.sh --include-unmerged --age 90 --execute

# Force mode still requires confirmation for unmerged branches
./clean-up-branches.sh --include-unmerged --execute --force --age 180
```

### False Positive Prevention

**The Problem**: Traditional git merge detection can show false positives where branches appear "merged" but were never actually merged. This happens when:

- Main branch moved forward independently
- Branch was created from an old commit
- Work was manually copied to main without proper merging

**The Solution**: This tool now:

1. **Detects actual merge commits** in the main branch history
2. **Warns about ancestor-only branches** that appear merged but weren't
3. **Requires explicit confirmation** for potentially dangerous deletions
4. **Shows detailed explanations** of why each branch has its status

### Example Output

When the tool detects a potential false positive:

```
╔════════════════════════════════════════════════════════════════╗
║ ⚠ ANCESTOR ONLY - NOT actually merged, just older!        ║
║   This branch may contain unmerged work - review carefully!   ║
╚════════════════════════════════════════════════════════════════╝

Branch Details:
  Name: upgrade/expo-53
  Last commit: 7 days ago (6 days ago)
  Behind main: 13 commits
  Ahead of main: 0 commits

  ⚠ WARNING: This branch appears to be an ancestor of main but was not
     actually merged. This often happens when:
     • Main branch moved forward independently
     • Branch was created from an old commit
     • Work was manually copied to main without proper merging
  👀 Please review the branch content before deleting!
```

### Safety Features

1. **Never deletes**:

   - Current branch
   - Main branch (configurable)
   - Unmerged branches (unless forced)
   - Ancestor-only branches (unless explicitly included)

2. **Preview mode by default**: Shows what would be deleted without actually deleting
3. **Explicit execution required**: Must use `--execute` flag to actually delete branches
4. **Protected branch safeguards**: Critical branches require typing exact name to confirm
5. **Unmerged branch protection**: Shows commits that would be lost and requires name confirmation
6. **Interactive confirmation**: Shows detailed branch analysis before deletion
7. **Git validation**: Ensures you're in a valid git repository
8. **Remote sync**: Updates remote tracking information before cleanup
9. **False positive detection**: Warns about potentially dangerous deletions

### Typical Workflow

1. **Analyze branches** first:

   ```bash
   ./git-branch-stats.sh
   ```

2. **Check protected branches**:

   ```bash
   ./clean-up-branches.sh --list-protected
   ```

3. **Preview cleanup** (safe default):

   ```bash
   ./clean-up-branches.sh
   ```

4. **Execute cleanup** after reviewing:

   ```bash
   ./clean-up-branches.sh --execute
   ```

5. **Review any ancestor-only branches manually**:

   ```bash
   ./clean-up-branches.sh --include-ancestors
   ```

6. **Or automate for old branches**:
   ```bash
   ./clean-up-branches.sh --execute --force --age 60
   ```

## Installation

1. Clone or download the scripts
2. Make them executable:
   ```bash
   chmod +x git-branch-stats.sh clean-up-branches.sh
   ```
3. Optionally, add them to your PATH for global access

## Requirements

- Git repository
- Bash shell
- Standard Unix tools (awk, sed, date)

## Examples

### Scenario 1: Regular Maintenance

```bash
# Weekly branch cleanup routine
./git-branch-stats.sh                    # Review current state
./clean-up-branches.sh --dry-run         # Preview cleanup
./clean-up-branches.sh                   # Interactive cleanup
```

### Scenario 2: Automated Cleanup

```bash
# Monthly automated cleanup (CI/CD)
./clean-up-branches.sh --force --age 30 --verbose
```

### Scenario 3: Different Main Branch

```bash
# Projects using 'develop' as main branch
./git-branch-stats.sh
./clean-up-branches.sh --main develop --dry-run
```

## Safety Notes

- Always run with `--dry-run` first to preview changes
- The scripts are designed to be safe, but use `--force` with caution
- Interactive mode is the default and recommended for manual use
- Age filtering helps prevent accidental deletion of recent work
- Both scripts work only with local branches (not remote branches)

## Contributing

Feel free to submit issues or pull requests to improve these tools.
