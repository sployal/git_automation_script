# GitGo — PowerShell Git & GitHub Workflow

> Interactive PowerShell automation for everyday Git and GitHub tasks on Windows.

[![PowerShell](https://img.shields.io/badge/PowerShell-7+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Git](https://img.shields.io/badge/Git-Required-green.svg)](https://git-scm.com/)
[![GitHub](https://img.shields.io/badge/GitHub-API-blue.svg)](https://github.com/)

## Current version

**`gitgo.ps1` is the latest and only supported entry point** for this project. Earlier scripts (`gitgov3.ps1`, `new.ps1`, and others) are legacy; use `gitgo.ps1` for all installs and documentation below.

## What is GitGo?

GitGo turns common Git and GitHub workflows into guided, menu-driven steps so you spend less time remembering flags and more time shipping code. Run it interactively or invoke a single action from the command line.

### Highlights

- **Multi-account GitHub** — Up to three accounts (personal, work, freelance, etc.) with per-account tokens and stored identity
- **HTTPS + Personal Access Tokens** — Clone, push, and API calls use tokens via `http.extraheader` (no credential helper prompts)
- **Repository lifecycle** — Clone, create (`addremote`), list, delete, rename, and inspect status
- **Guided commits** — Stage (including `git add -p`), conventional-commit templates, optional push
- **Branch & remote tools** — List/create/switch/delete branches; view or change `origin`
- **Secure setup** — Tokens in user environment variables; account metadata in `%USERPROFILE%\.gitgo\`

## Requirements

- **PowerShell 7+** (recommended) or Windows PowerShell 5.1
- **Git** installed and on your `PATH`
- **GitHub account(s)** with [Personal Access Tokens](https://github.com/settings/tokens)

OpenSSH is **not** required for the current release; SSH key setup in the script is disabled in favor of HTTPS + tokens.

## Quick start

### 1. Get the script

```powershell
# Clone this repo, or copy gitgo.ps1 into a folder on your machine
cd "C:\path\to\powershell"   # folder containing gitgo.ps1
```

### 2. Allow script execution (once)

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 3. First-time setup

```powershell
.\gitgo.ps1 setup
# Choose option 1 — configure accounts and tokens
```

Create tokens at https://github.com/settings/tokens with scopes: **`repo`**, **`delete_repo`**, **`user`**.

### 4. Run GitGo

```powershell
.\gitgo.ps1              # interactive menu
.\gitgo.ps1 --help       # full help, then exit
.\gitgo.ps1 push         # run one action
.\gitgo.ps1 2            # same as push (by action number)
```

### 5. Optional: add to PATH

```powershell
.\gitgo.ps1 --add-to-path
```

Restart the terminal, then run `gitgo` from any directory (Windows resolves `gitgo.ps1` when the folder is on `PATH`).

Remove from PATH:

```powershell
.\gitgo.ps1 --remove-from-path
```

## Usage

### Interactive mode

```powershell
.\gitgo.ps1
# or, after PATH setup:
gitgo
```

You’ll see all actions in a numbered grid. Enter an action **name**, **number**, or `q` to quit. First run: use **`setup`** (action **13**) to add accounts and tokens.

### Direct actions

| # | Action | Description |
|---|--------|-------------|
| 1 | `clone` | Clone from your account (by repo name) or from any GitHub HTTPS/SSH URL |
| 2 | `push` | Push committed changes to `origin` |
| 3 | `pull` | Pull from remote default branch |
| 4 | `adduser` | Set `user.name` and `user.email` for the current repo |
| 5 | `showuser` | Show current Git identity |
| 6 | `addremote` | Create a GitHub repo (README, visibility) and optionally clone |
| 7 | `remotelist` | List repositories for the selected account |
| 8 | `delremote` | Delete a GitHub repo (with confirmation) |
| 9 | `status` | Detailed repo status (branch, remotes, changes) |
| 10 | `commit` | Stage, commit (templates/amend), optional push |
| 11 | `history` | Commit history with summary stats |
| 12 | `tokeninfo` | Show token scopes for the selected account |
| 13 | `setup` | Accounts, tokens, PATH, updates, deletion |
| 14 | `branch` | List, create, switch, or delete branches |
| 15 | `remotem` | View or change remote URL for current repo |
| 16 | `changename` | Rename a repository on GitHub |
| 17 | `help` | Inline help (interactive menu only) |

Examples:

```powershell
gitgo clone
gitgo commit
gitgo 10          # commit by number
gitgo tokeninfo
gitgo setup
```

### CLI flags

| Flag | Purpose |
|------|---------|
| `--help` | Print actions and usage, then exit |
| `--add-to-path` | Append this script’s folder to the user `PATH` |
| `--remove-from-path` | Remove this script’s folder from the user `PATH` |

## Setup menu (`gitgo setup`)

| Option | What it does |
|--------|----------------|
| 1 | Add/update GitHub accounts and store PATs |
| 2 | Show token info and validate scopes |
| 3 | Update stored username, email, and local Git display name |
| 4 | Delete one or more configured accounts |
| 5 | Add GitGo folder to Windows PATH |
| 6 | Remove GitGo folder from PATH |
| 7 | Exit |

During token setup you can configure up to **three accounts** per machine. Each account gets:

- A stable **id** (e.g. `github-personal`)
- Display **name**, GitHub **username**, **email**, optional **gitName**
- A user environment variable for the token

## Configuration

### Account storage

```
%USERPROFILE%\.gitgo\accounts.json
```

Example structure:

```json
[
  {
    "id": "github-personal",
    "name": "personal",
    "username": "yourusername",
    "email": "you@example.com",
    "gitName": "Your Name",
    "tokenEnvVar": "GITHUB_GITHUB_PERSONAL_TOKEN"
  }
]
```

The `tokenEnvVar` name is derived from the account id: `GITHUB_<ID_UPPERCASE_WITH_UNDERSCORES>_TOKEN`.

### Environment variables

Tokens are stored as **User** environment variables (not in the JSON file):

```powershell
# Example after setting up a "personal" account (id: github-personal)
$env:GITHUB_GITHUB_PERSONAL_TOKEN
```

Restart PowerShell after setup so new variables are visible, or reload your profile.

### Authentication model

- **Git operations over HTTPS** use `git -c http.extraheader="Authorization: Basic …"` with your username and PAT.
- **GitHub REST API** calls use `Authorization: Bearer <token>`.
- Legacy SSH key generation remains in the script but is **disabled**; the current path is token-only HTTPS.

## Common workflows

### New project on GitHub

```powershell
gitgo addremote    # create repo, README, clone locally, set identity
```

### Day-to-day commit and push

```powershell
cd your-repo
gitgo commit       # stage → message (or template) → optional push
# or
gitgo push
```

### Multiple GitHub identities

```powershell
gitgo setup        # add personal + work accounts (max 3 total)
gitgo clone        # pick account when prompted
gitgo push         # same account picker
```

### Check token permissions

```powershell
gitgo tokeninfo
# or: gitgo setup → option 2
```

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| No accounts / missing config | `gitgo setup` → option 1 |
| Token not found | Re-run setup; confirm env var name in `accounts.json`; restart terminal |
| 404 on clone | Verify repo name and GitHub username for the selected account |
| Auth failed on push | `gitgo tokeninfo`; ensure `repo` scope on the PAT |
| Script won’t run | `Get-ExecutionPolicy`; use `RemoteSigned` for CurrentUser |

Verbose Git output:

```powershell
$VerbosePreference = "Continue"
.\gitgo.ps1
```

## Security notes

- PATs live in **user** environment variables, not in `accounts.json`.
- Tokens are read with `-AsSecureString` during setup and cleared from memory after use.
- Setup can validate token scopes via the GitHub API.
- Deleting repos or force-pushing always goes through confirmation prompts where applicable.

## Project layout

| File | Role |
|------|------|
| **`gitgo.ps1`** | Current GitGo implementation (use this) |
| `README.md` | This document |
| `gitgov1.py`, `gitgo1.ps1`, etc. | Older experiments — not maintained |

## Contributing

open to suggestions and improvements

## License

MIT — see [LICENSE](LICENSE) 

## Author

**David Muigai** —  Kenya  
Workflow automation & terminal tooling

---

If GitGo saves you time, consider starring the repo.
