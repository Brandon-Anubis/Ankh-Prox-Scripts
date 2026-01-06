# GitHub Copilot Instructions for Ankh-Prox-Scripts

## 🎯 What This Project Is

A comprehensive community-driven Proxmox VE automation framework that simplifies deploying 100+ applications as LXC containers or full VMs. The project maintains strict architectural separation and provides reusable libraries across thousands of lines of well-documented shell code.

- **Host-side container creators** (`/ct/*.sh`): Run on Proxmox host, orchestrate `pct create` and container configuration
- **Container-side installers** (`/install/*-install.sh`): Execute inside containers, perform 10-phase app installation (deps → download → config → DB → permissions → services → cleanup)
- **Shared function libraries** (`/misc/*.func`): Nine core libraries (build, core, error_handler, install, tools, alpine-install, alpine-tools, api, cloud-init) with flowcharts and deep documentation
- **VMs** (`/vm/*.sh`): KVM provisioning with cloud-init, paralleling container infrastructure
- **Complete documentation** (`/docs/*`): 60+ files with technical reference, exit codes, guides, and per-library deep dives

## 🏗️ Architecture & Layers

### Container Creation Pipeline

```
Proxmox Host
  └─ ct/AppName.sh (sourced, inherits build.func)
     ├─ Defines: APP, var_cpu, var_ram, var_disk, var_os, var_version, var_tags, var_unprivileged, etc.
     ├─ Calls: variables() → color() → catch_errors() → install_script()
     ├─ Optional: update_script() for app updates
     └─ Invokes: build_container() which runs pct create + pipes install/AppName-install.sh

Inside Container (spawned by pct create)
  └─ install/AppName-install.sh
     ├─ Sources: $FUNCTIONS_FILE_PATH (chains core.func + install.func + tools.func)
     ├─ Calls: setting_up_container() → network_check() → update_os()
     ├─ 10-phase install:
     │  1. Dependencies (apt/apk install)
     │  2. Base tools (Node.js, PHP, Python, etc. via setup_*() functions)
     │  3. Application download (git clone, wget, docker pull, etc.)
     │  4. Configuration (config files, .env, database schema)
     │  5. Database setup (CREATE DATABASE, migrations)
     │  6. Permissions (chown/chmod for app directories)
     │  7. Services (systemctl enable --now or rc-update add)
     │  8. Version tracking (echo $VERSION > /opt/app_version.txt)
     │  9. Cleanup (apt-get autoremove, rm temp files)
     │  10. Finalization (motd_ssh() → customize() → cleanup_lxc())
     └─ Result: Container ready, app running
```

### Variable Precedence (Build Execution Order)

```
Priority 1 (Highest): ENVIRONMENT VARIABLES
  └─ export var_cpu=16 before script execution

Priority 2: APP-SPECIFIC DEFAULTS
  └─ /usr/local/community-scripts/defaults/<app>.vars
  └─ Saved per-application settings (hostname, CPU, RAM, network config)

Priority 3: USER GLOBAL DEFAULTS
  └─ /usr/local/community-scripts/default.vars
  └─ Applies to all container installations

Priority 4 (Lowest): BUILT-IN DEFAULTS
  └─ Hardcoded in scripts (APP_CPU_DEFAULT, APP_RAM_DEFAULT, etc.)
```

### Function Library Dependency Chain

