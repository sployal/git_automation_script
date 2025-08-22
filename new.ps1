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
        "14. branch     → Manage branches (list/create/switch/delete)",
        "15. remotem    → Manage remote for current repository"
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

# Function to read accounts from SSH config file
function Get-AccountsFromSSHConfig {
    $sshDir = "$env:USERPROFILE\.ssh"
    $configPath = "$sshDir\config"
    
    if (-not (Test-Path $configPath)) {
        Write-Host "`n❌ SSH config file not found: $configPath"
        Write-Host "   → Please run 'gitgo setup' and select SSH Configuration first"
        throw "SSH config file not found"
    }
    
    try {
        $configContent = Get-Content $configPath -Raw
        $accounts = @()
        
        # Parse SSH config for GitHub hosts
        $lines = $configContent -split "`n"
        $currentHost = $null
        $currentAlias = $null
        
        foreach ($line in $lines) {
            $line = $line.Trim()
            
            if ($line.StartsWith("Host ") -and $line -match "^Host (.+)$") {
                $currentHost = $matches[1]
                $currentAlias = $currentHost
            }
            elseif ($line.StartsWith("IdentityFile ") -and $line -match "IdentityFile ~/\.ssh/id_ed25519_(.+)") {
                $alias = $matches[1]
                $accountType = $alias -replace 'github-', '' -replace '_', ' '
                $accountType = (Get-Culture).TextInfo.ToTitleCase($accountType.ToLower())
                
                $accounts += [PSCustomObject]@{
                    id = $alias
                    name = $accountType
                    sshAlias = $currentAlias
                    tokenEnvVar = "GITHUB_$($alias.ToUpper().Replace('-', '_'))_TOKEN"
                }
            }
        }
        
        if ($accounts.Count -eq 0) {
            throw "No GitHub accounts found in SSH config"
        }
        
        return $accounts
    } catch {
        Write-Host "`n❌ Error reading SSH config: $($_.Exception.Message)"
        throw $_.Exception.Message
    }
}

# Function to securely retrieve GitHub tokens
function Get-GitHubToken {
    param(
        [string]$Account
    )
    
    try {
        $accounts = Get-AccountsFromSSHConfig
        $accountConfig = $accounts | Where-Object { $_.id -eq $Account }
        
        if (-not $accountConfig) {
            throw "Account '$Account' not found in SSH config"
        }
        
        $token = [Environment]::GetEnvironmentVariable($accountConfig.tokenEnvVar, "User")
        
        if ([string]::IsNullOrWhiteSpace($token)) {
            Write-Host "`n❌ GitHub token not found for $($accountConfig.name)."
            Write-Host "   → Run 'gitgo setup' or action '13' to configure tokens."
            Write-Host "   → Or manually set environment variable: $($accountConfig.tokenEnvVar)"
            throw "Missing GitHub token for $($accountConfig.name)"
        }
        
        return $token
    } catch {
        Write-Host "`n❌ Error retrieving token: $($_.Exception.Message)"
        throw $_.Exception.Message
    }
}

