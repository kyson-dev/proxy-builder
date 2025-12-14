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

# 1. Get Project ID
CURRENT_PROJECT=$(gcloud config get-value project)
read -p "Enter GCP Project ID [$CURRENT_PROJECT]: " PROJECT_ID
PROJECT_ID=${PROJECT_ID:-$CURRENT_PROJECT}
echo "Using Project ID: $PROJECT_ID"

# 2. Get GitHub Repository
# Try to detect from git remote
DETECTED_REPO=$(git config --get remote.origin.url | sed 's/.*github.com\/\(.*\)\.git/\1/' || echo "")
read -p "Enter GitHub Repository (owner/repo) [$DETECTED_REPO]: " REPO
REPO=${REPO:-$DETECTED_REPO}

if [ -z "$REPO" ]; then
    echo "❌ Repository is required."
    exit 1
fi
echo "Using Repository: $REPO"

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
echo "📍 VM Configuration (Required for SSH deployment)"
echo "   You can find this in GCP Console → Compute Engine → VM instances"
echo ""

# Get VM Name
while true; do
    read -p "Enter VM Name: " VM_NAME
    if [ -n "$VM_NAME" ]; then
        # Verify VM exists
        if gcloud compute instances describe "$VM_NAME" --project "$PROJECT_ID" --format="value(name)" &>/dev/null; then
            echo "✅ VM '$VM_NAME' found"
            # Auto-detect zone
            DETECTED_ZONE=$(gcloud compute instances list --project "$PROJECT_ID" --filter="name=$VM_NAME" --format="value(zone)")
            break
        else
            echo "⚠️  VM '$VM_NAME' not found in project '$PROJECT_ID'"
            read -p "   Continue anyway? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                DETECTED_ZONE=""
                break
            fi
        fi
    else
        echo "❌ VM Name is required for deployment. Please enter a valid VM name."
    fi
done

# Get VM Zone
while true; do
    if [ -n "$DETECTED_ZONE" ]; then
        read -p "Enter VM Zone [$DETECTED_ZONE]: " VM_ZONE
        VM_ZONE=${VM_ZONE:-$DETECTED_ZONE}
    else
        read -p "Enter VM Zone (e.g., us-central1-a): " VM_ZONE
    fi
    
    if [ -n "$VM_ZONE" ]; then
        echo "Using VM Zone: $VM_ZONE"
        break
    else
        echo "❌ VM Zone is required for deployment. Please enter a valid zone."
    fi
done

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
