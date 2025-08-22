# Show help menu if --help is passed
if ($args.Count -gt 0 -and $args[0] -eq "--help") {
    Write-Host "`n📘 GitGo Help Menu"
    Write-Host "──────────────────────────────────────────────"
    Write-Host "Available Actions:`n"

    $helpItems = @(
        "1. clone       → Clone a remote repo and configure identity",
        "2. push        → Push already committed changes to origin",
        "3. pull        → Pull latest changes from origin/main",
        "4. adduser     → Set Git username and email for current repo",
        "5. showuser    → Display current Git identity",
        "6. addremote   → Create a new GitHub repo with README and optional clone",
        "7. delremote   → Delete a GitHub repo after confirmation",
        "8. remotelist  → List all repos under selected GitHub account",
        "9. status      → Show comprehensive repository information",
        "10. commit     → Add, commit, and optionally push changes",
        "11. history    → View commit history with details",
        "12. tokeninfo  → Display token permissions and scopes",
        "13. setup      → Configure GitHub tokens securely",
        "14. branch     → Manage branches (list/create/switch/delete)"
    )

    foreach ($line in $helpItems) {
        Write-Host "  $line"
    }

    Write-Host "`nUsage:"
    Write-Host "  gitgo         → Launch interactive menu"
    Write-Host "  gitgo --help  → Show this help menu"
    Write-Host "`nFirst time setup:"
    Write-Host "  gitgo setup   → Configure your GitHub tokens"

    Write-Host "`nCreator:"
    Write-Host "  🧑‍💻 David Muigai — Nairobi, Kenya"
    Write-Host "  ✨ Workflow architect & terminal automation enthusiast"

    Write-Host ""
    exit
}

# Function to securely retrieve GitHub tokens
function Get-GitHubToken {
    param(
        [ValidateSet("personal", "work")]
        [string]$Account
    )
    
    $envVar = if ($Account -eq "personal") { "GITHUB_PERSONAL_TOKEN" } else { "GITHUB_WORK_TOKEN" }
    $token = [Environment]::GetEnvironmentVariable($envVar, "User")
    
    if ([string]::IsNullOrWhiteSpace($token)) {
        Write-Host "`n❌ GitHub token not found for $Account account."
        Write-Host "   → Run 'gitgo setup' or action '10' to configure tokens."
        Write-Host "   → Or manually set environment variable: $envVar"
        throw "Missing GitHub token for $Account account"
    }
    
    return $token
}

# Function to setup GitHub tokens securely
function Set-GitHubTokens {
    Write-Host "`n🔐 GitHub Token Setup"
    Write-Host "──────────────────────────────────────────────"
    Write-Host "This will securely configure your GitHub Personal Access Tokens."
    Write-Host "Tokens will be stored as user environment variables.`n"
    
    Write-Host "📋 To create tokens, visit: https://github.com/settings/tokens"
    Write-Host "   Required scopes: repo, delete_repo, user`n"
    
    try {
        Write-Host "🔑 Personal Account Token:"
        $personalToken = Read-Host "Enter your PERSONAL GitHub token" -AsSecureString
        
        Write-Host "`n🔑 Work Account Token:"
        $workToken = Read-Host "Enter your WORK GitHub token" -AsSecureString
        
        # Convert secure strings to plain text for environment variables
        $personalTokenPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($personalToken))
        $workTokenPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($workToken))
        
        # Validate tokens are not empty
        if ([string]::IsNullOrWhiteSpace($personalTokenPlain) -or [string]::IsNullOrWhiteSpace($workTokenPlain)) {
            throw "Tokens cannot be empty"
        }
        
        # Set environment variables
        [Environment]::SetEnvironmentVariable("GITHUB_PERSONAL_TOKEN", $personalTokenPlain, "User")
        [Environment]::SetEnvironmentVariable("GITHUB_WORK_TOKEN", $workTokenPlain, "User")
        
        Write-Host "`n✅ Tokens configured successfully!"
        Write-Host "🔄 Environment variables updated:"
        Write-Host "   → GITHUB_PERSONAL_TOKEN"
        Write-Host "   → GITHUB_WORK_TOKEN"
        Write-Host "`n⚠️  Please restart PowerShell for changes to take effect."
        Write-Host "   Or reload environment: refreshenv (if using Chocolatey)"
        
    } catch {
        Write-Host "`n❌ Token setup failed: $($_.Exception.Message)"
    } finally {
        # Clear sensitive variables from memory
        if ($personalTokenPlain) { 
            $personalTokenPlain = $null 
        }
        if ($workTokenPlain) { 
            $workTokenPlain = $null 
        }
        if ($personalToken) { 
            $personalToken.Dispose() 
        }
        if ($workToken) { 
            $workToken.Dispose() 
        }
    }
}

