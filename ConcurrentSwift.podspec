Pod::Spec.new do |s|
  s.name             = "ConcurrentSwift"
  s.version          = "0.2"
  s.summary          = "Simple work with Future"
  s.homepage         = "https://github.com/msfrms/ConcurrentSwift"
  s.license          = 'Apache License 2.0'
  s.author           = { "msfrms" => "msfrms@gmail.com" }

  s.platform         = :ios, '8.0'
  s.requires_arc     = true
  s.pod_target_xcconfig = { 'SWIFT_VERSION' => '4.2' }

  s.source           = { :git => 'https://github.com/msfrms/ConcurrentSwift.git', :tag => s.version.to_s }
  s.source_files	 = 'Source/*.swift'

  s.frameworks       = 'Foundation'
  s.module_name      = 'ConcurrentSwift'
  
end
