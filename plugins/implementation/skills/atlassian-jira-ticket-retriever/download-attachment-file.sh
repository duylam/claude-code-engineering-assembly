#!/bin/bash

# ============================================================================
# Downloads a JIRA attachment file to a specified local path
# ============================================================================

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

OUT_FILE_PATH=""
ATTACHMENT_DOWNLOAD_URL=""

usage() {
    echo "Usage: $SCRIPT_NAME --out-file-path <path> --in-attachment-download-url <url>"
    echo "Options:"
    echo "  --out-file-path                Absolute path to save the downloaded file (required)"
    echo "  --in-attachment-download-url   Attachment file URL to download (required)"
    echo "  -h, --help                     Show this help"
    exit 0
}

validate_requirements() {
    if [[ -z "$OUT_FILE_PATH" ]]; then
        echo "Error: --out-file-path is required" >&2
        exit 1
    fi
    if [[ -z "$ATTACHMENT_DOWNLOAD_URL" ]]; then
        echo "Error: --in-attachment-download-url is required" >&2
        exit 1
    fi
}

main() {
    validate_requirements

    if curl -fsSL \
        -u "$MCP_ATLASSIAN_ACCOUNT_USERNAME:$MCP_ATLASSIAN_ACCOUNT_API_TOKEN" \
        -o "$OUT_FILE_PATH" \
        "$ATTACHMENT_DOWNLOAD_URL"; then
        echo "The url is saved at the path: $OUT_FILE_PATH"
    else
        echo "Error: failed to download attachment from $ATTACHMENT_DOWNLOAD_URL" >&2
        exit 1
    fi
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --out-file-path)
            OUT_FILE_PATH="$2"
            shift 2
            ;;
        --in-attachment-download-url)
            ATTACHMENT_DOWNLOAD_URL="$2"
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
