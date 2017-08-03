//
//  ViewController.swift
//  ARKit + QRMark
//
//  Created by Eugene Bokhan on 7/4/17.
//  Copyright © 2017 Eugene Bokhan. All rights reserved.
//

import ARKit
import UIKit
import Vision
import simd

class ViewController: UIViewController, ARSCNViewDelegate {
    
    private var requests = [VNRequest]()
    private var qrCode = QRCode()
    private lazy var drawLayer: CAShapeLayer = {
        let drawLayer = CAShapeLayer()
        self.sceneView.layer.addSublayer(drawLayer)
        drawLayer.frame = self.sceneView.bounds
        drawLayer.strokeColor = UIColor.green.cgColor
        drawLayer.lineWidth = 3
        drawLayer.lineJoin = kCALineJoinMiter
        drawLayer.fillColor = UIColor.clear.cgColor
        return drawLayer
    }()
    
    var pointGeom: SCNGeometry = {
        let geo = SCNSphere(radius: 0.002)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.blue
        material.locksAmbientWithDiffuse = true
        geo.firstMaterial = material
        return geo
    }()
    
    let earthGeometry: SCNGeometry = {
        let earth = SCNSphere(radius: 0.05)
        let earthMaterial = SCNMaterial()
        earthMaterial.diffuse.contents = UIImage(named: "earth_diffuse_4k")
        earthMaterial.specular.contents = UIImage(named: "earth_specular_1k")
        earthMaterial.emission.contents = UIImage(named: "earth_lights_4k")
        earthMaterial.normal.contents = UIImage(named: "earth_normal_4k")
        earthMaterial.multiply.contents = UIColor(white:  0.7, alpha: 1)
        earthMaterial.shininess = 0.05
        earth.firstMaterial = earthMaterial
        return earth
    }()
    
    var camera = SCNCamera()
    var cameraNode = SCNNode()
    var topLeftPointNode = SCNNode()
    var topRightPointNode = SCNNode()
    var bottomLeftPointNode = SCNNode()
    var bottomRightPointNode = SCNNode()
    var axesNode = createAxesNode(quiverLength: 0.06, quiverThickness: 1.0)
    var earthNode = SCNNode()
    var nodes = [SCNNode]()
    
    private let bufferQueue = DispatchQueue(label: "com.evgeniybokhan.BufferQueue",
                                            qos: .userInteractive,
                                            attributes: .concurrent)
    
    private let pnpSolver = PnPSolver()
    
    @IBAction func showButton(_ sender: UIButton) {
        addEarthNode()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupScene()
        setupNotifications()
        setupFocusSquare()
        setupVision()
        setupNodes()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.pause()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Prevent the screen from being dimmed after a while.
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Start the ARSession.
        restartPlaneDetection()
    }
    
    // MARK: - ARKit / ARSCNView
    let session = ARSession()
    var sessionConfig: ARSessionConfiguration = ARWorldTrackingSessionConfiguration()
    @IBOutlet var sceneView: ARSCNView!
    var screenCenter: CGPoint?
    
