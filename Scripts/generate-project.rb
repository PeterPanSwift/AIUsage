#!/usr/bin/env ruby
require 'xcodeproj'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.new(File.join(root, 'AIUsage.xcodeproj'))
project.root_object.attributes['LastUpgradeCheck'] = '2700'
project.root_object.development_region = 'zh_TW'
app = project.new_target(:application, 'AIUsage', :osx, '27.0')
controls = project.new_target(:app_extension, 'AIUsageControls', :osx, '27.0')

project.build_configurations.each do |config|
  config.build_settings.merge!('MACOSX_DEPLOYMENT_TARGET' => '27.0', 'SWIFT_VERSION' => '6.0',
    'CLANG_ENABLE_MODULES' => 'YES', 'CODE_SIGN_STYLE' => 'Automatic',
    'SWIFT_STRICT_CONCURRENCY' => 'complete')
  config.build_settings['DEVELOPMENT_TEAM'] = ENV['DEVELOPMENT_TEAM'] if ENV['DEVELOPMENT_TEAM']
end

[[app, 'App', 'local.aiusage'], [controls, 'Controls', 'local.aiusage.controls']].each do |target, name, identifier|
  target.build_configurations.each do |config|
    config.build_settings.merge!('PRODUCT_BUNDLE_IDENTIFIER' => identifier,
      'INFOPLIST_FILE' => "Config/#{name}-Info.plist", 'CODE_SIGN_ENTITLEMENTS' => "Config/#{name}.entitlements",
      'GENERATE_INFOPLIST_FILE' => 'NO', 'ENABLE_APP_SANDBOX' => name == 'Controls' ? 'YES' : 'NO',
      'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks',
      'SWIFT_EMIT_LOC_STRINGS' => 'YES')
    config.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) APP_HOST' if name == 'App'
    config.build_settings['APPLICATION_EXTENSION_API_ONLY'] = 'YES' if name == 'Controls'
    config.build_settings['SKIP_INSTALL'] = 'YES' if name == 'Controls'
  end
end

Dir.glob(File.join(root, 'Sources/{Core,Shared,App,Controls}/*.swift')).sort.each do |path|
  relative = path.delete_prefix(root + '/')
  reference = project.main_group.new_file(relative)
  if relative.include?('/App/') || relative.end_with?('UsageClient.swift') || relative.end_with?('UsageParsers.swift')
    app.add_file_references([reference])
  elsif relative.include?('/Controls/')
    controls.add_file_references([reference])
  else
    app.add_file_references([reference])
    controls.add_file_references([reference])
  end
end
Dir.glob(File.join(root, 'Config/*')).sort.each { |path| project.main_group.new_file(path.delete_prefix(root + '/')) }
app.add_dependency(controls)
embed = app.new_copy_files_build_phase('Embed App Extensions')
embed.dst_subfolder_spec = '13'
embed.add_file_reference(controls.product_reference).settings = {'ATTRIBUTES' => ['RemoveHeadersOnCopy']}
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.set_launch_target(app)
scheme.save_as(project.path, 'AIUsage', true)
project.save
