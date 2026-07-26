require 'xcodeproj'

project_path = '/Users/hetpatel/Desktop/sniphet/Snip/hetpaste.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

models_group = project.main_group.find_subpath(File.join('hetpaste', 'Models'), true)
views_group = project.main_group.find_subpath(File.join('hetpaste', 'Views'), true)

chain_file = models_group.new_file('Chain.swift')
chain_view_file = views_group.new_file('ChainView.swift')

target.add_file_references([chain_file, chain_view_file])

project.save
