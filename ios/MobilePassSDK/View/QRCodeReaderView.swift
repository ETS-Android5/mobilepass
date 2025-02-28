//
//  QRCodeReaderView.swift
//  MobilePassSDK
//
//  Created by Erinc Cakir on 13.02.2021.
//

import SwiftUI
import AVFoundation

public enum ScanError: Error {
    case addInputFailed, addOutputFailed, noMatching, invalidFormat, invalidContent
}

@available(iOS 13.0, *)
public struct QRCodeReaderView: UIViewControllerRepresentable {
    private let configScanInterval: Double = 2.0
    public var completion: (Result<String, ScanError>) -> Void

    public init(completion: @escaping (Result<String, ScanError>) -> Void) {
        self.completion = completion
    }

    public func makeCoordinator() -> QRCodeReaderCoordinator {
        return QRCodeReaderCoordinator(parent: self)
    }

    public func makeUIViewController(context: Context) -> QRCodeReaderViewController {
        let viewController = QRCodeReaderViewController()
        viewController.delegate = context.coordinator
        return viewController
    }

    public func updateUIViewController(_ uiViewController: QRCodeReaderViewController, context: Context) {

    }
}

@available(iOS 13.0, *)
struct QRCodeReaderView_Previews: PreviewProvider {
    static var previews: some View {
        QRCodeReaderView() { result in
            // do nothing
        }
    }
}

@available(iOS 13.0, *)
public class QRCodeReaderCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    var parent: QRCodeReaderView
    var isFound = false
    var foundQRCodes: Dictionary<String, TimeInterval> = [:]
    let scanInterval: Double = 2.0

    init(parent: QRCodeReaderView) {
        self.parent = parent
    }

    public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            
            if (foundQRCodes.index(forKey: stringValue) != nil && foundQRCodes[stringValue] != nil && Date().timeIntervalSince1970 - foundQRCodes[stringValue]! < 2.5) {
                return
            }
            
            guard isFound == false else { return }
            
            foundQRCodes[stringValue] = Date().timeIntervalSince1970;
            
            let pattern = "https://(app|sdk).armongate.com/(rq|bd|o|s)/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(/[0-2]{1})?()?$"
            let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)

            if let match = regex?.firstMatch(in: stringValue, options: [], range: NSRange(location: 0, length: stringValue.utf16.count)) {
                // Set found flag
                isFound = true
                
                var prefix:     Substring = ""
                var uuid:       Substring = ""
                var direction:  Substring = ""
                
                if let prefixRange = Range(match.range(at: 2), in: stringValue) {
                    prefix = stringValue[prefixRange]
                }

                if let uuidRange = Range(match.range(at: 3), in: stringValue) {
                    uuid = stringValue[uuidRange]
                }
                
                if let directionRange = Range(match.range(at: 4), in: stringValue) {
                    direction = stringValue[directionRange]
                }
                
                let qrCodeContent: String = "\(prefix)/\(uuid)\(direction)"

                let activeQRCodeContent = ConfigurationManager.shared.getQRCodeContent(qrCodeData: qrCodeContent)
                
                if (activeQRCodeContent == nil) {
                    LogManager.shared.warn(message: "QR code reader could not find matching content for \(qrCodeContent)", code: LogCodes.PASSFLOW_QRCODE_READER_NO_MATCHING)
                    
                    isFound = false
                    parent.completion(.failure(.noMatching))
                } else {
                    if (activeQRCodeContent!.valid) {
                        parent.completion(.success(qrCodeContent))
                    } else {
                        LogManager.shared.warn(message: "QR code reader found content for \(qrCodeContent) but it is invalid", code: LogCodes.PASSFLOW_QRCODE_READER_INVALID_CONTENT)
                        
                        isFound = false
                        parent.completion(.failure(.invalidContent))
                    }
                }
            } else {
                LogManager.shared.warn(message: "QR code reader found unknown format > \(stringValue)", code: LogCodes.PASSFLOW_QRCODE_READER_INVALID_FORMAT)
                
                isFound = false
                parent.completion(.failure(.invalidFormat))
            }
        }
    }

    func didFail(reason: ScanError) {
        parent.completion(.failure(reason))
    }
}

@available(iOS 13.0, *)
public class QRCodeReaderViewController: UIViewController, QRCodeScannerDelegate {
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var delegate: QRCodeReaderCoordinator?
    
    override public func viewDidLoad() {
        super.viewDidLoad()

        DelegateManager.shared.setQRCodeScannerDelegate(delegate: self)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateOrientation),
                                               name: Notification.Name("UIDeviceOrientationDidChangeNotification"),
                                               object: nil)

        view.backgroundColor = UIColor.black
        captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            delegate?.didFail(reason: .addInputFailed)
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            delegate?.didFail(reason: .addOutputFailed)
            return
        }
    }

    override public func viewWillLayoutSubviews() {
        previewLayer?.frame = view.layer.bounds
    }

    @objc func updateOrientation() {
        guard let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation else { return }
        guard let connection = captureSession.connections.last, connection.isVideoOrientationSupported else { return }
        connection.videoOrientation = AVCaptureVideoOrientation(rawValue: orientation.rawValue) ?? .portrait
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateOrientation()
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if previewLayer == nil {
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        }
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        if (captureSession?.isRunning == false) {
            captureSession.startRunning()
        }
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if (captureSession?.isRunning == true) {
            captureSession.stopRunning()
        }

        NotificationCenter.default.removeObserver(self)
    }

    override public var prefersStatusBarHidden: Bool {
        return true
    }

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    public func onSwitchCamera() {
        //Change camera source
        if let session = captureSession {
            //Remove existing input
            guard let currentCameraInput: AVCaptureInput = session.inputs.first else {
                return
            }

            //Indicate that some changes will be made to the session
            session.beginConfiguration()
            session.removeInput(currentCameraInput)

            //Get new input
            var newCamera: AVCaptureDevice! = nil
            if let input = currentCameraInput as? AVCaptureDeviceInput {
                if (input.device.position == .back) {
                    newCamera = cameraWithPosition(position: .front)
                } else {
                    newCamera = cameraWithPosition(position: .back)
                }
            }

            //Add input to session
            var err: NSError?
            var newVideoInput: AVCaptureDeviceInput!
            do {
                newVideoInput = try AVCaptureDeviceInput(device: newCamera)
            } catch let err1 as NSError {
                err = err1
                newVideoInput = nil
            }

            if newVideoInput == nil || err != nil {
                LogManager.shared.error(message: "Switch camera failed! Exception: \(err?.localizedDescription ?? "-")", code: LogCodes.UI_SWITCH_CAMERA_FAILED)
            } else {
                session.addInput(newVideoInput)
            }

            //Commit all the configuration changes at once
            session.commitConfiguration()
        }
    }
    
    private func cameraWithPosition(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .unspecified)
        for device in discoverySession.devices {
            if device.position == position {
                return device
            }
        }

        return nil
    }
}
