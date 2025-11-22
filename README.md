# Public Scripts

Bootstrap repository for setting up development environment.

## Usage

```bash
./setup-dev-env.sh
```

## Prerequisites

- Ubuntu/Debian system with sudo access
- Internet connection
- GitHub Personal Access Token with Contents: Read/Write permission for joel-snips repository

### PAT Setup

Generate a Personal Access Token at: https://github.com/settings/personal-access-tokens

**Required permissions:**
- Contents: Read/Write (for repository access)

**For fine-grained tokens:**
1. Select "Fine-grained personal access tokens"
2. Choose resource access for 'joelagnel/joel-snips' repository
3. Grant "Contents" permission with "Read and write" access

**Security Best Practice:**
- Delete the PAT immediately after the script completes
- Use short expiration times (1 hour or less recommended)
- Revoke unused tokens regularly

## What it does

- Updates package manager
- Installs ansible
- Creates `~/repo/` directory
- Clones joel-snips repository (with backup handling)
- Runs ansible test playbook

## Author

Joel Fernandes <joel@joelfernandes.org>