```
core.func (Foundation)
  ├─ Exports: msg_info(), msg_ok(), msg_error(), color codes, icons
  ├─ Checks: root_check(), pve_check(), arch_check(), shell_check()
  └─ Utilities: silent(), is_verbose_mode(), ensure_tput()

error_handler.func (Error Management)
  ├─ Exports: catch_errors(), error_handler(), explain_exit_code()
  ├─ Signals: SIGINT, SIGTERM, EXIT traps
  └─ Exit codes: 200-299 (Proxmox), 100-199 (packages/databases), 1-99 (Unix standard)

build.func (Host Orchestrator) [MOST COMPLEX]
  ├─ Initialization: variables(), header_info(), base_settings()
  ├─ UI: install_script() [5 modes], advanced_settings() [28-step wizard]
  ├─ Storage: storage_selector(), check_storage_requirements()
  ├─ Container: build_container(), build_defaults(), description()
  ├─ GPU: gpu_selector(), configure_gpu_passthrough()
  ├─ Defaults: load_vars_file(), default_var_settings(), maybe_offer_save_app_defaults()
  └─ Used by: All ct/*.sh scripts

install.func (Container Initializer)
  ├─ Initialization: setting_up_container(), network_check(), update_os()
  ├─ IPv6: verb_ip6() for enabling IPv6 persistently
  ├─ SSH: motd_ssh() for SSH daemon + MOTD setup
  ├─ Customization: customize(), cleanup_lxc()
  └─ Used by: All install/*.sh scripts

tools.func (Tool & Package Manager) [MOST FEATURE-RICH]
  ├─ Packages: pkg_install(), pkg_update(), pkg_remove() with retry logic
  ├─ Repositories: setup_deb822_repo(), cleanup_repo_metadata()
  ├─ Languages: setup_nodejs(), setup_php(), setup_python(), setup_ruby(), setup_golang()
  ├─ Databases: setup_mariadb(), setup_postgresql(), setup_mongodb(), setup_redis()
  ├─ Web Servers: setup_nginx(), setup_apache(), setup_caddy(), setup_traefik()
  ├─ Containers: setup_docker(), setup_podman(), setup_docker_compose()
  ├─ Tools: setup_git(), setup_build_tools(), setup_composer()
  ├─ Monitoring: setup_grafana(), setup_prometheus(), setup_telegraf()
  └─ 30+ total functions for Debian/Ubuntu

alpine-install.func (Alpine-Specific Initializer)
  ├─ Alternative to install.func for Alpine containers
  ├─ Uses: apk instead of apt-get
  ├─ Services: rc-update/rc-service instead of systemctl
  └─ Available in: /docs/misc/alpine-install.func/README.md

alpine-tools.func (Alpine Tool Installation)
  ├─ Alternative to tools.func for Alpine
  ├─ apk-specific package operations
  ├─ 15+ Alpine-native functions
  └─ Available in: /docs/misc/alpine-tools.func/README.md

api.func (Telemetry & Reporting)
  ├─ post_to_api(): Send container creation stats to API
  ├─ post_update_to_api(): Report application updates
  ├─ get_error_description(): Fetch human-readable error details
  └─ Privacy: Anonymous, aggregated data only

cloud-init.func (VM Provisioning)
  ├─ generate_cloud_init(): Create VM cloud-init config
  ├─ setup_ssh_keys(): Inject SSH public keys
  ├─ setup_static_ip(): Configure network
  └─ Used by: vm/*.sh scripts
```

## 📋 Essential Workflows & Patterns

### 🔵 Creating a Container Script (`ct/myapp.sh`)

**File Header & Imports:**

```bash
#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: YourGithubUsername
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/official-app/repo
```

**Variable Defaults (read by build.func):**

```bash
APP="MyApp"                          # Display name (title case)
var_tags="category1;category2"       # Max 2 tags: category;subcategory
var_cpu="${var_cpu:-2}"              # Default 2 cores
var_ram="${var_ram:-2048}"           # Default 2GB
var_disk="${var_disk:-8}"            # Default 8GB
var_os="${var_os:-debian}"           # debian, alpine, ubuntu
var_version="${var_version:-12}"     # Debian 12, 13; Ubuntu 22.04, 24.04
var_unprivileged="${var_unprivileged:-1}"  # 1=unprivileged (safer), 0=privileged
var_gpu="${var_gpu:-no}"             # GPU passthrough support: yes/no/nvidia/intel/amd
```