# Function to test token validity and get scopes
function Test-GitHubTokenScopes {
    param(
        [string]$Token,
        [string]$AccountName
    )
    
    try {
        $headers = @{
            Authorization = "Bearer $Token"
            Accept = "application/vnd.github+json"
            "User-Agent" = "GitGo-PowerShell-Script"
        }
        
        # Get user info and token scopes
        $response = Invoke-WebRequest -Uri "https://api.github.com/user" -Method Get -Headers $headers -TimeoutSec 10
        $userInfo = $response.Content | ConvertFrom-Json
        $scopes = $response.Headers['X-OAuth-Scopes'] -split ', ' | Where-Object { $_ }
        
        Write-Host "✅ $AccountName token is valid"
        Write-Host "   → User: $($userInfo.login)"
        Write-Host "   → Name: $($userInfo.name)"
        Write-Host "   → Email: $($userInfo.email)"
        Write-Host "   → Account Type: $($userInfo.type)"
        Write-Host "   → Rate Limit: $($response.Headers['X-RateLimit-Remaining'])/$($response.Headers['X-RateLimit-Limit']) remaining"
        Write-Host "   → Reset Time: $(([DateTimeOffset]::FromUnixTimeSeconds($response.Headers['X-RateLimit-Reset'])).ToString('yyyy-MM-dd HH:mm:ss'))"
        
        Write-Host "🔐 Token Scopes:"
        if ($scopes) {
            foreach ($scope in $scopes) {
                $scopeDescription = switch ($scope.Trim()) {
                    "repo" { "Full repository access (read/write)" }
                    "public_repo" { "Public repository access only" }
                    "delete_repo" { "Repository deletion permissions" }
                    "user" { "User profile information" }
                    "user:email" { "User email addresses" }
                    "admin:org" { "Organization administration" }
                    "workflow" { "GitHub Actions workflows" }
                    "gist" { "Gist access" }
                    default { "Unknown scope" }
                }
                Write-Host "   → $scope`: $scopeDescription"
            }
            
            # Check required scopes
            $requiredScopes = @("repo", "delete_repo", "user")
            $missingScopes = @()
            foreach ($required in $requiredScopes) {
                if ($required -notin $scopes -and ($required -eq "repo" -and "public_repo" -notin $scopes)) {
                    $missingScopes += $required
                }
            }
            
            if ($missingScopes.Count -gt 0) {
                Write-Host "⚠️ Missing required scopes: $($missingScopes -join ', ')"
                Write-Host "   → Some GitGo features may not work properly"
            } else {
                Write-Host "✅ All required scopes are present"
            }
        } else {
            Write-Host "   → No scopes found or token has full access"
        }
        
        return $true
    } catch {
        Write-Host "❌ $AccountName token is invalid or expired"
        Write-Host "   → Error: $($_.Exception.Message)"
        return $false
    }
}

# Handle direct setup command
if ($args.Count -gt 0 -and $args[0] -eq "setup") {
    Set-GitHubTokens
    exit
}

# Define valid actions
$validActions = @("clone", "push", "pull", "adduser", "showuser", "addremote", "remotelist", "delremote", "status", "commit", "history", "tokeninfo", "setup", "branch")

# Function to validate yes/no input
function Get-ValidYesNo {
    param(
        [string]$Prompt,
        [string]$DefaultValue = $null
    )
    
    do {
        if ($DefaultValue) {
            $input = Read-Host "$Prompt (y/n, default: $DefaultValue)"
            if ([string]::IsNullOrWhiteSpace($input)) {
                $input = $DefaultValue
            }
        } else {
            $input = Read-Host "$Prompt (y/n)"
        }
        
        $input = $input.ToLower().Trim()
        if ($input -eq "y" -or $input -eq "yes") {
            return $true
        } elseif ($input -eq "n" -or $input -eq "no") {
            return $false
        } else {
            Write-Host "`n❌ Invalid input. Please enter 'y' for yes or 'n' for no."
        }
    } while ($true)
}

# Function to get current Git branch
function Get-CurrentGitBranch {
    try {
        $branch = git branch --show-current 2>$null
        if ([string]::IsNullOrWhiteSpace($branch)) {
            # Fallback for older Git versions or detached HEAD
            $branch = git rev-parse --abbrev-ref HEAD 2>$null
            if ($branch -eq "HEAD") {
                return $null  # Detached HEAD
            }
        }
        return $branch
    } catch {
        return $null
    }
}

# Function to detect default branch
function Get-DefaultBranch {
    try {
        # Try to get default branch from remote
        $defaultBranch = git symbolic-ref refs/remotes/origin/HEAD 2>$null
        if ($defaultBranch) {
            return ($defaultBranch -replace 'refs/remotes/origin/', '')
        }
        
        # Fallback: check if main or master exists
        $branches = git branch -r 2>$null
        if ($branches -match 'origin/main') {
            return "main"
        } elseif ($branches -match 'origin/master') {
            return "master"
        }
        
        # Last resort: assume main
        return "main"
    } catch {
        return "main"
    }
}

