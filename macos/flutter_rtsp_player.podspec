Pod::Spec.new do |s|
  s.name             = 'flutter_rtsp_player'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin for RTSP stream playback using VLCKit (macOS).'
  s.description      = <<-DESC
A Flutter plugin for playing RTSP video streams on macOS using VLCKit.
Exposes FFmpeg/VLC tuning options for latency, buffering, transport, and codec control.
  DESC
  s.homepage         = 'https://github.com/example/flutter_rtsp_player'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'example' => 'example@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.dependency 'VLCKit', '~> 3.6'
  s.platform         = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