**Core Functions (Standard Pattern):**

```bash
header_info "$APP"                   # Display logo
variables                            # Parse arguments/env vars
color                                # Setup ANSI codes
catch_errors                         # Setup error traps

function update_script() {            # OPTIONAL: app-specific update logic
  header_info
  check_container_storage            # Verify storage space
  check_container_resources          # Verify resource usage

  if [[ ! -d /opt/myapp ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Fetch latest release, update app, restart services
  # See: ct/fileflows.sh or ct/wikijs.sh for patterns
}

start                                 # Launch mode selection (build.func)
build_container                       # Create LXC + run install script
description                          # Set container description
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
```

**Mode Selection (Automatic in build.func):**

- **Default Install**: Uses built-in defaults, minimal prompts
- **Advanced Install**: 28-step wizard for every config option
- **My Defaults**: Loads /usr/local/community-scripts/default.vars
- **App Defaults**: Loads /usr/local/community-scripts/defaults/myapp.vars
- **Settings Menu**: Edit any single setting before creation

### 🟢 Creating an Installation Script (`install/myapp-install.sh`)

**File Header & Function Sourcing:**

```bash
#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# Author: YourGithubUsername
# License: MIT
# Source: https://github.com/official-app/repo

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"   # Load all functions
color                                          # Setup colors
verb_ip6                                       # Optional: enable IPv6
catch_errors                                   # Setup error traps
setting_up_container                           # Display setup message
network_check                                  # Verify internet access
update_os                                      # Update apt/apk
```

**10-Phase Installation Pattern:**

**Phase 1-2: Dependencies & Tools**

```bash
msg_info "Installing Dependencies"
$STD apt-get install -y curl wget git build-essential libssl-dev python3-dev
msg_ok "Installed Dependencies"

msg_info "Installing Node.js"
setup_nodejs "20"                    # Function from tools.func
msg_ok "Installed Node.js"
```

**Phase 3-4: Application Download & Configuration**

```bash
msg_info "Installing MyApp"
git clone https://github.com/example/myapp /opt/myapp
cd /opt/myapp
$STD npm install --production        # Use $STD to suppress output
cat > .env <<EOF
DATABASE_URL=postgresql://user:pass@localhost/myapp
NODE_ENV=production
SECRET_KEY=$(openssl rand -base64 32)
EOF
msg_ok "Installed MyApp"
```

**Phase 5-6: Database Setup**

```bash
msg_info "Setting up Database"
setup_postgresql "15"                # Function from tools.func
psql -U postgres -c "CREATE DATABASE myapp;"
psql -U postgres -d myapp < schema.sql
msg_ok "Database configured"
```

**Phase 7: Permissions**

```bash
msg_info "Setting Permissions"
chown -R nobody:nogroup /opt/myapp
chmod -R 755 /opt/myapp
msg_ok "Permissions set"
```

**Phase 8: Services (Debian)**

```bash
msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/myapp.service
[Unit]
Description=MyApp
After=network.target postgresql.service

[Service]
Type=simple
User=nobody
WorkingDirectory=/opt/myapp
ExecStart=/usr/bin/node /opt/myapp/index.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now myapp
msg_ok "Service created"
```

**Phase 8 (Alpine):**

```bash
cat <<EOF >/etc/init.d/myapp
#!/sbin/openrc-run
name="MyApp"
command="/usr/bin/node /opt/myapp/index.js"
command_user="nobody"
pidfile="/var/run/${RC_SVCNAME}.pid"

depend() {
  need net
}
EOF
chmod +x /etc/init.d/myapp
rc-update add myapp
rc-service myapp start
msg_ok "Service created"
```

**Phase 9: Version Tracking**

```bash
RELEASE=$(curl -s https://api.github.com/repos/example/myapp/releases/latest | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4)
echo "${RELEASE}" >/opt/myapp_version.txt
```