# Function to generate GitHub SSH keys and configure SSH
function Generate-GitHubSSHKeysAndConfig {
    $sshDir = "$env:USERPROFILE\.ssh"
    $configPath = "$sshDir\config"
    $configEntries = @()

    # 🔧 Ensure .ssh directory exists
    if (-not (Test-Path $sshDir)) {
        Write-Host "🔧 Creating .ssh directory..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $sshDir | Out-Null
    }

    # 🔍 Check if ssh-keygen is available
    if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
        Write-Host "❌ 'ssh-keygen' not found. Please install OpenSSH Client or restart PowerShell." -ForegroundColor Red
        return
    }

    # 🔢 Prompt for number of accounts (max 3)
    do {
        $count = Read-Host "How many GitHub accounts do you want to set up? (Max: 3)" | ForEach-Object { [int]$_ }
        if ($count -gt 3) {
            Write-Host "⚠️ You can only set up a maximum of 3 accounts at once." -ForegroundColor DarkYellow
        }
    } while ($count -gt 3 -or $count -lt 1)

    for ($i = 1; $i -le $count; $i++) {
        Write-Host "`n🧑‍💻 Account #$i setup" -ForegroundColor Cyan
        $accountType = Read-Host "Enter account name/type (e.g., personal, work, freelance)"
        $email = Read-Host "Enter email for '$accountType' account"
        $alias = "github-" + ($accountType.ToLower().Trim() -replace '[^a-z0-9]', '_')
        $keyName = "id_ed25519_$alias"
        $keyPath = "$sshDir\$keyName"
        $pubKeyPath = "$keyPath.pub"

        # 🚀 Generate SSH key
        if (Test-Path $keyPath) {
            Write-Host "⚠️ Key '$keyName' already exists. Skipping generation." -ForegroundColor DarkYellow
        } else {
            Write-Host "🔐 Generating SSH key for '$accountType'..." -ForegroundColor Cyan
            ssh-keygen -t ed25519 -C "$email" -f "$keyPath" | Out-Null

            if (Test-Path $keyPath) {
                Write-Host "✅ Key generated: $keyPath" -ForegroundColor Green
            } else {
                Write-Host "❌ Key generation failed for '$accountType'." -ForegroundColor Red
                continue
            }
        }

        # 📋 Show public key
        if (Test-Path $pubKeyPath) {
            Write-Host "`n📋 Public key for '$accountType' (copy to GitHub):" -ForegroundColor Magenta
            Get-Content $pubKeyPath

            # 🧭 Guidance: Add the key to GitHub and copy to clipboard
            Write-Host "`n🧭 Add this SSH key to your GitHub account:" -ForegroundColor Yellow
            Write-Host "   1) Open: https://github.com/settings/keys"
            Write-Host "   2) Click 'New SSH key'"
            Write-Host "   3) Paste the key above into the 'Key' field and save"

            # 📋 Automatically copy the public key to clipboard (Windows/PowerShell)
            try {
                Get-Content $pubKeyPath | Set-Clipboard
                Write-Host "📌 Public key has been copied to your clipboard." -ForegroundColor Green
            } catch {
                Write-Host "⚠️ Could not copy to clipboard automatically. Please copy it manually." -ForegroundColor DarkYellow
            }
        }

        # 🧩 Add SSH config entry
        $entry = @"
# $accountType GitHub
Host $alias
  HostName github.com
  User git
  IdentityFile ~/.ssh/$keyName
  IdentitiesOnly yes
"@
        $configEntries += $entry
    }

    # 🛠️ Write SSH config file
    Write-Host "`n⚙️ Writing SSH config file..." -ForegroundColor Yellow
    $configEntries | Set-Content -Path $configPath -Encoding UTF8
    Write-Host "✅ SSH config saved to: $configPath" -ForegroundColor Green
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
        $accounts = Get-AccountsFromSSHConfig
        
        Write-Host "👤 Available GitHub Accounts:"
        Write-Host "──────────────────────────────────────────────"
        
        for ($i = 0; $i -lt $accounts.Count; $i++) {
            $account = $accounts[$i]
            Write-Host "   $($i + 1). $($account.name)"
        }
        
        $tokens = @{}
        
        for ($i = 0; $i -lt $accounts.Count; $i++) {
            $account = $accounts[$i]
            Write-Host "`n🔑 $($account.name) Token:"
            $token = Read-Host "Enter your $($account.name.ToUpper()) GitHub token" -AsSecureString
            
            # Convert secure string to plain text
            $tokenPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($token))
            
            # Validate token is not empty
            if ([string]::IsNullOrWhiteSpace($tokenPlain)) {
                throw "Token for $($account.name) cannot be empty"
            }
            
            $tokens[$account.tokenEnvVar] = $tokenPlain
            
            # Clear sensitive variables from memory
            $token.Dispose()
        }
        
        # Set all environment variables
        foreach ($envVar in $tokens.Keys) {
            [Environment]::SetEnvironmentVariable($envVar, $tokens[$envVar], "User")
        }
        
        Write-Host "`n✅ Tokens configured successfully!"
        Write-Host "🔄 Environment variables updated:"
        foreach ($envVar in $tokens.Keys) {
            Write-Host "   → $envVar"
        }
        Write-Host "`n⚠️  Please restart PowerShell for changes to take effect."
        Write-Host "   Or reload environment: refreshenv (if using Chocolatey)"
        
    } catch {
        Write-Host "`n❌ Token setup failed: $($_.Exception.Message)"
    } finally {
        # Clear sensitive variables from memory
        if ($tokens) {
            foreach ($token in $tokens.Values) {
                $token = $null
            }
            $tokens.Clear()
        }
    }
}

