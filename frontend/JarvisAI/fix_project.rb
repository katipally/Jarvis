#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'JarvisAI.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Remove all bad file references (those with doubled paths)
to_remove = []
target.source_build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  path = file_ref.path.to_s rescue nil
  next unless path
  
  # Check for doubled paths like JarvisAI/Views/JarvisAI/
  if path.include?('JarvisAI/') && path.scan('JarvisAI/').length > 1
    to_remove << build_file
    puts "Found bad path: #{path}"
  end
end

to_remove.each do |bf|
  bf.remove_from_project
  puts "Removed bad reference"
end

# Now add the correct file references
main_group = project.main_group['JarvisAI']

new_files = [
  { path: 'Services/RayMode/AppSearchManager.swift', folder: ['Services', 'RayMode'] },
  { path: 'Services/RayMode/RayModeViewModel.swift', folder: ['Services', 'RayMode'] },
  { path: 'Views/RayModeView.swift', folder: ['Views'] }
]

new_files.each do |file_info|
  # Navigate to correct group
  current_group = main_group
  file_info[:folder].each do |folder|
    current_group = current_group[folder] || current_group.new_group(folder, folder)
  end
  
  filename = File.basename(file_info[:path])
  
  # Check if already exists correctly
  existing = target.source_build_phase.files.find do |bf|
    bf.file_ref && bf.file_ref.path.to_s.end_with?(filename)
  end
  
  if existing
    puts "Already exists: #{filename}"
    next
  end
  
  # Add file with correct path
  file_ref = current_group.new_file(file_info[:path])
  target.add_file_references([file_ref])
  puts "Added: #{file_info[:path]}"
end

project.save
puts "\nProject saved!"