**Phase 10: Finalization**

```bash
motd_ssh                             # Configure SSH + MOTD
customize                            # Apply container customizations
cleanup_lxc                          # Final cleanup (apt-get autoremove)
```

## 🛠️ Core Development Patterns

### Conventions (Non-Negotiable)

- **File naming**: `ct/app.sh` + `install/app-install.sh` (lowercase, hyphens only for multi-word apps)
- **Shebang**: `#!/usr/bin/env bash` (not `/bin/bash` - allows portable execution)
- **Copyright block**: Author, license, source URL (see any script in `/ct/`)
- **Variable naming**: `var_lowercase_with_underscores` only (not `VAR_UPPERCASE`)
- **Logging**: Always use `msg_info()`, `msg_ok()`, `msg_error()` from core.func
- **Silent execution**: Wrap all package operations with `$STD` to respect verbosity
- **Service enable**: Debian=`systemctl enable -q --now`, Alpine=`rc-update add` + `rc-service start`

### Error Handling Pattern

```bash
catch_errors                         # Initialize trap handlers
# ... your code ...
msg_error "Something failed"         # These exit with codes from error_handler.func
exit 1                               # Exit codes: 1-99=Unix, 100-199=packages, 200-299=Proxmox
```

### Verbosity Respecting (`$STD`)

```bash
# $STD is empty (runs normally) or "> /dev/null 2>&1" (silent)
# Set by: VERBOSE environment variable or advanced settings

$STD apt-get install -y package      # Silent in normal mode, verbose if VERBOSE=yes
msg_info "Installing..."             # These msg_* functions always show
$STD curl -fsSL https://example.com  # Silent download
```

### Password Generation (Secure)

```bash
# ✅ Good: Alphanumeric only
PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | head -c13)

# ❌ Bad: May include special chars that break config files
PASSWORD=$(openssl rand -base64 18)
```

### Configuration File Writing (Atomicity)

```bash
# ✅ Use heredoc with safe expansion
cat > /path/to/config.conf <<EOF
setting1=value1
setting2=$(date)
database_url="${DATABASE_URL}"
EOF

# ❌ Avoid: Risk of file corruption on interruption
echo "setting=value" >> /path/to/config.conf
```

## 📚 Finding Documentation Quickly

### Project Documentation Hub

- **Start here**: [docs/README.md](docs/README.md) - Navigation by role/task
- **Contribution guide**: [docs/contribution/README.md](docs/contribution/README.md)
- **Technical deep dive**: [docs/TECHNICAL_REFERENCE.md](docs/TECHNICAL_REFERENCE.md)

### By Task Type

**Creating Container Scripts**
→ [docs/ct/DETAILED_GUIDE.md](docs/ct/DETAILED_GUIDE.md) (complete reference with 28-step wizard details)
→ [docs/ct/README.md](docs/ct/README.md) (quick overview)

**Creating Installation Scripts**
→ [docs/install/DETAILED_GUIDE.md](docs/install/DETAILED_GUIDE.md) (10-phase pattern, examples)
→ [docs/install/README.md](docs/install/README.md) (quick overview)

**Installing Tools/Packages**
→ [docs/misc/tools.func/README.md](docs/misc/tools.func/README.md) (30+ functions)
→ [docs/misc/tools.func/TOOLS_FUNC_FUNCTIONS_REFERENCE.md](docs/misc/tools.func/TOOLS_FUNC_FUNCTIONS_REFERENCE.md) (alphabetical)
→ [docs/misc/tools.func/TOOLS_FUNC_USAGE_EXAMPLES.md](docs/misc/tools.func/TOOLS_FUNC_USAGE_EXAMPLES.md) (patterns)

