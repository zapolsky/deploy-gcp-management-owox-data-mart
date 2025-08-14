#!/bin/bash

# OWOX Data Marts GCP Management Script
# Unified script for deployment, authentication, and cleanup operations

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}$1${NC}"
}

print_menu() {
    echo -e "${CYAN}$1${NC}"
}

# Display main menu
show_main_menu() {
    clear
    print_header "╔══════════════════════════════════════════════════════════════╗"
    print_header "║               OWOX Data Marts GCP Manager v0.3.0             ║"
    print_header "║                                                              ║"
    print_header "║  Complete solution for OWOX deployment and management        ║"
    print_header "╚══════════════════════════════════════════════════════════════╝"
    echo
    
    print_menu "🚀 DEPLOYMENT OPTIONS:"
    echo "   1. Deploy new OWOX instance (VM + Authentication + IAP)"
    echo "   2. Deploy OWOX without authentication (public access)"
    echo
    
    print_menu "🔐 AUTHENTICATION OPTIONS:"
    echo "   3. Configure Basic Authentication for existing VM"
    echo "   4. Configure Identity-Aware Proxy (IAP) for existing VM"
    echo "   5. Remove authentication (make public)"
    echo
    
    print_menu "🔄 UPDATE OPTIONS:"
    echo "   6. Update OWOX app on existing VM"
    echo
    
    print_menu "🗑️  CLEANUP OPTIONS:"
    echo "   7. Remove OWOX deployment (all resources)"
    echo "   8. Remove only authentication (keep VM)"
    echo
    
    print_menu "ℹ️  INFORMATION:"
    echo "   9. Show deployment status"
    echo "   10. Test authentication setup"
    echo "   0. Exit"
    echo
}

# Check if gcloud is installed and authenticated
check_gcloud() {
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        print_error "You are not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check and setup SSH keys for Cloud Shell
    setup_ssh_keys
}

