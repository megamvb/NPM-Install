#!/bin/bash
#
# Improved script to install Nginx Proxy Manager on Ubuntu 24.04
# Fixes migration issues and other common errors
# Adapted from the original ProxmoxVE Helper-Scripts project
#
# Author: Marcos V Bohrer, AgileHost (www.agilehost.com.br)

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Message functions
msg_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

msg_ok() {
  echo -e "${GREEN}[OK]${NC} $1"
}

msg_warn() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

msg_error() {
  echo -e "${RED}[ERROR]${NC} $1"
  exit 1
}

msg_step() {
  echo -e "\n${MAGENTA}==== $1 ====${NC}"
}

# Check if the script is being run as root
if [ "$EUID" -ne 0 ]; then
  msg_error "This script must be run as root or with sudo"
fi

# Define installation directories
INSTALL_DIR="/opt/nginx-proxy-manager"
APP_DIR="/app"
DATA_DIR="/data"

# Check and install dependencies
install_dependencies() {
  msg_step "Checking and installing dependencies"
  
  # Update repositories
  msg_info "Updating package lists..."
  apt update -y
  
  # Check if packages are installed
  local DEPS=(curl wget gnupg2 ca-certificates lsb-release python3 python3-pip python3-venv openssl git logrotate build-essential sudo sqlite3)
  local MISSING_DEPS=()
  
  for dep in "${DEPS[@]}"; do
    if ! dpkg -l | grep -qw "$dep"; then
      MISSING_DEPS+=("$dep")
    fi
  done
  
  # Install missing dependencies
  if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    msg_info "Installing dependencies: ${MISSING_DEPS[*]}"
    apt install -y "${MISSING_DEPS[@]}"
  else
    msg_ok "All basic dependencies are already installed"
  fi
  
  # Install Node.js 18.x
  if ! command -v node &> /dev/null; then
    msg_info "Installing Node.js 18.x"
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
    node_version=$(node -v)
    msg_ok "Node.js ${node_version} installed"
  else
    node_version=$(node -v)
    msg_ok "Node.js ${node_version} is already installed"
  fi
  
  # Check Node.js version
  if [[ "$(node -v)" != v18* ]]; then
    msg_warn "Node.js version is not 18.x. We recommend using Node.js 18 for better compatibility."
  fi
  
  # Install PNPM
  if ! command -v pnpm &> /dev/null; then
    msg_info "Installing pnpm"
    npm install -g pnpm@8.15
    msg_ok "pnpm installed"
  else
    pnpm_version=$(pnpm --version)
    msg_ok "pnpm ${pnpm_version} is already installed"
  fi
  
  # Install Certbot
  if ! command -v certbot &> /dev/null; then
    msg_info "Installing Certbot"
    apt install -y certbot
    mkdir -p /opt/certbot/bin
    ln -sf /usr/bin/certbot /opt/certbot/bin/certbot
    msg_ok "Certbot installed"
  else
    msg_ok "Certbot is already installed"
  fi
  
  # Install Openresty
  if ! command -v openresty &> /dev/null; then
    msg_info "Installing Openresty"
    wget -qO - https://openresty.org/package/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/openresty.gpg
    echo "deb [signed-by=/usr/share/keyrings/openresty.gpg] http://openresty.org/package/ubuntu $(lsb_release -sc) main" | \
      tee /etc/apt/sources.list.d/openresty.list
    apt update -y
    apt install -y openresty
    msg_ok "Openresty installed"
  else
    msg_ok "Openresty is already installed"
  fi
  
  # Check if sqlite3 is installed
  if ! command -v sqlite3 &> /dev/null; then
    msg_info "Installing SQLite3"
    apt install -y sqlite3
    msg_ok "SQLite3 installed"
  else
    msg_ok "SQLite3 is already installed"
  fi
  
  msg_ok "All dependencies are installed"
}