**Understanding build.func (most complex)**
→ [docs/misc/build.func/README.md](docs/misc/build.func/README.md) (overview, 7 files)
→ [docs/misc/build.func/BUILD_FUNC_FLOWCHART.md](docs/misc/build.func/BUILD_FUNC_FLOWCHART.md) (visual flows)
→ [docs/misc/build.func/BUILD_FUNC_ADVANCED_SETTINGS.md](docs/misc/build.func/BUILD_FUNC_ADVANCED_SETTINGS.md) (28-step wizard details)

**Debugging Errors**
→ [docs/EXIT_CODES.md](docs/EXIT_CODES.md) (comprehensive exit code reference, 1-299)
→ [docs/DEV_MODE.md](docs/DEV_MODE.md) (dev modes: motd, keep, trace, pause, breakpoint, logs)

**Configuration & Defaults System**
→ [docs/guides/DEFAULTS_SYSTEM_GUIDE.md](docs/guides/DEFAULTS_SYSTEM_GUIDE.md) (user/app defaults, precedence)
→ [docs/guides/CONFIGURATION_REFERENCE.md](docs/guides/CONFIGURATION_REFERENCE.md) (all var\_\* variables)
→ [docs/TECHNICAL_REFERENCE.md](docs/TECHNICAL_REFERENCE.md) (deep architecture)

**Alpine Linux Containers**
→ [docs/misc/alpine-install.func/README.md](docs/misc/alpine-install.func/README.md)
→ [docs/misc/alpine-tools.func/README.md](docs/misc/alpine-tools.func/README.md)

**Virtual Machines (Cloud-init)**
→ [docs/vm/README.md](docs/vm/README.md)
→ [docs/misc/cloud-init.func/README.md](docs/misc/cloud-init.func/README.md)

### Function Library Documentation

Each library in `/misc/` has 5-7 files per library:

```
/misc/LIBNAME.func/
  ├─ README.md                          # Quick reference
  ├─ LIBNAME_FLOWCHART.md               # Visual execution flows
  ├─ LIBNAME_FUNCTIONS_REFERENCE.md     # All functions alphabetically
  ├─ LIBNAME_USAGE_EXAMPLES.md          # Practical copy-paste examples
  ├─ LIBNAME_INTEGRATION.md             # How library connects to others
  └─ LIBNAME_ENVIRONMENT_VARIABLES.md   # (if applicable)
```

## 🔍 Real Script Examples (Learn By Reading)

**Simple Container** → `ct/debian.sh` (minimal example)
**Medium Container** → `ct/docker.sh` or `ct/pihole.sh` (typical pattern)
**Complex Container** → `ct/fileflows.sh` or `ct/wikijs.sh` (with update functions)
**Installation** → `install/agentdvr-install.sh` (reference example)

### Example: Anatomy of ct/fileflows.sh

```bash
# 1. Header & imports
#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright ...
# Author: kkroboth

# 2. Metadata
APP="FileFlows"
var_tags="media;automation"
var_cpu="2"
var_ram="2048"
var_disk="8"
var_gpu="yes"  # Indicates GPU support

# 3. Core functions
header_info "$APP"
variables
color
catch_errors

# 4. Update function (OPTIONAL but recommended)
function update_script() {
  # ... fetch latest release, stop service, update, restart ...
}

# 5. Launcher
start
build_container
description

# 6. Success message
msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup...${CL}"
```

## 🧪 Testing & Development

### Quick Test Local (Development)

```bash
# Test ct script (host)
VERBOSE=yes bash ct/myapp.sh

# Test with dev modes (keep container, show logs, trace commands)
export dev_mode="keep,logs,trace"
bash ct/myapp.sh
```

### Dev Modes Available

- **motd**: Early SSH setup before installation (for quick debugging)
- **keep**: Never delete container on failure (for repeated testing)
- **trace**: Enable `set -x` command tracing (for detailed debugging)
- **pause**: Pause at each phase for manual inspection
- **breakpoint**: Stop before critical operations
- **logs**: Save comprehensive logs to /tmp/

