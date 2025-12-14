#!/bin/bash
set -e

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
echo ""

# Helper function to display numbered list and get selection
select_from_list() {
    local prompt="$1"
    shift
    local options=("$@")
    
    if [ ${#options[@]} -eq 0 ]; then
        return 1
    fi
    
    echo "$prompt"
    for i in "${!options[@]}"; do
        echo "  $((i+1)). ${options[$i]}"
    done
    
    while true; do
        read -p "Enter number (1-${#options[@]}): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#options[@]}" ]; then
            echo "${options[$((selection-1))]}"
            return 0
        fi
        echo "Invalid selection. Please try again."
    done
}

# 1. Get Project ID
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
        
        # If empty, use current project
        if [ -z "$selection" ] && [ -n "$CURRENT_PROJECT" ]; then
            PROJECT_ID="$CURRENT_PROJECT"
            break
        fi
        
        # If 0, enter manually
        if [ "$selection" = "0" ]; then
            read -p "Enter GCP Project ID: " PROJECT_ID
            break
        fi
        
        # If valid number, use selected project
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#PROJECTS[@]}" ]; then
            PROJECT_ID="${PROJECTS[$((selection-1))]}"
            break
        fi
        
        echo "Invalid selection. Please try again."
    done
fi

echo "✅ Using Project ID: $PROJECT_ID"
echo ""

# 2. Get GitHub Repository
echo "📋 Step 2: Confirm GitHub Repository"
echo ""

# Try to detect from git remote
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

# 3. Enable APIs
echo "Enable necessary APIs..."
gcloud services enable iam.googleapis.com cloudresourcemanager.googleapis.com iamcredentials.googleapis.com compute.googleapis.com --project "$PROJECT_ID"

# 4. Create Service Account
echo "Creating Service Account ($SA_NAME)..."
if ! gcloud iam service-accounts describe "$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" --project "$PROJECT_ID" &>/dev/null; then
    gcloud iam service-accounts create "$SA_NAME" \
        --display-name "$DESCRIPTION" \
        --project "$PROJECT_ID"
else
    echo "Service Account already exists, skipping creation."
fi

# 5. Grant Permissions (Compute OS Login & Instance Admin)
echo "Granting permissions..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/compute.instanceAdmin.v1" \
    --condition=None
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/compute.osAdminLogin" \
    --condition=None
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser" \
    --condition=None

# 6. Create Workload Identity Pool
echo "Creating Workload Identity Pool ($POOL_NAME)..."
if ! gcloud iam workload-identity-pools describe "$POOL_NAME" --project "$PROJECT_ID" --location="global" &>/dev/null; then
    gcloud iam workload-identity-pools create "$POOL_NAME" \
        --project "$PROJECT_ID" \
        --location="global" \
        --display-name "$DESCRIPTION"
else
    echo "Pool already exists, skipping creation."
fi

POOL_ID=$(gcloud iam workload-identity-pools describe "$POOL_NAME" --project "$PROJECT_ID" --location="global" --format="value(name)")

# 7. Create Workload Identity Provider
echo "Creating Workload Identity Provider ($PROVIDER_NAME)..."
if ! gcloud iam workload-identity-pools providers describe "$PROVIDER_NAME" --workload-identity-pool="$POOL_NAME" --project "$PROJECT_ID" --location="global" &>/dev/null; then
    gcloud iam workload-identity-pools providers create-oidc "$PROVIDER_NAME" \
        --workload-identity-pool="$POOL_NAME" \
        --project "$PROJECT_ID" \
        --location="global" \
        --issuer-uri="https://token.actions.githubusercontent.com" \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
        --attribute-condition="assertion.repository_owner == '$(echo $REPO | cut -d'/' -f1)'"
    
    echo "Waiting for provider to be ready..."
    sleep 5
else
    echo "Provider already exists, skipping creation."
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

# 8. Allow GitHub Repo to impersonate Service Account
echo "Binding GitHub repo to Service Account..."
gcloud iam service-accounts add-iam-policy-binding "$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --project "$PROJECT_ID" \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/$POOL_ID/attribute.repository/$REPO"

# 9. Get VM Information (Required for deployment)
echo ""
echo "� Step 3: Select VM Instance"
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
    
    # Parse VM list into arrays
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
        read -p "Select VM (0-${#VM_NAMES[@]}): " selection
        
        # If 0, enter manually
        if [ "$selection" = "0" ]; then
            read -p "Enter VM Name: " VM_NAME
            read -p "Enter VM Zone (e.g., us-central1-a): " VM_ZONE
            
            if [ -z "$VM_NAME" ] || [ -z "$VM_ZONE" ]; then
                echo "❌ VM Name and Zone are required."
                continue
            fi
            break
        fi
        
        # If valid number, use selected VM
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

echo "✅ Selected VM: $VM_NAME (Zone: $VM_ZONE)"
echo ""

# 10. Ensure VM has OS Login enabled
echo ""
echo "🔐 Checking OS Login configuration..."
if gcloud compute instances describe "$VM_NAME" --zone="$VM_ZONE" --project "$PROJECT_ID" &>/dev/null; then
    OS_LOGIN=$(gcloud compute instances describe "$VM_NAME" --zone="$VM_ZONE" --project "$PROJECT_ID" --format="get(metadata.items[key=enable-oslogin].value)" 2>/dev/null || echo "")
    
    if [ "$OS_LOGIN" != "TRUE" ]; then
        echo "⚠️  OS Login is not enabled on VM '$VM_NAME'"
        read -p "   Enable OS Login now? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            gcloud compute instances add-metadata "$VM_NAME" \
                --zone="$VM_ZONE" \
                --project "$PROJECT_ID" \
                --metadata enable-oslogin=TRUE
            echo "✅ OS Login enabled"
        else
            echo "⚠️  Warning: Deployment may fail without OS Login. You can enable it later with:"
            echo "   gcloud compute instances add-metadata $VM_NAME --zone=$VM_ZONE --metadata enable-oslogin=TRUE"
        fi
    else
        echo "✅ OS Login is already enabled"
    fi
else
    echo "⚠️  Could not verify VM. Skipping OS Login check."
fi

# 11. Summary and Set Secrets
WIF_PROVIDER="$PROVIDER_ID"
WIF_SA="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"

echo ""
echo "✅ Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Workload Identity Provider: $WIF_PROVIDER"
echo "Service Account: $WIF_SA"
echo "VM Name: $VM_NAME"
echo "VM Zone: $VM_ZONE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Setting GitHub Secrets..."

gh secret set GCP_PROJECT_ID --body "$PROJECT_ID" --repo "$REPO"
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "$WIF_PROVIDER" --repo "$REPO"
gh secret set GCP_SERVICE_ACCOUNT --body "$WIF_SA" --repo "$REPO"
gh secret set GCP_VM_NAME --body "$VM_NAME" --repo "$REPO"
gh secret set GCP_VM_ZONE --body "$VM_ZONE" --repo "$REPO"

echo ""
echo "✅ All GitHub Secrets have been set!"
echo ""
echo "📋 Next Steps:"
echo "   1. Run 'make push-env' to upload your .env file"
echo "   2. Push code to trigger deployment: 'git push origin main'"
echo ""
echo "Done."