# Function to handle Git add and commit
function Invoke-GitCommit {
    # Check if we're in a Git repository
    if (-not (Test-Path ".git")) {
        Write-Host "`n❌ Not a Git repository. Initialize with 'git init' first."
        return
    }

    Write-Host "`n📝 Git Add & Commit"
    Write-Host "──────────────────────────────────────────────"

    # Show current status
    Write-Host "📊 Current repository status:"
    $statusOutput = git status --porcelain 2>$null
    if ([string]::IsNullOrWhiteSpace($statusOutput)) {
        Write-Host "   ✅ Working tree clean - nothing to commit"
        return
    } else {
        Write-Host "   📋 Changes detected:"
        $statusLines = $statusOutput -split "`n" | Where-Object { $_.Trim() -ne "" }
        foreach ($line in $statusLines) {
            if ($line.Length -ge 3) {
                $status = $line.Substring(0, 2)
                $file = $line.Substring(3)
                
                $statusIcon = switch ($status.Trim()) {
                    "M" { "📝" }   # Modified
                    "A" { "➕" }   # Added
                    "D" { "🗑️" }   # Deleted
                    "R" { "🔄" }   # Renamed
                    "C" { "📋" }   # Copied
                    "??" { "❓" }  # Untracked
                    default { "📄" }
                }
                
                Write-Host "      $statusIcon $file"
            }
        }
    }

    # Ask what to add
    Write-Host "`n🎯 What would you like to add?"
    Write-Host "   1. All changes (git add .)"
    Write-Host "   2. All tracked files (git add -u)"
    Write-Host "   3. Specific files (manual selection)"
    Write-Host "   4. Interactive staging (git add -p)"
    
    do {
        $addChoice = Read-Host "`nEnter your choice (1-4)"
        switch ($addChoice) {
            "1" {
                Write-Host "`n➕ Adding all changes..."
                git add .
                $addAction = "all changes"
                $validChoice = $true
            }
            "2" {
                Write-Host "`n➕ Adding all tracked files..."
                git add -u
                $addAction = "all tracked files"
                $validChoice = $true
            }
            "3" {
                Write-Host "`n📝 Enter file paths separated by spaces:"
                $files = Read-Host "Files to add"
                if (-not [string]::IsNullOrWhiteSpace($files)) {
                    Write-Host "`n➕ Adding specified files..."
                    $fileArray = $files -split '\s+' | Where-Object { $_.Trim() -ne "" }
                    foreach ($file in $fileArray) {
                        git add $file
                    }
                    $addAction = "specified files"
                    $validChoice = $true
                } else {
                    Write-Host "❌ No files specified."
                    $validChoice = $false
                }
            }
            "4" {
                Write-Host "`n🎯 Starting interactive staging..."
                git add -p
                $addAction = "interactive selection"
                $validChoice = $true
            }
            default {
                Write-Host "❌ Invalid choice. Please enter 1, 2, 3, or 4."
                $validChoice = $false
            }
        }
    } while (-not $validChoice)

    # Check if anything was actually staged
    $stagedFiles = git diff --cached --name-only 2>$null
    if ([string]::IsNullOrWhiteSpace($stagedFiles)) {
        Write-Host "`n⚠️ No changes staged for commit."
        return
    }

    Write-Host "`n✅ Files staged for commit:"
    $stagedFiles -split "`n" | ForEach-Object { Write-Host "   → $_" }

    # Get commit message
    Write-Host "`n💬 Commit message options:"
    Write-Host "   1. Enter custom message"
    Write-Host "   2. Use template message"
    Write-Host "   3. Amend previous commit"
    
    do {
        $msgChoice = Read-Host "`nEnter your choice (1-3)"
        switch ($msgChoice) {
            "1" {
                $commitMsg = Read-Host "`n📝 Enter your commit message"
                if ([string]::IsNullOrWhiteSpace($commitMsg)) {
                    Write-Host "❌ Commit message cannot be empty."
                    $validMsg = $false
                } else {
                    $validMsg = $true
                }
            }
            "2" {
                Write-Host "`n📋 Available templates:"
                Write-Host "   1. feat: add new feature"
                Write-Host "   2. fix: bug fix"
                Write-Host "   3. docs: update documentation"  
                Write-Host "   4. style: formatting changes"
                Write-Host "   5. refactor: code refactoring"
                Write-Host "   6. test: add or update tests"
                Write-Host "   7. chore: maintenance tasks"
                
                $templateChoice = Read-Host "Select template (1-7)"
                $templates = @{
                    "1" = "feat: "
                    "2" = "fix: "
                    "3" = "docs: "
                    "4" = "style: "
                    "5" = "refactor: "
                    "6" = "test: "
                    "7" = "chore: "
                }
                
                if ($templates.ContainsKey($templateChoice)) {
                    $templatePrefix = $templates[$templateChoice]
                    $customPart = Read-Host "Complete the message: '$templatePrefix'"
                    $commitMsg = $templatePrefix + $customPart
                    $validMsg = $true
                } else {
                    Write-Host "❌ Invalid template choice."
                    $validMsg = $false
                }
            }
            "3" {
                Write-Host "`n🔄 Amending previous commit..."
                git commit --amend
                Write-Host "✅ Commit amended successfully!"
                
                # Ask about pushing
                $currentBranch = Get-CurrentGitBranch
                if ($currentBranch -and (Get-ValidYesNo "🚀 Push amended commit to origin/$currentBranch? (Note: This will force push)")) {
                    git push origin $currentBranch --force-with-lease
                    Write-Host "✅ Amended commit pushed successfully!"
                }
                return
            }
            default {
                Write-Host "❌ Invalid choice. Please enter 1, 2, or 3."
                $validMsg = $false
            }
        }
    } while (-not $validMsg)

    # Perform the commit
    Write-Host "`n💾 Committing changes..."
    try {
        git commit -m "$commitMsg"
        Write-Host "✅ Commit successful!"
        Write-Host "   → Message: $commitMsg"
        Write-Host "   → Added: $addAction"
        
        # Show commit hash
        $commitHash = git rev-parse --short HEAD
        Write-Host "   → Commit hash: $commitHash"

        # Ask about pushing
        $currentBranch = Get-CurrentGitBranch
        if ($currentBranch) {
            $shouldPush = Get-ValidYesNo "🚀 Push commit to origin/$currentBranch?"
            if ($shouldPush) {
                # Check if upstream is set
                $upstreamExists = git rev-parse --abbrev-ref "$currentBranch@{upstream}" 2>$null
                if (-not $upstreamExists) {
                    Write-Host "🔗 Setting upstream and pushing..."
                    git push -u origin $currentBranch
                } else {
                    git push origin $currentBranch
                }
                Write-Host "✅ Changes pushed successfully!"
            }
        }
        
    } catch {
        Write-Host "❌ Commit failed: $($_.Exception.Message)"
    }
}