### Testing Install Script Inside Container (Advanced)

```bash
# Create container manually
pct create 200 local:vztmpl/debian-12-standard_12.3-1_amd64.tar.zst \
  -hostname testapp -cores 2 -memory 2048 -disk 10 \
  -net0 name=eth0,bridge=vmbr0,firewall=1

# Get functions and run install script
pct enter 200 -- bash <<'EOF'
source /dev/stdin <<<"$(cat /path/to/misc/install.func)"
# ... run installation commands manually ...
EOF
```

## 🚫 Exit Codes & Troubleshooting

### Common Exit Codes (Reference)

```
0       = Success
1       = General error
100     = APT package error
127     = Command not found
200-209 = Container creation errors (CTID conflict, etc.)
206     = CTID already in use - choose different ID
210     = Cluster not quorate
214     = Not enough storage space
255     = DPKG fatal error
```

**Full Reference**: [docs/EXIT_CODES.md](docs/EXIT_CODES.md) (100+ codes with solutions)

### Debugging with EXIT_CODES.md

When a script fails:

1. Note the exit code
2. Check [EXIT_CODES.md](docs/EXIT_CODES.md) for category and cause
3. Follow solutions section
4. If needed: Use `VERBOSE=yes` and dev modes for tracing

## 📖 External Documentation via MCP

For language/tool-specific details not in repo docs:

**Using mcp_context7-mcp Tools:**

```bash
# Resolve library ID first:
mcp_context7-mcp_resolve-library-id "gnu bash manual"

# Then fetch documentation:
mcp_context7-mcp_get-library-docs "/gnu-project/bash" mode="code"
```

**Common External References:**

- **Bash scripting**: GNU Bash Manual (bash functions, expansions, special variables)
- **systemd**: Systemd documentation (unit files, service directives)
- **Docker**: Docker official docs (image creation, Dockerfiles)
- **Node.js**: Node.js official docs (npm, package.json, versions)
- **PostgreSQL**: PostgreSQL official docs (CREATE DATABASE, migrations)
- **Alpine Linux**: Alpine Linux wiki (apk commands, OpenRC)
- **Cloud-init**: Cloud-init documentation (user-data scripts, modules)

## ✅ Contributing Checklist

Before submitting a PR:

**Code Quality**

- [ ] Follows shebang, copyright block, variable naming conventions
- [ ] Uses `msg_info/msg_ok/msg_error` for all output
- [ ] Wraps all package operations with `$STD`
- [ ] Proper error handling (no `set -e` abuse, use catch_errors)
- [ ] Generates secure passwords (alphanumeric only)
- [ ] Sets proper file permissions (chown/chmod)

**Completeness**

- [ ] Includes update function if app has releases
- [ ] Saves version to `/opt/app_version.txt` or similar
- [ ] Follows 10-phase installation pattern
- [ ] SSH/MOTD setup (motd_ssh)
- [ ] Final cleanup (cleanup_lxc)

**Testing**

- [ ] Runs on Debian 12+ or Alpine (as appropriate)
- [ ] Tested with `VERBOSE=yes`
- [ ] Tested with dev_mode="keep" for repeated runs
- [ ] Confirms app is accessible and functional
- [ ] Tested on Proxmox VE 8.4+ or 9.0+

**Documentation**

- [ ] Templates used: docs/contribution/templates_ct/_.sh + templates_install/_.sh
- [ ] CT and install scripts paired (myapp.sh + myapp-install.sh)
- [ ] Naming follows project convention (lowercase, hyphens for multi-word)
- [ ] Exit codes understood (see EXIT_CODES.md if custom)

## 🎓 Learning Resources

### For First-Time Contributors