# Function to delete GitHub tokens
function Remove-GitHubTokens {
    Write-Host "`n🗑️ Delete GitHub Tokens"
    Write-Host "──────────────────────────────────────────────"
    Write-Host "This will remove your stored GitHub Personal Access Tokens."
    Write-Host "Tokens will be deleted from user environment variables.`n"
    
    try {
        $accounts = Get-AccountsFromSSHConfig
        
        Write-Host "👤 Available GitHub Accounts:"
        Write-Host "──────────────────────────────────────────────"
        
        for ($i = 0; $i -lt $accounts.Count; $i++) {
            $account = $accounts[$i]
            $tokenExists = [Environment]::GetEnvironmentVariable($account.tokenEnvVar, "User")
            $status = if ($tokenExists) { "✅ Token exists" } else { "❌ No token" }
            Write-Host "   $($i + 1). $($account.name) - $status"
        }
        
        Write-Host "`n🎯 Delete options:"
        Write-Host "   1) Delete tokens for specific account"
        Write-Host "   2) Delete all tokens"
        Write-Host "   3) Cancel"
        
        do {
            $deleteChoice = Read-Host "`nEnter your choice (1-3)"
            switch ($deleteChoice) {
                "1" {
                    Write-Host "`n👤 Select account to delete tokens:"
                    for ($i = 0; $i -lt $accounts.Count; $i++) {
                        $account = $accounts[$i]
                        $tokenExists = [Environment]::GetEnvironmentVariable($account.tokenEnvVar, "User")
                        if ($tokenExists) {
                            Write-Host "   $($i + 1). $($account.name)"
                        }
                    }
                    
                    do {
                        $accountChoice = Read-Host "`nEnter account number to delete tokens"
                        if ([int]::TryParse($accountChoice, [ref]$null) -and [int]$accountChoice -ge 1 -and [int]$accountChoice -le $accounts.Count) {
                            $selectedAccount = $accounts[[int]$accountChoice - 1]
                            $tokenExists = [Environment]::GetEnvironmentVariable($selectedAccount.tokenEnvVar, "User")
                            
                            if ($tokenExists) {
                                $confirm = Get-ValidYesNo "Are you sure you want to delete tokens for $($selectedAccount.name)?"
                                if ($confirm) {
                                    [Environment]::SetEnvironmentVariable($selectedAccount.tokenEnvVar, $null, "User")
                                    Write-Host "✅ Tokens deleted for $($selectedAccount.name)"
                                    Write-Host "   → Removed: $($selectedAccount.tokenEnvVar)"
                                } else {
                                    Write-Host "🚫 Token deletion cancelled for $($selectedAccount.name)"
                                }
                            } else {
                                Write-Host "ℹ️ No tokens found for $($selectedAccount.name)"
                            }
                            $validAccountChoice = $true
                        } else {
                            Write-Host "❌ Invalid choice. Please enter a number between 1 and $($accounts.Count)."
                            $validAccountChoice = $false
                        }
                    } while (-not $validAccountChoice)
                    $validDeleteChoice = $true
                }
                "2" {
                    $confirm = Get-ValidYesNo "Are you absolutely sure you want to delete ALL GitHub tokens?"
                    if ($confirm) {
                        $deletedCount = 0
                        foreach ($account in $accounts) {
                            $tokenExists = [Environment]::GetEnvironmentVariable($account.tokenEnvVar, "User")
                            if ($tokenExists) {
                                [Environment]::SetEnvironmentVariable($account.tokenEnvVar, $null, "User")
                                Write-Host "✅ Deleted: $($account.tokenEnvVar)"
                                $deletedCount++
                            }
                        }
                        
                        if ($deletedCount -gt 0) {
                            Write-Host "`n✅ Successfully deleted $deletedCount token(s)"
                            Write-Host "🔄 Environment variables updated"
                            Write-Host "⚠️  Please restart PowerShell for changes to take effect"
                        } else {
                            Write-Host "`nℹ️ No tokens were found to delete"
                        }
                    } else {
                        Write-Host "🚫 Token deletion cancelled"
                    }
                    $validDeleteChoice = $true
                }
                "3" {
                    Write-Host "🚫 Token deletion cancelled"
                    $validDeleteChoice = $true
                }
                default {
                    Write-Host "❌ Invalid choice. Please enter 1, 2, or 3."
                    $validDeleteChoice = $false
                }
            }
        } while (-not $validDeleteChoice)
        
    } catch {
        Write-Host "`n❌ Error deleting tokens: $($_.Exception.Message)"
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
    Write-Host "`n🔧 Setup Options"
    Write-Host "──────────────────────────────────────────────"
    Write-Host "   1) SSH Configuration (Generate SSH keys for GitHub accounts)"
    Write-Host "   2) GitHub Token Setup (Configure Personal Access Tokens)"
    Write-Host "   3) Delete GitHub Tokens (Remove stored tokens)"
    
    do {
        $setupChoice = Read-Host "`nEnter your choice (1-3)"
        switch ($setupChoice) {
            "1" {
                Write-Host "`n🔐 SSH Configuration Setup"
                Write-Host "──────────────────────────────────────────────"
                Generate-GitHubSSHKeysAndConfig
                $validSetupChoice = $true
            }
            "2" {
                Write-Host "`n🔑 GitHub Token Setup"
                Write-Host "──────────────────────────────────────────────"
                Set-GitHubTokens
                $validSetupChoice = $true
            }
            "3" {
                Write-Host "`n🗑️ Delete GitHub Tokens"
                Write-Host "──────────────────────────────────────────────"
                Remove-GitHubTokens
                $validSetupChoice = $true
            }
            default {
                Write-Host "❌ Invalid choice. Please enter 1, 2, or 3."
                $validSetupChoice = $false
            }
        }
    } while (-not $validSetupChoice)
    exit
}

# Define valid actions
$validActions = @("clone", "push", "pull", "adduser", "showuser", "addremote", "remotelist", "delremote", "status", "commit", "history", "tokeninfo", "setup", "branch", "remotem", "help")

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

    # Show current branch
    $currentBranchInfo = Get-CurrentGitBranch
    if ($currentBranchInfo) {
        Write-Host "🌿 Current Branch: $currentBranchInfo"
    }

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

        # After commit: ensure remote and optionally push
        $currentBranch = Get-CurrentGitBranch
        if ($currentBranch) {
            # Check if remote 'origin' exists
            $remoteExists = git remote | Where-Object { $_ -eq "origin" }
            if (-not $remoteExists) {
                Write-Host "`n🔗 No remote configured. Let's set one up to push your changes."
                # Reuse account selection helper
                $account = Get-ValidAccount
                $accounts = Get-AccountsFromSSHConfig
                $accountConfig = $accounts | Where-Object { $_.id -eq $account }
                
                Write-Host "`n👤 Account: $($accountConfig.name)"
                $githubUser = Read-Host "Enter your GitHub username for this account"
                $gitEmail = Read-Host "Enter your Git email for this account"
                $sshAlias = $accountConfig.sshAlias

                $repoName = Read-Host "Enter the repository name to push to"
                $remoteUrl = "git@${sshAlias}:${githubUser}/${repoName}.git"
                git remote add origin $remoteUrl
                Write-Host "🔗 Remote 'origin' added: $remoteUrl"
            }

            $shouldPush = Get-ValidYesNo "🚀 Push commit to origin/$currentBranch?"
            if ($shouldPush) {
                # Choose push mode
                Write-Host "`n📤 Push options:"
                Write-Host "   1) Normal push"
                Write-Host "   2) Force push (with lease)"
                Write-Host "   3) Force push (without lease)"
                do {
                    $commitPushChoice = Read-Host "Enter your choice (1-3)"
                    switch ($commitPushChoice) {
                        "1" { $commitForceMode = "normal"; $validCommitPushChoice = $true }
                        "2" { $commitForceMode = "with-lease"; $validCommitPushChoice = $true }
                        "3" { $commitForceMode = "force"; $validCommitPushChoice = $true }
                        default { Write-Host "❌ Invalid choice. Please enter 1, 2, or 3."; $validCommitPushChoice = $false }
                    }
                } while (-not $validCommitPushChoice)

                # Check if upstream is set
                $upstreamExists = git rev-parse --abbrev-ref "$currentBranch@{upstream}" 2>$null
                if (-not $upstreamExists) {
                    if ($commitForceMode -eq "with-lease") {
                        Write-Host "🔗 Setting upstream and force pushing (with lease)..."
                        git push -u --force-with-lease origin $currentBranch
                    } elseif ($commitForceMode -eq "force") {
                        Write-Host "🔗 Setting upstream and force pushing (without lease)..."
                        git push -u --force origin $currentBranch
                    } else {
                        Write-Host "🔗 Setting upstream and pushing..."
                        git push -u origin $currentBranch
                    }
                } else {
                    if ($commitForceMode -eq "with-lease") {
                        git push --force-with-lease origin $currentBranch
                    } elseif ($commitForceMode -eq "force") {
                        git push --force origin $currentBranch
                    } else {
                        git push origin $currentBranch
                    }
                }
                Write-Host "✅ Changes pushed successfully!"
            }
        }

        # Post-commit actions
        Write-Host "`n📂 Post-commit actions:"
        Write-Host "   1) Open repo in File Explorer"
        Write-Host "   2) Open repo in VS Code"
        Write-Host "   3) Not now"
        do {
            $postCommitChoice = Read-Host "Enter your choice (1-3)"
            switch ($postCommitChoice) {
                "1" {
                    Write-Host "🔍 Opening File Explorer..."
                    Start-Process "explorer.exe" -ArgumentList "."
                    $validPostChoice = $true
                }
                "2" {
                    Write-Host "💻 Opening VS Code..."
                    Start-Process "code" -ArgumentList "."
                    $validPostChoice = $true
                }
                "3" {
                    Write-Host "⏭️ Skipping post-commit actions."
                    $validPostChoice = $true
                }
                default {
                    Write-Host "❌ Invalid choice. Please enter 1, 2, or 3."
                    $validPostChoice = $false
                }
            }
        } while (-not $validPostChoice)
        
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

# Dynamically find setup action number
$setupActionNumber = $numberedActions.GetEnumerator() | Where-Object { $_.Value -eq "setup" } | Select-Object -ExpandProperty Key
Write-Host "`nFirst time? Run 'setup' ($setupActionNumber) to configure GitHub tokens securely."

# Prompt until valid action or 'q' is entered
do {
    $input = Read-Host "`nEnter your action"
    if ($input -eq "q") {
        Write-Host "`n👋 Exiting GitGo."
        exit
    } elseif (($validActions -contains $input) -or ($numberedActions.ContainsKey($input))) {
        # Resolve to action name if a number was provided
        $resolvedAction = if ($numberedActions.ContainsKey($input)) { $numberedActions[$input] } else { $input }
        if ($resolvedAction -eq "help") {
            # Inline help that doesn't exit; re-display actions and continue loop
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
                "14. branch     → Manage branches (list/create/switch/delete)",
                "15. remotem    → Manage remote for current repository",
                "16. help       → Show this help and return to prompt"
            )
            foreach ($line in $helpItems) { Write-Host "  $line" }
            Write-Host "`nUsage:"
            Write-Host "  gitgo         → Launch interactive menu"
            Write-Host "  gitgo --help  → Show this help menu"
            Write-Host "`nFirst time setup:"
            Write-Host "  gitgo setup   → Configure your GitHub tokens"
            Write-Host "`n(Type an action name/number or 'q' to quit)"
            $action = $null
        } else {
            $action = $resolvedAction
        }
    } else {
        Write-Host "`n❌ Invalid input. Please enter a valid action name, number, or 'q' to quit."
        $action = $null
    }
} until ($action)

