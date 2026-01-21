platform :ios, '13.0'

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))

  # Force compatible pod versions
  pod 'Firebase/CoreOnly', '11.15.0'
  pod 'FirebaseCore', '11.15.0'
  pod 'GoogleUtilities', '8.1.0'
  pod 'GoogleMLKit/MLKitCore', '6.0.0'
end
