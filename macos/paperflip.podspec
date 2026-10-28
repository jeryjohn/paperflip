Pod::Spec.new do |s|
  s.name             = 'paperflip'
  s.version          = '0.1.0'
  s.summary          = 'A mesh-based page-flip engine for Flutter.'
  s.description      = <<-DESC
Paperflip renders custom, EPUB, and PDF content with a mesh-based page-curl engine.
                       DESC
  s.homepage         = 'https://github.com/jeryjohn/paperflip'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = 'Jerin John'
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.osx.deployment_target = '10.15'
  s.swift_version    = '5.0'
  s.static_framework = true
end
