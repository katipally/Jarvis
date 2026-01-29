#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'JarvisAI.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.first

# Find and remove duplicate source files by filename
seen_names = {}
to_remove = []

target.source_build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  # Get just the filename
  filename = File.basename(file_ref.path.to_s) rescue nil
  next unless filename && filename.end_with?('.swift')
  
  if seen_names[filename]
    to_remove << build_file
    puts "Found duplicate: #{filename}"
  else
    seen_names[filename] = build_file
  end
end

to_remove.each do |build_file|
  build_file.remove_from_project
  puts "Removed: #{build_file.file_ref.path rescue 'unknown'}"
end

project.save
puts "\nCleaned up #{to_remove.count} duplicate build files"
puts "Project saved!"
