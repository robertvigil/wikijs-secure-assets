#!/bin/bash

# Production Configuration Example
# Copy this file outside the repo to your wiki.js folder as 'production-config.sh'
# and customize with your actual values

# Server connection
export WIKI_SERVER="user@your-server.com"
export WIKI_USER="user"
export WIKI_HOME="/home/user"

# Group to folder mapping
# Format: "group-name:folder-path"
export SECURE_FOLDERS=(
    "managers:secure-assets/managers"
    "developers:secure-assets/developers"
)

# Example file to copy during setup
export EXAMPLE_FILE_SOURCE="/home/user/wiki/data/cache/example-file.dat"
export EXAMPLE_FILE_DEST="secure-assets/managers/example.png"

# Port for auth service (default: 3002)
export AUTH_SERVICE_PORT="3002"

# Database name (default: wikijs)
export WIKI_DB="wikijs"