# Function to show commit history
function Show-GitHistory {
    # Check if we're in a Git repository
    if (-not (Test-Path ".git")) {
        Write-Host "`n❌ Not a Git repository."
        return
    }

    Write-Host "`n📚 Git Commit History"
    Write-Host "──────────────────────────────────────────────"

    # Get current branch
    $currentBranch = Get-CurrentGitBranch
    if ($currentBranch) {
        Write-Host "🌿 Current Branch: $currentBranch"
    }

    # Ask for number of commits to show
    do {
        $numCommits = Read-Host "`n📊 How many commits to show? (default: 10, max: 50)"
        if ([string]::IsNullOrWhiteSpace($numCommits)) {
            $numCommits = 10
            break
        }
        if ([int]::TryParse($numCommits, [ref]$null) -and [int]$numCommits -gt 0 -and [int]$numCommits -le 50) {
            $numCommits = [int]$numCommits
            break
        } else {
            Write-Host "❌ Please enter a number between 1 and 50."
        }
    } while ($true)

    Write-Host "`n📋 Last $numCommits commits:`n"

    try {
        # Get commit history with detailed format
        $commits = git log --oneline --graph --decorate -n $numCommits 2>$null
        if ($commits) {
            foreach ($commit in $commits) {
                Write-Host "   $commit"
            }
            
            # Show detailed view option
            Write-Host "`n🔍 View options:"
            Write-Host "   1. Show detailed commit info"
            Write-Host "   2. Show file changes for a specific commit"
            Write-Host "   3. Show commit statistics"
            Write-Host "   4. Exit history view"
            
            $viewChoice = Read-Host "`nEnter your choice (1-4, default: 4)"
            
            switch ($viewChoice) {
                "1" {
                    Write-Host "`n📋 Detailed commit information:`n"
                    git log --stat -n $numCommits --pretty=format:"%h - %an, %ar : %s"
                }
                "2" {
                    $commitHash = Read-Host "`n🔍 Enter commit hash (short or full)"
                    if (-not [string]::IsNullOrWhiteSpace($commitHash)) {
                        Write-Host "`n📝 Changes in commit $commitHash`:`n"
                        git show --stat $commitHash
                    }
                }
                "3" {
                    Write-Host "`n📊 Repository statistics:`n"
                    Write-Host "📈 Contribution stats (last $numCommits commits):"
                    git shortlog -sn -$numCommits
                    Write-Host "`n📅 Commit activity:"
                    git log --pretty=format:"%ad" --date=short -n $numCommits | Sort-Object | Group-Object | ForEach-Object {
                        Write-Host "   $($_.Name): $($_.Count) commits"
                    }
                }
            }
        } else {
            Write-Host "   (no commits found)"
        }
    } catch {
        Write-Host "❌ Error retrieving commit history: $($_.Exception.Message)"
    }
}
function Get-GitRepositoryInfo {
    # Check if we're in a Git repository
    if (-not (Test-Path ".git")) {
        Write-Host "`n❌ Not a Git repository. Run this command from within a Git repository."
        return
    }

    Write-Host "`n📊 Git Repository Status & Info"
    Write-Host "──────────────────────────────────────────────"

    # Repository name (current directory)
    $repoName = Split-Path -Leaf (Get-Location)
    Write-Host "📁 Repository: $repoName"

    try {
        # Current branch
        $currentBranch = git branch --show-current 2>$null
        if ($currentBranch) {
            Write-Host "🌿 Current Branch: $currentBranch"
        } else {
            Write-Host "🌿 Current Branch: (detached HEAD or no commits)"
        }

        # Git identity
        $gitName = git config user.name 2>$null
        $gitEmail = git config user.email 2>$null
        Write-Host "👤 Git Identity:"
        if ($gitName) {
            Write-Host "   → Name: $gitName"
        } else {
            Write-Host "   → Name: (not configured)"
        }
        if ($gitEmail) {
            Write-Host "   → Email: $gitEmail"
        } else {
            Write-Host "   → Email: (not configured)"
        }

        # Remote URLs
        $remotes = git remote -v 2>$null
        if ($remotes) {
            Write-Host "🔗 Remote URLs:"
            foreach ($remote in $remotes) {
                $parts = $remote -split "`t"
                if ($parts.Count -ge 2) {
                    $remoteName = $parts[0]
                    $remoteInfo = $parts[1]
                    Write-Host "   → $remoteName`: $remoteInfo"
                }
            }
        } else {
            Write-Host "🔗 Remote URLs: (no remotes configured)"
        }

        # Working tree status
        Write-Host "📈 Repository Status:"
        $statusOutput = git status --porcelain 2>$null
        if ([string]::IsNullOrWhiteSpace($statusOutput)) {
            Write-Host "   ✅ Working tree clean"
        } else {
            Write-Host "   ⚠️ Working tree has changes:"
            $statusLines = $statusOutput -split "`n" | Where-Object { $_.Trim() -ne "" }
            foreach ($line in $statusLines) {
                if ($line.Length -ge 3) {
                    $status = $line.Substring(0, 2)
                    $file = $line.Substring(3)
                    
                    $statusIcon = switch ($status.Trim()) {
                        "M" { "📝" }   # Modified
                        "A" { "➕" }   # Added
                        "D" { "🗑️" }   # Deleted
                        "R" { "🔄" }   # Renamed
                        "C" { "📋" }   # Copied
                        "??" { "❓" }  # Untracked
                        default { "📄" }
                    }
                    
                    Write-Host "      $statusIcon $file"
                }
            }
        }

        # Recent commits (last 3)
        Write-Host "📚 Recent Commits (last 3):"
        $commitOutput = git log --oneline -3 2>$null
        if ($commitOutput) {
            $commits = $commitOutput -split "`n" | Where-Object { $_.Trim() -ne "" }
            foreach ($commit in $commits) {
                if ($commit.Trim() -ne "") {
                    Write-Host "   → $commit"
                }
            }
        } else {
            Write-Host "   (no commits found)"
        }

    } catch {
        Write-Host "`n❌ Error retrieving Git information:"
        Write-Host "   $($_.Exception.Message)"
    }
}

# Display actions in 3 numbered, left-aligned columns
Write-Host "`n🛠️ Available Actions:`n"
$columnWidth = 22
$columns = 3
$numberedActions = @{}
for ($i = 0; $i -lt $validActions.Count; $i++) {
    $numberedActions["$($i + 1)"] = $validActions[$i]
}
$actionList = $numberedActions.GetEnumerator() | Sort-Object { [int]$_.Key } | ForEach-Object { "$($_.Key). $($_.Value)" }

for ($i = 0; $i -lt $actionList.Count; $i += $columns) {
    $row = $actionList[$i..([Math]::Min($i + $columns - 1, $actionList.Count - 1))]
    $formattedRow = $row | ForEach-Object { $_.PadRight($columnWidth) }
    Write-Host ("   " + ($formattedRow -join ""))
}

