#!/bin/bash

# ============================================================================
# Uploads a local file as an attachment to a JIRA Cloud ticket
# ============================================================================

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

JIRA_SITE_URL=""
FILE_PATH=""
TICKET_KEY=""

usage() {
    echo "Usage: $SCRIPT_NAME --jira-site-url <url> --file-path <path> --ticket-key <key>"
    echo "Options:"
    echo "  --jira-site-url   JIRA site URL (e.g. https://yourname.atlassian.net/) (required)"
    echo "  --file-path       Absolute path to the file to upload (required)"
    echo "  --ticket-key      JIRA ticket key (e.g. ABC-1) (required)"
    echo "  -h, --help        Show this help"
    exit 0
}

validate_requirements() {
    if [[ -z "$JIRA_SITE_URL" ]]; then
        echo "Error: --jira-site-url is required" >&2
        exit 1
    fi
    if [[ -z "$FILE_PATH" ]]; then
        echo "Error: --file-path is required" >&2
        exit 1
    fi
    if [[ -z "$TICKET_KEY" ]]; then
        echo "Error: --ticket-key is required" >&2
        exit 1
    fi
    if [[ ! -f "$FILE_PATH" ]]; then
        echo "Error: file not found: $FILE_PATH" >&2
        exit 1
    fi
}

main() {
    validate_requirements

    local site_url="${JIRA_SITE_URL%/}"
    local api_url="${site_url}/rest/api/3/issue/${TICKET_KEY}/attachments"
    local response_file
    response_file="$(mktemp)"

    local http_code
    local curl_exit=0
    http_code=$(curl -s -w "%{http_code}" \
        -o "$response_file" \
        -u "$MCP_ATLASSIAN_ACCOUNT_USERNAME:$MCP_ATLASSIAN_ACCOUNT_API_TOKEN" \
        -X POST \
        -H "X-Atlassian-Token: no-check" \
        -F "file=@${FILE_PATH}" \
        "$api_url") || curl_exit=$?

    local response
    response="$(cat "$response_file")"
    rm -f "$response_file"

    if [[ "$curl_exit" -ne 0 ]]; then
        echo "$response" >&2
        exit "$curl_exit"
    fi

    if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
        echo "$response" >&2
        exit 1
    fi

    echo "$response"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --jira-site-url)
            JIRA_SITE_URL="$2"
            shift 2
            ;;
        --file-path)
            FILE_PATH="$2"
            shift 2
            ;;
        --ticket-key)
            TICKET_KEY="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

main
