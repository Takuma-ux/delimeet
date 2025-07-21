#!/bin/bash

# Flutter Web Production Build Script (with clean)
# 本番環境用の完全クリーンビルドを実行
# 注意: cleanを実行するため時間がかかります

echo "🚀 Starting clean production Flutter Web build..."

# 1. Clean previous builds
echo "📦 Cleaning previous builds..."
flutter clean

# 2. Get dependencies
echo "📚 Getting dependencies..."
flutter pub get

# 3. Build with optimizations
echo "🔧 Building with optimizations..."
flutter build web \
  --release \
  --tree-shake-icons \
  --source-maps

echo "✅ Build completed!"
echo "📁 Output directory: build/web"
echo "🔧 To deploy: firebase deploy --only hosting"

# 4. Analyze bundle size (optional)
if command -v du &> /dev/null; then
  echo "📊 Bundle size analysis:"
  du -sh build/web/
  echo "📄 Main bundle:"
  find build/web -name "*.js" -exec du -sh {} \; | head -5
fi 