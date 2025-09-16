#
# Be sure to run `pod lib lint VerisoulSDK.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'VerisoulSDK'
  s.version          = '0.4.57'
  s.summary          = 'Verisoul helps businesses stop fake accounts and fraud'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
Today, legitimate applications are inundated with fake users. Fake users includes programmatic users like bots or botnets as well as real people who are multi-accounting, malicious, cheating, and spamming applications. The problem is so widespread that estimates show fake users affect 95% of B2C businesses and cause over $100 billion of losses annually.

Verisoul's solution provides a seamless way to understand an application's fake user prevalence and take the first steps toward preventing fake user harm. The client SDK and backend API enable continuous monitoring and prevention of multi-accounting, bots and high risk accounts. It's critical for applications to prevent such accounts both at the onset but also at critical moments in an accounts lifespan.

The Verisoul platform provides an all-in-one fake user prevention solution that can adapt to a range of needs all with a single quick integration. Verisoul helps to establish that each account is:

1.Real (not bots)
2.Trusted (not fraudsters)
3.Unique (not duplicates)
                       DESC

  s.homepage         = 'https://www.verisoul.ai/'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Verisoul' => 'hello@verisoul.ai' }
  s.source           = { :git => 'https://github.com/verisoul/ios-sdk.git', :tag => s.version.to_s }
  s.swift_versions = [5.0]
  s.ios.deployment_target = '14.0'
  s.ios.vendored_frameworks = [
    "Sources/VerisoulSDK.xcframework"
  ]

end
