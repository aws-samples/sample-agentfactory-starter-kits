#!/usr/bin/env bash
# Deploy the Intelligent Ticket Triage agent.
#
# What this script does (in order):
#   1. Pre-flight (AWS CLI, yq, credentials, config)
#   2. CloudFormation deploy of the Bedrock Agent + KB + Guardrails + Lambda stack
#   3. Package each Lambda action-group function (zip src/agent/tools/*.py)
#   4. Upload code to each Lambda via aws lambda update-function-code
#   5. prepare-agent + create-or-update an agent alias
#   6. Print the runtime invocation example
#
# Usage:
#   ./deploy.sh                  # full deploy
#   ./deploy.sh --skip-package   # CFN only, skip Lambda packaging step
#   ./deploy.sh --skip-prepare   # CFN + Lambda only, skip prepare/alias

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.yaml"
TEMPLATE_FILE="${SCRIPT_DIR}/template.yaml"
TOOLS_DIR="${KIT_DIR}/src/agent/tools"
ALIAS_NAME="live"

# --- Flags ---
SKIP_PACKAGE=false
SKIP_PREPARE=false
for arg in "$@"; do
  case "$arg" in
    --skip-package) SKIP_PACKAGE=true ;;
    --skip-prepare) SKIP_PREPARE=true ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) ;;
  esac
done

# --- Helpers ---
log() { echo "[$(date '+%H:%M:%S')] $*"; }
err() { echo "[ERROR] $*" >&2; exit 1; }

# --- Pre-flight checks ---
command -v aws >/dev/null 2>&1 || err "AWS CLI not found. Install: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
command -v yq >/dev/null 2>&1 || err "yq not found. Install: brew install yq"
command -v zip >/dev/null 2>&1 || err "zip not found."
command -v python3 >/dev/null 2>&1 || err "python3 not found."

aws sts get-caller-identity >/dev/null 2>&1 || err "AWS credentials not configured or expired. Run 'aws configure' or set AWS_PROFILE."

log "Pre-flight checks passed."

# --- Read config ---
[[ -f "$CONFIG_FILE" ]] || err "Config file not found. Copy config.example.yaml to config.yaml and fill in values."

AWS_REGION=$(yq '.aws_region' "$CONFIG_FILE")
STACK_NAME=$(yq '.stack_name' "$CONFIG_FILE")
CUSTOMER_NAME=$(yq '.customer_name' "$CONFIG_FILE")
WEBHOOK_URL=$(yq '.webhook_url' "$CONFIG_FILE")
CONFIDENCE_THRESHOLD=$(yq '.confidence_threshold' "$CONFIG_FILE")

[[ "$WEBHOOK_URL" != "null" && "$WEBHOOK_URL" != "" ]] || err "webhook_url is required in config.yaml"
[[ "$CUSTOMER_NAME" != "null" && "$CUSTOMER_NAME" != "" ]] || err "customer_name is required in config.yaml"

log "Deploying stack '${STACK_NAME}' for customer '${CUSTOMER_NAME}' in ${AWS_REGION}"

# --- 1. Validate template ---
log "Validating CloudFormation template..."
aws cloudformation validate-template \
  --template-body "file://${TEMPLATE_FILE}" \
  --region "$AWS_REGION" >/dev/null

# --- 2. CloudFormation deploy ---
log "Creating/updating CloudFormation stack..."
aws cloudformation deploy \
  --template-file "$TEMPLATE_FILE" \
  --stack-name "$STACK_NAME" \
  --region "$AWS_REGION" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    AwsRegion="$AWS_REGION" \
    TicketSourceWebhookUrl="$WEBHOOK_URL" \
    ConfidenceThreshold="$CONFIDENCE_THRESHOLD" \
    CustomerNamePrefix="$CUSTOMER_NAME" \
  --no-fail-on-empty-changeset

log "Waiting for stack to reach stable state..."
aws cloudformation wait stack-create-complete \
  --stack-name "$STACK_NAME" \
  --region "$AWS_REGION" 2>/dev/null || \
aws cloudformation wait stack-update-complete \
  --stack-name "$STACK_NAME" \
  --region "$AWS_REGION" 2>/dev/null || true

# --- Outputs ---
log "Fetching stack outputs..."

OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$AWS_REGION" \
  --query 'Stacks[0].Outputs' \
  --output json)

extract_output() {
  echo "$OUTPUTS" | python3 -c "
import sys,json
d={o['OutputKey']:o['OutputValue'] for o in json.load(sys.stdin)}
v=d.get('$1','')
if not v:
  sys.stderr.write('Missing CloudFormation output: $1\n'); sys.exit(1)
print(v)
"
}

AGENT_ID=$(extract_output AgentId)
KB_ID=$(extract_output KnowledgeBaseId)
S3_BUCKET=$(extract_output S3BucketName)
DASHBOARD_URL=$(extract_output DashboardUrl)
CLASSIFY_FN=$(extract_output ClassifyTicketFunctionName)
ROUTE_FN=$(extract_output RouteTicketFunctionName)
RESOLVE_FN=$(extract_output ResolveTicketFunctionName)

