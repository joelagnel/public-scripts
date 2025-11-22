# Public Scripts

Bootstrap repository for setting up development environment.

## Usage

```bash
./setup-dev-env.sh
```

## Prerequisites

- Ubuntu/Debian system with sudo access
- Internet connection
- GitHub Personal Access Token for private repository access

## What it does

- Updates package manager
- Installs ansible
- Creates `~/repo/` directory
- Clones joel-snips repository (with backup handling)
- Runs ansible test playbook

## Author

Joel Fernandes <joel@joelfernandes.org>