# Check existing services and stop conflicts
check_existing_services() {
  msg_step "Checking existing services"
  
  # Check and stop Nginx services
  if systemctl is-active --quiet nginx; then
    msg_warn "Nginx service is running and may conflict with Openresty"
    msg_info "Stopping and disabling Nginx service..."
    systemctl stop nginx
    systemctl disable nginx
    msg_ok "Nginx stopped and disabled"
  fi
  
  # Check and stop existing NPM services
  if systemctl is-active --quiet openresty; then
    msg_info "Stopping Openresty service..."
    systemctl stop openresty
  fi
  
  if systemctl is-active --quiet npm; then
    msg_info "Stopping NPM service..."
    systemctl stop npm
  fi
  
  # Check used ports
  for port in 80 81 443; do
    if ss -tuln | grep -q ":$port "; then
      msg_warn "Port $port is already in use. This may conflict with NPM."
      process=$(lsof -i :$port | grep LISTEN | awk '{print $1}' | head -n 1)
      if [ -n "$process" ]; then
        msg_warn "Port $port is being used by process: $process"
      fi
    fi
  done
}

# Clean previous installations
clean_previous_installation() {
  msg_step "Cleaning previous installations"
  
  if [ -d "$APP_DIR" ] || [ -d "$DATA_DIR" ] || [ -f "/lib/systemd/system/npm.service" ]; then
    msg_info "Previous NPM installation detected"
    
    # Backup important data
    if [ -f "$DATA_DIR/database.sqlite" ]; then
      msg_info "Creating database backup..."
      mkdir -p /root/npm-backup
      cp "$DATA_DIR/database.sqlite" "/root/npm-backup/database.sqlite.$(date +%Y%m%d%H%M%S)"
      msg_ok "Database backup created in /root/npm-backup"
    fi
    
    # Remove files from previous installation
    msg_info "Removing files from previous installation..."
    rm -rf "$APP_DIR"
    rm -f /lib/systemd/system/npm.service
    
    # Clean /migrations directory if it exists as a symbolic link
    if [ -L "/migrations" ]; then
      msg_info "Removing /migrations symbolic link..."
      rm -f /migrations
    elif [ -d "/migrations" ]; then
      msg_info "Removing /migrations directory..."
      rm -rf /migrations
    fi
    
    msg_ok "Cleanup completed"
  else
    msg_ok "No previous installation detected"
  fi
}