# --- 3. Package + 4. Upload Lambda code ---
if [[ "$SKIP_PACKAGE" == false ]]; then
  log "Packaging and uploading Lambda action-group code..."
  TMP_PKG_DIR=$(mktemp -d)
  trap 'rm -rf "$TMP_PKG_DIR"' EXIT

  package_and_upload() {
    local source_file="$1"
    local function_name="$2"
    local zip_path="${TMP_PKG_DIR}/$(basename "${source_file%.py}").zip"

    [[ -f "$source_file" ]] || err "Lambda source not found: $source_file"

    # The CFN template Lambda expects its handler at the basename. Bedrock
    # Agent action-group Lambdas use the file's lambda_handler directly, so we
    # zip the file at the root of the archive (no nested directory).
    (cd "$(dirname "$source_file")" && zip -q -j "$zip_path" "$(basename "$source_file")")

    log "  Uploading $(basename "$source_file") → ${function_name}"
    aws lambda update-function-code \
      --function-name "$function_name" \
      --zip-file "fileb://${zip_path}" \
      --region "$AWS_REGION" \
      --output text \
      --query 'FunctionArn' >/dev/null

    # Wait for the Lambda to leave the InProgress LastUpdateStatus before
    # the next prepare-agent call (otherwise prepare can race).
    aws lambda wait function-updated \
      --function-name "$function_name" \
      --region "$AWS_REGION"
  }

  package_and_upload "${TOOLS_DIR}/classify-ticket.py" "$CLASSIFY_FN"
  package_and_upload "${TOOLS_DIR}/route-ticket.py" "$ROUTE_FN"
  package_and_upload "${TOOLS_DIR}/resolve-ticket.py" "$RESOLVE_FN"

  log "Lambda code uploaded."
else
  log "Skipping Lambda packaging (--skip-package). The Lambdas will run the placeholder ZipFile from template.yaml — agent action groups will return empty responses."
fi

# --- 5. Prepare agent + create/update alias ---
ALIAS_ID=""
if [[ "$SKIP_PREPARE" == false ]]; then
  log "Preparing agent (compiling action groups)..."
  aws bedrock-agent prepare-agent \
    --agent-id "$AGENT_ID" \
    --region "$AWS_REGION" \
    --output text \
    --query 'agentStatus' >/dev/null

  # prepare-agent is async; poll until status reaches PREPARED.
  log "Waiting for agent to reach PREPARED..."
  for _ in $(seq 1 30); do
    STATUS=$(aws bedrock-agent get-agent --agent-id "$AGENT_ID" --region "$AWS_REGION" \
              --query 'agent.agentStatus' --output text)
    if [[ "$STATUS" == "PREPARED" ]]; then break; fi
    if [[ "$STATUS" == "FAILED" ]]; then err "Agent preparation FAILED. Check the Bedrock console for details."; fi
    sleep 5
  done
  [[ "$STATUS" == "PREPARED" ]] || err "Agent did not reach PREPARED state in time (last seen: $STATUS)"
  log "Agent prepared."

  # Create alias if missing, otherwise update to the latest version.
  EXISTING_ALIAS_ID=$(aws bedrock-agent list-agent-aliases \
    --agent-id "$AGENT_ID" \
    --region "$AWS_REGION" \
    --query "agentAliasSummaries[?agentAliasName=='${ALIAS_NAME}'].agentAliasId" \
    --output text 2>/dev/null || echo "")

  if [[ -z "$EXISTING_ALIAS_ID" || "$EXISTING_ALIAS_ID" == "None" ]]; then
    log "Creating agent alias '${ALIAS_NAME}'..."
    ALIAS_ID=$(aws bedrock-agent create-agent-alias \
      --agent-id "$AGENT_ID" \
      --agent-alias-name "$ALIAS_NAME" \
      --region "$AWS_REGION" \
      --query 'agentAlias.agentAliasId' --output text)
  else
    log "Updating existing alias '${ALIAS_NAME}' (${EXISTING_ALIAS_ID}) to latest agent version..."
    ALIAS_ID="$EXISTING_ALIAS_ID"
    aws bedrock-agent update-agent-alias \
      --agent-id "$AGENT_ID" \
      --agent-alias-id "$ALIAS_ID" \
      --agent-alias-name "$ALIAS_NAME" \
      --region "$AWS_REGION" \
      --output text >/dev/null
  fi
  log "Agent alias ready: ${ALIAS_ID}"
else
  log "Skipping prepare-agent (--skip-prepare). Run manually before invoking:"
  log "  aws bedrock-agent prepare-agent --agent-id ${AGENT_ID}"
  log "  aws bedrock-agent create-agent-alias --agent-id ${AGENT_ID} --agent-alias-name live"
fi

# --- 6. Summary + next steps ---
echo ""
echo "============================================"
echo "  Deployment Outputs"
echo "============================================"
echo "  Agent ID:          ${AGENT_ID}"
echo "  Agent alias ID:    ${ALIAS_ID:-<not created — used --skip-prepare>}"
echo "  Knowledge Base ID: ${KB_ID}"
echo "  S3 Bucket:         ${S3_BUCKET}"
echo "  Dashboard:         ${DASHBOARD_URL}"
echo "============================================"
echo ""

echo "--- Customer-side next steps ---"
echo "1. Upload your ticket history and product docs to the KB source bucket:"
echo "     aws s3 cp ./data/ s3://${S3_BUCKET}/ --recursive"
echo ""
echo "2. Sync the Knowledge Base (find the data-source-id in the Bedrock console):"
echo "     aws bedrock-agent start-ingestion-job \\"
echo "       --knowledge-base-id ${KB_ID} \\"
echo "       --data-source-id <data-source-id>"
echo ""
if [[ -n "$ALIAS_ID" ]]; then
  echo "3. Test with a sample ticket:"
  echo "     aws bedrock-agent-runtime invoke-agent \\"
  echo "       --agent-id ${AGENT_ID} \\"
  echo "       --agent-alias-id ${ALIAS_ID} \\"
  echo "       --session-id test-1 \\"
  echo "       --input-text 'I cannot log in to my account'"
  echo ""
fi
log "Done."
