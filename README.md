# ARKit + QRMarker

This test project is able to get an initial anchor near the marker and track it even if the marker is out of view. An inital anchor is a bottom left qorner of the QR mark. If you know a better solution for using qr marks in ARKit please let me know =)

## Requirements

* Xcode 9 Beta 2
* iOS 11 Beta 2
* A9 or better chip for ARWorldTrackingSessionConfiguration

> Note: The app automatically detects if your device supports the ARWorldTrackingSessionConfiguration. If not, it will use the less immersive ARSessionConfiguration, which is to be supported by all devices. However, at the current time (Beta 2), ARSessionConfiguration is also only supported by devices with an A9 or better chip. See the [release notes](https://9to5mac.com/2017/06/21/apple-ios-11-beta-2/) for details. **This means you need an iPhone 6S or better to use ARKit at the current time.**

![status](https://github.com/evgeniybokhan/ARKit-QRMarker/blob/master/Media/ARKit%20+%20QRMark.gif "Status GIF")