# Function to download and prepare NPM
download_and_prepare_npm() {
  msg_step "Downloading and preparing Nginx Proxy Manager"
  
  # Get the latest version
  msg_info "Getting latest version information..."
  RELEASE=$(curl -s https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest |
    grep "tag_name" |
    awk '{print substr($2, 3, length($2)-4) }')
  
  if [ -z "$RELEASE" ]; then
    msg_error "Could not get the latest NPM version. Check your internet connection."
  fi
  
  msg_info "Latest version: ${RELEASE}"
  
  # Create installation directories
  mkdir -p "$APP_DIR" "$DATA_DIR"
  
  # Download NPM
  msg_info "Downloading Nginx Proxy Manager v${RELEASE}..."
  cd /tmp
  wget -q https://codeload.github.com/NginxProxyManager/nginx-proxy-manager/tar.gz/v${RELEASE} -O - | tar -xz
  
  if [ ! -d "/tmp/nginx-proxy-manager-${RELEASE}" ]; then
    msg_error "Failed to download or extract NPM files"
  fi
  
  cd "/tmp/nginx-proxy-manager-${RELEASE}"
  msg_ok "Download completed"
  
  # Configure environment
  msg_info "Configuring environment..."
  
  # Create necessary symbolic links
  ln -sf /usr/bin/python3 /usr/bin/python
  ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/sbin/nginx
  ln -sf /usr/local/openresty/nginx/ /etc/nginx
  
  # Update version in package.json files
  sed -i "s|\"version\": \"0.0.0\"|\"version\": \"$RELEASE\"|" backend/package.json
  sed -i "s|\"version\": \"0.0.0\"|\"version\": \"$RELEASE\"|" frontend/package.json
  
  # Modify configuration files
  sed -i 's+^daemon+#daemon+g' docker/rootfs/etc/nginx/nginx.conf
  NGINX_CONFS=$(find "$(pwd)" -type f -name "*.conf")
  for NGINX_CONF in $NGINX_CONFS; do
    sed -i 's+include conf.d+include /etc/nginx/conf.d+g' "$NGINX_CONF"
  done
  
  # Create necessary directories
  mkdir -p /var/www/html /etc/nginx/logs
  cp -r docker/rootfs/var/www/html/* /var/www/html/
  cp -r docker/rootfs/etc/nginx/* /etc/nginx/
  cp docker/rootfs/etc/letsencrypt.ini /etc/letsencrypt.ini
  cp docker/rootfs/etc/logrotate.d/nginx-proxy-manager /etc/logrotate.d/nginx-proxy-manager
  ln -sf /etc/nginx/nginx.conf /etc/nginx/conf/nginx.conf
  rm -f /etc/nginx/conf.d/dev.conf
  
  # Create directory structure
  mkdir -p /tmp/nginx/body \
    /run/nginx \
    "$DATA_DIR/nginx" \
    "$DATA_DIR/custom_ssl" \
    "$DATA_DIR/logs" \
    "$DATA_DIR/access" \
    "$DATA_DIR/nginx/default_host" \
    "$DATA_DIR/nginx/default_www" \
    "$DATA_DIR/nginx/proxy_host" \
    "$DATA_DIR/nginx/redirection_host" \
    "$DATA_DIR/nginx/stream" \
    "$DATA_DIR/nginx/dead_host" \
    "$DATA_DIR/nginx/temp" \
    /var/lib/nginx/cache/public \
    /var/lib/nginx/cache/private \
    /var/cache/nginx/proxy_temp
  
  chmod -R 777 /var/cache/nginx
  chown root /tmp/nginx
  
  # Configure DNS resolvers
  echo resolver "$(awk 'BEGIN{ORS=" "} $1=="nameserver" {print ($2 ~ ":")? "["$2"]": $2}' /etc/resolv.conf);" > /etc/nginx/conf.d/include/resolvers.conf
  
  # Generate dummy certificates for internal use
  if [ ! -f "$DATA_DIR/nginx/dummycert.pem" ] || [ ! -f "$DATA_DIR/nginx/dummykey.pem" ]; then
    msg_info "Generating dummy certificates..."
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 -subj "/O=Nginx Proxy Manager/OU=Dummy Certificate/CN=localhost" -keyout "$DATA_DIR/nginx/dummykey.pem" -out "$DATA_DIR/nginx/dummycert.pem"
  fi
  
  # Configure application directories
  mkdir -p "$APP_DIR/global" "$APP_DIR/frontend/images"
  cp -r backend/* "$APP_DIR"
  cp -r global/* "$APP_DIR/global"
  
  # IMPORTANT FIX: Copy migrations and create symbolic link
  msg_info "Configuring database migrations..."
  if [ -d "backend/migrations" ]; then
    # Create migrations directory in APP_DIR
    mkdir -p "$APP_DIR/migrations"
    cp -r backend/migrations/* "$APP_DIR/migrations/"
    
    # Create symbolic link from /migrations to APP_DIR/migrations
    if [ -L "/migrations" ]; then
      rm -f /migrations
    elif [ -d "/migrations" ]; then
      rm -rf /migrations
    fi
    ln -sf "$APP_DIR/migrations" /migrations
    msg_ok "Migrations configured correctly"
  else
    msg_error "Migrations directory not found in source code!"
  fi
  
  # Install Cloudflare plugin for Certbot
  msg_info "Installing Cloudflare plugin for Certbot..."
  python3 -m pip install --no-cache-dir certbot-dns-cloudflare
  
  msg_ok "Environment configured"
}

# Build frontend
build_frontend() {
  msg_step "Building frontend"
  
  cd "/tmp/nginx-proxy-manager-${RELEASE}/frontend"
  
  # Check directory
  if [ ! -d "$(pwd)" ]; then
    msg_error "Frontend directory not found"
  fi
  
  msg_info "Installing frontend dependencies..."
  pnpm install
  
  if [ $? -ne 0 ]; then
    msg_error "Failed to install frontend dependencies"
  fi
  
  msg_info "Upgrading packages..."
  pnpm upgrade
  
  msg_info "Building frontend..."
  pnpm run build
  
  if [ $? -ne 0 ]; then
    msg_error "Failed to build frontend"
  fi
  
  # Copy files to application directory
  cp -r dist/* "$APP_DIR/frontend"
  cp -r app-images/* "$APP_DIR/frontend/images"
  
  msg_ok "Frontend built successfully"
}

# Initialize backend
initialize_backend() {
  msg_step "Initializing backend"
  
  msg_info "Configuring database configuration file..."
  
  # Remove default configuration if it exists
  if [ -f "$APP_DIR/config/default.json" ]; then
    rm -f "$APP_DIR/config/default.json"
  fi
  
  # Create production configuration
  mkdir -p "$APP_DIR/config"
  if [ ! -f "$APP_DIR/config/production.json" ]; then
    cat <<'EOF' > "$APP_DIR/config/production.json"
{
  "database": {
    "engine": "knex-native",
    "knex": {
      "client": "sqlite3",
      "connection": {
        "filename": "/data/database.sqlite"
      }
    }
  }
}
EOF
  fi
  
  # Install backend dependencies
  msg_info "Installing backend dependencies..."
  cd "$APP_DIR"
  pnpm install
  
  if [ $? -ne 0 ]; then
    msg_error "Failed to install backend dependencies"
  fi
  
  msg_ok "Backend initialized successfully"
}

# Configure systemd service for NPM
setup_systemd_service() {
  msg_step "Configuring systemd service"
  
  msg_info "Creating npm.service..."
  
  cat <<'EOF' > /lib/systemd/system/npm.service
[Unit]
Description=Nginx Proxy Manager
After=network.target

[Service]
Type=simple
Environment=NODE_ENV=production
ExecStartPre=/bin/mkdir -p /tmp/nginx/body
ExecStart=/usr/bin/node /app/index.js
WorkingDirectory=/app
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
  
  # Reload systemd configurations
  systemctl daemon-reload
  
  msg_ok "Systemd service configured"
}

# Adjust settings and permissions
adjust_permissions() {
  msg_step "Adjusting settings and permissions"
  
  # Adjust Nginx/Openresty settings
  msg_info "Adjusting user settings in nginx.conf..."
  sed -i 's/user npm/user root/g; s/^pid/#pid/g' /usr/local/openresty/nginx/conf/nginx.conf
  
  # Adjust logrotate configuration
  msg_info "Adjusting logrotate configuration..."
  sed -i 's/su npm npm/su root root/g' /etc/logrotate.d/nginx-proxy-manager
  
  # Adjust Certbot configuration if it exists
  if [ -f "/opt/certbot/pyvenv.cfg" ]; then
    msg_info "Adjusting Certbot configuration..."
    sed -i 's/include-system-site-packages = false/include-system-site-packages = true/g' /opt/certbot/pyvenv.cfg
  fi
  
  # Check and fix permissions
  msg_info "Adjusting directory permissions..."
  chmod -R 755 "$APP_DIR/migrations" 
  chmod -R 755 "$APP_DIR"
  chmod -R 755 "$DATA_DIR"
  chmod -R 777 /var/cache/nginx
  chmod 777 /tmp/nginx
  
  msg_ok "Permissions adjusted"
}

# Start services
start_services() {
  msg_step "Starting services"
  
  msg_info "Starting Openresty service..."
  systemctl enable --now openresty
  
  if [ $? -ne 0 ]; then
    msg_error "Failed to start Openresty service. Check logs with: journalctl -u openresty"
  fi
  
  # Wait a bit for Openresty to initialize
  sleep 2
  
  msg_info "Starting NPM service..."
  systemctl enable --now npm
  
  if [ $? -ne 0 ]; then
    msg_error "Failed to start NPM service. Check logs with: journalctl -u npm"
  fi
  
  # Wait a few seconds for the service to fully start
  sleep 5
  
  # Check if services are running
  if systemctl is-active --quiet openresty; then
    msg_ok "Openresty service is running"
  else
    msg_error "Openresty service did not start correctly"
  fi
  
  if systemctl is-active --quiet npm; then
    msg_ok "NPM service is running"
  else
    msg_error "NPM service did not start correctly"
  fi
  
  msg_ok "Services started successfully"
}

# Cleanup and finalization
cleanup() {
  msg_step "Cleaning temporary files"
  
  msg_info "Removing temporary files..."
  rm -rf /tmp/nginx-proxy-manager-*
  
  msg_ok "Cleanup completed"
}

# Verify installation
verify_installation() {
  msg_step "Verifying installation"
  
  # Check services
  msg_info "Checking service status..."
  
  if ! systemctl is-active --quiet openresty; then
    msg_error "Openresty service is not running!"
  fi
  
  if ! systemctl is-active --quiet npm; then
    msg_error "NPM service is not running!"
  fi
  
  # Check NPM logs for errors
  msg_info "Checking NPM logs for errors..."
  if journalctl -u npm --no-pager -n 50 | grep -q "error"; then
    msg_warn "Errors found in NPM logs:"
    journalctl -u npm --no-pager -n 10 | grep "error"
  else
    msg_ok "No errors found in NPM logs"
  fi
  
  # Check if port 81 is open
  msg_info "Checking if port 81 is open..."
  if ss -tuln | grep -q ":81 "; then
    msg_ok "Port 81 is open and ready for admin panel access"
  else
    msg_error "Port 81 is not open!"
  fi
  
  msg_ok "Verification completed. The installation appears to be working correctly."
}

# Main function
main() {
  echo -e "${YELLOW}===================================================${NC}"
  echo -e "${GREEN}    Nginx Proxy Manager Installation for Ubuntu 24.04    ${NC}"
  echo -e "${YELLOW}===================================================${NC}"
  
  # 1. Install dependencies
  install_dependencies
  
  # 2. Check existing services
  check_existing_services
  
  # 3. Clean previous installation
  clean_previous_installation
  
  # 4. Download and prepare NPM
  download_and_prepare_npm
  
  # 5. Build frontend
  build_frontend
  
  # 6. Initialize backend
  initialize_backend
  
  # 7. Configure systemd service
  setup_systemd_service
  
  # 8. Adjust permissions
  adjust_permissions
  
  # 9. Start services
  start_services
  
  # 10. Cleanup
  cleanup
  
  # 11. Verify installation
  verify_installation
  
  # Display access information
  IP=$(hostname -I | awk '{print $1}')
  echo -e "\n${GREEN}===================================================${NC}"
  echo -e "${GREEN}      Installation completed successfully!      ${NC}"
  echo -e "${GREEN}===================================================${NC}"
  echo -e "${YELLOW}Access Nginx Proxy Manager at:${NC}"
  echo -e "URL: ${GREEN}http://${IP}:81${NC}"
  echo -e "\n${YELLOW}Default credentials:${NC}"
  echo -e "Email: ${GREEN}admin@example.com${NC}"
  echo -e "Password: ${GREEN}changeme${NC}"
  echo -e "\n${YELLOW}Remember to change your password on first login!${NC}\n"
  echo -e "${YELLOW}Important: If you encounter any issues, check the logs with:${NC}"
  echo -e "${BLUE}sudo journalctl -u npm -f${NC}"
  echo -e "${GREEN}===================================================${NC}\n"
}

# Execute the script
main
