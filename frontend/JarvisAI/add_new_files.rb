#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'JarvisAI.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.first
main_group = project.main_group['JarvisAI']

# Add new files
new_files = [
  'Models/Conversation.swift',
  'Services/ConversationService.swift', 
  'ViewModels/ConversationViewModel.swift',
  'Views/MainContentView.swift',
  'Views/SidebarView.swift',
  'Views/SettingsView.swift',
  'Views/FileAttachmentView.swift',
  'Services/RayMode/AppSearchManager.swift',
  'Services/RayMode/RayModeViewModel.swift',
  'Views/RayModeView.swift'
]

new_files.each do |file_path|
  parts = file_path.split('/')
  
  # Navigate/create nested groups
  current_group = main_group
  parts[0..-2].each do |folder|
    current_group = current_group[folder] || current_group.new_group(folder, folder)
  end
  
  # Check if file already exists in group
  filename = parts.last
  existing = current_group.files.find { |f| f.path&.end_with?(filename) }
  if existing
    puts "Skipped (exists): #{file_path}"
    next
  end
  
  file_ref = current_group.new_file("JarvisAI/#{file_path}")
  target.add_file_references([file_ref])
  
  puts "Added: #{file_path}"
end

project.save
puts "Project saved!"