1. Read [docs/contribution/README.md](docs/contribution/README.md) (Quick Start)
2. Study [docs/ct/DETAILED_GUIDE.md](docs/ct/DETAILED_GUIDE.md) OR [docs/install/DETAILED_GUIDE.md](docs/install/DETAILED_GUIDE.md)
3. Review 2-3 similar existing scripts (ct/pihole.sh + install/pihole-install.sh)
4. Copy templates: `docs/contribution/templates_ct/AppName.sh` + `templates_install/AppName-install.sh`
5. Test on your Proxmox system

### For Experienced Developers

1. Review [docs/TECHNICAL_REFERENCE.md](docs/TECHNICAL_REFERENCE.md) for architectural decisions
2. Study [docs/misc/build.func/BUILD_FUNC_FUNCTIONS_REFERENCE.md](docs/misc/build.func/BUILD_FUNC_FUNCTIONS_REFERENCE.md) (50+ functions)
3. Check [docs/misc/tools.func/TOOLS_FUNC_FUNCTIONS_REFERENCE.md](docs/misc/tools.func/TOOLS_FUNC_FUNCTIONS_REFERENCE.md) (30+ functions)
4. Review [docs/guides/DEFAULTS_SYSTEM_GUIDE.md](docs/guides/DEFAULTS_SYSTEM_GUIDE.md) for config precedence
5. Contribute complex features with confidence

### Advanced Topics

- **GPU Passthrough**: Check build.func for gpu_selector(), nvidia/intel/amd logic
- **Alpine Support**: Read alpine-install.func and alpine-tools.func README files
- **VMs**: Review cloud-init.func and vm/\*.sh scripts
- **Unattended Deployments**: [docs/guides/UNATTENDED_DEPLOYMENTS.md](docs/guides/UNATTENDED_DEPLOYMENTS.md)

## 🔐 Security Notes

- **No hardcoded credentials**: All secrets generated dynamically (openssl rand)
- **Safe variable parsing**: Load .vars files safely with load_vars_file() (no source/eval)
- **Privileged containers**: Only when necessary (hardware access, nested virt); default is unprivileged
- **SSH keys**: Injected via cloud-init for VMs, configured in motd_ssh for containers
- **No shell injection**: Avoid command substitution in user-controlled values, sanitize with \_sanitize_value()

## 📝 Key Files to Know

| File                                                                   | Purpose                                                            |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------ |
| [ct/AppName.sh](ct/AppName.sh)                                         | Host-side container creation entry point                           |
| [install/AppName-install.sh](install/AppName-install.sh)               | Container-side 10-phase installer                                  |
| [misc/build.func](misc/build.func)                                     | Host orchestrator (2000+ lines) - container creation, UI, defaults |
| [misc/core.func](misc/core.func)                                       | Foundation utilities, colors, messaging                            |
| [misc/install.func](misc/install.func)                                 | Container initializer, network check, OS setup                     |
| [misc/tools.func](misc/tools.func)                                     | 30+ tool installation functions (Node, PHP, databases)             |
| [misc/error_handler.func](misc/error_handler.func)                     | Error trapping, signal handling, exit codes                        |
| [docs/EXIT_CODES.md](docs/EXIT_CODES.md)                               | Comprehensive exit code reference (100+ codes)                     |
| [docs/TECHNICAL_REFERENCE.md](docs/TECHNICAL_REFERENCE.md)             | Architecture deep dive                                             |
| [docs/contribution/CONTRIBUTING.md](docs/contribution/CONTRIBUTING.md) | Coding standards                                                   |

## 🎯 One-Minute Template for ct/myapp.sh

```bash
#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: YourUsername
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/example/myapp

APP="MyApp"
var_tags="category;subcategory"
var_cpu="2"
var_ram="2048"
var_disk="8"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  if [[ ! -d /opt/myapp ]]; then msg_error "Not installed"; exit; fi
  # Update logic here
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup initialized!${CL}"
echo -e "${INFO}${YW} Access it here:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
```

---

**Last Updated**: January 2026 | **Comprehensive Deep Dive Edition** | **100+ Scripts Supported**
