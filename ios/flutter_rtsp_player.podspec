Pod::Spec.new do |s|
  s.name             = 'flutter_rtsp_player'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin for RTSP stream playback using VLCKit.'
  s.description      = <<-DESC
A Flutter plugin for playing RTSP video streams on iOS using MobileVLCKit.
Exposes FFmpeg/VLC tuning options for latency, buffering, transport, and codec control.
  DESC
  s.homepage         = 'https://github.com/example/flutter_rtsp_player'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'example' => 'example@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'MobileVLCKit', '~> 3.6'
  s.platform         = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
