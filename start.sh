#!/bin/bash
set -e

if [ -z "$AZVM_URL" ]; then
  echo 1>&2 "error: missing AZVM_URL environment variable"
  exit 1
fi

if [ -z "$AZVM_TOKEN_FILE" ]; then
  if [ -z "$AZVM_TOKEN" ]; then
    echo 1>&2 "error: missing AZVM_TOKEN environment variable"
    exit 1
  fi

  AZVM_TOKEN_FILE=/AZVM/.token
  echo -n $AZVM_TOKEN > "$AZVM_TOKEN_FILE"
fi

unset AZVM_TOKEN

if [ -n "$AZVM_WORK" ]; then
  mkdir -p "$AZVM_WORK"
fi

rm -rf /azvm/agent
mkdir /azvm/agent
cd /azvm/agent

export AGENT_ALLOW_RUNASROOT="1"

cleanup() {
  if [ -e config.sh ]; then
    print_header "Cleanup. Removing Azure virtual machine deployment agent..."

    ./config.sh remove --unattended \
      --auth PAT \
      --token $(cat "$AZVM_TOKEN_FILE")
  fi
}

print_header() {
  lightcyan='\033[1;36m'
  nocolor='\033[0m'
  echo -e "${lightcyan}$1${nocolor}"
}

# Let the agent ignore the token env variables
export VSO_AGENT_IGNORE=AZVM_TOKEN,AZVM_TOKEN_FILE

print_header "1. Determining matching Azure virtual machine deployment agent..."

AZVM_AGENT_RESPONSE=$(curl -LsS \
  -u user:$(cat "$AZVM_TOKEN_FILE") \
  -H 'Accept:application/json;api-version=3.0-preview' \
  "$AZVM_URL/_apis/distributedtask/packages/agent?platform=linux-x64")

if echo "$AZVM_AGENT_RESPONSE" | jq . >/dev/null 2>&1; then
  AZVM_AGENTPACKAGE_URL=$(echo "$AZVM_AGENT_RESPONSE" \
    | jq -r '.value | map([.version.major,.version.minor,.version.patch,.downloadUrl]) | sort | .[length-1] | .[3]')
fi

if [ -z "$AZVM_AGENTPACKAGE_URL" -o "$AZVM_AGENTPACKAGE_URL" == "null" ]; then
  echo 1>&2 "error: could not determine a matching Azure virtual machine deployment agent - check that account '$AZVM_URL' is correct and the token is valid for that account"
  exit 1
fi

print_header "2. Downloading and installing Azure virtual machine deployment agent..."

curl -LsS $AZVM_AGENTPACKAGE_URL | tar -xz & wait $!

source ./env.sh

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

print_header "3. Configuring Azure virtual machine deployment agent..."

./config.sh \
  --unattended \
  --environment \
  --environmentname "$AZVM_ENVIRONMENT_NAME" \
  --addvirtualmachineresourcetags \
  --virtualMachineResourceTags "$AZVM_TAGS" \
  --acceptTeeEula \
  --agent "${AZVM_HOSTNAME:-$(hostname)}" \
  --url "$AZVM_URL" \
  --work "${AZVM_WORK:-_work}" \
  --projectname "$AZVM_PROJECT_NAME" \
  --auth PAT --token $(cat "$AZVM_TOKEN_FILE") \
  --replace & wait $!

print_header "4. Running Azure virtual machine deployment agent..."

# `exec` the node runtime so it's aware of TERM and INT signals
# AgentService.js understands how to handle agent self-update and restart
exec ./externals/node/bin/node ./bin/AgentService.js interactive