Write-Host "`nType the action name or number. Type 'q' to quit."
Write-Host "`nFirst time? Run 'setup' (10) to configure GitHub tokens securely."

# Prompt until valid action or 'q' is entered
do {
    $input = Read-Host "`nEnter your action"
    if ($input -eq "q") {
        Write-Host "`n👋 Exiting GitGo."
        exit
    } elseif ($validActions -contains $input) {
        $action = $input
    } elseif ($numberedActions.ContainsKey($input)) {
        $action = $numberedActions[$input]
    } else {
        Write-Host "`n❌ Invalid input. Please enter a valid action name, number, or 'q' to quit."
        $action = $null
    }
} until ($action)

# Function to validate and get account selection
function Get-ValidAccount {
    do {
        $account = Read-Host "Which account are you using? (personal/work)"
        if ($account -eq "personal" -or $account -eq "work") {
            return $account
        } else {
            Write-Host "`n❌ Invalid account. Please enter 'personal' or 'work' only."
        }
    } while ($true)
}

# Function to validate and get repository visibility
function Get-ValidVisibility {
    do {
        $visibility = Read-Host "Should the repo be public or private? (public/private)"
        if ($visibility -eq "public" -or $visibility -eq "private") {
            return $visibility
        } else {
            Write-Host "`n❌ Invalid visibility. Please enter 'public' or 'private' only."
        }
    } while ($true)
}

# Initialize variables
$gitName = "Davie"
$gitEmail = ""
$githubUser = ""
$sshAlias = ""
$repoName = ""
$remoteUrl = ""
$tokenPlain = ""

# Handle account setup for relevant actions
if ($action -in @("clone", "push", "addremote", "delremote", "remotelist", "tokeninfo")) {
    $account = Get-ValidAccount
    $githubUser = if ($account -eq "personal") { "sployal" } else { "Dvulkran" }
    $sshAlias   = if ($account -eq "personal") { "personal" } else { "work" }
    $gitEmail   = if ($account -eq "personal") { "muigaid91@dmail.com" } else { "muigaidavie6@gmail.com" }
    
    # Securely retrieve token from environment variables
    try {
        $tokenPlain = Get-GitHubToken -Account $account
    } catch {
        Write-Host $_.Exception.Message
        return
    }
}

