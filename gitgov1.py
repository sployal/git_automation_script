#!/usr/bin/env python3
"""
GitGo - Git Workflow Automation Tool
Python version of the PowerShell GitGo script
Creator: David Muigai — Nairobi, Kenya
"""

import os
import sys
import subprocess
import json
import getpass
import re
from datetime import datetime
from urllib.parse import urlparse
import requests
from pathlib import Path
import platform
import shutil


def safe_input(prompt):
    try:
        return input(prompt)
    except KeyboardInterrupt:
        print("\n👋 Exiting GitGo. Goodbye!")
        sys.exit(0)


def generate_github_ssh_keys_and_config():
    """Generate GitHub SSH keys and configure SSH for multiple GitHub accounts"""
    # Determine home directory based on platform
    home_dir = str(Path.home())
    ssh_dir = os.path.join(home_dir, ".ssh")
    config_path = os.path.join(ssh_dir, "config")
    accounts_config_path = os.path.join(ssh_dir, "accounts.json")
    config_entries = []
    accounts_data = []
    
    # Ensure .ssh directory exists
    print("🔧 Creating .ssh directory..." if not os.path.exists(ssh_dir) else "🔧 .ssh directory exists")
    os.makedirs(ssh_dir, exist_ok=True)
    
    # Check if ssh-keygen is available
    if shutil.which("ssh-keygen") is None:
        print("❌ 'ssh-keygen' not found. Please install OpenSSH Client.")
        return
    
    # Prompt for number of accounts (max 3)
    while True:
        try:
            count = int(safe_input("How many GitHub accounts do you want to set up? (Max: 3) "))
            if 1 <= count <= 3:
                break
            print("❌ Please enter only 1, 2, or 3 for the number of accounts.")
        except ValueError:
            print("❌ Please enter a valid number.")
    
    for i in range(1, count + 1):
        print(f"\n🧑‍💻 Account #{i} setup")
        account_type = safe_input("Enter account name/type (e.g., personal, work, freelance): ")
        email = safe_input(f"Enter email for '{account_type}' account: ")
        # This username must match your actual GitHub username where repositories exist
        username = safe_input(f"Enter your actual GitHub username for '{account_type}' account: ")
        # Prompt for local username for Git config
        local_username = safe_input(f"Enter your preferred local Git username for '{account_type}' (for commits, can be different from GitHub username): ")
        if not local_username.strip():
            local_username = username
        
        # Create alias and key names
        alias = "github-" + re.sub(r'[^a-z0-9]', '_', account_type.lower().strip())
        key_name = f"id_ed25519_{alias}"
        key_path = os.path.join(ssh_dir, key_name)
        pub_key_path = f"{key_path}.pub"
        
        # Generate SSH key
        if os.path.exists(key_path):
            print(f"⚠️ Key '{key_name}' already exists. Skipping generation.")
        else:
            print(f"🔐 Generating SSH key for '{account_type}'...")
            try:
                subprocess.run(
                    ["ssh-keygen", "-t", "ed25519", "-C", email, "-f", key_path],
                    check=True, input=b"\n\n", capture_output=True
                )
                if os.path.exists(key_path):
                    print(f"✅ Key generated: {key_path}")
                else:
                    print(f"❌ Key generation failed for '{account_type}'.")
                    continue
            except subprocess.CalledProcessError:
                print(f"❌ Key generation failed for '{account_type}'.")
                continue
        
        # Show public key
        if os.path.exists(pub_key_path):
            print(f"\n📋 Public key for '{account_type}' (copy to GitHub):")
            with open(pub_key_path, 'r') as f:
                pub_key = f.read().strip()
                print(pub_key)
            
            # Guidance: Add the key to GitHub
            print("\n🧭 Add this SSH key to your GitHub account:")
            print("   1) Open: https://github.com/settings/keys")
            print("   2) Click 'New SSH key'")
            print("   3) Paste the key above into the 'Key' field and save")
            
            # Try to copy to clipboard if on Windows or macOS
            try:
                if platform.system() == "Windows":
                    subprocess.run(["clip"], input=pub_key.encode(), check=True)
                    print("📌 Public key has been copied to your clipboard.")
                elif platform.system() == "Darwin":  # macOS
                    subprocess.run(["pbcopy"], input=pub_key.encode(), check=True)
                    print("📌 Public key has been copied to your clipboard.")
                else:  # Linux
                    if shutil.which("xclip"):
                        subprocess.run(["xclip", "-selection", "clipboard"], input=pub_key.encode(), check=True)
                        print("📌 Public key has been copied to your clipboard.")
                    else:
                        print("⚠️ Could not copy to clipboard automatically. Please copy it manually.")
            except Exception:
                print("⚠️ Could not copy to clipboard automatically. Please copy it manually.")
        
        # Add SSH config entry
        entry = f"""# {account_type} GitHub
Host {alias}
  HostName github.com
  User git
  IdentityFile ~/.ssh/{key_name}
  IdentitiesOnly yes
"""
        config_entries.append(entry)
        
        # Store account information for later use
        accounts_data.append({
            "id": alias,
            "name": account_type,
            "sshAlias": alias,
            "githubUser": username,
            "email": email,
            "localGitUser": local_username,
            "tokenEnvVar": f"GITHUB_{alias.upper().replace('-', '_')}_TOKEN"
        })
    
    # Write SSH config file
    print("\n⚙️ Writing SSH config file...")
    with open(config_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(config_entries))
    print(f"✅ SSH config saved to: {config_path}")
    
    # Test SSH connections for each account
    print("\n🔍 Testing SSH connections for each account...")
    for account in accounts_data:
        print(f"\n🧪 Testing connection to {account['name']} account...")
        try:
            # Use -o StrictHostKeyChecking=no to avoid host key verification prompts
            result = subprocess.run(
                ["ssh", "-o", "StrictHostKeyChecking=no", "-T", f"git@{account['sshAlias']}"],
                capture_output=True, text=True, timeout=10
            )
            output = result.stdout + result.stderr
            if "successfully authenticated" in output.lower():
                print(f"✅ SSH connection successful for {account['name']} account!")
            else:
                print(f"⚠️ SSH connection established but authentication message unclear for {account['name']}")
                print("   → This usually means the key is working but you may need to add it to GitHub")
        except Exception as e:
            print(f"❌ SSH connection failed for {account['name']} account")
            print("   → Please ensure the SSH key is added to your GitHub account")
    
    # Save account information to JSON file
    print("\n💾 Saving account information...")
    with open(accounts_config_path, 'w', encoding='utf-8') as f:
        json.dump(accounts_data, f, indent=2)
    print(f"✅ Account information saved to: {accounts_config_path}")

