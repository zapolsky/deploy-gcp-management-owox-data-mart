# OWOX Data Marts GCP Deployment Guide

Comprehensive deployment and management solution for OWOX Data Marts on Google Cloud Platform.
<div align="center">
  <img width="471" height="436" alt="image" src="https://github.com/user-attachments/assets/63ba03a8-9479-4d5a-b05a-dfa75d41a110" />
</div>

⭐ **Like this project?** [Star our awesome repo »](https://github.com/OWOX/owox-data-marts)

## Overview

This guide covers the `deploy-gcp.sh` script that provides a complete unified solution for deploying, managing, and maintaining OWOX Data Marts instances on GCP. It includes VM creation, authentication setup, version management, and cleanup operations.

## Features

### 🚀 **Deployment Options**
- **New OWOX Instance**: Complete deployment with VM creation, Node.js 22.x installation, and authentication setup
- **Public Access Deployment**: Deploy without authentication for development/testing
- **OWOX Version Selection**: Choose between stable (`owox`), next (`owox@next`), or custom versions
- **Automated Setup**: Nginx proxy, firewall rules, and systemd service configuration

### 🔐 **Authentication Management**
- **Basic Authentication**: Nginx-based login/password protection
- **Identity-Aware Proxy (IAP)**: Google Cloud IAM-based authentication (NOT RECOMMENDED FOR NON-DEVOPS USERS, many handly manual steps in gcp console)
- **Public API Access**: Always-accessible `/api/external/*` endpoints
- **Authentication Removal**: Convert protected instances to public access
- **Credential Management**: Automatic password generation or custom passwords

### 🔄 **Update & Maintenance**
- **OWOX Updates**: Update to stable, next, or specific versions
- **Service Management**: Safe stop/start with status verification
- **Version Checking**: View current installed versions
- **Health Testing**: Automatic service health checks after updates

### 🗑️ **Cleanup Operations**
- **Complete Removal**: Delete all OWOX resources (VM, firewall rules, etc.)
- **Authentication-Only Cleanup**: Remove auth while keeping VM running
- **Safety Confirmations**: Multiple confirmation steps to prevent accidental deletions

### 📋 **Management Tools**
- **Numbered Selection**: Easy project and VM selection by numbers
- **Status Monitoring**: View deployment status and resource information
- **Authentication Testing**: Verify auth setup and API accessibility
- **Resource Scanning**: Automatic detection of existing OWOX resources

## IMPORTANT

**IF YOU SETUP BASIC AUTHENTICATION AND AUTHENTICATION IS NOT WORKING, YOU NEED CREATE USER AGAIN USE THIS SCRIPT. SELECT 3 OPTION AND FOLLOW INSTRUCTIONS.**

## Prerequisites

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) installed and configured
- Active GCP project with billing enabled
- Authenticated with `gcloud auth login`
- Required APIs enabled (will be prompted if needed)

### OS Requirements

- macOS
- Linux
- Windows (WSL only)

### MacOS

Need to install coreutils for timeout command on macOS:

```bash
brew install coreutils
```

### Linux

Need to install timeout command:

```bash
sudo apt-get install timeout
```

## Quick Start

### Local Machine

1. **Make the script executable:**
   ```bash
   chmod +x deploy-gcp.sh
   ```

2. **Run the script:**
   ```bash
   ./deploy-gcp.sh
   ```

3. **Follow the interactive menu** to select your desired operation.

### Google Cloud Shell

**Google Cloud Shell** is the easiest way to run the deployment script as it comes pre-configured with `gcloud` CLI and proper authentication.

**IMPORTANT SSH Setup for Cloud Shell:**

If you encounter SSH connection issues or passphrase prompts, follow these steps to set up passwordless SSH:

### **SSH Key Setup (One-time)**

1. **Create SSH key without passphrase:**
   ```bash
   # Remove existing key if it has passphrase
   rm -f ~/.ssh/google_compute_engine ~/.ssh/google_compute_engine.pub
   
   # Create new key without passphrase (just press Enter when prompted)
   ssh-keygen -t rsa -f ~/.ssh/google_compute_engine -C "$(whoami)" -N ""
   ```