switch ($action) {

    "setup" {
        Set-GitHubTokens
    }

    "clone" {
        $repoName = Read-Host "Enter the repository name to clone"
        $remoteUrl = "git@${sshAlias}:${githubUser}/${repoName}.git"

        Write-Host "`n🔍 Cloning from: $remoteUrl"
        try {
            $cloneOutput = git clone $remoteUrl 2>&1
            Write-Host $cloneOutput

            if (Test-Path $repoName) {
                Set-Location $repoName
                git config user.name "$gitName"
                git config user.email "$gitEmail"

                Write-Host "`n✅ Repo cloned and configured:"
                Write-Host "  → Remote: $remoteUrl"
                Write-Host "  → Git user.name: $gitName"
                Write-Host "  → Git user.email: $gitEmail"
            } else {
                Write-Host "`n⚠️ Clone succeeded but folder '$repoName' not found."
            }
        } catch {
            Write-Host "`n❌ Error during clone:"
            Write-Host $_.Exception.Message
        }
    }

    "push" {
        # Check if we're in a Git repository
        if (-not (Test-Path ".git")) {
            Write-Host "`n❌ Not a Git repository. Initialize with 'git init' first."
            return
        }

        # Get current branch
        $currentBranch = Get-CurrentGitBranch
        if (-not $currentBranch) {
            Write-Host "`n❌ Unable to determine current branch. You may be in a detached HEAD state."
            return
        }

        Write-Host "`n🚀 Preparing to push from branch: $currentBranch"

        # Check for uncommitted changes
        $statusOutput = git status --porcelain 2>$null
        if (-not [string]::IsNullOrWhiteSpace($statusOutput)) {
            Write-Host "⚠️ You have uncommitted changes:"
            $statusLines = $statusOutput -split "`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 5
            foreach ($line in $statusLines) {
                if ($line.Length -ge 3) {
                    Write-Host "   → $($line.Substring(3))"
                }
            }
            
            $shouldContinue = Get-ValidYesNo "Continue pushing without committing these changes?"
            if (-not $shouldContinue) {
                Write-Host "🚫 Push cancelled. Commit your changes first or use the 'commit' action."
                return
            }
        }

        # Ask for repository name (with auto-detection option)
        $detectedRepo = $null
        try {
            $remoteUrl = git config --get remote.origin.url 2>$null
            if ($remoteUrl) {
                if ($remoteUrl -match '/([^/]+?)(?:\.git)?$') {
                    $detectedRepo = $matches[1]
                }
            }
        } catch {}

        if ($detectedRepo) {
            $useDetected = Get-ValidYesNo "Use detected repository name '$detectedRepo'?" "y"
            if ($useDetected) {
                $repoName = $detectedRepo
            } else {
                $repoName = Read-Host "Enter the repository name to push to"
            }
        } else {
            $repoName = Read-Host "Enter the repository name to push to"
        }

        $remoteUrl = "git@${sshAlias}:${githubUser}/${repoName}.git"

        # Configure Git identity
        git config user.name "$gitName"
        git config user.email "$gitEmail"

        # Handle remote setup
        $remoteExists = git remote | Where-Object { $_ -eq "origin" }
        if (-not $remoteExists) {
            git remote add origin $remoteUrl
            Write-Host "`n🔗 Remote 'origin' added: $remoteUrl"
        } else {
            # Check if remote URL matches
            $existingUrl = git config --get remote.origin.url
            if ($existingUrl -ne $remoteUrl) {
                git remote set-url origin $remoteUrl
                Write-Host "`n🔄 Remote 'origin' updated: $remoteUrl"
            }
        }

        # Check if upstream is set for current branch
        $upstreamExists = git rev-parse --abbrev-ref "$currentBranch@{upstream}" 2>$null
        
        Write-Host "`n🚀 Pushing branch '$currentBranch'..."
        try {
            if (-not $upstreamExists) {
                Write-Host "🔗 Setting upstream and pushing..."
                $pushOutput = git push -u origin $currentBranch 2>&1
            } else {
                $pushOutput = git push origin $currentBranch 2>&1
            }
            Write-Host $pushOutput

            Write-Host "`n✅ Push complete using '$account' identity:"
            Write-Host "  → Repo: $repoName"
            Write-Host "  → Branch: $currentBranch"
            Write-Host "  → Remote: origin ($sshAlias)"
            Write-Host "  → Git user.name: $gitName"
            Write-Host "  → Git user.email: $gitEmail"
        } catch {
            Write-Host "`n❌ Error during push:"
            Write-Host $_.Exception.Message
        }
    }

    "pull" {
        Write-Host "`n📥 Checking for Git repository..."
        if (-not (Test-Path ".git")) {
            Write-Host "`n❌ No Git repository found in the current directory."
            Write-Host "   → Make sure you're inside a valid Git repo before pulling."
            return
        }

        # Get current branch
        $currentBranch = Get-CurrentGitBranch
        if (-not $currentBranch) {
            Write-Host "`n❌ Unable to determine current branch. You may be in a detached HEAD state."
            return
        }

        # Check for uncommitted changes
        $statusOutput = git status --porcelain 2>$null
        if (-not [string]::IsNullOrWhiteSpace($statusOutput)) {
            Write-Host "⚠️ You have uncommitted changes:"
            $statusLines = $statusOutput -split "`n" | Where-Object { $_.Trim() -ne "" } | Select-Object -First 5
            foreach ($line in $statusLines) {
                if ($line.Length -ge 3) {
                    Write-Host "   → $($line.Substring(3))"
                }
            }
            
            Write-Host "`n🎯 Options:"
            Write-Host "   1. Stash changes and pull"
            Write-Host "   2. Continue pulling (may cause conflicts)"
            Write-Host "   3. Cancel pull"
            
            do {
                $pullChoice = Read-Host "Enter your choice (1-3)"
                switch ($pullChoice) {
                    "1" {
                        Write-Host "`n📦 Stashing changes..."
                        git stash push -m "Auto-stash before pull $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
                        $shouldPopStash = $true
                        $validChoice = $true
                    }
                    "2" {
                        Write-Host "`n⚠️ Continuing with uncommitted changes..."
                        $shouldPopStash = $false
                        $validChoice = $true
                    }
                    "3" {
                        Write-Host "`n🚫 Pull cancelled."
                        return
                    }
                    default {
                        Write-Host "❌ Invalid choice. Please enter 1, 2, or 3."
                        $validChoice = $false
                    }
                }
            } while (-not $validChoice)
        }

        Write-Host "`n📥 Pulling latest changes from origin/$currentBranch..."
        try {
            # Check if upstream is set
            $upstreamExists = git rev-parse --abbrev-ref "$currentBranch@{upstream}" 2>$null
            if (-not $upstreamExists) {
                Write-Host "🔗 No upstream set. Trying to pull from origin/$currentBranch..."
                $pullOutput = git pull origin $currentBranch 2>&1
            } else {
                $pullOutput = git pull 2>&1
            }
            
            Write-Host $pullOutput

            # Check if pull was successful
            if ($LASTEXITCODE -eq 0) {
                Write-Host "`n✅ Pull complete. Local repo updated with remote changes."
                
                # Pop stash if we stashed changes
                if ($shouldPopStash) {
                    Write-Host "`n📦 Restoring stashed changes..."
                    $stashOutput = git stash pop 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "✅ Stashed changes restored successfully."
                    } else {
                        Write-Host "⚠️ Conflict while restoring stash:"
                        Write-Host $stashOutput
                        Write-Host "   → Resolve conflicts manually and run 'git stash drop' when done"
                    }
                }
            } else {
                Write-Host "`n❌ Pull encountered issues. Check the output above."
                if ($shouldPopStash) {
                    Write-Host "   → Your changes are safely stashed. Use 'git stash pop' to restore them."
                }
            }
        } catch {
            Write-Host "`n❌ Error during pull:"
            Write-Host $_.Exception.Message
            if ($shouldPopStash) {
                Write-Host "   → Your changes are safely stashed. Use 'git stash pop' to restore them."
            }
        }
    }

    "remotelist" {
        $headers = @{
            Authorization = "Bearer $tokenPlain"
            Accept        = "application/vnd.github+json"
            "User-Agent"  = "GitGo-PowerShell-Script"
        }

        $apiUrl = "https://api.github.com/user/repos?per_page=100&sort=updated"

        Write-Host "`n📦 Fetching repositories for '$githubUser'..."
        try {
            $repos = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -TimeoutSec 30
            if ($repos.Count -eq 0) {
                Write-Host "`n📭 No repositories found under '$githubUser'."
            } else {
                Write-Host "`n📚 Repositories under '$githubUser' (sorted by last updated):`n"
                $index = 1
                foreach ($repo in $repos) {
                    $visibility = if ($repo.private) { "🔒 private" } else { "🌐 public" }
                    $lastUpdated = ([DateTime]$repo.updated_at).ToString("yyyy-MM-dd")
                    Write-Host ("  $index. $($repo.name)  [$visibility] (updated: $lastUpdated)")
                    $index++
                }
                Write-Host "`n📊 Total repositories: $($repos.Count)"
            }
        } catch {
            Write-Host "`n❌ Failed to fetch repositories:"
            Write-Host "   → Check your token validity with 'gitgo setup'"
            Write-Host "   → Verify network connectivity"
            Write-Host "   → Error: $($_.Exception.Message)"
        }
    }

    "addremote" {
        $headers = @{
            Authorization = "Bearer $tokenPlain"
            Accept        = "application/vnd.github+json"
            "User-Agent"  = "GitGo-PowerShell-Script"
        }

        do {
            $repoName = Read-Host "Enter the repository name (e.g., habit_flow_app)"
            
            # Validate repository name format
            if ($repoName -match '^[a-zA-Z0-9._-]+$' -and $repoName.Length -le 100) {
                $checkUrl = "https://api.github.com/repos/$githubUser/$repoName"

                try {
                    $existingRepo = Invoke-RestMethod -Uri $checkUrl -Method Get -Headers $headers -ErrorAction Stop -TimeoutSec 10
                    Write-Host "`n🚫 A repository named '$repoName' already exists under '$githubUser'. Please choose a different name."
                    $nameTaken = $true
                } catch {
                    if ($_.Exception.Response.StatusCode -eq 404) {
                        Write-Host "`n✅ Repo name '$repoName' is available."
                        $nameTaken = $false
                    } else {
                        Write-Host "`n❌ Error checking repository availability: $($_.Exception.Message)"
                        $nameTaken = $true
                    }
                }
            } else {
                Write-Host "`n❌ Invalid repository name. Use only letters, numbers, dots, hyphens, and underscores (max 100 chars)."
                $nameTaken = $true
            }
        } while ($nameTaken)

        $description = Read-Host "Enter a short description (optional)"
        $visibility = Get-ValidVisibility

        $body = @{
            name        = $repoName
            description = if ($description) { $description } else { "" }
            private     = if ($visibility -eq "private") { $true } else { $false }
            auto_init   = $true
        } | ConvertTo-Json -Depth 3

        Write-Host "`n🌐 Creating remote repository on GitHub with README..."
        Write-Host "🔑 Using $account account token"
        try {
            $response = Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Method Post -Headers $headers -Body $body -TimeoutSec 30
            Write-Host "`n✅ Remote repository created:"
            Write-Host "  → Name: $($response.name)"
            Write-Host "  → URL: $($response.html_url)"
            Write-Host "  → README.md initialized"
            Write-Host "  → Visibility: $visibility"

            $shouldClone = Get-ValidYesNo "🧲 Clone repo to current directory?"
            if ($shouldClone) {
                $aliasUrl = "git@${sshAlias}:${githubUser}/${repoName}.git"
                Write-Host "`n🔍 Cloning from: $aliasUrl"
                try {
                    $cloneOutput = git clone $aliasUrl 2>&1
                    Write-Host "`n📦 Cloning..."
                    Write-Host $cloneOutput
                    
                    if (Test-Path $repoName) {
                        Set-Location $repoName
                        git config user.name "$gitName"
                        git config user.email "$gitEmail"
                        
                        Write-Host "`n✅ Repo cloned and configured:"
                        Write-Host "  → Remote: $aliasUrl"
                        Write-Host "  → Git user.name: $gitName"
                        Write-Host "  → Git user.email: $gitEmail"
                        Write-Host "  → Current directory: .\$repoName"
                    } else {
                        Write-Host "`n⚠️ Clone succeeded but folder '$repoName' not found."
                    }
                } catch {
                    Write-Host "`n❌ Error during clone:"
                    Write-Host $_.Exception.Message
                }
            } else {
                Write-Host "`n🚫 Skipped cloning. Repo is live at: $($response.html_url)"
            }
        } catch {
            Write-Host "`n❌ Error creating remote repo:"
            Write-Host "   → Verify token has 'repo' scope"
            Write-Host "   → Check rate limits (5000 requests/hour)"
            Write-Host "   → Error: $($_.Exception.Message)"
        }
    }

    "delremote" {
        $headers = @{
            Authorization = "Bearer $tokenPlain"
            Accept        = "application/vnd.github+json"
            "User-Agent"  = "GitGo-PowerShell-Script"
        }

        do {
            $repoName = Read-Host "Enter the name of the repository to delete"
            $checkUrl = "https://api.github.com/repos/$githubUser/$repoName"

            try {
                $existingRepo = Invoke-RestMethod -Uri $checkUrl -Method Get -Headers $headers -ErrorAction Stop -TimeoutSec 10
                Write-Host "`n⚠️ Repo '$repoName' found under '$githubUser'."
                Write-Host "   Repository details:"
                Write-Host "   → Full name: $($existingRepo.full_name)"
                Write-Host "   → Visibility: $(if ($existingRepo.private) { 'Private' } else { 'Public' })"
                Write-Host "   → Last updated: $([DateTime]$existingRepo.updated_at)"
                $nameValid = $true
            } catch {
                if ($_.Exception.Response.StatusCode -eq 404) {
                    Write-Host "`n🚫 Repo '$repoName' not found under '$githubUser'. Please enter a valid name."
                } else {
                    Write-Host "`n❌ Error accessing repository: $($_.Exception.Message)"
                }
                $nameValid = $false
            }
        } while (-not $nameValid)

        Write-Host "`n⚠️ WARNING: This action cannot be undone!"
        Write-Host "🔑 Using $account account token"
        Write-Host "   → All code, issues, and wiki content will be permanently deleted"
        Write-Host "   → Repository name will be immediately available for reuse"
        
        $shouldDelete = Get-ValidYesNo "Are you absolutely sure you want to delete '$repoName'?"
        if ($shouldDelete) {
            try {
                Invoke-RestMethod -Uri $checkUrl -Method Delete -Headers $headers -TimeoutSec 30
                Write-Host "`n🗑️ Repository '$repoName' has been permanently deleted."
                Write-Host "   → The repository name '$repoName' is now available for reuse"
            } catch {
                Write-Host "`n❌ Failed to delete repository '$repoName':"
                Write-Host "   → Verify token has 'delete_repo' scope"
                Write-Host "   → Check if you have admin access to this repository"
                Write-Host "   → Error: $($_.Exception.Message)"
            }
        } else {
            Write-Host "`n🚫 Repository deletion cancelled. '$repoName' remains intact."
        }
    }

    "adduser" {
        $isGitRepo = Test-Path ".git"
        if (-not $isGitRepo) {
            Write-Host "`n🧱 No Git repo detected. Initializing..."
            git init
            Write-Host "✅ Git repository initialized."
        }

        $customName = Read-Host "Enter the Git username to set"
        $customEmail = Read-Host "Enter the Git email to set"
        
        # Validate email format
        if ($customEmail -match '^[^\s@]+@[^\s@]+\.[^\s@]+$') {
            git config user.name "$customName"
            git config user.email "$customEmail"

            Write-Host "`n✅ Git identity configured for this repository:"
            Write-Host "  → Git user.name: $customName"
            Write-Host "  → Git user.email: $customEmail"
        } else {
            Write-Host "`n❌ Invalid email format. Please enter a valid email address."
        }
    }

    "showuser" {
        $currentName = git config user.name 2>$null
        $currentEmail = git config user.email 2>$null
        $globalName = git config --global user.name 2>$null
        $globalEmail = git config --global user.email 2>$null

        Write-Host "`n👤 Git Identity Configuration:"
        Write-Host "──────────────────────────────────────────────"
        
        if (Test-Path ".git") {
            Write-Host "📁 Current Repository:"
            Write-Host "  → Name: $(if ($currentName) { $currentName } else { '(not set)' })"
            Write-Host "  → Email: $(if ($currentEmail) { $currentEmail } else { '(not set)' })"
        } else {
            Write-Host "📁 Current Directory: (not a Git repository)"
        }
        
        Write-Host "`n🌍 Global Configuration:"
        Write-Host "  → Name: $(if ($globalName) { $globalName } else { '(not set)' })"
        Write-Host "  → Email: $(if ($globalEmail) { $globalEmail } else { '(not set)' })"
    }

    "commit" {
        Invoke-GitCommit
    }

    "history" {
        Show-GitHistory
    }

    "tokeninfo" {
        Write-Host "`n🔐 GitHub Token Information"
        Write-Host "──────────────────────────────────────────────"
        
        try {
            $tokenPlain = Get-GitHubToken -Account $account
            Test-GitHubTokenScopes -Token $tokenPlain -AccountName $account
        } catch {
            Write-Host $_.Exception.Message
        }
    }

    "status" {
        Get-GitRepositoryInfo
    }

    "branch" {
        # Ensure we are inside a git repo
        if (-not (Test-Path ".git")) {
            Write-Host "`n❌ Not a Git repository. Initialize with 'git init' first."
            return
        }

        Write-Host "`n🌿 Branch Manager"
        Write-Host "──────────────────────────────────────────────"
        Write-Host "  1) Show available branches"
        Write-Host "  2) Create a new branch"
        Write-Host "  3) Switch branch"
        Write-Host "  4) Delete branch"

        do {
            $branchChoice = Read-Host "`nEnter your choice (1-4)"
            switch ($branchChoice) {
                "1" {
                    Write-Host "`n📋 Available branches:`n"
                    try {
                        # Mark current with *
                        $branches = git branch --all 2>$null
                        if ($branches) { $branches | ForEach-Object { Write-Host "   $_" } }
                        else { Write-Host "   (no branches found)" }
                    } catch {
                        Write-Host "❌ Failed to list branches: $($_.Exception.Message)"
                    }
                    $validBranchChoice = $true
                }
                "2" {
                    $newBranch = Read-Host "Enter new branch name"
                    if ([string]::IsNullOrWhiteSpace($newBranch)) {
                        Write-Host "❌ Branch name cannot be empty."
                        $validBranchChoice = $false
                    } else {
                        try {
                            git checkout -b $newBranch 2>&1 | Write-Host
                            Write-Host "✅ Created and switched to '$newBranch'"
                            $validBranchChoice = $true
                        } catch {
                            Write-Host "❌ Failed to create branch: $($_.Exception.Message)"
                            $validBranchChoice = $false
                        }
                    }
                }
                "3" {
                    $targetBranch = Read-Host "Enter branch name to switch to"
                    if ([string]::IsNullOrWhiteSpace($targetBranch)) {
                        Write-Host "❌ Branch name cannot be empty."
                        $validBranchChoice = $false
                    } else {
                        try {
                            git checkout $targetBranch 2>&1 | Write-Host
                            Write-Host "✅ Switched to '$targetBranch'"
                            $validBranchChoice = $true
                        } catch {
                            Write-Host "❌ Failed to switch branch: $($_.Exception.Message)"
                            $validBranchChoice = $false
                        }
                    }
                }
                "4" {
                    $deleteBranch = Read-Host "Enter branch name to delete"
                    if ([string]::IsNullOrWhiteSpace($deleteBranch)) {
                        Write-Host "❌ Branch name cannot be empty."
                        $validBranchChoice = $false
                    } else {
                        $forceDelete = Get-ValidYesNo "Force delete? (use if branch not fully merged)" "n"
                        try {
                            if ($forceDelete) { git branch -D $deleteBranch 2>&1 | Write-Host }
                            else { git branch -d $deleteBranch 2>&1 | Write-Host }
                            Write-Host "✅ Deleted branch '$deleteBranch'"
                            $validBranchChoice = $true
                        } catch {
                            Write-Host "❌ Failed to delete branch: $($_.Exception.Message)"
                            $validBranchChoice = $false
                        }
                    }
                }
                default {
                    Write-Host "❌ Invalid choice. Please enter 1, 2, 3, or 4."
                    $validBranchChoice = $false
                }
            }
        } while (-not $validBranchChoice)
    }

    default {
        Write-Host "`n❌ Invalid action. Please enter one of the following:"
        Write-Host "   → clone / push / pull / adduser / showuser / addremote / delremote / remotelist / status / commit / history / tokeninfo / setup / branch"
    }
}