class GitGo:
    def handle_changename(self, account, token, github_user):
        """Change the name of a GitHub repository for a chosen account"""
        headers = {
            'Authorization': f'Bearer {token}',
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'GitGo-Python-Script'
        }
        old_name = safe_input("Enter the current repository name: ").strip()
        new_name = safe_input("Enter the new repository name: ").strip()
        if not old_name or not new_name:
            print("❌ Both old and new names are required.")
            return
        url = f"https://api.github.com/repos/{github_user}/{old_name}"
        data = {"name": new_name}
        try:
            response = requests.patch(url, headers=headers, json=data, timeout=20)
            if response.status_code == 200:
                print(f"✅ Repository renamed to '{new_name}'.")
                print(f"   → New URL: {response.json().get('html_url')}")
            else:
                print(f"❌ Failed to rename repository: {response.status_code} {response.text}")
        except Exception as e:
            print(f"❌ Error: {e}")

    def handle_help(self):
        """Show the help menu and return to prompt"""
        self.show_help()
    def handle_branch(self):
        """Manage local git branches: list, create, switch, delete"""
        if not self.is_git_repo():
            print("\n❌ Not a Git repository. Initialize with 'git init' first.")
            return
        while True:
            print("\n🌿 Branch Management")
            print("──────────────────────────────────────────────")
            print("1. List branches")
            print("2. Create new branch")
            print("3. Switch branch")
            print("4. Delete branch")
            print("5. Exit branch menu")
            choice = safe_input("\nEnter your choice (1-5): ").strip()
            if choice == "1":
                # List branches
                out, _, _ = self.run_git_command(["branch"], check=False)
                print("\nAvailable branches:")
                print(out)
            elif choice == "2":
                # Create new branch
                new_branch = safe_input("Enter new branch name: ").strip()
                if new_branch:
                    out, err, code = self.run_git_command(["branch", new_branch], check=False)
                    if code == 0:
                        print(f"✅ Branch '{new_branch}' created.")
                    else:
                        print(f"❌ Failed to create branch: {err}")
            elif choice == "3":
                # Switch branch
                target_branch = safe_input("Enter branch name to switch to: ").strip()
                if target_branch:
                    out, err, code = self.run_git_command(["checkout", target_branch], check=False)
                    if code == 0:
                        print(f"✅ Switched to branch '{target_branch}'.")
                    else:
                        print(f"❌ Failed to switch branch: {err}")
            elif choice == "4":
                # Delete branch
                del_branch = safe_input("Enter branch name to delete: ").strip()
                if del_branch:
                    out, err, code = self.run_git_command(["branch", "-d", del_branch], check=False)
                    if code == 0:
                        print(f"✅ Branch '{del_branch}' deleted.")
                    else:
                        # Try force delete if normal delete fails
                        confirm = safe_input("Delete failed. Force delete? (y/n): ").strip().lower()
                        if confirm == "y":
                            out, err, code = self.run_git_command(["branch", "-D", del_branch], check=False)
                            if code == 0:
                                print(f"✅ Branch '{del_branch}' force deleted.")
                            else:
                                print(f"❌ Force delete failed: {err}")
                        else:
                            print("❌ Delete cancelled.")
            elif choice == "5":
                print("Exiting branch menu.")
                break
            else:
                print("❌ Invalid choice. Please enter 1, 2, 3, 4, or 5.")
    def __init__(self):
        self.valid_actions = [
            "clone", "push", "pull", "adduser", "showuser", "addremote", 
            "delremote", "remotelist", "status", "commit", "history", "tokeninfo", "setup",
            "branch", "remotem", "changename", "help"
        ]
        self.numbered_actions = {str(i+1): action for i, action in enumerate(self.valid_actions)}
        
        # Load GitHub accounts from config file
        self.accounts = self.load_github_accounts()
        
    def load_github_accounts(self):
        """Load GitHub accounts from the config file created during SSH setup"""
        home_dir = str(Path.home())
        accounts_config_path = os.path.join(home_dir, ".ssh", "accounts.json")
        
        if os.path.exists(accounts_config_path):
            try:
                with open(accounts_config_path, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"⚠️ Error loading accounts: {str(e)}")
                return []
        else:
            print("⚠️ No GitHub accounts found. Run 'python gitgo.py ssh-setup' to configure SSH keys.")
            return []
    
    def select_github_account(self):
        """Prompt user to select a GitHub account from the available accounts"""
        if not self.accounts:
            print("❌ No GitHub accounts found. Run 'python gitgo.py ssh-setup' to configure SSH keys.")
            return None
        
        print("\n👤 Available GitHub Accounts:")
        print("──────────────────────────────────────────────")
        
        for i, account in enumerate(self.accounts, 1):
            print(f"   {i}. {account['name']} ({account['sshAlias']})")
        
        print()
        while True:
            try:
                choice = int(safe_input(f"Enter your choice (1-{len(self.accounts)}): "))
                if 1 <= choice <= len(self.accounts):
                    return self.accounts[choice - 1]
                print(f"❌ Please enter a number between 1 and {len(self.accounts)}.")
            except ValueError:
                print("❌ Please enter a valid number.")
            except KeyboardInterrupt:
                print("\n❌ Operation cancelled.")
                return None

    def show_help(self):
        """Display help menu"""
        print("\n📘 GitGo Help Menu")
        print("──────────────────────────────────────────────")
        print("Available Actions:\n")

        help_items = [
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
            "13. setup      → Configure GitHub accounts and tokens securely",
            "14. branch     → Manage branches (list/create/switch/delete)",
            "15. remotem    → Manage remote for current repository",
            "16. changename → Change name of a GitHub repository",
            "17. help       → Show this help and return to prompt (or use: gitgo help)"
        ]

        for line in help_items:
            print(f"  {line}")

        print("\nUsage:")
        print("  python gitgo.py         → Launch interactive menu")
        print("  python gitgo.py --help  → Show this help menu")
        print("  python gitgo.py ssh-setup → Configure SSH keys for GitHub")
        print("\nFirst time setup:")
        print("  python gitgo.py setup   → Configure your GitHub tokens")
        print("  python gitgo.py ssh-setup → Configure SSH keys for multiple accounts")

        print("\nCreator:")
        print("  🧑‍💻 David Muigai — Nairobi, Kenya")
        print("  ✨ Workflow architect & terminal automation enthusiast")
        print()

    def get_github_token(self, account):
        """Securely retrieve GitHub tokens from environment variables"""
        env_var = account.get('tokenEnvVar')
        token = os.environ.get(env_var)
        
        if not token:
            print(f"\n❌ GitHub token not found for {account['name']} account.")
            print(f"   → Run 'python gitgo.py setup' to configure tokens.")
            print(f"   → Or manually set environment variable: {env_var}")
            raise ValueError(f"Missing GitHub token for {account['name']} account")
        
        return token
        
    def handle_showuser(self):
        """Display current Git identity configuration"""
        # Get current repository configuration
        try:
            current_name = subprocess.run(["git", "config", "user.name"], capture_output=True, text=True).stdout.strip()
        except:
            current_name = None
            
        try:
            current_email = subprocess.run(["git", "config", "user.email"], capture_output=True, text=True).stdout.strip()
        except:
            current_email = None
            
        # Get global configuration
        try:
            global_name = subprocess.run(["git", "config", "--global", "user.name"], capture_output=True, text=True).stdout.strip()
        except:
            global_name = None
            
        try:
            global_email = subprocess.run(["git", "config", "--global", "user.email"], capture_output=True, text=True).stdout.strip()
        except:
            global_email = None
        
        print("\n👤 Git Identity Configuration:")
        print("──────────────────────────────────────────────")
        
        # Check if current directory is a git repository
        is_git_repo = os.path.exists(".git")
        
        if is_git_repo:
            print("📁 Current Repository:")
            print(f"  → Name: {current_name if current_name else '(not set)'}")
            print(f"  → Email: {current_email if current_email else '(not set)'}")
        else:
            print("📁 Current Directory: (not a Git repository)")
        
        print("\n🌍 Global Configuration:")
        print(f"  → Name: {global_name if global_name else '(not set)'}")
        print(f"  → Email: {global_email if global_email else '(not set)'}")
        print()

    def set_github_tokens(self):
        """Setup GitHub tokens securely"""
        print("\n🔐 GitHub Token Setup")
        print("──────────────────────────────────────────────")
        print("This will configure your GitHub Personal Access Tokens.")
        print("Tokens will be stored as environment variables.\n")
        
        print("📋 To create tokens, visit: https://github.com/settings/tokens")
        print("   Required scopes: repo, delete_repo, user\n")
        
        try:
            print("🔑 Personal Account Token:")
            personal_token = getpass.getpass("Enter your PERSONAL GitHub token: ")
            
            print("\n🔑 Work Account Token:")
            work_token = getpass.getpass("Enter your WORK GitHub token: ")
            
            if not personal_token or not work_token:
                raise ValueError("Tokens cannot be empty")
            
            # Set environment variables for current session
            os.environ["GITHUB_PERSONAL_TOKEN"] = personal_token
            os.environ["GITHUB_WORK_TOKEN"] = work_token
            
            print("\n✅ Tokens configured successfully for current session!")
            print("🔄 Environment variables set:")
            print("   → GITHUB_PERSONAL_TOKEN")
            print("   → GITHUB_WORK_TOKEN")
            print("\n⚠️  To persist tokens, add them to your shell profile:")
            print(f"   export GITHUB_PERSONAL_TOKEN='{personal_token}'")
            print(f"   export GITHUB_WORK_TOKEN='{work_token}'")
            
        except Exception as e:
            print(f"\n❌ Token setup failed: {str(e)}")

    def test_github_token_scopes(self, token, account_name):
        """Test token validity and get scopes"""
        try:
            headers = {
                'Authorization': f'Bearer {token}',
                'Accept': 'application/vnd.github+json',
                'User-Agent': 'GitGo-Python-Script'
            }
            
            response = requests.get('https://api.github.com/user', headers=headers, timeout=10)
            response.raise_for_status()
            
            user_info = response.json()
            scopes = response.headers.get('X-OAuth-Scopes', '').split(', ') if response.headers.get('X-OAuth-Scopes') else []
            
            print(f"✅ {account_name} token is valid")
            print(f"   → User: {user_info.get('login', 'N/A')}")
            print(f"   → Name: {user_info.get('name', 'N/A')}")
            print(f"   → Email: {user_info.get('email', 'N/A')}")
            print(f"   → Account Type: {user_info.get('type', 'N/A')}")
            print(f"   → Rate Limit: {response.headers.get('X-RateLimit-Remaining', 'N/A')}/{response.headers.get('X-RateLimit-Limit', 'N/A')} remaining")
            
            if response.headers.get('X-RateLimit-Reset'):
                reset_time = datetime.fromtimestamp(int(response.headers['X-RateLimit-Reset']))
                print(f"   → Reset Time: {reset_time.strftime('%Y-%m-%d %H:%M:%S')}")
            
            print("🔐 Token Scopes:")
            if scopes and scopes[0]:  # Check if scopes exist and aren't empty
                scope_descriptions = {
                    "repo": "Full repository access (read/write)",
                    "public_repo": "Public repository access only",
                    "delete_repo": "Repository deletion permissions",
                    "user": "User profile information",
                    "user:email": "User email addresses",
                    "admin:org": "Organization administration",
                    "workflow": "GitHub Actions workflows",
                    "gist": "Gist access"
                }
                
                for scope in scopes:
                    scope = scope.strip()
                    if scope:
                        description = scope_descriptions.get(scope, "Unknown scope")
                        print(f"   → {scope}: {description}")
                
                # Check required scopes
                required_scopes = ["repo", "delete_repo", "user"]
                missing_scopes = [req for req in required_scopes 
                                if req not in scopes and (req != "repo" or "public_repo" not in scopes)]
                
                if missing_scopes:
                    print(f"⚠️ Missing required scopes: {', '.join(missing_scopes)}")
                    print("   → Some GitGo features may not work properly")
                else:
                    print("✅ All required scopes are present")
            else:
                print("   → No scopes found or token has full access")
            
            return True
        except requests.exceptions.RequestException as e:
            print(f"❌ {account_name} token is invalid or expired")
            print(f"   → Error: {str(e)}")
            return False

    def get_valid_yes_no(self, prompt, default_value=None):
        """Validate yes/no input"""
        while True:
            if default_value:
                user_input = safe_input(f"{prompt} (y/n, default: {default_value}): ").strip().lower()
                if not user_input:
                    user_input = default_value.lower()
            else:
                user_input = safe_input(f"{prompt} (y/n): ").strip().lower()
            
            if user_input in ['y', 'yes']:
                return True
            elif user_input in ['n', 'no']:
                return False
            else:
                print("\n❌ Invalid input. Please enter 'y' for yes or 'n' for no.")

    def get_current_git_branch(self):
        """Get current Git branch"""
        try:
            result = subprocess.run(['git', 'branch', '--show-current'], 
                                  capture_output=True, text=True, check=True)
            branch = result.stdout.strip()
            if not branch:
                # Fallback for older Git versions or detached HEAD
                result = subprocess.run(['git', 'rev-parse', '--abbrev-ref', 'HEAD'], 
                                      capture_output=True, text=True, check=True)
                branch = result.stdout.strip()
                if branch == "HEAD":
                    return None  # Detached HEAD
            return branch
        except subprocess.CalledProcessError:
            return None

    def get_default_branch(self):
        """Detect default branch"""
        try:
            # Try to get default branch from remote
            result = subprocess.run(['git', 'symbolic-ref', 'refs/remotes/origin/HEAD'], 
                                  capture_output=True, text=True)
            if result.returncode == 0:
                return result.stdout.strip().replace('refs/remotes/origin/', '')
            
            # Fallback: check if main or master exists
            result = subprocess.run(['git', 'branch', '-r'], capture_output=True, text=True)
            if result.returncode == 0:
                branches = result.stdout
                if 'origin/main' in branches:
                    return "main"
                elif 'origin/master' in branches:
                    return "master"
            
            # Last resort: assume main
            return "main"
        except:
            return "main"

    def run_git_command(self, cmd, check=True):
        """Run git command and return result"""
        try:
            result = subprocess.run(['git'] + cmd, capture_output=True, text=True, check=check)
            return result.stdout.strip(), result.stderr.strip(), result.returncode
        except subprocess.CalledProcessError as e:
            return e.stdout, e.stderr, e.returncode

    def is_git_repo(self):
        """Check if current directory is a Git repository"""
        return os.path.exists('.git')

    def get_valid_account(self):
        """Get valid account selection"""
        while True:
            account = safe_input("Which account are you using? (personal/work): ").strip().lower()
            if account in ['personal', 'work']:
                return account
            else:
                print("\n❌ Invalid account. Please enter 'personal' or 'work' only.")

    def get_valid_visibility(self):
        """Get valid repository visibility"""
        while True:
            visibility = safe_input("Should the repo be public or private? (public/private): ").strip().lower()
            if visibility in ['public', 'private']:
                return visibility
            else:
                print("\n❌ Invalid visibility. Please enter 'public' or 'private' only.")

    def invoke_git_commit(self):
        """Handle Git add and commit"""
        if not self.is_git_repo():
            print("\n❌ Not a Git repository. Initialize with 'git init' first.")
            return

        print("\n📝 Git Add & Commit")
        print("──────────────────────────────────────────────")

        # Show current status
        print("📊 Current repository status:")
        stdout, stderr, returncode = self.run_git_command(['status', '--porcelain'], check=False)
        
        if not stdout:
            print("   ✅ Working tree clean - nothing to commit")
            return
        else:
            print("   📋 Changes detected:")
            status_lines = [line for line in stdout.split('\n') if line.strip()]
            for line in status_lines:
                if len(line) >= 3:
                    status = line[:2]
                    file_name = line[3:]
                    
                    status_icons = {
                        'M': '📝',   # Modified
                        'A': '➕',   # Added
                        'D': '🗑️',   # Deleted
                        'R': '🔄',   # Renamed
                        'C': '📋',   # Copied
                        '??': '❓'   # Untracked
                    }
                    
                    icon = status_icons.get(status.strip(), '📄')
                    print(f"      {icon} {file_name}")

        # Ask what to add
        print("\n🎯 What would you like to add?")
        print("   1. All changes (git add .)")
        print("   2. All tracked files (git add -u)")
        print("   3. Specific files (manual selection)")
        print("   4. Interactive staging (git add -p)")

        valid_choice = False
        while not valid_choice:
            add_choice = safe_input("\nEnter your choice (1-4): ").strip()
            
            if add_choice == "1":
                print("\n➕ Adding all changes...")
                self.run_git_command(['add', '.'])
                add_action = "all changes"
                valid_choice = True
            elif add_choice == "2":
                print("\n➕ Adding all tracked files...")
                self.run_git_command(['add', '-u'])
                add_action = "all tracked files"
                valid_choice = True
            elif add_choice == "3":
                files = safe_input("\n📝 Enter file paths separated by spaces: ").strip()
                if files:
                    print("\n➕ Adding specified files...")
                    file_list = files.split()
                    for file_name in file_list:
                        self.run_git_command(['add', file_name])
                    add_action = "specified files"
                    valid_choice = True
                else:
                    print("❌ No files specified.")
            elif add_choice == "4":
                print("\n🎯 Starting interactive staging...")
                subprocess.run(['git', 'add', '-p'])
                add_action = "interactive selection"
                valid_choice = True
            else:
                print("❌ Invalid choice. Please enter 1, 2, 3, or 4.")

        # Check if anything was actually staged
        stdout, stderr, returncode = self.run_git_command(['diff', '--cached', '--name-only'], check=False)
        if not stdout:
            print("\n⚠️ No changes staged for commit.")
            return

        print("\n✅ Files staged for commit:")
        for file_name in stdout.split('\n'):
            if file_name.strip():
                print(f"   → {file_name}")

        # Get commit message
        print("\n💬 Commit message options:")
        print("   1. Enter custom message")
        print("   2. Use template message")
        print("   3. Amend previous commit")

        valid_msg = False
        while not valid_msg:
            msg_choice = safe_input("\nEnter your choice (1-3): ").strip()
            
            if msg_choice == "1":
                commit_msg = safe_input("\n📝 Enter your commit message: ").strip()
                if commit_msg:
                    valid_msg = True
                else:
                    print("❌ Commit message cannot be empty.")
            elif msg_choice == "2":
                print("\n📋 Available templates:")
                templates = {
                    "1": "feat: ",
                    "2": "fix: ",
                    "3": "docs: ",
                    "4": "style: ",
                    "5": "refactor: ",
                    "6": "test: ",
                    "7": "chore: "
                }
                
                for key, value in templates.items():
                    template_names = {
                        "feat: ": "add new feature",
                        "fix: ": "bug fix",
                        "docs: ": "update documentation",
                        "style: ": "formatting changes",
                        "refactor: ": "code refactoring",
                        "test: ": "add or update tests",
                        "chore: ": "maintenance tasks"
                    }
                    print(f"   {key}. {value}{template_names[value]}")
                
                template_choice = safe_input("Select template (1-7): ").strip()
                if template_choice in templates:
                    template_prefix = templates[template_choice]
                    custom_part = safe_input(f"Complete the message: '{template_prefix}'").strip()
                    commit_msg = template_prefix + custom_part
                    valid_msg = True
                else:
                    print("❌ Invalid template choice.")
            elif msg_choice == "3":
                print("\n🔄 Amending previous commit...")
                subprocess.run(['git', 'commit', '--amend'])
                print("✅ Commit amended successfully!")
                
                # Ask about pushing
                current_branch = self.get_current_git_branch()
                if current_branch and self.get_valid_yes_no(f"🚀 Push amended commit to origin/{current_branch}? (Note: This will force push)"):
                    subprocess.run(['git', 'push', 'origin', current_branch, '--force-with-lease'])
                    print("✅ Amended commit pushed successfully!")
                return
            else:
                print("❌ Invalid choice. Please enter 1, 2, or 3.")

        # Perform the commit
        print("\n💾 Committing changes...")
        try:
            self.run_git_command(['commit', '-m', commit_msg])
            print("✅ Commit successful!")
            print(f"   → Message: {commit_msg}")
            print(f"   → Added: {add_action}")
            
            # Show commit hash
            commit_hash, _, _ = self.run_git_command(['rev-parse', '--short', 'HEAD'])
            print(f"   → Commit hash: {commit_hash}")

            # Ask about pushing
            current_branch = self.get_current_git_branch()
            if current_branch:
                should_push = self.get_valid_yes_no(f"🚀 Push commit to origin/{current_branch}?")
                if should_push:
                    # Check if upstream is set
                    _, _, returncode = self.run_git_command(['rev-parse', '--abbrev-ref', f'{current_branch}@{{upstream}}'], check=False)
                    if returncode != 0:
                        print("🔗 Setting upstream and pushing...")
                        self.run_git_command(['push', '-u', 'origin', current_branch])
                    else:
                        self.run_git_command(['push', 'origin', current_branch])
                    print("✅ Changes pushed successfully!")
                    
        except subprocess.CalledProcessError as e:
            print(f"❌ Commit failed: {str(e)}")

    def show_git_history(self):
        """Show commit history"""
        if not self.is_git_repo():
            print("\n❌ Not a Git repository.")
            return

        print("\n📚 Git Commit History")
        print("──────────────────────────────────────────────")

        current_branch = self.get_current_git_branch()
        if current_branch:
            print(f"🌿 Current Branch: {current_branch}")

        # Ask for number of commits to show
        while True:
            num_commits = safe_input("\n📊 How many commits to show? (default: 10, max: 50): ").strip()
            if not num_commits:
                num_commits = 10
                break
            try:
                num_commits = int(num_commits)
                if 1 <= num_commits <= 50:
                    break
                else:
                    print("❌ Please enter a number between 1 and 50.")
            except ValueError:
                print("❌ Please enter a valid number.")

        print(f"\n📋 Last {num_commits} commits:\n")

        try:
            stdout, stderr, returncode = self.run_git_command(['log', '--oneline', '--graph', '--decorate', f'-n{num_commits}'], check=False)
            if returncode == 0 and stdout:
                for line in stdout.split('\n'):
                    if line.strip():
                        print(f"   {line}")
                
                print("\n🔍 View options:")
                print("   1. Show detailed commit info")
                print("   2. Show file changes for a specific commit")
                print("   3. Show commit statistics")
                print("   4. Exit history view")
                
                view_choice = safe_input("\nEnter your choice (1-4, default: 4): ").strip()
                
                if view_choice == "1":
                    print("\n📋 Detailed commit information:\n")
                    stdout, _, _ = self.run_git_command(['log', '--stat', f'-n{num_commits}', '--pretty=format:%h - %an, %ar : %s'])
                    print(stdout)
                elif view_choice == "2":
                    commit_hash = safe_input("\n🔍 Enter commit hash (short or full): ").strip()
                    if commit_hash:
                        print(f"\n📝 Changes in commit {commit_hash}:\n")
                        stdout, _, _ = self.run_git_command(['show', '--stat', commit_hash], check=False)
                        print(stdout)
                elif view_choice == "3":
                    print("\n📊 Repository statistics:\n")
                    print(f"📈 Contribution stats (last {num_commits} commits):")
                    stdout, _, _ = self.run_git_command(['shortlog', '-sn', f'-{num_commits}'])
                    print(stdout)
            else:
                print("   (no commits found)")
        except subprocess.CalledProcessError as e:
            print(f"❌ Error retrieving commit history: {str(e)}")

    def get_git_repository_info(self):
        """Get Git repository status and info"""
        if not self.is_git_repo():
            print("\n❌ Not a Git repository. Run this command from within a Git repository.")
            return

        print("\n📊 Git Repository Status & Info")
        print("──────────────────────────────────────────────")

        # Repository name (current directory)
        repo_name = os.path.basename(os.getcwd())
        print(f"📁 Repository: {repo_name}")

        try:
            # Current branch
            current_branch = self.get_current_git_branch()
            if current_branch:
                print(f"🌿 Current Branch: {current_branch}")
            else:
                print("🌿 Current Branch: (detached HEAD or no commits)")

            # Git identity
            git_name, _, _ = self.run_git_command(['config', 'user.name'], check=False)
            git_email, _, _ = self.run_git_command(['config', 'user.email'], check=False)
            print("👤 Git Identity:")
            print(f"   → Name: {git_name if git_name else '(not configured)'}")
            print(f"   → Email: {git_email if git_email else '(not configured)'}")

            # Remote URLs
            remotes, _, returncode = self.run_git_command(['remote', '-v'], check=False)
            if returncode == 0 and remotes:
                print("🔗 Remote URLs:")
                for line in remotes.split('\n'):
                    if line.strip():
                        print(f"   → {line}")
            else:
                print("🔗 Remote URLs: (no remotes configured)")

            # Working tree status
            print("📈 Repository Status:")
            status_output, _, _ = self.run_git_command(['status', '--porcelain'], check=False)
            if not status_output:
                print("   ✅ Working tree clean")
            else:
                print("   ⚠️ Working tree has changes:")
                status_lines = [line for line in status_output.split('\n') if line.strip()]
                for line in status_lines:
                    if len(line) >= 3:
                        status = line[:2]
                        file_name = line[3:]
                        
                        status_icons = {
                            'M': '📝',   # Modified
                            'A': '➕',   # Added
                            'D': '🗑️',   # Deleted
                            'R': '🔄',   # Renamed
                            'C': '📋',   # Copied
                            '??': '❓'   # Untracked
                        }
                        
                        icon = status_icons.get(status.strip(), '📄')
                        print(f"      {icon} {file_name}")

            # Recent commits (last 3)
            print("📚 Recent Commits (last 3):")
            commit_output, _, returncode = self.run_git_command(['log', '--oneline', '-3'], check=False)
            if returncode == 0 and commit_output:
                commits = [line for line in commit_output.split('\n') if line.strip()]
                for commit in commits:
                    if commit.strip():
                        print(f"   → {commit}")
            else:
                print("   (no commits found)")

        except Exception as e:
            print(f"\n❌ Error retrieving Git information:")
            print(f"   {str(e)}")

    def display_actions_menu(self):
        """Display the main actions menu"""
        print("\n🛠️ Available Actions:\n")
        
        # Display actions in 3 columns
        column_width = 22
        columns = 3
        action_list = [f"{i+1}. {action}" for i, action in enumerate(self.valid_actions)]
        
        for i in range(0, len(action_list), columns):
            row = action_list[i:i+columns]
            formatted_row = [item.ljust(column_width) for item in row]
            print("   " + "".join(formatted_row))

    print("\nType the action name or number. Type 'q' to quit.")
    print("\nFirst time? Run 'setup' (13) to configure GitHub accounts and tokens securely.")

    def get_action_input(self):
        """Get and validate action input"""
        try:
            while True:
                user_input = input("\nEnter your action: ").strip().lower()
                if user_input == "q":
                    print("\n👋 Exiting GitGo.")
                    sys.exit(0)
                elif user_input in self.valid_actions:
                    return user_input
                elif user_input in self.numbered_actions:
                    return self.numbered_actions[user_input]
                else:
                    print("\n❌ Invalid input. Please enter a valid action name, number, or 'q' to quit.")
        except KeyboardInterrupt:
            print("\n👋 Exiting GitGo. Goodbye!")
            sys.exit(0)

    def handle_clone(self, github_user, ssh_alias, git_email):
        """Handle repository cloning"""
        repo_name = safe_input("Enter the repository name to clone: ").strip()
        remote_url = f"git@{ssh_alias}:{github_user}/{repo_name}.git"

        print(f"\n🔍 Cloning from: {remote_url}")
        try:
            result = subprocess.run(['git', 'clone', remote_url], capture_output=True, text=True, check=True)
            print(result.stdout)
            if result.stderr:
                print(result.stderr)

            if os.path.exists(repo_name):
                os.chdir(repo_name)
                # Check if Git username is already configured locally
                existing_name, _, name_returncode = self.run_git_command(['config', 'user.name'], check=False)
                existing_email, _, email_returncode = self.run_git_command(['config', 'user.email'], check=False)

                # Get localGitUser from account config if available
                local_git_user = None
                for acc in self.accounts:
                    if acc.get('sshAlias') == ssh_alias:
                        local_git_user = acc.get('localGitUser', github_user)
                        break
                if not local_git_user:
                    local_git_user = github_user

                # Set user.email if not set
                if email_returncode != 0 or not existing_email.strip():
                    self.run_git_command(['config', 'user.email', git_email])
                    configured_email = git_email
                else:
                    configured_email = existing_email.strip()

                # Set user.name if not set: auto-configure from config file (no prompt)
                if name_returncode != 0 or not existing_name.strip():
                    self.run_git_command(['config', 'user.name', local_git_user])
                    configured_name = local_git_user
                else:
                    configured_name = existing_name.strip()

                print("\n✅ Repo cloned and configured:")
                print(f"  → Remote: {remote_url}")
                print(f"  → Git user.name: {configured_name}")
                print(f"  → Git user.email: {configured_email}")
            else:
                print(f"\n⚠️ Clone succeeded but folder '{repo_name}' not found.")
        except subprocess.CalledProcessError as e:
            print("\n❌ Error during clone:")
            print(e.stderr if e.stderr else str(e))

    def handle_push(self, account, github_user, ssh_alias, git_email):
        """Handle repository pushing"""
        if not self.is_git_repo():
            print("\n❌ Not a Git repository. Initialize with 'git init' first.")
            return

        current_branch = self.get_current_git_branch()
        if not current_branch:
            print("\n❌ Unable to determine current branch. You may be in a detached HEAD state.")
            return

        print(f"\n🚀 Preparing to push from branch: {current_branch}")

        # Check for uncommitted changes
        status_output, _, _ = self.run_git_command(['status', '--porcelain'], check=False)
        if status_output:
            print("⚠️ You have uncommitted changes:")
            status_lines = [line for line in status_output.split('\n') if line.strip()][:5]
            for line in status_lines:
                if len(line) >= 3:
                    print(f"   → {line[3:]}")
            
            should_continue = self.get_valid_yes_no("Continue pushing without committing these changes?")
            if not should_continue:
                print("🚫 Push cancelled. Commit your changes first or use the 'commit' action.")
                return

        # Ask for repository name (with auto-detection option)
        detected_repo = None
        try:
            remote_url, _, returncode = self.run_git_command(['config', '--get', 'remote.origin.url'], check=False)
            if returncode == 0 and remote_url:
                match = re.search(r'/([^/]+?)(?:\.git)?$', remote_url)
                if match:
                    detected_repo = match.group(1)
        except:
            pass

        if detected_repo:
            use_detected = self.get_valid_yes_no(f"Use detected repository name '{detected_repo}'?", "y")
            if use_detected:
                repo_name = detected_repo
            else:
                repo_name = safe_input("Enter the repository name to push to: ").strip()
        else:
            repo_name = safe_input("Enter the repository name to push to: ").strip()

        remote_url = f"git@{ssh_alias}:{github_user}/{repo_name}.git"

        # Check if Git username is already configured locally
        existing_name, _, name_returncode = self.run_git_command(['config', 'user.name'], check=False)
        if name_returncode != 0 or not existing_name.strip():
            self.run_git_command(['config', 'user.name', github_user])
            configured_name = github_user
        else:
            configured_name = existing_name.strip()
        
        # Check if Git email is already configured locally
        existing_email, _, email_returncode = self.run_git_command(['config', 'user.email'], check=False)
        if email_returncode != 0 or not existing_email.strip():
            self.run_git_command(['config', 'user.email', git_email])
            configured_email = git_email
        else:
            configured_email = existing_email.strip()

        # Handle remote setup
        remotes, _, _ = self.run_git_command(['remote'], check=False)
        if 'origin' not in remotes:
            self.run_git_command(['remote', 'add', 'origin', remote_url])
            print(f"\n🔗 Remote 'origin' added: {remote_url}")
        else:
            # Check if remote URL matches
            existing_url, _, _ = self.run_git_command(['config', '--get', 'remote.origin.url'], check=False)
            if existing_url != remote_url:
                self.run_git_command(['remote', 'set-url', 'origin', remote_url])
                print(f"\n🔄 Remote 'origin' updated: {remote_url}")

        # Check if upstream is set for current branch
        _, _, returncode = self.run_git_command(['rev-parse', '--abbrev-ref', f'{current_branch}@{{upstream}}'], check=False)
        upstream_exists = returncode == 0
        
        print(f"\n🚀 Pushing branch '{current_branch}'...")
        try:
            if not upstream_exists:
                print("🔗 Setting upstream and pushing...")
                result = subprocess.run(['git', 'push', '-u', 'origin', current_branch], 
                                      capture_output=True, text=True, check=True)
            else:
                result = subprocess.run(['git', 'push', 'origin', current_branch], 
                                      capture_output=True, text=True, check=True)
            
            print(result.stdout)
            if result.stderr:
                print(result.stderr)

            print(f"\n✅ Push complete using '{account}' identity:")
            print(f"  → Repo: {repo_name}")
            print(f"  → Branch: {current_branch}")
            print(f"  → Remote: origin ({ssh_alias})")
            print(f"  → Git user.name: {configured_name}")
            print(f"  → Git user.email: {configured_email}")
        except subprocess.CalledProcessError as e:
            print("\n❌ Error during push:")
            print(e.stderr if e.stderr else str(e))

    def handle_pull(self):
        """Handle repository pulling"""
        print("\n📥 Checking for Git repository...")
        if not self.is_git_repo():
            print("\n❌ No Git repository found in the current directory.")
            print("   → Make sure you're inside a valid Git repo before pulling.")
            return

        current_branch = self.get_current_git_branch()
        if not current_branch:
            print("\n❌ Unable to determine current branch. You may be in a detached HEAD state.")
            return

        # Check for uncommitted changes
        status_output, _, _ = self.run_git_command(['status', '--porcelain'], check=False)
        should_pop_stash = False
        
        if status_output:
            print("⚠️ You have uncommitted changes:")
            status_lines = [line for line in status_output.split('\n') if line.strip()][:5]
            for line in status_lines:
                if len(line) >= 3:
                    print(f"   → {line[3:]}")
            
            print("\n🎯 Options:")
            print("   1. Stash changes and pull")
            print("   2. Continue pulling (may cause conflicts)")
            print("   3. Cancel pull")
            
            valid_choice = False
            while not valid_choice:
                pull_choice = input("Enter your choice (1-3): ").strip()
                if pull_choice == "1":
                    print("\n📦 Stashing changes...")
                    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M')
                    self.run_git_command(['stash', 'push', '-m', f'Auto-stash before pull {timestamp}'])
                    should_pop_stash = True
                    valid_choice = True
                elif pull_choice == "2":
                    print("\n⚠️ Continuing with uncommitted changes...")
                    should_pop_stash = False
                    valid_choice = True
                elif pull_choice == "3":
                    print("\n🚫 Pull cancelled.")
                    return
                else:
                    print("❌ Invalid choice. Please enter 1, 2, or 3.")

        print(f"\n📥 Pulling latest changes from origin/{current_branch}...")
        try:
            # Check if upstream is set
            _, _, returncode = self.run_git_command(['rev-parse', '--abbrev-ref', f'{current_branch}@{{upstream}}'], check=False)
            upstream_exists = returncode == 0
            
            if not upstream_exists:
                print(f"🔗 No upstream set. Trying to pull from origin/{current_branch}...")
                result = subprocess.run(['git', 'pull', 'origin', current_branch], 
                                      capture_output=True, text=True, check=True)
            else:
                result = subprocess.run(['git', 'pull'], capture_output=True, text=True, check=True)
            
            print(result.stdout)
            if result.stderr:
                print(result.stderr)

            print("\n✅ Pull complete. Local repo updated with remote changes.")
            
            # Pop stash if we stashed changes
            if should_pop_stash:
                print("\n📦 Restoring stashed changes...")
                result = subprocess.run(['git', 'stash', 'pop'], capture_output=True, text=True)
                if result.returncode == 0:
                    print("✅ Stashed changes restored successfully.")
                else:
                    print("⚠️ Conflict while restoring stash:")
                    print(result.stderr)
                    print("   → Resolve conflicts manually and run 'git stash drop' when done")
                    
        except subprocess.CalledProcessError as e:
            print("\n❌ Pull encountered issues. Check the output above.")
            if should_pop_stash:
                print("   → Your changes are safely stashed. Use 'git stash pop' to restore them.")

    def handle_remotelist(self, token, github_user):
        """List repositories under GitHub account"""
        headers = {
            'Authorization': f'Bearer {token}',
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'GitGo-Python-Script'
        }

        api_url = 'https://api.github.com/user/repos?per_page=100&sort=updated'

        print(f"\n📦 Fetching repositories for '{github_user}'...")
        try:
            response = requests.get(api_url, headers=headers, timeout=30)
            response.raise_for_status()
            repos = response.json()
            
            if len(repos) == 0:
                print(f"\n📭 No repositories found under '{github_user}'.")
            else:
                print(f"\n📚 Repositories under '{github_user}' (sorted by last updated):\n")
                for index, repo in enumerate(repos, 1):
                    visibility = "🔒 private" if repo['private'] else "🌐 public"
                    last_updated = datetime.fromisoformat(repo['updated_at'].replace('Z', '+00:00')).strftime('%Y-%m-%d')
                    print(f"  {index}. {repo['name']}  [{visibility}] (updated: {last_updated})")
                
                print(f"\n📊 Total repositories: {len(repos)}")
                
        except requests.exceptions.RequestException as e:
            print("\n❌ Failed to fetch repositories:")
            print("   → Check your token validity with 'python gitgo.py setup'")
            print("   → Verify network connectivity")
            print(f"   → Error: {str(e)}")

    def handle_addremote(self, account, token, github_user, ssh_alias, git_email):
        """Create a new GitHub repository"""
        headers = {
            'Authorization': f'Bearer {token}',
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'GitGo-Python-Script'
        }

        name_taken = True
        while name_taken:
            repo_name = safe_input("Enter the repository name (e.g., habit_flow_app): ").strip()
            # Validate repository name format
            if re.match(r'^[a-zA-Z0-9._-]+$', repo_name) and len(repo_name) <= 100:
                check_url = f'https://api.github.com/repos/{github_user}/{repo_name}'
                try:
                    response = requests.get(check_url, headers=headers, timeout=10)
                    if response.status_code == 200:
                        print(f"\n🚫 A repository named '{repo_name}' already exists under '{github_user}'. Please choose a different name.")
                        name_taken = True
                    elif response.status_code == 404:
                        print(f"\n✅ Repo name '{repo_name}' is available.")
                        name_taken = False
                    else:
                        print(f"\n❌ Error checking repository availability: {response.status_code}")
                        name_taken = True
                except requests.exceptions.RequestException as e:
                    print(f"\n❌ Error checking repository availability: {str(e)}")
                    name_taken = True
            else:
                print("\n❌ Invalid repository name. Use only letters, numbers, dots, hyphens, and underscores (max 100 chars).")

        description = safe_input("Enter a short description (optional): ").strip()
        visibility = self.get_valid_visibility()

        body = {
            'name': repo_name,
            'description': description if description else "",
            'private': visibility == 'private',
            'auto_init': True
        }

        print("\n🌐 Creating remote repository on GitHub with README...")
        print(f"🔑 Using {account} account token")
        try:
            response = requests.post('https://api.github.com/user/repos', 
                                   headers=headers, json=body, timeout=30)
            response.raise_for_status()
            repo_data = response.json()
            print("\n✅ Remote repository created:")
            print(f"  → Name: {repo_data['name']}")
            print(f"  → URL: {repo_data['html_url']}")
            print("  → README.md initialized")
            print(f"  → Visibility: {visibility}")

            should_clone = self.get_valid_yes_no("🧲 Clone repo to current directory?")
            if should_clone:
                alias_url = f"git@{ssh_alias}:{github_user}/{repo_name}.git"
                print(f"\n🔍 Cloning from: {alias_url}")
                try:
                    result = subprocess.run(['git', 'clone', alias_url], 
                                          capture_output=True, text=True, check=True)
                    print("\n📦 Cloning...")
                    print(result.stdout)
                    if result.stderr:
                        print(result.stderr)
                    
                    if os.path.exists(repo_name):
                        os.chdir(repo_name)
                        # Check if Git username is already configured locally
                        existing_name, _, name_returncode = self.run_git_command(['config', 'user.name'], check=False)
                        if name_returncode != 0 or not existing_name.strip():
                            self.run_git_command(['config', 'user.name', github_user])
                            configured_name = github_user
                        else:
                            configured_name = existing_name.strip()
                        
                        # Check if Git email is already configured locally
                        existing_email, _, email_returncode = self.run_git_command(['config', 'user.email'], check=False)
                        if email_returncode != 0 or not existing_email.strip():
                            self.run_git_command(['config', 'user.email', git_email])
                            configured_email = git_email
                        else:
                            configured_email = existing_email.strip()
                        
                        print("\n✅ Repo cloned and configured:")
                        print(f"  → Remote: {alias_url}")
                        print(f"  → Git user.name: {configured_name}")
                        print(f"  → Git user.email: {configured_email}")
                        print(f"  → Current directory: ./{repo_name}")
                    else:
                        print(f"\n⚠️ Clone succeeded but folder '{repo_name}' not found.")
                except subprocess.CalledProcessError as e:
                    print("\n❌ Error during clone:")
                    print(e.stderr if e.stderr else str(e))
            else:
                print(f"\n🚫 Skipped cloning. Repo is live at: {repo_data['html_url']}")
                
        except requests.exceptions.RequestException as e:
            print("\n❌ Error creating remote repo:")
            print("   → Verify token has 'repo' scope")
            print("   → Check rate limits (5000 requests/hour)")
            print(f"   → Error: {str(e)}")

    def handle_delremote(self, account, token, github_user):
        """Delete a GitHub repository"""
        headers = {
            'Authorization': f'Bearer {token}',
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'GitGo-Python-Script'
        }

        name_valid = False
        while not name_valid:
            repo_name = safe_input("Enter the name of the repository to delete: ").strip()
            check_url = f'https://api.github.com/repos/{github_user}/{repo_name}'

            try:
                response = requests.get(check_url, headers=headers, timeout=10)
                if response.status_code == 200:
                    repo_data = response.json()
                    print(f"\n⚠️ Repo '{repo_name}' found under '{github_user}'.")
                    print("   Repository details:")
                    print(f"   → Full name: {repo_data['full_name']}")
                    print(f"   → Visibility: {'Private' if repo_data['private'] else 'Public'}")
                    updated_at = datetime.fromisoformat(repo_data['updated_at'].replace('Z', '+00:00'))
                    print(f"   → Last updated: {updated_at.strftime('%Y-%m-%d %H:%M:%S')}")
                    name_valid = True
                elif response.status_code == 404:
                    print(f"\n🚫 Repo '{repo_name}' not found under '{github_user}'. Please enter a valid name.")
                else:
                    print(f"\n❌ Error accessing repository: {response.status_code}")
            except requests.exceptions.RequestException as e:
                print(f"\n❌ Error accessing repository: {str(e)}")

        print("\n⚠️ WARNING: This action cannot be undone!")
        print(f"🔑 Using {account} account token")
        print("   → All code, issues, and wiki content will be permanently deleted")
        print("   → Repository name will be immediately available for reuse")
        
        should_delete = self.get_valid_yes_no(f"Are you absolutely sure you want to delete '{repo_name}'?")
        if should_delete:
            try:
                response = requests.delete(check_url, headers=headers, timeout=30)
                response.raise_for_status()
                print(f"\n🗑️ Repository '{repo_name}' has been permanently deleted.")
                print(f"   → The repository name '{repo_name}' is now available for reuse")
            except requests.exceptions.RequestException as e:
                print(f"\n❌ Failed to delete repository '{repo_name}':")
                print("   → Verify token has 'delete_repo' scope")
                print("   → Check if you have admin access to this repository")
                print(f"   → Error: {str(e)}")
        else:
            print(f"\n🚫 Repository deletion cancelled. '{repo_name}' remains intact.")

    def handle_adduser(self):
        """Set Git username and email for current repo"""
        is_git_repo = self.is_git_repo()
        if not is_git_repo:
            print("\n🧱 No Git repo detected. Initializing...")
            self.run_git_command(['init'])
            print("✅ Git repository initialized.")

        custom_name = safe_input("Enter the Git username to set: ").strip()
        custom_email = safe_input("Enter the Git email to set: ").strip()
        # Validate email format
        email_pattern = r'^[^\s@]+@[^\s@]+\.[^\s@]+$'
        if re.match(email_pattern, custom_email):
            self.run_git_command(['config', 'user.name', custom_name])
            self.run_git_command(['config', 'user.email', custom_email])
            print("\n✅ Git identity configured for this repository:")
            print(f"  → Git user.name: {custom_name}")
            print(f"  → Git user.email: {custom_email}")
        else:
            print("\n❌ Invalid email format. Please enter a valid email address.")

    def handle_showuser(self):
        """Display current Git identity"""
        current_name, _, _ = self.run_git_command(['config', 'user.name'], check=False)
        current_email, _, _ = self.run_git_command(['config', 'user.email'], check=False)
        global_name, _, _ = self.run_git_command(['config', '--global', 'user.name'], check=False)
        global_email, _, _ = self.run_git_command(['config', '--global', 'user.email'], check=False)

        print("\n👤 Git Identity Configuration:")
        print("──────────────────────────────────────────────")
        
        if self.is_git_repo():
            print("📁 Current Repository:")
            print(f"  → Name: {current_name if current_name else '(not set)'}")
            print(f"  → Email: {current_email if current_email else '(not set)'}")
        else:
            print("📁 Current Directory: (not a Git repository)")
        
        print("\n🌍 Global Configuration:")
        print(f"  → Name: {global_name if global_name else '(not set)'}")
        print(f"  → Email: {global_email if global_email else '(not set)'}")

    def add_gitgo_to_env(self):
        """Add the current script directory to the Windows PATH environment variable (user scope)"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Environment', 0, winreg.KEY_ALL_ACCESS) as key:
                try:
                    current_path, _ = winreg.QueryValueEx(key, 'Path')
                except FileNotFoundError:
                    current_path = ''
                if script_dir not in current_path.split(';'):
                    new_path = current_path + (';' if current_path and not current_path.endswith(';') else '') + script_dir
                    winreg.SetValueEx(key, 'Path', 0, winreg.REG_EXPAND_SZ, new_path)
                    print(f"✅ Added '{script_dir}' to user PATH. Restart your terminal to use 'gitgo' anywhere.")
                else:
                    print(f"ℹ️ '{script_dir}' is already in your user PATH.")
        except Exception as e:
            print(f"❌ Failed to add to PATH: {e}")

    def remove_gitgo_from_env(self):
        """Remove the script directory from the Windows PATH environment variable (user scope)"""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Environment', 0, winreg.KEY_ALL_ACCESS) as key:
                try:
                    current_path, _ = winreg.QueryValueEx(key, 'Path')
                except FileNotFoundError:
                    current_path = ''
                paths = [p for p in current_path.split(';') if p and os.path.normcase(p) != os.path.normcase(script_dir)]
                new_path = ';'.join(paths)
                winreg.SetValueEx(key, 'Path', 0, winreg.REG_EXPAND_SZ, new_path)
                print(f"✅ Removed '{script_dir}' from user PATH. Restart your terminal for changes to take effect.")
        except Exception as e:
            print(f"❌ Failed to remove from PATH: {e}")

    def setup_menu(self):
        """Show setup menu for SSH, token, and environment variable actions"""
        try:
            while True:
                print("\n🛠️ GitGo Setup Menu")
                print("──────────────────────────────────────────────")
                print("1. Setup SSH key for accounts")
                print("2. Configure your token for accounts")
                print("3. Add GitGo to Windows environment variable (PATH)")
                print("4. Remove GitGo from Windows environment variable (PATH)")
                print("5. Exit setup menu")
                choice = input("\nEnter your choice (1-5): ").strip()
                if choice == "1":
                    generate_github_ssh_keys_and_config()
                elif choice == "2":
                    self.set_github_tokens()
                elif choice == "3":
                    self.add_gitgo_to_env()
                elif choice == "4":
                    self.remove_gitgo_from_env()
                elif choice == "5":
                    print("Exiting setup menu.")
                    break
                else:
                    print("❌ Invalid choice. Please enter 1, 2, 3, 4, or 5.")
        except KeyboardInterrupt:
            print("\n👋 Exiting setup menu. Goodbye!")

    def run(self):
        """Main application runner"""
        if len(sys.argv) > 1:
            if sys.argv[1] == "--help":
                self.show_help()
                return
            elif sys.argv[1] == "setup":
                self.setup_menu()
                return
            elif sys.argv[1] == "ssh-setup":
                generate_github_ssh_keys_and_config()
                return

        # Display main menu
        self.display_actions_menu()

        # Get action from user
        action = self.get_action_input()

        # Handle account setup for relevant actions
        if action in ["clone", "push", "addremote", "delremote", "remotelist", "tokeninfo"]:
            selected_account = self.select_github_account()
            if not selected_account:
                return
            account = selected_account['name']
            github_user = selected_account.get('githubUser', selected_account.get('username', ''))
            ssh_alias = selected_account['sshAlias']
            git_email = selected_account['email']
            try:
                token = self.get_github_token(selected_account)
            except ValueError as e:
                print(str(e))
                return
        else:
            account = None
            github_user = None
            ssh_alias = None
            git_email = None
            token = None

        # Execute the selected action
        if action == "setup":
            self.setup_menu()
        elif action == "clone":
            self.handle_clone(account, github_user, ssh_alias, git_email)
        elif action == "push":
            self.handle_push(account, github_user, ssh_alias, git_email)
        elif action == "pull":
            self.handle_pull()
        elif action == "adduser":
            self.handle_adduser()
        elif action == "showuser":
            self.handle_showuser()
        elif action == "addremote":
            self.handle_addremote(account, token, github_user, ssh_alias, git_email)
        elif action == "delremote":
            self.handle_delremote(account, token, github_user)
        elif action == "remotelist":
            self.handle_remotelist(token, github_user)
        elif action == "status":
            self.get_git_repository_info()
        elif action == "commit":
            self.invoke_git_commit()
        elif action == "history":
            self.show_git_history()
        elif action == "tokeninfo":
            print("\n🔐 GitHub Token Information")
            print("──────────────────────────────────────────────")
            try:
                token = self.get_github_token(account)
                self.test_github_token_scopes(token, account)
            except ValueError as e:
                print(str(e))
        elif action == "branch":
            self.handle_branch()
        elif action == "changename":
            self.handle_changename(account, token, github_user)
        elif action == "help":
            self.handle_help()
        else:
            print("\n❌ Invalid action. Please enter one of the following:")
            print("   → clone / push / pull / adduser / showuser / addremote / delremote / remotelist / status / commit / history / tokeninfo / setup / branch / remotem / changename / help")


if __name__ == "__main__":
    gitgo = GitGo()
    gitgo.run()