2. **Configure gcloud to use the key:**
   ```bash
   # This will automatically add your public key to project metadata
   gcloud compute config-ssh
   ```

3. **Test SSH connection:**
   ```bash
   # Replace with your actual instance name and zone
   gcloud compute ssh INSTANCE_NAME --zone=ZONE
   ```

### **Alternative: Use gcloud without manual SSH**

If you still have issues, our script automatically handles SSH through gcloud commands, so you shouldn't need manual SSH connection for most operations.

1. **Open Google Cloud Shell:**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Click the Cloud Shell icon (terminal) in the top-right corner
   - Wait for Cloud Shell to initialize

2. **Use bash command**
    ```bash
    bash <(curl -s https://raw.githubusercontent.com/zapolsky/deploy-gcp-management-owox-data-mart/refs/heads/main/deploy-gcp.sh)
    ```

OR

2. **Clone or upload the script:**
   ```bash
   # Option 1: If script is in a repository
   git clone https://github.com/zapolsky/deploy-gcp-management-owox-data-mart
   cd deploy-gcp-management-owox-data-mart
   
   # Option 2: Upload script directly
   # Use the upload button in Cloud Shell to upload deploy-gcp.sh
   ```

3. **Make the script executable:**
   ```bash
   chmod +x deploy-gcp.sh
   ```

4. **Run the deployment:**
   ```bash
   ./deploy-gcp.sh
   ```


**Benefits of using Cloud Shell:**
- ✅ No local gcloud installation required
- ✅ Automatic authentication with your Google account
- ✅ All required APIs and tools pre-installed
- ✅ Persistent storage for scripts and configurations
- ✅ Built-in code editor for script modifications
- ✅ No timeout command issues (like on macOS)

## Menu Options

```
🚀 DEPLOYMENT OPTIONS:
   1. Deploy new OWOX instance (VM + Authentication + IAP)
   2. Deploy OWOX without authentication (public access)

🔐 AUTHENTICATION OPTIONS:
   3. Configure Basic Authentication for existing VM
   4. Configure Identity-Aware Proxy (IAP) for existing VM
   5. Remove authentication (make public)

🔄 UPDATE OPTIONS:
   6. Update OWOX app on existing VM

🗑️ CLEANUP OPTIONS:
   7. Remove OWOX deployment (all resources)
   8. Remove only authentication (keep VM)

ℹ️ INFORMATION:
   9. Show deployment status
   10. Test authentication setup
   0. Exit
```

## Deployment Process

### New Instance Deployment

1. **Project Selection**: Choose from numbered list of available GCP projects
2. **Region Selection**: Select deployment region (US, Europe, Asia, or custom)
3. **OWOX Version**: Choose stable, next, or custom version
4. **VM Configuration**: Select machine type and disk size
5. **Authentication Setup**: Configure Basic Auth, IAP, or no authentication
6. **Automatic Setup**: VM creation, software installation, and service configuration

### OWOX Version Options

- **Stable (`owox`)**: Recommended for production use
- **Next (`owox@next`)**: Latest features and fixes
- **Custom**: Specify exact version (e.g., `owox@1.2.3`)

### VM Size Options

- **Small (e2-micro)**: 1 vCPU, 1GB RAM - Free tier eligible (very slow, not recommended)
- **Medium (e2-small)**: 1 vCPU, 2GB RAM
- **Large (e2-medium)**: 1 vCPU, 4GB RAM  (recommended)
- **Custom**: Specify machine type

## Authentication Methods

### Basic Authentication
- Nginx-based HTTP Basic Auth
- Multiple users supported
- Automatic or custom password generation
- Public API endpoints remain accessible

### Public Access
- No authentication required
- Suitable for development/testing
- All endpoints publicly accessible

## Update Process

The update functionality allows you to safely update OWOX on existing VMs:

1. **Version Selection**: Choose stable, next, specific version, or just check current version
2. **Service Management**: Automatic stop → update → start → verify
3. **Health Checking**: Verify service status and HTTP responses
4. **Rollback Safety**: Process includes error handling and status verification

## Resource Management

### Created Resources

When deploying a new instance, the script creates:

- **Compute Instance**: Debian 12 VM with Node.js 22.x and OWOX
- **Firewall Rules**: 
  - `owox-http-rule`: HTTP (port 80) access
  - `owox-https-rule`: HTTPS (port 443) access
- **Service Configuration**: Systemd service for auto-start
- **Nginx Proxy**: Reverse proxy with optional authentication

### Cleanup Options

- **Complete Cleanup**: Removes all OWOX-related resources
- **Auth-Only Cleanup**: Removes authentication but keeps VM running
- **Safety Measures**: Multiple confirmation prompts prevent accidental deletion

## API Access

### Public Endpoints
Always accessible without authentication:
- `http://your-vm-ip/api/external/*`

### Protected Endpoints
Require authentication when configured:
- `http://your-vm-ip/` (main application)
- All other endpoints

## Troubleshooting

### Common Issues

1. **SSH Connection Failures**
   - Ensure SSH keys are generated: `gcloud compute config-ssh`
   - Wait 2-3 minutes after VM creation for full startup
   - On macOS, install coreutils for better timeout handling: `brew install coreutils`

2. **Authentication Not Working**
   - Verify nginx configuration: `sudo nginx -t`
   - Check service status: `sudo systemctl status nginx owox`
   - Review logs: `sudo journalctl -u owox -f`

3. **Update Failures**
   - Check VM connectivity before updates
   - Verify sufficient disk space
   - Review update logs on VM: `cat ~/update-owox.log`

### Manual Commands

Connect to your VM:
```bash
gcloud compute ssh INSTANCE_NAME --zone=ZONE
```

Check OWOX status:
```bash
sudo systemctl status owox
owox --version
```

View logs:
```bash
sudo journalctl -u owox -f
sudo tail -f /var/log/owox-install.log
```

## Platform Compatibility

- **Linux**: Full support
- **macOS**: Full support (includes macOS-specific optimizations)
- **Windows**: Use WSL or Cloud Shell

### macOS Specific Features
- Automatic detection of `gtimeout` vs `timeout`
- Compatible `sed` syntax for in-place editing
- Brew installation suggestions for better tooling

## Security Considerations

- **Basic Auth**: Uses OpenSSL for password hashing (APR1)
- **Public API**: External API endpoints remain accessible for integrations
- **Firewall**: Only necessary ports (22, 80, 443) are opened
- **Service User**: OWOX runs under dedicated `owox` user account
- **Backup**: Nginx configs are backed up before modifications

## Cost Management

- **Free Tier**: e2-micro instances eligible for GCP free tier
- **Resource Cleanup**: Easy removal of all resources to avoid ongoing costs
- **Monitoring**: Use GCP Console to monitor actual costs

## Script Features

### Version Management
- **Installation**: Choose OWOX version during initial deployment
- **Updates**: Update existing installations to different versions
- **Verification**: Check current versions and test functionality

### Interactive Interface
- **Numbered Selection**: Projects and VMs selectable by number
- **Error Handling**: Comprehensive error messages and recovery options
- **Progress Tracking**: Real-time status updates during operations

### Cross-Platform Support
- **macOS Compatibility**: Handles macOS-specific command differences
- **Timeout Handling**: Graceful fallbacks for missing timeout commands
- **SSH Management**: Automatic SSH key setup guidance

## Support

For issues or feature requests:
1. Check the troubleshooting section above
2. Review GCP logs and service status
3. Ensure all prerequisites are met
4. Check the [OWOX Data Marts GitHub repository](https://github.com/OWOX/owox-data-marts) for additional documentation and support

---

⭐ **Like this project?** [Star our awesome repo »](https://github.com/OWOX/owox-data-marts)
