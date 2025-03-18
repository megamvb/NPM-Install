# Nginx Proxy Manager Installer for Ubuntu 24.04

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A robust installation script for Nginx Proxy Manager on Ubuntu 24.04. This script fixes common installation issues, particularly the migration directory problem that causes "Bad Gateway" errors.

## Features

- Complete installation of Nginx Proxy Manager on Ubuntu 24.04
- Fixes the migration issues that cause Bad Gateway errors
- Automated dependency installation including Node.js, Openresty, and Certbot
- Proper configuration of systemd services
- Intelligent cleanup of previous installations with database backup
- Comprehensive verification of the installation
- Detailed, color-coded logs of the installation process

## Requirements

- Ubuntu 24.04 LTS
- Root or sudo access
- Internet connection

## Quick Installation

```bash
# Download the script
wget https://raw.githubusercontent.com/agilehost-io/npm-installer/main/install-npm.sh

# Make it executable
chmod +x install-npm.sh

# Run with sudo
sudo ./install-npm.sh
```

## What's Included

The installation script handles everything needed to get Nginx Proxy Manager up and running:

1. Installs all required dependencies
2. Checks for and resolves conflicts with existing services
3. Downloads and configures the latest version of Nginx Proxy Manager
4. Properly sets up the database migrations (fixes common "Bad Gateway" errors)
5. Builds the frontend and initializes the backend
6. Creates and enables systemd services
7. Adjusts permissions and security settings
8. Verifies the installation is working correctly

## After Installation

After running the script, you can access the Nginx Proxy Manager admin interface at:

```
http://YOUR_SERVER_IP:81
```

Default login credentials:
- Email: `admin@example.com`
- Password: `changeme`

**Important:** Change your password immediately upon first login!

## Troubleshooting

If you encounter any issues:

1. Check the logs with: `sudo journalctl -u npm -f`
2. Ensure all required ports (80, 81, 443) are open and not used by other services
3. Verify that the system has sufficient resources (RAM, CPU, storage)

Common solutions:
- Restart the services: `sudo systemctl restart openresty npm`
- Check firewall settings: `sudo ufw status`

## Security Recommendations

After installation, consider:

1. Securing the admin interface by restricting IP access
2. Setting up HTTPS for the admin interface
3. Using strong passwords and regular updates
4. Setting up a firewall (UFW) to restrict access

## Additional Scripts

This repository also includes helpful scripts for:

- Restricting admin panel access to specific IPs
- Troubleshooting common issues
- Updating Nginx Proxy Manager

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Credits

Developed by [Marcos V Bohrer](https://github.com/marcosbohrer) at [AgileHost](https://www.agilehost.com.br).

Based on the original [Nginx Proxy Manager](https://nginxproxymanager.com/) project.

---

<p align="center">
  <a href="https://www.agilehost.com.br">
    <img src="https://www.agilehost.com.br/logo.png" alt="AgileHost" width="200">
  </a>
</p>
<p align="center">
  <i>Fast, reliable hosting solutions</i>
</p>
