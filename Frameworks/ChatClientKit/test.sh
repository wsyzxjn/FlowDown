#!/bin/bash

# Test script for ChatClientKit
# Runs all tests using Swift Testing System

set -e

echo "=========================================="
echo "ChatClientKit Test Suite"
echo "=========================================="
echo ""

# Check if OPENROUTER_API_KEY is set
if [ -z "$OPENROUTER_API_KEY" ]; then
    echo "ERROR: OPENROUTER_API_KEY environment variable is not set"
    echo "Please set it in your .zshrc or .bashrc:"
    echo "  export OPENROUTER_API_KEY='your-key-here'"
    exit 1
fi

echo "✓ OPENROUTER_API_KEY is set"
echo ""

# Run tests
echo "Running all tests..."
echo ""

swift test

echo ""
echo "=========================================="
echo "All tests completed!"
echo "=========================================="

