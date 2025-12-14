#!/bin/bash
set -e

# ============================================================
# 多环境 WIF 配置脚本
# 支持 production 和 development 环境
# ============================================================

# Configuration
SA_NAME="github-deploy"
POOL_NAME="github-pool"
PROVIDER_NAME="github-provider"
DESCRIPTION="GitHub Actions Deployment"

# Check dependencies
if ! command -v gcloud &> /dev/null; then
    echo "❌ gcloud CLI is not installed."
    exit 1
fi
if ! command -v gh &> /dev/null; then
    echo "❌ GitHub CLI (gh) is not installed."
    exit 1
fi

echo "🚀 Setting up Workload Identity Federation for GitHub Actions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================
# Step 0: Select Environment
# ============================================================
echo "📋 Step 0: Select Environment"
echo ""
echo "  1. production  (main 分支 → 生产 VM)"
echo "  2. development (dev 分支 → 测试 VM)"
echo ""

while true; do
    read -p "Select environment (1/2): " env_choice
    case $env_choice in
        1)
            ENV_NAME="production"
            break
            ;;
        2)
            ENV_NAME="development"
            break
            ;;
        *)
            echo "Invalid choice. Please enter 1 or 2."
            ;;
    esac
done

echo ""
echo "✅ Selected environment: $ENV_NAME"
echo ""

# ============================================================
# Step 1: Select GCP Project
# ============================================================
echo "📋 Step 1: Select GCP Project"
echo ""

CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")

# Get list of all projects
echo "Fetching your GCP projects..."
PROJECTS=($(gcloud projects list --format="value(projectId)" 2>/dev/null))