# Function to validate and get account selection
function Get-ValidAccount {
    try {
        $accounts = Get-AccountsFromSSHConfig
        
        Write-Host "`n👤 Available GitHub Accounts:"
        Write-Host "──────────────────────────────────────────────"
        
        for ($i = 0; $i -lt $accounts.Count; $i++) {
            $account = $accounts[$i]
            Write-Host "   $($i + 1). $($account.name)"
        }
        
        do {
            $choice = Read-Host "`nEnter your choice (1-$($accounts.Count))"
            if ([int]::TryParse($choice, [ref]$null) -and [int]$choice -ge 1 -and [int]$choice -le $accounts.Count) {
                $selectedAccount = $accounts[[int]$choice - 1]
                return $selectedAccount.id
            } else {
                Write-Host "`n❌ Invalid choice. Please enter a number between 1 and $($accounts.Count)."
            }
        } while ($true)
    } catch {
        Write-Host "`n❌ Error loading accounts: $($_.Exception.Message)"
        throw $_.Exception.Message
    }
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
    try {
        $account = Get-ValidAccount
        $accounts = Get-AccountsFromSSHConfig
        $accountConfig = $accounts | Where-Object { $_.id -eq $account }
        
        # For now, we'll need to get the GitHub username and email from user input
        # since they're not stored in the SSH config
        Write-Host "`n👤 Account: $($accountConfig.name)"
        $githubUser = Read-Host "Enter your GitHub username for this account"
        $gitEmail = Read-Host "Enter your Git email for this account"
        $sshAlias = $accountConfig.sshAlias
        
        # Securely retrieve token from environment variables
        try {
            $tokenPlain = Get-GitHubToken -Account $account
        } catch {
            Write-Host $_.Exception.Message
            return
        }
    } catch {
        Write-Host "`n❌ Error setting up account: $($_.Exception.Message)"
        return
    }
}