    func setupNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(fixSceneViewPosition), name: NSNotification.Name.UIApplicationDidChangeStatusBarOrientation, object: nil)
    }
    
    func setupScene() {
        // set up sceneView
        sceneView.delegate = self
        sceneView.session = session
        sceneView.antialiasingMode = .multisampling4X
        sceneView.automaticallyUpdatesLighting = false
        
        sceneView.preferredFramesPerSecond = 60
        sceneView.contentScaleFactor = 1.3
        //sceneView.showsStatistics = true
        
        let camera = SCNCamera()
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        sceneView.scene.rootNode.addChildNode(cameraNode)
        
        fixSceneViewPosition()
        
        //enableEnvironmentMapWithIntensity(25.0)
        
        DispatchQueue.main.async {
            self.screenCenter = self.sceneView.bounds.mid
        }
        
        if let camera = sceneView.pointOfView?.camera {
            camera.wantsHDR = true
            camera.wantsExposureAdaptation = true
            camera.exposureOffset = -1
            camera.minimumExposure = -1
        }
    }
    
    func enableEnvironmentMapWithIntensity(_ intensity: CGFloat) {
        sceneView.scene.lightingEnvironment.intensity = intensity
    }
    
    func restartPlaneDetection() {
        
        // configure session
        if let worldSessionConfig = sessionConfig as? ARWorldTrackingSessionConfiguration {
            worldSessionConfig.planeDetection = .horizontal
            session.run(worldSessionConfig, options: [.resetTracking, .removeExistingAnchors])
        }
    }
    
    // MARK: - SCNNodes
    
    func setupNodes() {
        topLeftPointNode.name = "Top Left"
        topLeftPointNode.geometry = self.pointGeom
        nodes.append(topLeftPointNode)
        topRightPointNode.name = "Top Right"
        topRightPointNode.geometry = self.pointGeom
        nodes.append(topRightPointNode)
        bottomLeftPointNode.name = "Bottom Left"
        bottomLeftPointNode.geometry = self.pointGeom
        let constraint = SCNLookAtConstraint.init(target: self.topLeftPointNode)
        constraint.worldUp = SCNUtils.getNormal(v0: self.topRightPointNode.position, v1: self.topLeftPointNode.position, v2:  self.bottomLeftPointNode.position)
        bottomLeftPointNode.constraints = [constraint]
        nodes.append(bottomLeftPointNode)
        
        // create and add a light to the scene
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = SCNLight.LightType.omni
        lightNode.position = SCNVector3(x: 0, y: 10, z: 10)
        sceneView.scene.rootNode.addChildNode(lightNode)
        
        // create and add an ambient light to the scene
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = SCNLight.LightType.ambient
        ambientLightNode.light!.color = UIColor.darkGray
        sceneView.scene.rootNode.addChildNode(ambientLightNode)
        
        // The Earth
        earthNode.geometry = earthGeometry
        
        let rotate = CABasicAnimation(keyPath:"rotation.w") // animate the angle
        rotate.byValue   = Double.pi * 20.0
        rotate.duration  = 100.0;
        rotate.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
        rotate.repeatCount = Float.infinity;
        
        earthNode.position.x = 0.08
        earthNode.position.y = 0.08
        earthNode.position.z = -0.08
        earthNode.rotation = SCNVector4Make(1, 0, 0, Float(Double.pi/6));
        earthNode.addAnimation(rotate, forKey: "rotate the earth")
        
        // Create a larger sphere to look like clouds
        let clouds = SCNSphere(radius: 0.053)
        clouds.segmentCount = 144; // 3 times the default
        let cloudsMaterial = SCNMaterial()
        
        cloudsMaterial.diffuse.contents = UIColor.white
        cloudsMaterial.locksAmbientWithDiffuse = true
        // Use a texture where RGB (or lack thereof) determines transparency of the material
        cloudsMaterial.transparent.contents = UIImage(named: "clouds_transparent_2K")
        cloudsMaterial.transparencyMode = SCNTransparencyMode.rgbZero;
        
        // Don't have the clouds cast shadows
        cloudsMaterial.writesToDepthBuffer = false;
        
        clouds.firstMaterial = cloudsMaterial;
        let cloudNode = SCNNode(geometry: clouds)
        
        earthNode.addChildNode(cloudNode)
        
        earthNode.rotation = SCNVector4Make(0, 1, 0, 0); // specify the rotation axis
        cloudNode.rotation = SCNVector4Make(0, 1, 0, 0); // specify the rotation axis
        
        // Animate the rotation of the earth and the clouds
        // ------------------------------------------------
        let rotateClouds = CABasicAnimation(keyPath: "rotation.w") // animate the angle
        rotateClouds.byValue   = -Double.pi * 2.0
        rotateClouds.duration  = 150.0;
        rotateClouds.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
        rotateClouds.repeatCount = Float.infinity;
        cloudNode.addAnimation(rotateClouds, forKey:"slowly move the clouds")
        
        sceneView.scene.rootNode.addChildNode(axesNode)
    }
    
    // MARK: - Vision
    
    func setupVision() {
        let barcodeRequest = VNDetectBarcodesRequest(completionHandler: barcodeDetectionHandler)
        barcodeRequest.symbologies = [.QR] // VNDetectBarcodesRequest.supportedSymbologies
        self.requests = [barcodeRequest]
    }
    
    func barcodeDetectionHandler(request: VNRequest, error: Error?) {
        guard let results = request.results else { return }
        
        DispatchQueue.main.async() {
            // Loop through the results found.
            let path = CGMutablePath()
            
            guard self.sceneView.session.currentFrame != nil else {
                return
            }
            
            for result in results {
                guard let barcode = result as? VNBarcodeObservation else { continue }
                self.qrCode.topLeftCorner.screenPosition = self.convert(point: barcode.topLeft)
                path.move(to: self.qrCode.topLeftCorner.screenPosition)
                self.qrCode.topRightCorner.screenPosition = self.convert(point: barcode.topRight)
                path.addLine(to: self.qrCode.topRightCorner.screenPosition)
                self.qrCode.bottomRightCorner.screenPosition = self.convert(point: barcode.bottomRight)
                path.addLine(to: self.qrCode.bottomRightCorner.screenPosition)
                self.qrCode.bottomLeftCorner.screenPosition = self.convert(point: barcode.bottomLeft)
                path.addLine(to: self.qrCode.bottomLeftCorner.screenPosition)
                path.addLine(to: self.qrCode.topLeftCorner.screenPosition)
                
                //    v0 --------------v3
                //    |             __/ |
                //    |          __/    |
                //    |       __/       |
                //    |    __/          |
                //    | __/             |
                //    v1 --------------v2
                
                let imageResolution = self.session.currentFrame?.camera.imageResolution
                let viewSize = self.sceneView.bounds.size
                
                let xCoef = (imageResolution?.width)! / viewSize.width
                let yCoef = (imageResolution?.height)! / viewSize.height
                
                let _c0 = CGPoint(x: self.qrCode.topLeftCorner.screenPosition.x * xCoef, y: self.qrCode.topLeftCorner.screenPosition.y * yCoef)
                let _c1 = CGPoint(x: self.qrCode.bottomLeftCorner.screenPosition.x * xCoef, y: self.qrCode.bottomLeftCorner.screenPosition.y * yCoef)
                let _c2 = CGPoint(x: self.qrCode.bottomRightCorner.screenPosition.x * xCoef, y: self.qrCode.bottomRightCorner.screenPosition.y * yCoef)
                let _c3 = CGPoint(x: self.qrCode.topRightCorner.screenPosition.x * xCoef, y: self.qrCode.topRightCorner.screenPosition.y * yCoef)
                
                let half_of_real_size: Float = 0.05 // 10sm / 2 = 0.05m 
                
                let f_x = self.session.currentFrame?.camera.intrinsics.columns.0.x // Focal length in x axis
                let f_y = self.session.currentFrame?.camera.intrinsics.columns.1.y // Focal length in y axis
                let c_x = self.session.currentFrame?.camera.intrinsics.columns.2.x // Camera primary point x
                let c_y = self.session.currentFrame?.camera.intrinsics.columns.2.y // Camera primary point y
                
                self.pnpSolver.processCorners(_c0, _c1, _c2, _c3, half_of_real_size, f_x!, f_y!, c_x!, c_y!)
                
                let qw = self.pnpSolver.qw
                let qx = self.pnpSolver.qx
                let qy = -self.pnpSolver.qy
                let qz = -self.pnpSolver.qz
                let t0 = self.pnpSolver.t0
                let t1 = -self.pnpSolver.t1
                let t2 = -self.pnpSolver.t2

                let r1 = vector_float4(x: 1 - 2*qy*qy - 2*qz*qz, y: (2*qx*qy + 2*qz*qw), z: (2*qx*qz - 2*qy*qw), w: 0)
                let r2 = vector_float4(x: (2*qx*qy - 2*qz*qw), y: 1 - 2*qx*qx - 2*qz*qz, z: (2*qy*qz + 2*qx*qw), w: 0)
                let r3 = vector_float4(x: (2*qx*qz + 2*qy*qw), y: (2*qy*qz - 2*qx*qw), z: 1 - 2*qx*qx - 2*qy*qy, w: 0)
                let r4 = vector_float4(x: t0, y: t1, z: t2, w: 1)

                let modelMatrix = matrix_float4x4(r1, r2, r3, r4)
                
                let cameraTransform = self.session.currentFrame?.camera.transform
               
                let pose = SCNMatrix4(matrix_multiply(cameraTransform!, modelMatrix))

                self.axesNode.transform = pose
            }
            self.drawLayer.path = path
        }
    }
    
    private func convert(point: CGPoint) -> CGPoint {
        var convertedPoint = CGPoint()
        let height = sceneView.bounds.size.height
        let width = sceneView.bounds.size.width
        switch UIApplication.shared.statusBarOrientation {
        case .portrait:
            convertedPoint.x = point.x * width
            convertedPoint.y = (1 - point.y) * height
        case .portraitUpsideDown:
            convertedPoint.x = (1 - point.x) * width
            convertedPoint.y = point.y * height
        case .landscapeLeft:
            convertedPoint.x = point.y * width
            convertedPoint.y = point.x * height
        case .landscapeRight:
            convertedPoint.x = (1 - point.y) * width
            convertedPoint.y = (1 - point.x) * height
        case .unknown:
            convertedPoint.x = point.x * width
            convertedPoint.y = (1 - point.y) * height
        }
        return convertedPoint
    }
    
    // MARK: - Add nodes to SceneView
    
    private func addNodeAtQRCorner(qrCorner: QRCode.corner) {
        for node in nodes {
            if node.name == qrCorner.name {
                node.removeFromParentNode()
                node.position = (self.sceneView.hitTestWithFeatures(qrCorner.screenPosition).first?.position)!
                self.sceneView.scene.rootNode.addChildNode(node)
            }
        }
    }
    
    @objc private func addEarthNode() {
        axesNode.addChildNode(earthNode)
    }
    
    // MARK: - Focus Square
    var focusSquare: FocusSquare?
    
    func setupFocusSquare() {
        focusSquare?.isHidden = true
        focusSquare?.removeFromParentNode()
        focusSquare = FocusSquare()
        sceneView.scene.rootNode.addChildNode(focusSquare!)
        
        //textManager.scheduleMessage("TRY MOVING LEFT OR RIGHT", inSeconds: 5.0, messageType: .focusSquare)
    }
    
    func updateFocusSquare() {
        guard let screenCenter = screenCenter else { return }
        focusSquare?.unhide()
        
        let (worldPos, planeAnchor, _) = worldPositionFromScreenPosition(screenCenter, objectPos: focusSquare?.position)
        if let worldPos = worldPos {
            focusSquare?.update(for: worldPos, planeAnchor: planeAnchor, camera: self.session.currentFrame?.camera)
            //textManager.cancelScheduledMessage(forType: .focusSquare)
        }
        
        
        guard let pixelBuffer = self.session.currentFrame?.capturedImage else { return }
        
        var requestOptions: [VNImageOption: Any] = [:]
        
        requestOptions = [.cameraIntrinsics: self.session.currentFrame?.camera.intrinsics as Any]
        
        
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: CGImagePropertyOrientation(rawValue: 6)!, options: requestOptions)
        
        do {
            try imageRequestHandler.perform(self.requests)
        } catch {
            print(error)
        }
    }
    
    var dragOnInfinitePlanesEnabled = false
    
    func worldPositionFromScreenPosition(_ position: CGPoint,
                                         objectPos: SCNVector3?,
                                         infinitePlane: Bool = false) -> (position: SCNVector3?, planeAnchor: ARPlaneAnchor?, hitAPlane: Bool) {
        
        // -------------------------------------------------------------------------------
        // 1. Always do a hit test against exisiting plane anchors first.
        //    (If any such anchors exist & only within their extents.)
        
        let planeHitTestResults = sceneView.hitTest(position, types: .existingPlaneUsingExtent)
        if let result = planeHitTestResults.first {
            
            let planeHitTestPosition = SCNVector3.positionFromTransform(result.worldTransform)
            let planeAnchor = result.anchor
            
            // Return immediately - this is the best possible outcome.
            return (planeHitTestPosition, planeAnchor as? ARPlaneAnchor, true)
        }
        
        // -------------------------------------------------------------------------------
        // 2. Collect more information about the environment by hit testing against
        //    the feature point cloud, but do not return the result yet.
        
        var featureHitTestPosition: SCNVector3?
        var highQualityFeatureHitTestResult = false
        
        let highQualityfeatureHitTestResults = sceneView.hitTestWithFeatures(position, coneOpeningAngleInDegrees: 18, minDistance: 0.2, maxDistance: 2.0)
        
        if !highQualityfeatureHitTestResults.isEmpty {
            let result = highQualityfeatureHitTestResults[0]
            featureHitTestPosition = result.position
            highQualityFeatureHitTestResult = true
        }
        
        // -------------------------------------------------------------------------------
        // 3. If desired or necessary (no good feature hit test result): Hit test
        //    against an infinite, horizontal plane (ignoring the real world).
        
        if (infinitePlane && dragOnInfinitePlanesEnabled) || !highQualityFeatureHitTestResult {
            
            let pointOnPlane = objectPos ?? SCNVector3Zero
            
            let pointOnInfinitePlane = sceneView.hitTestWithInfiniteHorizontalPlane(position, pointOnPlane)
            if pointOnInfinitePlane != nil {
                return (pointOnInfinitePlane, nil, true)
            }
        }
        
        // -------------------------------------------------------------------------------
        // 4. If available, return the result of the hit test against high quality
        //    features if the hit tests against infinite planes were skipped or no
        //    infinite plane was hit.
        
        if highQualityFeatureHitTestResult {
            return (featureHitTestPosition, nil, false)
        }
        
        // -------------------------------------------------------------------------------
        // 5. As a last resort, perform a second, unfiltered hit test against features.
        //    If there are no features in the scene, the result returned here will be nil.
        
        let unfilteredFeatureHitTestResults = sceneView.hitTestWithFeatures(position)
        if !unfilteredFeatureHitTestResults.isEmpty {
            let result = unfilteredFeatureHitTestResults[0]
            return (result.position, nil, false)
        }
        
        return (nil, nil, false)
    }
    
    // MARK: - Fix view on orientation change
    
    @objc func fixSceneViewPosition() {
        let viewWidth = self.view.bounds.width
        let viewHeight = self.view.bounds.height
        let sceneViewPortraitWidth = viewWidth
        let sceneViewPortraitHeight = viewWidth / 9 * 16
        let sceneViewLandscapeWidth = viewHeight / 9 * 16
        let sceneViewLandscapeHeight = viewHeight
        
        let landscapeWidthDifference = abs(viewWidth - sceneViewLandscapeWidth)
        let portraitHeightDifference = abs(viewHeight - sceneViewPortraitHeight)
        
        switch UIApplication.shared.statusBarOrientation {
        case .portrait:
            self.sceneView.bounds = CGRect(x: 0, y: -portraitHeightDifference / 2, width: sceneViewPortraitWidth, height: sceneViewPortraitHeight)
        case .portraitUpsideDown:
            self.sceneView.bounds = CGRect(x: 0, y: -portraitHeightDifference / 2, width: sceneViewPortraitWidth, height: sceneViewPortraitHeight)
        case .landscapeLeft:
            self.sceneView.bounds = CGRect(x: -landscapeWidthDifference / 2, y: 0, width: sceneViewLandscapeWidth, height: sceneViewLandscapeHeight)
        case .landscapeRight:
            self.sceneView.bounds = CGRect(x: -landscapeWidthDifference / 2, y: 0, width: sceneViewLandscapeWidth, height: sceneViewLandscapeHeight)
        case .unknown: break
        }
        self.sceneView.frame = self.sceneView.bounds
        drawLayer.frame = self.sceneView.frame
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        //refreshFeaturePoints()
        
        DispatchQueue.main.async {
            self.updateFocusSquare()
        }
    }
}
