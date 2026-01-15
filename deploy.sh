#!/bin/bash
# deploy.sh - Build Flutter frontend and deploy to Flask static folder

echo "🚧 Building Flutter Web App..."
cd frontend
# Using standard build, auto-detects best renderer
flutter build web

if [ $? -eq 0 ]; then
    echo "✅ Build Successful."
    echo "📦 Deploying to Flask static/ folder..."
    # Ensure static directory exists
    mkdir -p ../static
    # Copy build artifacts
    cp -R build/web/* ../static/
    echo "🚀 Deployment Complete!"
else
    echo "❌ Build Failed."
    exit 1
fi
