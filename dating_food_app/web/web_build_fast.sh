#!/bin/bash

# Flutter Web Ultra Lightweight Build Script
# Google Mapsパッケージ削除により大幅軽量化

echo "🚀 Starting ultra lightweight Flutter Web build..."

# 1. Clean and get dependencies
echo "📦 Cleaning and getting dependencies..."
flutter clean
flutter pub get

# 2. Build with maximum lightweighting
echo "🔧 Building ultra lightweight version..."
flutter build web \
  --release \
  --tree-shake-icons

echo "✅ Ultra lightweight build completed!"
echo "📁 Output directory: build/web"
echo "🔧 To deploy: firebase deploy --only hosting"

# 3. Analyze bundle size (should be much smaller now)
if command -v du &> /dev/null; then
  echo "📊 Bundle size analysis:"
  du -sh build/web/
  echo "📄 Main bundle:"
  find build/web -name "*.js" -exec du -sh {} \; | head -5
fi 