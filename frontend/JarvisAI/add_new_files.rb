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
  'Views/FileAttachmentView.swift'
]

new_files.each do |file_path|
  parts = file_path.split('/')
  folder = parts[0]
  filename = parts[1]
  
  folder_group = main_group[folder] || main_group.new_group(folder, folder)
  
  file_ref = folder_group.new_file("JarvisAI/#{file_path}")
  target.add_file_references([file_ref])
  
  puts "Added: #{file_path}"
end

project.save
puts "Project saved!"