switch ($action) {

    "setup" {
        Write-Host "`n🔧 Setup Options"
        Write-Host "──────────────────────────────────────────────"
        Write-Host "   1) SSH Configuration (Generate SSH keys for GitHub accounts)"
        Write-Host "   2) GitHub Token Setup (Configure Personal Access Tokens)"
        Write-Host "   3) Delete GitHub Tokens (Remove stored tokens)"
        
        do {
            $setupChoice = Read-Host "`nEnter your choice (1-3)"
            switch ($setupChoice) {
                "1" {
                    Write-Host "`n🔐 SSH Configuration Setup"
                    Write-Host "──────────────────────────────────────────────"
                    Generate-GitHubSSHKeysAndConfig
                    $validSetupChoice = $true
                }
                "2" {
                    Write-Host "`n🔑 GitHub Token Setup"
                    Write-Host "──────────────────────────────────────────────"
                    Set-GitHubTokens
                    $validSetupChoice = $true
                }
                "3" {
                    Write-Host "`n🗑️ Delete GitHub Tokens"
                    Write-Host "──────────────────────────────────────────────"
                    Remove-GitHubTokens
                    $validSetupChoice = $true
                }
                default {
                    Write-Host "❌ Invalid choice. Please enter 1, 2, or 3."
                    $validSetupChoice = $false
                }
            }
        } while (-not $validSetupChoice)
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

                # Post-clone actions
                Write-Host "`n📂 Post-clone actions:"
                Write-Host "   1) Open repo in File Explorer"
                Write-Host "   2) Open repo in VS Code"
                Write-Host "   3) Not now"
                do {
                    $postCloneChoice = Read-Host "Enter your choice (1-3)"
                    switch ($postCloneChoice) {
                        "1" {
                            Write-Host "🔍 Opening File Explorer..."
                            Start-Process "explorer.exe" -ArgumentList "."
                            $validPostCloneChoice = $true
                        }
                        "2" {
                            Write-Host "💻 Opening VS Code..."
                            Start-Process "code" -ArgumentList "."
                            $validPostCloneChoice = $true
                        }
                        "3" {
                            Write-Host "⏭️ Skipping post-clone actions."
                            $validPostCloneChoice = $true
                        }
                        default {
                            Write-Host "❌ Invalid choice. Please enter 1, 2, or 3."
                            $validPostCloneChoice = $false
                        }
                    }
                } while (-not $validPostCloneChoice)
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

        # Choose push mode
        Write-Host "`n📤 Push options:"
        Write-Host "   1) Normal push"
        Write-Host "   2) Force push (with lease)"
        Write-Host "   3) Force push (without lease)"
        do {
            $pushChoice = Read-Host "Enter your choice (1-3)"
            switch ($pushChoice) {
                "1" { $pushMode = "normal";      $validPushChoice = $true }
                "2" { $pushMode = "with-lease";  $validPushChoice = $true }
                "3" { $pushMode = "force";       $validPushChoice = $true }
                default { Write-Host "❌ Invalid choice. Please enter 1, 2, or 3."; $validPushChoice = $false }
            }
        } while (-not $validPushChoice)

        Write-Host "`n🚀 Pushing branch '$currentBranch'..."
        try {
            if (-not $upstreamExists) {
                if ($pushMode -eq "with-lease") {
                    Write-Host "🔗 Setting upstream and force pushing (with lease)..."
                    $pushOutput = git push -u --force-with-lease origin $currentBranch 2>&1
                } elseif ($pushMode -eq "force") {
                    Write-Host "🔗 Setting upstream and force pushing (without lease)..."
                    $pushOutput = git push -u --force origin $currentBranch 2>&1
                } else {
                    Write-Host "🔗 Setting upstream and pushing..."
                    $pushOutput = git push -u origin $currentBranch 2>&1
                }
            } else {
                if ($pushMode -eq "with-lease") {
                    $pushOutput = git push --force-with-lease origin $currentBranch 2>&1
                } elseif ($pushMode -eq "force") {
                    $pushOutput = git push --force origin $currentBranch 2>&1
                } else {
                    $pushOutput = git push origin $currentBranch 2>&1
                }
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

                        # Post-clone actions
                        Write-Host "`n📂 Post-clone actions:"
                        Write-Host "   1) Open repo in File Explorer"
                        Write-Host "   2) Open repo in VS Code"
                        Write-Host "   3) Not now"
                        do {
                            $postCloneChoice = Read-Host "Enter your choice (1-3)"
                            switch ($postCloneChoice) {
                                "1" {
                                    Write-Host "🔍 Opening File Explorer..."
                                    Start-Process "explorer.exe" -ArgumentList "."
                                    $validPostCloneChoice = $true
                                }
                                "2" {
                                    Write-Host "💻 Opening VS Code..."
                                    Start-Process "code" -ArgumentList "."
                                    $validPostCloneChoice = $true
                                }
                                "3" {
                                    Write-Host "⏭️ Skipping post-clone actions."
                                    $validPostCloneChoice = $true
                                }
                                default {
                                    Write-Host "❌ Invalid choice. Please enter 1, 2, or 3."
                                    $validPostCloneChoice = $false
                                }
                            }
                        } while (-not $validPostCloneChoice)
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

    "remotem" {
        # Ensure we are inside a git repo
        if (-not (Test-Path ".git")) {
            Write-Host "`n❌ Not a Git repository. Initialize with 'git init' first."
            return
        }

        Write-Host "`n🔗 Remote Manager"
        Write-Host "──────────────────────────────────────────────"

        # Show current remote and upstream info
        $currentBranch = Get-CurrentGitBranch
        if ($currentBranch) { Write-Host "🌿 Current Branch: $currentBranch" }
        $existingUrl = git config --get remote.origin.url 2>$null
        if ($existingUrl) {
            Write-Host "🔗 Current remote 'origin': $existingUrl"
            $upstream = git rev-parse --abbrev-ref "$currentBranch@{upstream}" 2>$null
            if ($upstream) { Write-Host "   → Upstream: $upstream" }

            Write-Host "`nOptions:"
            Write-Host "  u) Update remote URL (switch to another repo)"
            Write-Host "  r) Remove remote and add a new one"

            do {
                $remoteChoice = Read-Host "Enter choice (u/r)"
                switch ($remoteChoice.ToLower()) {
                    "u" {
                        $account = Get-ValidAccount
                        $accounts = Get-AccountsFromSSHConfig
                        $accountConfig = $accounts | Where-Object { $_.id -eq $account }
                        
                        Write-Host "`n👤 Account: $($accountConfig.name)"
                        $githubUser = Read-Host "Enter your GitHub username for this account"
                        $sshAlias = $accountConfig.sshAlias
                        $newRepo    = Read-Host "Enter the NEW repository name"
                        if ([string]::IsNullOrWhiteSpace($newRepo)) { Write-Host "❌ Repo name cannot be empty."; $valid = $false; break }
                        $newUrl = "git@${sshAlias}:${githubUser}/${newRepo}.git"
                        git remote set-url origin $newUrl
                        Write-Host "✅ Remote updated: origin → $newUrl"
                        $valid = $true
                    }
                    "r" {
                        git remote remove origin 2>$null
                        Write-Host "✅ Removed remote 'origin'."
                        $account = Get-ValidAccount
                        $accounts = Get-AccountsFromSSHConfig
                        $accountConfig = $accounts | Where-Object { $_.id -eq $account }
                        
                        Write-Host "`n👤 Account: $($accountConfig.name)"
                        $githubUser = Read-Host "Enter your GitHub username for this account"
                        $sshAlias = $accountConfig.sshAlias
                        $repoName   = Read-Host "Enter the repository name to add as origin"
                        if ([string]::IsNullOrWhiteSpace($repoName)) { Write-Host "❌ Repo name cannot be empty."; $valid = $false; break }
                        $newUrl = "git@${sshAlias}:${githubUser}/${repoName}.git"
                        git remote add origin $newUrl
                        Write-Host "✅ Added remote 'origin': $newUrl"
                        $valid = $true
                    }
                    default {
                        Write-Host "❌ Invalid choice. Enter 'u' to update or 'r' to remove & add."
                        $valid = $false
                    }
                }
            } while (-not $valid)
        } else {
            Write-Host "🔍 No remote found for this repository."
            $shouldAdd = Get-ValidYesNo "Add a remote now?" "y"
            if ($shouldAdd) {
                $account = Get-ValidAccount
                $accounts = Get-AccountsFromSSHConfig
                $accountConfig = $accounts | Where-Object { $_.id -eq $account }
                
                Write-Host "`n👤 Account: $($accountConfig.name)"
                $githubUser = Read-Host "Enter your GitHub username for this account"
                $sshAlias = $accountConfig.sshAlias
                $repoName   = Read-Host "Enter the repository name to add as origin"
                if ([string]::IsNullOrWhiteSpace($repoName)) { Write-Host "❌ Repo name cannot be empty."; return }
                $newUrl = "git@${sshAlias}:${githubUser}/${repoName}.git"
                git remote add origin $newUrl
                Write-Host "✅ Added remote 'origin': $newUrl"
            }
        }
    }

    default {
        Write-Host "`n❌ Invalid action. Please enter one of the following:"
        Write-Host "   → clone / push / pull / adduser / showuser / addremote / delremote / remotelist / status / commit / history / tokeninfo / setup / branch / remotem"
    }
}