# Setup SSH keys without passphrase for Cloud Shell
setup_ssh_keys() {
    local ssh_key_path="$HOME/.ssh/google_compute_engine"
    
    # Check if we're in Cloud Shell environment
    if [[ -n "$CLOUD_SHELL" ]] || [[ "$HOME" == /home/* ]] && [[ -n "$DEVSHELL_PROJECT_ID" ]]; then
        print_info "Detected Cloud Shell environment"
        
        # Check if SSH key exists and has passphrase
        if [[ -f "$ssh_key_path" ]]; then
            # Test if key has passphrase by trying to load it
            if ! ssh-keygen -y -f "$ssh_key_path" &>/dev/null; then
                print_warning "SSH key has passphrase which may cause issues in Cloud Shell"
                read -p "Create new SSH key without passphrase? (Y/n): " CREATE_NEW_KEY
                
                if [[ ! "$CREATE_NEW_KEY" =~ ^[Nn]$ ]]; then
                    print_info "Creating new SSH key without passphrase..."
                    rm -f "$ssh_key_path" "${ssh_key_path}.pub"
                    ssh-keygen -t rsa -f "$ssh_key_path" -C "$(whoami)" -N "" -q
                    print_success "New SSH key created without passphrase"
                    
                    # Configure gcloud to use the new key
                    print_info "Configuring gcloud SSH..."
                    gcloud compute config-ssh --quiet &>/dev/null || true
                    print_success "SSH configuration updated"
                fi
            fi
        else
            # No SSH key exists, create one
            print_info "Creating SSH key for gcloud compute..."
            mkdir -p "$(dirname "$ssh_key_path")"
            ssh-keygen -t rsa -f "$ssh_key_path" -C "$(whoami)" -N "" -q
            print_success "SSH key created without passphrase"
            
            # Configure gcloud to use the new key
            print_info "Configuring gcloud SSH..."
            gcloud compute config-ssh --quiet &>/dev/null || true
            print_success "SSH configuration updated"
        fi
    fi
}

# Interactive project selection by number
select_project() {
    print_info "=== Project Selection ==="
    
    # Get projects and store in arrays
    local projects_data=$(gcloud projects list --format="value(projectId,name)")
    local project_ids=()
    local project_names=()
    local counter=1
    
    if [[ -z "$projects_data" ]]; then
        print_error "No projects found or access denied"
        return 1
    fi
    
    print_info "Available GCP projects:"
    echo
    
    # Parse projects and display numbered list
    while IFS=$'\t' read -r project_id project_name; do
        project_ids+=("$project_id")
        project_names+=("$project_name")
        printf "%2d. %-25s %s\n" "$counter" "$project_id" "$project_name"
        ((counter++))
    done <<< "$projects_data"
    
    echo
    local max_choice=$((counter - 1))
    
    while true; do
        read -p "Select project (1-$max_choice) or enter Project ID directly: " CHOICE
        
        # Check if input is a number
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [[ $CHOICE -ge 1 ]] && [[ $CHOICE -le $max_choice ]]; then
            # Number selection
            local index=$((CHOICE - 1))
            PROJECT_ID="${project_ids[$index]}"
            PROJECT_NAME="${project_names[$index]}"
            break
        elif [[ -n "$CHOICE" ]] && [[ ! "$CHOICE" =~ ^[0-9]+$ ]]; then
            # Direct Project ID input
            PROJECT_ID="$CHOICE"
            if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
                PROJECT_NAME=$(gcloud projects describe "$PROJECT_ID" --format="value(name)" 2>/dev/null || echo "Unknown")
                break
            else
                print_error "Project '$PROJECT_ID' does not exist or you don't have access"
                continue
            fi
        else
            print_error "Invalid selection. Please enter a number between 1 and $max_choice, or a valid Project ID"
            continue
        fi
    done
    
    gcloud config set project "$PROJECT_ID"
    print_success "Selected project: $PROJECT_ID ($PROJECT_NAME)"
    return 0
}

# Deployment functions (integrated from deploy-to-gcp.sh)

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local zone="$3"
    
    case "$resource_type" in
        "vm")
            gcloud compute instances describe "$resource_name" --zone="$zone" &>/dev/null
            ;;
        "firewall")
            gcloud compute firewall-rules describe "$resource_name" &>/dev/null
            ;;
        "instance-group")
            gcloud compute instance-groups describe "$resource_name" --zone="$zone" &>/dev/null
            ;;
        "health-check")
            gcloud compute health-checks describe "$resource_name" &>/dev/null
            ;;
        "backend-service")
            gcloud compute backend-services describe "$resource_name" --global &>/dev/null
            ;;
        "url-map")
            gcloud compute url-maps describe "$resource_name" --global &>/dev/null
            ;;
        "ssl-cert")
            gcloud compute ssl-certificates describe "$resource_name" --global &>/dev/null
            ;;
        "target-proxy-http")
            gcloud compute target-http-proxies describe "$resource_name" --global &>/dev/null
            ;;
        "target-proxy-https")
            gcloud compute target-https-proxies describe "$resource_name" --global &>/dev/null
            ;;
        "forwarding-rule")
            gcloud compute forwarding-rules describe "$resource_name" --global &>/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Interactive region selection
select_region() {
    print_info "Popular regions:"
    echo "1. us-central1-a (Iowa, USA)"
    echo "2. europe-west1-b (Belgium, Europe)"
    echo "3. asia-east1-a (Taiwan, Asia)"
    echo "4. Custom region"
    
    read -p "Select region (1-4): " REGION_CHOICE
    
    case $REGION_CHOICE in
        1) ZONE="us-central1-a" ;;
        2) ZONE="europe-west1-b" ;;
        3) ZONE="asia-east1-a" ;;
        4) 
            read -p "Enter custom zone (e.g., us-west1-a): " ZONE
            ;;
        *) 
            print_error "Invalid choice"
            exit 1
            ;;
    esac
    
    print_success "Zone set to: $ZONE"
}

# Interactive OWOX version selection
select_owox_version() {
    print_info "=== OWOX Version Selection ==="
    echo "1. Stable version (owox) - recommended for production"
    echo "2. Next version (owox@next) - latest features and fixes"
    echo "3. Custom version"
    
    read -p "Select OWOX version (1-3): " VERSION_CHOICE
    
    case $VERSION_CHOICE in
        1) 
            OWOX_PACKAGE="owox"
            print_success "Selected: Stable version (owox)"
            ;;
        2) 
            OWOX_PACKAGE="owox@next"
            print_success "Selected: Next version (owox@next)"
            ;;
        3) 
            read -p "Enter custom version (e.g., owox@1.2.3): " OWOX_PACKAGE
            if [[ -z "$OWOX_PACKAGE" ]]; then
                print_error "Version cannot be empty"
                exit 1
            fi
            print_success "Selected: Custom version ($OWOX_PACKAGE)"
            ;;
        *) 
            print_error "Invalid choice. Using stable version."
            OWOX_PACKAGE="owox"
            ;;
    esac
}

# Interactive VM configuration
configure_vm() {
    print_info "VM Configuration Options:"
    echo "1. Small (e2-micro, 1 vCPU, 1GB RAM) - Free tier eligible"
    echo "2. Medium (e2-small, 1 vCPU, 2GB RAM)"
    echo "3. Large (e2-medium, 1 vCPU, 4GB RAM)"
    echo "4. Custom"
    
    read -p "Select VM size (1-4): " VM_CHOICE
    
    case $VM_CHOICE in
        1) MACHINE_TYPE="e2-micro" ;;
        2) MACHINE_TYPE="e2-small" ;;
        3) MACHINE_TYPE="e2-medium" ;;
        4) 
            read -p "Enter custom machine type (e.g., e2-standard-2): " MACHINE_TYPE
            ;;
        *) 
            print_error "Invalid choice"
            exit 1
            ;;
    esac
    
    read -p "Enter VM instance name [owox-data-marts]: " INSTANCE_NAME
    INSTANCE_NAME=${INSTANCE_NAME:-owox-data-marts}
    
    read -p "Enter boot disk size in GB [20]: " DISK_SIZE
    DISK_SIZE=${DISK_SIZE:-20}
    
    print_success "VM Configuration:"
    print_success "  Instance name: $INSTANCE_NAME"
    print_success "  Machine type: $MACHINE_TYPE"
    print_success "  Disk size: ${DISK_SIZE}GB"
}

# Create startup script
create_startup_script() {
    cat > startup-script.sh << EOF
#!/bin/bash

# Update system
apt-get update -y
apt-get install -y curl wget gnupg software-properties-common nginx

# Install Node.js 22.x (required by the project)
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

# Verify installation
node --version
npm --version

# Install OWOX globally (version: $OWOX_PACKAGE)
npm install -g $OWOX_PACKAGE
echo "Installed OWOX package: $OWOX_PACKAGE" >> /var/log/owox-install.log

# Create owox user
useradd -m -s /bin/bash owox
mkdir -p /home/owox/.owox

# Create systemd service for auto-start (using port 3000)
cat > /etc/systemd/system/owox.service << 'SERVICE_EOF'
[Unit]
Description=OWOX Data Marts Service
After=network.target

[Service]
Type=simple
User=owox
WorkingDirectory=/home/owox
ExecStart=/usr/bin/owox serve --port 3000
Restart=always
RestartSec=10
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Create basic nginx configuration (will be updated based on auth method)
cat > /etc/nginx/sites-available/owox << 'NGINX_EOF'
server {
    listen 80;
    server_name _;
    
    # External API access for all users (always public)
    location /api/external/ {
        proxy_pass http://localhost:3000/api/external/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
    
    # All other traffic (auth will be added later if needed)
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINX_EOF

# Configure nginx
ln -sf /etc/nginx/sites-available/owox /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Enable and start services
systemctl daemon-reload
systemctl enable owox
systemctl enable nginx
systemctl start owox
systemctl restart nginx

# Configure firewall (if ufw is available)
if command -v ufw &> /dev/null; then
    ufw --force enable
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
fi

# Log installation completion
echo "OWOX installation completed at \$(date)" >> /var/log/owox-install.log
echo "OWOX running on port 3000, proxied through nginx on port 80" >> /var/log/owox-install.log
EOF
}

deploy_new_instance() {
    print_info "=== OWOX Data Marts GCP Deployment Script ==="
    
    if ! select_project; then
        return 1
    fi
    
    select_region
    select_owox_version
    configure_vm
    
    # Create and deploy
    create_firewall_rules
    create_vm
    get_vm_info
    wait_for_vm_ready
    select_auth_method
    apply_auth_configuration
    display_access_info
    
    print_success "=== Deployment Complete ==="
    print_info "OWOX should now be operational and properly configured"
}

# Safe resource creation with cleanup option
create_or_recreate_vm() {
    if resource_exists "vm" "$INSTANCE_NAME" "$ZONE"; then
        print_warning "VM instance '$INSTANCE_NAME' already exists in zone '$ZONE'"
        echo "Current VM status:"
        gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="table(name,status,machineType.basename(),networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)"
        
        echo
        print_error "⚠️  WARNING: Recreating VM will DELETE all data on the instance!"
        read -p "Do you want to recreate the VM? (y/N): " RECREATE_VM
        
        if [[ "$RECREATE_VM" =~ ^[Yy]$ ]]; then
            print_info "Deleting existing VM instance..."
            gcloud compute instances delete "$INSTANCE_NAME" --zone="$ZONE" --quiet
            print_success "VM instance deleted"
            create_vm_instance
        else
            print_info "Keeping existing VM instance"
            return 0
        fi
    else
        create_vm_instance
    fi
}

# Create VM instance (separated from main create_vm function)
create_vm_instance() {
    print_info "Creating VM instance: $INSTANCE_NAME"
    
    create_startup_script
    
    gcloud compute instances create "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --machine-type="$MACHINE_TYPE" \
        --network-tier=PREMIUM \
        --maintenance-policy=MIGRATE \
        --provisioning-model=STANDARD \
        --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append \
        --tags=owox-server,http-server,https-server \
        --create-disk=auto-delete=yes,boot=yes,device-name="$INSTANCE_NAME",image=projects/debian-cloud/global/images/family/debian-12,mode=rw,size="$DISK_SIZE",type=projects/"$PROJECT_ID"/zones/"$ZONE"/diskTypes/pd-standard \
        --no-shielded-secure-boot \
        --shielded-vtpm \
        --shielded-integrity-monitoring \
        --labels=environment=production,application=owox \
        --reservation-affinity=any \
        --metadata-from-file startup-script=startup-script.sh
    
    print_success "VM instance created: $INSTANCE_NAME"
    
    # Clean up startup script
    rm -f startup-script.sh
}

# Create firewall rule for HTTP traffic
create_firewall_rules() {
    print_info "Creating firewall rules..."
    
    # Allow HTTP traffic
    if resource_exists "firewall" "owox-http-rule"; then
        print_info "Firewall rule 'owox-http-rule' already exists"
    else
        gcloud compute firewall-rules create owox-http-rule \
            --allow tcp:80 \
            --source-ranges 0.0.0.0/0 \
            --description "Allow HTTP traffic to OWOX" \
            --target-tags owox-server
        print_success "HTTP firewall rule created"
    fi
    
    # Allow HTTPS traffic
    if resource_exists "firewall" "owox-https-rule"; then
        print_info "Firewall rule 'owox-https-rule' already exists"
    else
        gcloud compute firewall-rules create owox-https-rule \
            --allow tcp:443 \
            --source-ranges 0.0.0.0/0 \
            --description "Allow HTTPS traffic to OWOX" \
            --target-tags owox-server
        print_success "HTTPS firewall rule created"
    fi
    
    print_success "Firewall rules configured"
}

# Create the VM instance (now calls the safe version)
create_vm() {
    create_or_recreate_vm
}

# Get VM external IP
get_vm_info() {
    print_info "Getting VM information..."
    
    EXTERNAL_IP=$(gcloud compute instances describe "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --format='get(networkInterfaces[0].accessConfigs[0].natIP)')
    
    print_success "VM Details:"
    print_success "  Name: $INSTANCE_NAME"
    print_success "  Zone: $ZONE"
    print_success "  External IP: $EXTERNAL_IP"
    print_success "  Machine Type: $MACHINE_TYPE"
    print_info "OWOX will be available at: http://$EXTERNAL_IP"
    print_info "External API will be accessible at: http://$EXTERNAL_IP/api/external/*"
}

# Test VM readiness with comprehensive checks
test_vm_ready() {
    print_info "Verifying VM readiness for configuration..."
    
    # Step 1: Test basic SSH connectivity 
    local ssh_ready=false
    local ssh_attempts=3
    
    for ((i=1; i<=ssh_attempts; i++)); do
        print_info "SSH connectivity test $i/$ssh_attempts..."
        
        # Use gtimeout on macOS if available, otherwise fallback to basic test
        local timeout_cmd="timeout"
        if command -v gtimeout &> /dev/null; then
            timeout_cmd="gtimeout"
        elif ! command -v timeout &> /dev/null; then
            timeout_cmd=""
        fi
        
        local ssh_result=false
        if [[ -n "$timeout_cmd" ]]; then
            if $timeout_cmd 20 gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" \
               --command="echo 'SSH connection successful'" --quiet 2>/dev/null; then
                ssh_result=true
            fi
        else
            # Fallback without timeout for macOS without gtimeout
            if gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" \
               --command="echo 'SSH connection successful'" --quiet 2>/dev/null; then
                ssh_result=true
            fi
        fi
        
        if [[ "$ssh_result" == true ]]; then
            print_success "SSH connection established!"
            ssh_ready=true
            break
        else
            if [[ $i -lt $ssh_attempts ]]; then
                print_warning "SSH attempt $i failed, retrying in 15 seconds..."
                sleep 15
            fi
        fi
    done
    
    if [[ "$ssh_ready" == false ]]; then
        print_error "Cannot establish SSH connection after $ssh_attempts attempts"
        return 1
    fi
    
    return 0
}

# Smart VM readiness check
wait_for_vm_ready() {
    print_info "Waiting for VM to be ready..."
    sleep 60  # Initial wait for VM to boot
    
    if test_vm_ready; then
        return 0
    else
        print_info "VM not quite ready - waiting 2 more minutes..."
        sleep 120
        test_vm_ready
    fi
}

# Select authentication method
select_auth_method() {
    if [[ -n "$AUTH_METHOD" ]]; then
        # Auth method already set (e.g., for public deployment)
        return 0
    fi
    
    print_info "=== Authentication Configuration ==="
    print_info "Choose authentication method for OWOX access:"
    echo "1. No authentication (public access - NOT recommended for production)"
    echo "2. Basic Authentication (nginx login/password)"
    echo "3. Identity-Aware Proxy (Google SSO)"
    echo "4. Both Basic Auth + IAP (maximum security)"
    
    read -p "Select authentication method (1-4): " AUTH_CHOICE
    
    case $AUTH_CHOICE in
        1) 
            AUTH_METHOD="none"
            print_warning "Selected: No authentication (public access)"
            ;;
        2) 
            AUTH_METHOD="basic"
            print_success "Selected: Basic Authentication"
            ;;
        3) 
            AUTH_METHOD="iap"
            print_success "Selected: Identity-Aware Proxy"
            ;;
        4) 
            AUTH_METHOD="both"
            print_success "Selected: Both Basic Auth + IAP"
            ;;
        *) 
            print_error "Invalid choice. Defaulting to Basic Authentication"
            AUTH_METHOD="basic"
            ;;
    esac
}

# Apply authentication configuration
apply_auth_configuration() {
    case "$AUTH_METHOD" in
        "none")
            print_info "No authentication configured - all endpoints are public"
            ;;
        "basic")
            configure_basic_auth
            ;;
        "iap")
            print_info "IAP configuration requires the full deploy-to-gcp.sh script"
            print_info "This simplified version only supports basic auth"
            ;;
        "both")
            print_info "Combined auth requires the full deploy-to-gcp.sh script"
            print_info "This simplified version only supports basic auth"
            configure_basic_auth
            ;;
    esac
}

# Display final access information
display_access_info() {
    print_success "=== Access Information ==="
    
    local auth_info=""
    case "$AUTH_METHOD" in
        "none")
            auth_info="No authentication required"
            ;;
        "basic")
            auth_info="Basic Authentication required"
            ;;
        "iap")
            auth_info="Google IAP authentication required"
            ;;
        "both")
            auth_info="Both Basic Auth + Google IAP required"
            ;;
    esac
    
    # Direct VM access
    print_success "🔐 OWOX Access: http://$EXTERNAL_IP/ ($auth_info)"
    print_success "🌐 Public API: http://$EXTERNAL_IP/api/external/* (always public)"
    
    # Display credentials if basic auth was configured
    if [[ "$AUTH_METHOD" == "basic" || "$AUTH_METHOD" == "both" ]] && [[ -n "$USER_CREDENTIALS" ]]; then
        print_info "=== Basic Auth Credentials ==="
        IFS=',' read -ra CREDS <<< "$USER_CREDENTIALS"
        for cred in "${CREDS[@]}"; do
            IFS=':' read -ra USER_PASS <<< "$cred"
            print_success "Username: ${USER_PASS[0]} | Password: ${USER_PASS[1]}"
        done
        print_warning "Save these credentials securely!"
    fi
}

deploy_new_instance() {
    print_info "=== OWOX Data Marts GCP Deployment Script ==="
    
    if ! select_project; then
        return 1
    fi
    
    select_region
    select_owox_version
    configure_vm
    
    # Create and deploy
    create_firewall_rules
    create_vm
    get_vm_info
    wait_for_vm_ready
    select_auth_method
    apply_auth_configuration
    display_access_info
    
    print_success "=== Deployment Complete ==="
    print_info "OWOX should now be operational and properly configured"
}

deploy_public_instance() {
    print_info "Starting new OWOX deployment (public access)..."
    print_warning "This will create a VM without any authentication"
    read -p "Are you sure? (y/N): " CONFIRM
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Deployment cancelled"
        return 0
    fi
    
    # Set auth method to none and deploy
    AUTH_METHOD="none"
    deploy_new_instance
}

# Simplified Basic Auth for Cloud Shell
configure_basic_auth_simple() {
    print_info "=== Cloud Shell Basic Authentication Setup ==="
    
    # Create a default admin user
    local DEFAULT_USERNAME="admin"
    local DEFAULT_PASSWORD=$(openssl rand -base64 12)
    
    print_info "Creating default admin user for Cloud Shell..."
    print_success "Username: $DEFAULT_USERNAME"
    print_success "Password: $DEFAULT_PASSWORD"
    
    read -p "Use these credentials? (Y/n): " USE_DEFAULT
    
    local USERNAME="$DEFAULT_USERNAME"
    local PASSWORD="$DEFAULT_PASSWORD"
    
    if [[ "$USE_DEFAULT" =~ ^[Nn]$ ]]; then
        read -p "Enter username: " USERNAME
        if [[ -z "$USERNAME" ]]; then
            USERNAME="admin"
        fi
        
        read -p "Generate random password? (Y/n): " RANDOM_PASS
        if [[ "$RANDOM_PASS" =~ ^[Nn]$ ]]; then
            read -s -p "Enter password: " PASSWORD
            echo
        else
            PASSWORD=$(openssl rand -base64 12)
            print_success "Generated password: $PASSWORD"
        fi
    fi
    
    # Create htpasswd entry
    local HASH=$(openssl passwd -apr1 "$PASSWORD")
    local users_config="$USERNAME:$HASH"
    
    # Store credentials for display
    USER_CREDENTIALS="$USERNAME:$PASSWORD"
    
    print_info "Creating authentication configuration..."
    
    # Create the remote script directly
    cat > configure-auth-remote.sh << EOF
#!/bin/bash

# Backup current nginx config
cp /etc/nginx/sites-available/owox /etc/nginx/sites-available/owox.backup

# Create htpasswd file
cat > /etc/nginx/.htpasswd << 'HTPASSWD_EOF'
$users_config
HTPASSWD_EOF

# Update nginx configuration to include basic auth
# Remove any existing auth_basic lines first
sed -i '/auth_basic/d' /etc/nginx/sites-available/owox

# Create a new nginx config with basic auth using a more reliable method
cp /etc/nginx/sites-available/owox /tmp/owox.tmp

# Insert auth_basic lines after the main location / { line
sed '/location \/ {/a\
        auth_basic "OWOX Access Required";\
        auth_basic_user_file /etc/nginx/.htpasswd;' /tmp/owox.tmp > /etc/nginx/sites-available/owox

# Clean up temp file
rm -f /tmp/owox.tmp

# Test nginx configuration
if nginx -t; then
    systemctl reload nginx
    echo "SUCCESS: Basic authentication configured and nginx reloaded"
else
    echo "ERROR: Nginx configuration test failed"
    # Restore backup
    cp /etc/nginx/sites-available/owox.backup /etc/nginx/sites-available/owox
    echo "Restored backup configuration"
    exit 1
fi
EOF
    
    # Upload and execute
    print_info "Uploading configuration to VM..."
    if ! gcloud compute scp configure-auth-remote.sh "$INSTANCE_NAME":~/configure-auth-remote.sh --zone="$ZONE" --quiet; then
        print_error "Failed to upload configuration"
        rm -f configure-auth-remote.sh
        return 1
    fi
    
    print_info "Configuring authentication on VM..."
    if gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --quiet \
       --command="sudo bash ~/configure-auth-remote.sh && rm ~/configure-auth-remote.sh"; then
        print_success "Basic authentication configured successfully!"
    else
        print_error "Failed to configure authentication"
        rm -f configure-auth-remote.sh
        return 1
    fi
    
    rm -f configure-auth-remote.sh
    
    # Test authentication
    print_info "Testing authentication..."
    local auth_test=$(gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --quiet \
        --command="curl -s -o /dev/null -w '%{http_code}' http://localhost/ 2>/dev/null" 2>/dev/null)
    
    if [[ "$auth_test" == "401" ]]; then
        print_success "✅ Authentication is working correctly"
    else
        print_warning "⚠️ Authentication test returned: $auth_test"
    fi
}

# Configure Basic Authentication (integrated from configure-owox-auth.sh)
configure_basic_auth() {
    print_info "=== Configuring Basic Authentication ==="
    
    # Check if we're in Cloud Shell and use simplified approach
    if [[ -n "$CLOUD_SHELL" ]] || [[ "$HOME" == /home/* ]] && [[ -n "$DEVSHELL_PROJECT_ID" ]]; then
        print_warning "Detected Cloud Shell - using simplified user creation"
        configure_basic_auth_simple
        return
    fi
    
    # Generate htpasswd content on local machine then upload to VM
    print_info "Creating nginx basic authentication users..."
    
    local users_config=""
    local user_count=0
    
    while true; do
        echo
        echo -n "Enter username (or press Enter to finish): "
        read USERNAME
        
        
        if [[ -z "$USERNAME" ]]; then
            if [[ $user_count -eq 0 ]]; then
                print_error "At least one user is required"
                continue
            else
                break
            fi
        fi
        
        
        # Validate username (alphanumeric and underscore only)
        if [[ ! "$USERNAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
            print_error "Username must contain only alphanumeric characters and underscores"
            continue
        fi
        
        # Generate random password or ask for custom
        echo "Password options for '$USERNAME':"
        echo "  1. Generate random password (recommended)"
        echo "  2. Enter custom password"
        read -p "Choose option (1-2): " PASSWORD_CHOICE
        
        case $PASSWORD_CHOICE in
            1)
                PASSWORD=$(openssl rand -base64 12)
                print_success "Generated password for '$USERNAME': $PASSWORD"
                ;;
            2)
                while true; do
                    read -s -p "Enter password for '$USERNAME': " PASSWORD
                    echo
                    if [[ ${#PASSWORD} -lt 6 ]]; then
                        print_error "Password must be at least 6 characters long"
                        continue
                    fi
                    read -s -p "Confirm password: " PASSWORD_CONFIRM
                    echo
                    if [[ "$PASSWORD" != "$PASSWORD_CONFIRM" ]]; then
                        print_error "Passwords don't match. Try again."
                        continue
                    fi
                    break
                done
                ;;
            *)
                print_error "Invalid option. Using random password."
                PASSWORD=$(openssl rand -base64 12)
                print_success "Generated password for '$USERNAME': $PASSWORD"
                ;;
        esac
        
        # Create htpasswd entry (using OpenSSL for portability)
        local HASH=$(openssl passwd -apr1 "$PASSWORD")
        users_config+="$USERNAME:$HASH\n"
        
        print_success "Added user: $USERNAME"
        ((user_count++))
        
        # Store credentials for later display
        if [[ -z "$USER_CREDENTIALS" ]]; then
            USER_CREDENTIALS="$USERNAME:$PASSWORD"
        else
            USER_CREDENTIALS="$USER_CREDENTIALS,$USERNAME:$PASSWORD"
        fi
        
        # Debug: Confirm loop continuation
        print_info "User added successfully. Total users: $user_count"
        echo "Continuing to next user prompt..."
        
        # Flush output to ensure it's displayed
        exec 1>&1
        sleep 0.5
    done
    
    # Validate that we have users configured
    if [[ $user_count -eq 0 ]]; then
        print_error "No users were configured"
        return 1
    fi
    
    print_info "Created $user_count user(s) for basic authentication"
    
    # Create and upload configuration script
    print_info "Configuring basic authentication on VM..."
    
    cat > configure-auth-remote.sh << 'AUTH_SCRIPT_EOF'
#!/bin/bash

# Backup current nginx config
cp /etc/nginx/sites-available/owox /etc/nginx/sites-available/owox.backup

# Create htpasswd file
cat > /etc/nginx/.htpasswd << 'HTPASSWD_EOF'
USERS_PLACEHOLDER
HTPASSWD_EOF

# Update nginx configuration to include basic auth
# Remove any existing auth_basic lines first
sed -i '/auth_basic/d' /etc/nginx/sites-available/owox

# Add auth_basic after the "location /" line but before proxy directives
sed -i '/location \/ {/a\        auth_basic "OWOX Access Required";\
        auth_basic_user_file /etc/nginx/.htpasswd;' /etc/nginx/sites-available/owox

# Test nginx configuration
if nginx -t; then
    systemctl reload nginx
    echo "SUCCESS: Basic authentication configured and nginx reloaded"
else
    echo "ERROR: Nginx configuration test failed"
    # Restore backup
    cp /etc/nginx/sites-available/owox.backup /etc/nginx/sites-available/owox
    echo "Restored backup configuration"
    exit 1
fi
AUTH_SCRIPT_EOF
    
    # Replace placeholder with actual users
    # Use different approach for sed that works better in Cloud Shell
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS version
        sed -i '' "s|USERS_PLACEHOLDER|$(echo -e "$users_config")|g" configure-auth-remote.sh
    else
        # Linux/Cloud Shell version
        local temp_file=$(mktemp)
        awk -v users="$(echo -e "$users_config")" '{gsub(/USERS_PLACEHOLDER/, users); print}' configure-auth-remote.sh > "$temp_file"
        mv "$temp_file" configure-auth-remote.sh
    fi
    
    # Debug: Show what we're about to upload
    print_info "Generated authentication script:"
    echo "--- Script content preview ---"
    head -n 20 configure-auth-remote.sh
    echo "--- End preview ---"
    
    # Upload and execute on VM
    print_info "Uploading authentication configuration to VM..."
    if gcloud compute scp configure-auth-remote.sh "$INSTANCE_NAME":~/configure-auth-remote.sh --zone="$ZONE" --quiet; then
        print_success "Configuration uploaded to VM"
    else
        print_error "Failed to upload configuration to VM"
        print_error "This might be due to SSH connectivity issues"
        print_info "Try manually: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
        rm -f configure-auth-remote.sh
        return 1
    fi
    
    print_info "Executing authentication setup on VM..."
    print_info "This may take a few seconds..."
    
    # Execute with more verbose output
    if gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --quiet \
       --command="set -x; sudo bash ~/configure-auth-remote.sh 2>&1; echo 'Exit code:' \$?; rm -f ~/configure-auth-remote.sh"; then
        print_success "Basic authentication configured successfully!"
    else
        print_error "Failed to configure basic authentication on VM"
        print_info "Debugging steps:"
        print_info "1. Check VM status: gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE"
        print_info "2. Test SSH manually: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
        print_info "3. Check nginx status: sudo systemctl status nginx"
        rm -f configure-auth-remote.sh
        return 1
    fi
    
    # Clean up local file
    rm -f configure-auth-remote.sh
    
    # Test the configuration
    print_info "Testing authentication setup..."
    local auth_test=$(gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --quiet \
        --command="curl -s -o /dev/null -w '%{http_code}' http://localhost/ 2>/dev/null" 2>/dev/null)
    
    if [[ "$auth_test" == "401" ]]; then
        print_success "✅ Authentication is working correctly (401 Unauthorized)"
    else
        print_warning "⚠️ Authentication test returned: $auth_test (expected: 401)"
    fi
    
    # Test that public API still works
    local api_test=$(gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --quiet \
        --command="curl -s -o /dev/null -w '%{http_code}' http://localhost/api/external/ 2>/dev/null" 2>/dev/null)
    
    if [[ "$api_test" == "200" ]]; then
        print_success "✅ Public API is accessible (200 OK)"
    else
        print_warning "⚠️ Public API test returned: $api_test (expected: 200)"
    fi
}

# Update OWOX app on existing VM
update_owox_app() {
    print_info "=== Update OWOX Application ==="
    
    # Select project and VM
    if ! select_project; then
        return 1
    fi
    
    if ! select_vm_for_config; then
        return 1
    fi
    
    # Select OWOX version for update
    print_info "=== OWOX Version Selection for Update ==="
    echo "1. Update to stable version (owox@latest)"
    echo "2. Update to next version (owox@next)"
    echo "3. Update to specific version"
    echo "4. Check current version only"
    
    read -p "Select option (1-4): " UPDATE_CHOICE
    
    case $UPDATE_CHOICE in
        1) 
            UPDATE_PACKAGE="owox@latest"
            print_success "Selected: Update to stable version (owox@latest)"
            ;;
        2) 
            UPDATE_PACKAGE="owox@next"
            print_success "Selected: Update to next version (owox@next)"
            ;;
        3) 
            read -p "Enter specific version (e.g., owox@1.2.3): " UPDATE_PACKAGE
            if [[ -z "$UPDATE_PACKAGE" ]]; then
                print_error "Version cannot be empty"
                return 1
            fi
            print_success "Selected: Update to specific version ($UPDATE_PACKAGE)"
            ;;
        4)
            print_info "Checking current OWOX version..."
            local current_version=$(gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --quiet \
                --command="owox --version 2>/dev/null || echo 'Version check failed'" 2>/dev/null)
            
            if [[ "$current_version" == "Version check failed" ]]; then
                print_error "Could not retrieve OWOX version"
                print_info "OWOX might not be installed or not responding"
            else
                print_success "Current OWOX version: $current_version"
            fi
            
            # Check npm package info
            local npm_info=$(gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --quiet \
                --command="npm list -g owox 2>/dev/null || echo 'NPM info failed'" 2>/dev/null)
            
            if [[ "$npm_info" != "NPM info failed" ]]; then
                print_info "NPM package info:"
                echo "$npm_info"
            fi
            
            return 0
            ;;
        *) 
            print_error "Invalid choice"
            return 1
            ;;
    esac
    
    # Create update script
    print_info "Creating update script..."
    cat > update-owox.sh << 'UPDATE_SCRIPT_EOF'
#!/bin/bash

echo "=== OWOX Update Process Started at $(date) ==="

# Check current version
echo "Current OWOX version:"
owox --version 2>/dev/null || echo "Could not get current version"

echo "Current npm package info:"
npm list -g owox 2>/dev/null || echo "Package not found in global npm"

# Stop OWOX service
echo "Stopping OWOX service..."
systemctl stop owox || echo "Failed to stop owox service"

# Update OWOX package
echo "Updating OWOX package to: UPDATE_PACKAGE_PLACEHOLDER"
npm install -g UPDATE_PACKAGE_PLACEHOLDER

# Verify installation
echo "Verifying new installation..."
owox --version || echo "Version check failed after update"

# Start OWOX service
echo "Starting OWOX service..."
systemctl start owox

# Check service status
echo "OWOX service status:"
systemctl status owox --no-pager -l

# Wait a moment for service to start
sleep 5

# Test if OWOX is responding
echo "Testing OWOX response..."
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:3000 2>/dev/null || echo "OWOX test failed"

echo "=== OWOX Update Process Completed at $(date) ==="
UPDATE_SCRIPT_EOF
    
    # Replace placeholder with actual package
    sed -i '' "s|UPDATE_PACKAGE_PLACEHOLDER|$UPDATE_PACKAGE|g" update-owox.sh
    
    # Upload and execute update script
    print_info "Uploading update script to VM..."
    if ! gcloud compute scp update-owox.sh "$INSTANCE_NAME":~/update-owox.sh --zone="$ZONE" --quiet; then
        print_error "Failed to upload update script"
        rm -f update-owox.sh
        return 1
    fi
    
    print_info "Executing update on VM..."
    print_warning "This may take a few minutes. The OWOX service will be temporarily unavailable."
    
    if gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --quiet \
       --command="sudo bash ~/update-owox.sh 2>&1 | tee ~/update-owox.log && rm ~/update-owox.sh"; then
        print_success "OWOX update completed successfully!"
        
        # Show update results
        print_info "Update results:"
        local update_log=$(gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --quiet \
            --command="tail -10 ~/update-owox.log 2>/dev/null" 2>/dev/null)
        
        if [[ -n "$update_log" ]]; then
            echo "$update_log"
        fi
        
        # Test the updated installation
        print_info "Testing updated OWOX installation..."
        local new_version=$(gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --quiet \
            --command="owox --version 2>/dev/null" 2>/dev/null)
        
        if [[ -n "$new_version" ]]; then
            print_success "✅ OWOX is running with version: $new_version"
        else
            print_warning "⚠️ Could not verify OWOX version after update"
        fi
        
        # Test HTTP response
        local http_test=$(gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --quiet \
            --command="curl -s -o /dev/null -w '%{http_code}' http://localhost 2>/dev/null" 2>/dev/null)
        
        if [[ "$http_test" == "200" || "$http_test" == "401" ]]; then
            print_success "✅ OWOX HTTP service is responding (status: $http_test)"
        else
            print_warning "⚠️ OWOX HTTP service test returned: $http_test"
        fi
        
    else
        print_error "OWOX update failed"
        print_info "You can check the update log manually:"
        print_info "  gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
        print_info "  cat ~/update-owox.log"
        
        # Clean up
        rm -f update-owox.sh
        return 1
    fi
    
    # Clean up local file
    rm -f update-owox.sh
    
    print_success "🎉 OWOX update process completed!"
    print_info "The OWOX application has been updated to: $UPDATE_PACKAGE"
    print_info "Service should be running normally now."
}

# Authentication functions (integrated)
configure_basic_auth_standalone() {
    print_info "Starting Basic Authentication configuration..."
    
    # Select project and VM
    if ! select_project; then
        return 1
    fi
    
    if ! select_vm_for_config; then
        return 1
    fi
    
    # Test SSH connectivity before proceeding
    print_info "Testing SSH connectivity to VM..."
    if ! gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --quiet \
         --command="echo 'SSH test successful'" 2>/dev/null; then
        print_error "Cannot establish SSH connection to VM"
        print_info "Please ensure:"
        print_info "1. VM is running and ready"
        print_info "2. SSH keys are properly configured"
        print_info "3. Try: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
        return 1
    fi
    print_success "SSH connectivity confirmed"
    
    # Use the integrated configure_basic_auth function
    configure_basic_auth
}

configure_iap_only() {
    print_info "Starting IAP configuration for existing VM..."
    print_warning "This feature requires manual OAuth consent screen setup"
    
    # Basic IAP setup logic would go here
    print_info "IAP-only configuration not yet implemented in unified script"
    print_info "Please use full deployment (option 1) and select IAP when prompted"
}

remove_authentication() {
    print_info "Removing authentication from OWOX..."
    
    # Select project and VM
    if ! select_project; then
        return 1
    fi
    
    if ! select_vm_for_config; then
        return 1
    fi
    
    # Remove auth logic would go here
    print_warning "Authentication removal not yet implemented"
    print_info "Manual steps:"
    print_info "1. SSH to VM: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
    print_info "2. Edit nginx config: sudo nano /etc/nginx/sites-available/owox"
    print_info "3. Remove auth_basic lines and reload nginx"
}

# Cleanup functions (integrated from undeploy-owox-gcp.sh)
cleanup_deployment() {
    print_info "Starting OWOX deployment cleanup..."
    
    if ! select_project; then
        return 1
    fi
    
    # Scan for resources
    print_info "Scanning for OWOX resources..."
    
    local found_resources=()
    
    # Check common zones for VM
    local zones=("us-central1-a" "europe-west1-b" "asia-east1-a")
    local vm_zone=""
    
    for zone in "${zones[@]}"; do
        if resource_exists "vm" "owox-data-marts" "$zone"; then
            found_resources+=("VM instance: owox-data-marts (zone: $zone)")
            vm_zone="$zone"
            break
        fi
    done
    
    # Check firewall rules
    if resource_exists "firewall" "owox-http-rule"; then
        found_resources+=("Firewall rule: owox-http-rule")
    fi
    if resource_exists "firewall" "owox-https-rule"; then
        found_resources+=("Firewall rule: owox-https-rule")
    fi
    if resource_exists "firewall" "owox-lb-health-check"; then
        found_resources+=("Firewall rule: owox-lb-health-check")
    fi
    
    if [ ${#found_resources[@]} -eq 0 ]; then
        print_success "No OWOX resources found to delete"
        return 0
    fi
    
    print_warning "Found the following OWOX resources:"
    for resource in "${found_resources[@]}"; do
        echo "  🗑️  $resource"
    done
    
    echo
    print_error "⚠️  WARNING: This will DELETE ALL listed resources permanently!"
    print_error "⚠️  This action CANNOT be undone!"
    echo
    read -p "Are you sure you want to delete all OWOX resources? (yes/NO): " CONFIRM_DELETE
    
    if [[ "$CONFIRM_DELETE" != "yes" ]]; then
        print_info "Cleanup cancelled by user"
        return 0
    fi
    
    echo
    print_error "Final confirmation: Type 'DELETE EVERYTHING' to proceed:"
    read -p "> " FINAL_CONFIRM
    
    if [[ "$FINAL_CONFIRM" != "DELETE EVERYTHING" ]]; then
        print_info "Cleanup cancelled by user"
        return 0
    fi
    
    # Delete resources
    print_info "=== Deleting Resources ==="
    
    # Delete firewall rules
    if resource_exists "firewall" "owox-lb-health-check"; then
        print_info "Deleting load balancer health check firewall rule..."
        gcloud compute firewall-rules delete owox-lb-health-check --quiet
        print_success "Load balancer firewall rule deleted"
    fi
    
    if resource_exists "firewall" "owox-https-rule"; then
        print_info "Deleting HTTPS firewall rule..."
        gcloud compute firewall-rules delete owox-https-rule --quiet
        print_success "HTTPS firewall rule deleted"
    fi
    
    if resource_exists "firewall" "owox-http-rule"; then
        print_info "Deleting HTTP firewall rule..."
        gcloud compute firewall-rules delete owox-http-rule --quiet
        print_success "HTTP firewall rule deleted"
    fi
    
    # Delete VM instance
    if [[ -n "$vm_zone" ]] && resource_exists "vm" "owox-data-marts" "$vm_zone"; then
        print_info "Deleting VM instance: owox-data-marts"
        gcloud compute instances delete "owox-data-marts" --zone="$vm_zone" --quiet
        print_success "VM instance deleted"
    fi
    
    print_success "=== Cleanup Complete ==="
    print_info "All OWOX resources have been deleted from project: $PROJECT_ID"
}

cleanup_auth_only() {
    print_info "Removing only authentication (keeping VM)..."
    
    print_warning "This will remove Basic Auth configuration"
    print_warning "VM and OWOX application will remain running"
    read -p "Continue? (y/N): " CONFIRM
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Cleanup cancelled"
        return 0
    fi
    
    # Select project and VM
    if ! select_project; then
        return 1
    fi
    
    if ! select_vm_for_config; then
        return 1
    fi
    
    print_info "Removing Basic Authentication from nginx..."
    
    # Create script to remove auth
    cat > remove-auth-remote.sh << 'REMOVE_AUTH_EOF'
#!/bin/bash

# Backup current nginx config
cp /etc/nginx/sites-available/owox /etc/nginx/sites-available/owox.backup

# Remove auth_basic lines from nginx config
sed -i '/auth_basic/d' /etc/nginx/sites-available/owox

# Remove htpasswd file
rm -f /etc/nginx/.htpasswd

# Test nginx configuration
if nginx -t; then
    systemctl reload nginx
    echo "SUCCESS: Authentication removed and nginx reloaded"
else
    echo "ERROR: Nginx configuration test failed"
    # Restore backup
    cp /etc/nginx/sites-available/owox.backup /etc/nginx/sites-available/owox
    echo "Restored backup configuration"
    exit 1
fi
REMOVE_AUTH_EOF
    
    # Upload and execute on VM
    if gcloud compute scp remove-auth-remote.sh "$INSTANCE_NAME":~/remove-auth-remote.sh --zone="$ZONE" --quiet; then
        print_success "Script uploaded to VM"
    else
        print_error "Failed to upload script to VM"
        rm -f remove-auth-remote.sh
        return 1
    fi
    
    if gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --quiet \
       --command="sudo bash ~/remove-auth-remote.sh && rm ~/remove-auth-remote.sh"; then
        print_success "Basic authentication removed successfully!"
    else
        print_error "Failed to remove authentication"
        rm -f remove-auth-remote.sh
        return 1
    fi
    
    # Clean up local file
    rm -f remove-auth-remote.sh
    
    print_success "🎉 Authentication removal completed!"
    print_info "OWOX is now publicly accessible without authentication"
}

# Select VM for configuration by number
select_vm_for_config() {
    print_info "=== VM Instance Selection ==="
    
    # Get VM instances and store in arrays
    local instances_data=$(gcloud compute instances list --filter="status:RUNNING" --format="value(name,zone,machineType.basename(),networkInterfaces[0].accessConfigs[0].natIP)")
    
    if [[ -z "$instances_data" ]]; then
        print_error "No running VM instances found in project $PROJECT_ID"
        return 1
    fi
    
    local vm_names=()
    local vm_zones=()
    local vm_types=()
    local vm_ips=()
    local counter=1
    
    print_info "Available running VM instances:"
    echo
    printf "%2s %-20s %-15s %-12s %s\n" "#" "NAME" "ZONE" "TYPE" "EXTERNAL_IP"
    printf "%2s %-20s %-15s %-12s %s\n" "=" "====" "====" "====" "==========="
    
    # Parse instances and display numbered list
    while IFS=$'\t' read -r name zone machine_type external_ip; do
        # Extract zone name from full path
        zone=$(basename "$zone")
        
        vm_names+=("$name")
        vm_zones+=("$zone")
        vm_types+=("$machine_type")
        vm_ips+=("${external_ip:-No IP}")
        
        printf "%2d %-20s %-15s %-12s %s\n" "$counter" "$name" "$zone" "$machine_type" "${external_ip:-No IP}"
        ((counter++))
    done <<< "$instances_data"
    
    echo
    local max_choice=$((counter - 1))
    
    if [[ $max_choice -eq 0 ]]; then
        print_error "No running VM instances found"
        return 1
    fi
    
    while true; do
        read -p "Select VM (1-$max_choice) or enter VM name directly: " CHOICE
        
        # Check if input is a number
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [[ $CHOICE -ge 1 ]] && [[ $CHOICE -le $max_choice ]]; then
            # Number selection
            local index=$((CHOICE - 1))
            INSTANCE_NAME="${vm_names[$index]}"
            ZONE="${vm_zones[$index]}"
            MACHINE_TYPE="${vm_types[$index]}"
            EXTERNAL_IP="${vm_ips[$index]}"
            break
        elif [[ -n "$CHOICE" ]] && [[ ! "$CHOICE" =~ ^[0-9]+$ ]]; then
            # Direct VM name input
            INSTANCE_NAME="$CHOICE"
            
            # Find VM in our arrays
            local found=false
            for i in "${!vm_names[@]}"; do
                if [[ "${vm_names[$i]}" == "$INSTANCE_NAME" ]]; then
                    ZONE="${vm_zones[$i]}"
                    MACHINE_TYPE="${vm_types[$i]}"
                    EXTERNAL_IP="${vm_ips[$i]}"
                    found=true
                    break
                fi
            done
            
            if [[ "$found" == true ]]; then
                break
            else
                print_error "VM '$INSTANCE_NAME' not found in running instances"
                continue
            fi
        else
            print_error "Invalid selection. Please enter a number between 1 and $max_choice, or a valid VM name"
            continue
        fi
    done
    
    print_success "Selected VM: $INSTANCE_NAME"
    print_success "Zone: $ZONE"
    print_success "Machine Type: $MACHINE_TYPE"
    print_success "External IP: $EXTERNAL_IP"
    
    return 0
}

# Show deployment status
show_deployment_status() {
    print_info "=== Deployment Status Check ==="
    
    if ! select_project; then
        return 1
    fi
    
    print_info "Checking OWOX-related resources in project: $PROJECT_ID"
    echo
    
    # Check VMs
    print_info "🖥️  Virtual Machines:"
    local vms=$(gcloud compute instances list --filter="labels.application=owox OR name~owox" --format="table(name,zone,status,networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)" 2>/dev/null)
    if [[ -n "$vms" ]] && [[ "$vms" != *"Listed 0 items"* ]]; then
        echo "$vms"
    else
        print_warning "No OWOX VMs found"
    fi
    echo
    
    # Check Load Balancers
    print_info "⚖️  Load Balancers:"
    local lbs=$(gcloud compute forwarding-rules list --filter="name~owox" --format="table(name,IPAddress,target)" 2>/dev/null)
    if [[ -n "$lbs" ]] && [[ "$lbs" != *"Listed 0 items"* ]]; then
        echo "$lbs"
    else
        print_warning "No OWOX Load Balancers found"
    fi
    echo
    
    # Check Firewall Rules
    print_info "🔥 Firewall Rules:"
    local fw=$(gcloud compute firewall-rules list --filter="name~owox" --format="table(name,direction,allowed[].ports)" 2>/dev/null)
    if [[ -n "$fw" ]] && [[ "$fw" != *"Listed 0 items"* ]]; then
        echo "$fw"
    else
        print_warning "No OWOX Firewall Rules found"
    fi
    echo
    
    print_info "Status check complete"
}

# Test authentication setup
test_authentication() {
    print_info "=== Authentication Test ==="
    
    if ! select_project; then
        return 1
    fi
    
    if ! select_vm_for_config; then
        return 1
    fi
    
    print_info "Testing authentication for: $INSTANCE_NAME"
    
    if [[ "$EXTERNAL_IP" == "No external IP" ]]; then
        print_error "VM has no external IP - cannot test from outside"
        return 1
    fi
    
    # Test HTTP access
    print_info "Testing HTTP access to: http://$EXTERNAL_IP/"
    local http_result=$(curl -s -o /dev/null -w '%{http_code}' "http://$EXTERNAL_IP/" 2>/dev/null || echo "connection-failed")
    
    case "$http_result" in
        "200")
            print_success "✅ HTTP 200 OK - No authentication configured"
            ;;
        "401")
            print_success "✅ HTTP 401 Unauthorized - Basic authentication is working"
            ;;
        "403")
            print_success "✅ HTTP 403 Forbidden - IAP authentication required"
            ;;
        "connection-failed")
            print_error "❌ Connection failed - VM might not be ready or firewall issues"
            ;;
        *)
            print_warning "⚠️ HTTP $http_result - Unexpected response"
            ;;
    esac
    
    # Test public API
    print_info "Testing public API access: http://$EXTERNAL_IP/api/external/"
    local api_result=$(curl -s -o /dev/null -w '%{http_code}' "http://$EXTERNAL_IP/api/external/" 2>/dev/null || echo "connection-failed")
    
    if [[ "$api_result" == "200" ]]; then
        print_success "✅ Public API is accessible (200 OK)"
    else
        print_warning "⚠️ Public API returned: $api_result"
    fi
    
    echo
    print_info "Authentication test complete"
}

# Main execution loop
main() {
    check_gcloud
    
    while true; do
        show_main_menu
        
        read -p "Select option (0-10): " CHOICE
        echo
        
        case $CHOICE in
            1)
                deploy_new_instance
                ;;
            2)
                deploy_public_instance
                ;;
            3)
                configure_basic_auth_standalone
                ;;
            4)
                configure_iap_only
                ;;
            5)
                remove_authentication
                ;;
            6)
                update_owox_app
                ;;
            7)
                cleanup_deployment
                ;;
            8)
                cleanup_auth_only
                ;;
            9)
                show_deployment_status
                ;;
            10)
                test_authentication
                ;;
            0)
                print_info "Thank you for using OWOX GCP Manager!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 0-10."
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Run the main function
main "$@"