if [ ${#PROJECTS[@]} -eq 0 ]; then
    echo "⚠️  No projects found or unable to list projects."
    read -p "Enter GCP Project ID manually: " PROJECT_ID
else
    echo ""
    echo "Available projects:"
    for i in "${!PROJECTS[@]}"; do
        project="${PROJECTS[$i]}"
        if [ "$project" = "$CURRENT_PROJECT" ]; then
            echo "  $((i+1)). $project (current)"
        else
            echo "  $((i+1)). $project"
        fi
    done
    echo "  0. Enter manually"
    echo ""
    
    while true; do
        read -p "Select project (0-${#PROJECTS[@]}) [default: $CURRENT_PROJECT]: " selection
        
        if [ -z "$selection" ] && [ -n "$CURRENT_PROJECT" ]; then
            PROJECT_ID="$CURRENT_PROJECT"
            break
        fi
        
        if [ "$selection" = "0" ]; then
            read -p "Enter GCP Project ID: " PROJECT_ID
            break
        fi
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#PROJECTS[@]}" ]; then
            PROJECT_ID="${PROJECTS[$((selection-1))]}"
            break
        fi
        
        echo "Invalid selection. Please try again."
    done
fi

echo "✅ Using Project ID: $PROJECT_ID"
echo ""

# ============================================================
# Step 2: Confirm GitHub Repository
# ============================================================
echo "📋 Step 2: Confirm GitHub Repository"
echo ""

DETECTED_REPO=$(git config --get remote.origin.url 2>/dev/null | sed 's/.*github.com\/\(.*\)\.git/\1/' || echo "")

if [ -n "$DETECTED_REPO" ]; then
    read -p "GitHub Repository [$DETECTED_REPO]: " REPO
    REPO=${REPO:-$DETECTED_REPO}
else
    read -p "Enter GitHub Repository (owner/repo): " REPO
fi

if [ -z "$REPO" ]; then
    echo "❌ Repository is required."
    exit 1
fi

echo "✅ Using Repository: $REPO"
echo ""

# ============================================================
# Step 3: Enable APIs (only needs to be done once per project)
# ============================================================
echo "📋 Step 3: Enable necessary APIs..."
gcloud services enable iam.googleapis.com cloudresourcemanager.googleapis.com iamcredentials.googleapis.com compute.googleapis.com --project "$PROJECT_ID"
echo "✅ APIs enabled"
echo ""

# ============================================================
# Step 4: Create Service Account (shared across environments)
# ============================================================
echo "📋 Step 4: Creating Service Account ($SA_NAME)..."
if ! gcloud iam service-accounts describe "$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" --project "$PROJECT_ID" &>/dev/null; then
    gcloud iam service-accounts create "$SA_NAME" \
        --display-name "$DESCRIPTION" \
        --project "$PROJECT_ID"
    echo "✅ Service Account created"
else
    echo "✅ Service Account already exists, skipping creation."
fi
echo ""

# ============================================================
# Step 5: Grant Permissions
# ============================================================
echo "📋 Step 5: Granting permissions..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/compute.instanceAdmin.v1" \
    --condition=None --quiet

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/compute.osAdminLogin" \
    --condition=None --quiet

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser" \
    --condition=None --quiet

echo "✅ Permissions granted"
echo ""

# ============================================================
# Step 6: Create Workload Identity Pool (shared)
# ============================================================
echo "📋 Step 6: Creating Workload Identity Pool ($POOL_NAME)..."
if ! gcloud iam workload-identity-pools describe "$POOL_NAME" --project "$PROJECT_ID" --location="global" &>/dev/null; then
    gcloud iam workload-identity-pools create "$POOL_NAME" \
        --project "$PROJECT_ID" \
        --location="global" \
        --display-name "$DESCRIPTION"
    echo "✅ Pool created"
else
    echo "✅ Pool already exists, skipping creation."
fi

POOL_ID=$(gcloud iam workload-identity-pools describe "$POOL_NAME" --project "$PROJECT_ID" --location="global" --format="value(name)")
echo ""

# ============================================================
# Step 7: Create Workload Identity Provider (shared)
# ============================================================
echo "📋 Step 7: Creating Workload Identity Provider ($PROVIDER_NAME)..."
if ! gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" --workload-identity-pool="$POOL_NAME" --project "$PROJECT_ID" --location="global" &>/dev/null; then
    REPO_OWNER=$(echo $REPO | cut -d'/' -f1)
    gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
        --workload-identity-pool="$POOL_NAME" \
        --project "$PROJECT_ID" \
        --location="global" \
        --issuer-uri="https://token.actions.githubusercontent.com" \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
        --attribute-condition="assertion.repository_owner == '$REPO_OWNER'"
    
    echo "Waiting for provider to be ready..."
    sleep 5
    echo "✅ Provider created"
else
    echo "✅ Provider already exists, skipping creation."
fi

# Retry logic to get PROVIDER_ID
echo "Retrieving Provider ID..."
for i in {1..5}; do
    PROVIDER_ID=$(gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" --workload-identity-pool="$POOL_NAME" --project "$PROJECT_ID" --location="global" --format="value(name)" 2>/dev/null)
    if [ -n "$PROVIDER_ID" ]; then
        break
    fi
    echo "Waiting for provider to propagate (attempt $i/5)..."
    sleep 3
done

if [ -z "$PROVIDER_ID" ]; then
    echo "❌ Failed to retrieve Provider ID after multiple attempts"
    exit 1
fi
echo ""

# ============================================================
# Step 8: Bind GitHub repo to Service Account
# ============================================================
echo "📋 Step 8: Binding GitHub repo to Service Account..."
gcloud iam service-accounts add-iam-policy-binding "$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --project "$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/$POOL_ID/attribute.repository/$REPO" \
    --quiet
echo "✅ Binding complete"
echo ""

# ============================================================
# Step 9: Select VM for this environment
# ============================================================
echo "📋 Step 9: Select VM for '$ENV_NAME' environment"
echo ""

# Get list of VMs in the project
echo "Fetching VM instances in project '$PROJECT_ID'..."
VM_LIST=$(gcloud compute instances list --project "$PROJECT_ID" --format="csv[no-heading](name,zone,status)" 2>/dev/null)

if [ -z "$VM_LIST" ]; then
    echo "⚠️  No VM instances found in project '$PROJECT_ID'"
    echo ""
    read -p "Enter VM Name manually: " VM_NAME
    read -p "Enter VM Zone (e.g., us-central1-a): " VM_ZONE
    
    if [ -z "$VM_NAME" ] || [ -z "$VM_ZONE" ]; then
        echo "❌ VM Name and Zone are required."
        exit 1
    fi
else
    echo ""
    echo "Available VM instances:"
    
    declare -a VM_NAMES
    declare -a VM_ZONES
    declare -a VM_STATUSES
    
    i=0
    while IFS=',' read -r name zone status; do
        VM_NAMES[$i]="$name"
        VM_ZONES[$i]="$zone"
        VM_STATUSES[$i]="$status"
        
        status_icon="⚪"
        [ "$status" = "RUNNING" ] && status_icon="🟢"
        [ "$status" = "TERMINATED" ] && status_icon="🔴"
        
        echo "  $((i+1)). $name"
        echo "      Zone: $zone | Status: $status_icon $status"
        i=$((i+1))
    done <<< "$VM_LIST"
    
    echo "  0. Enter manually"
    echo ""
    
    while true; do
        read -p "Select VM for $ENV_NAME (0-${#VM_NAMES[@]}): " selection
        
        if [ "$selection" = "0" ]; then
            read -p "Enter VM Name: " VM_NAME
            read -p "Enter VM Zone (e.g., us-central1-a): " VM_ZONE
            
            if [ -z "$VM_NAME" ] || [ -z "$VM_ZONE" ]; then
                echo "❌ VM Name and Zone are required."
                continue
            fi
            break
        fi
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#VM_NAMES[@]}" ]; then
            VM_NAME="${VM_NAMES[$((selection-1))]}"
            VM_ZONE="${VM_ZONES[$((selection-1))]}"
            VM_STATUS="${VM_STATUSES[$((selection-1))]}"
            
            if [ "$VM_STATUS" != "RUNNING" ]; then
                echo "⚠️  Warning: VM '$VM_NAME' is not running (status: $VM_STATUS)"
                read -p "   Continue anyway? (y/n): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    continue
                fi
            fi
            break
        fi
        
        echo "Invalid selection. Please try again."
    done
fi

echo "✅ Selected VM for $ENV_NAME: $VM_NAME (Zone: $VM_ZONE)"
echo ""

# ============================================================
# Step 10: Ensure VM has OS Login enabled
# ============================================================
echo "📋 Step 10: Checking OS Login configuration..."

OS_LOGIN_STATUS=$(gcloud compute instances describe "$VM_NAME" --zone="$VM_ZONE" --project="$PROJECT_ID" --format="get(metadata.items[key=enable-oslogin].value)" 2>/dev/null || echo "")

if [ "$OS_LOGIN_STATUS" = "TRUE" ]; then
    echo "✅ OS Login is already enabled on $VM_NAME"
else
    echo "⚠️  OS Login is not enabled on $VM_NAME"
    read -p "   Enable OS Login now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        gcloud compute instances add-metadata "$VM_NAME" \
            --zone="$VM_ZONE" \
            --project="$PROJECT_ID" \
            --metadata enable-oslogin=TRUE
        echo "✅ OS Login enabled"
    else
        echo "⚠️  Skipping OS Login. Deployment may fail without it."
    fi
fi
echo ""

# ============================================================
# Step 11: Set GitHub Environment Secrets
# ============================================================
echo "📋 Step 11: Setting GitHub Secrets for '$ENV_NAME' environment..."
echo ""

# Check if the environment exists
echo "Note: Make sure you have created the '$ENV_NAME' environment in GitHub:"
echo "      Settings → Environments → New environment → '$ENV_NAME'"
echo ""
read -p "Have you created the '$ENV_NAME' environment in GitHub? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "⚠️  Please create the environment first:"
    echo "   1. Go to: https://github.com/$REPO/settings/environments"
    echo "   2. Click 'New environment'"
    echo "   3. Name it: $ENV_NAME"
    echo "   4. Run this script again"
    exit 1
fi

echo ""
echo "Setting secrets..."

# Set WIF secrets to environment
gh secret set GCP_PROJECT_ID \
    --env "$ENV_NAME" \
    --body "$PROJECT_ID" \
    --repo "$REPO"
echo "✓ GCP_PROJECT_ID"

gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER \
    --env "$ENV_NAME" \
    --body "$PROVIDER_ID" \
    --repo "$REPO"
echo "✓ GCP_WORKLOAD_IDENTITY_PROVIDER"

gh secret set GCP_SERVICE_ACCOUNT \
    --env "$ENV_NAME" \
    --body "$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --repo "$REPO"
echo "✓ GCP_SERVICE_ACCOUNT"

gh secret set GCP_VM_NAME \
    --env "$ENV_NAME" \
    --body "$VM_NAME" \
    --repo "$REPO"
echo "✓ GCP_VM_NAME"

gh secret set GCP_VM_ZONE \
    --env "$ENV_NAME" \
    --body "$VM_ZONE" \
    --repo "$REPO"
echo "✓ GCP_VM_ZONE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ WIF Setup Complete for '$ENV_NAME' environment!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Configuration Summary:"
echo "  Environment: $ENV_NAME"
echo "  Project ID:  $PROJECT_ID"
echo "  VM Name:     $VM_NAME"
echo "  VM Zone:     $VM_ZONE"
echo "  Provider:    $PROVIDER_ID"
echo ""
echo "📋 Next Steps:"
echo "   1. Create the environment config file: .env.$ENV_NAME"
echo "   2. Push environment variables: make push-env ENV=$ENV_NAME"
if [ "$ENV_NAME" = "production" ]; then
    echo "   3. Push to main branch to deploy: git push origin main"
else
    echo "   3. Push to dev branch to deploy: git push origin dev"
fi
echo ""
