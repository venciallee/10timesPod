#!/bin/bash

# 10timesPod HTML Demo - Quick Start Script

echo "🎵 10timesPod HTML Demo"
echo "========================"
echo ""

# Check if we're in the right directory
if [ ! -f "demo/index.html" ]; then
    echo "❌ Error: demo/index.html not found"
    echo "Please run this script from the repository root"
    exit 1
fi

echo "✅ Demo files found"
echo ""

# Detect OS and open browser
if command -v python3 &> /dev/null; then
    echo "🚀 Starting Python HTTP server on port 8000..."
    echo ""
    echo "📱 Demo pages available:"
    echo "   - Discover:       http://localhost:8000/demo/"
    echo "   - Subscriptions:  Click '订阅' in nav"
    echo "   - Player:         Click any podcast card"
    echo "   - Settings:       Click '设置' in nav"
    echo ""
    echo "Press Ctrl+C to stop the server"
    echo ""
    
    # Open browser based on OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        open "http://localhost:8000/demo/" 2>/dev/null
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        xdg-open "http://localhost:8000/demo/" 2>/dev/null || echo "Please open http://localhost:8000/demo/ in your browser"
    fi
    
    cd demo && python3 -m http.server 8000
else
    echo "❌ Python 3 not found"
    echo ""
    echo "Alternative options:"
    echo "1. Install Python 3"
    echo "2. Use Node.js: npx http-server demo -p 8000"
    echo "3. Open demo/index.html directly in your browser"
    exit 1
fi
