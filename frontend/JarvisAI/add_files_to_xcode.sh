#!/bin/bash

# Script to add new Swift files to Xcode project
# Run this from the JarvisAI directory

echo "🔧 Adding new Swift files to Xcode project..."

# List of new files that need to be in the project
NEW_FILES=(
    "JarvisAI/Models/Conversation.swift"
    "JarvisAI/Services/ConversationService.swift"
    "JarvisAI/ViewModels/ConversationViewModel.swift"
    "JarvisAI/Views/MainContentView.swift"
    "JarvisAI/Views/SidebarView.swift"
    "JarvisAI/Views/SettingsView.swift"
    "JarvisAI/Views/FileAttachmentView.swift"
)

echo "📝 New files to add:"
for file in "${NEW_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✅ $file"
    else
        echo "  ❌ $file (NOT FOUND)"
    fi
done

echo ""
echo "📌 MANUAL STEPS REQUIRED:"
echo ""
echo "1. Open JarvisAI.xcodeproj in Xcode"
echo "2. Right-click on the project in sidebar"
echo "3. Select 'Add Files to JarvisAI...'"
echo "4. Select all these files:"
for file in "${NEW_FILES[@]}"; do
    echo "   - $file"
done
echo "5. Make sure 'Copy items if needed' is UNCHECKED"
echo "6. Make sure 'Add to targets: JarvisAI' is CHECKED"
echo "7. Click 'Add'"
echo ""
echo "OR simply rebuild in Xcode - it should auto-detect files!"
echo ""
echo "Then press ⌘B to build and ⌘R to run"
