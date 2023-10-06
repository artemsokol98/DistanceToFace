//
//  ViewController.swift
//  distanceToFaceVision
//
//  Created by Артем Соколовский on 06.10.2023.
//

import UIKit
import AVFoundation

let DIAGONAL_35MM_FILM = 43.2666

class ViewController: UIViewController {
	
	var session: AVCaptureSession = AVCaptureSession()
	var previewLayer: AVCaptureVideoPreviewLayer!

	
	private var distanceLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 120, height: 150))
	
	let dataOutputQueue: DispatchQueue = DispatchQueue(label: "video data queue",
										qos: .userInitiated,
										attributes: [],
										autoreleaseFrequency: .workItem)

	override func viewDidLoad() {
		super.viewDidLoad()
		
		configureCaptureSession()
		DispatchQueue.global(qos: .background).async {

			self.session.startRunning()
		}
		view.layer.addSublayer(previewLayer)
		view.addSubview(distanceLabel)
	}
	
	override func viewWillLayoutSubviews() {
		super.viewWillLayoutSubviews()
		
		distanceLabel.numberOfLines = 0
		distanceLabel.frame.origin.x = 50
		distanceLabel.frame.origin.y = 50
		distanceLabel.font = UIFont.boldSystemFont(ofSize: 30)

	}
	
	func configureCaptureSession() {
		
		guard let camera: AVCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
																	for: .video,
																	position: .front) else {
			return
		}
		
		do {
			
			let cameraInput: AVCaptureDeviceInput = try AVCaptureDeviceInput(device: camera)
			
			session.addInput(cameraInput)
			
		} catch {
			
			print(error.localizedDescription)
		}
		
		// Create the video data output
		
		let videoOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
		videoOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
		videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
		
		// Add the video output to the capture session
		
		session.addOutput(videoOutput)
		
		let videoConnection: AVCaptureConnection? = videoOutput.connection(with: .video)
		videoConnection?.videoOrientation = .portrait
		
		// Configure the preview layer
		
		previewLayer = AVCaptureVideoPreviewLayer(session: session)
		previewLayer.videoGravity = .resizeAspectFill
		previewLayer.frame = view.bounds
	}
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
	func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {

		let focalLength = getFocalLength(sampleBuffer: sampleBuffer)
		let image = imageFromSampleBuffer(sampleBuffer: sampleBuffer)
		guard let eyeDistancePx = visionFaceCrop(image: image) else { return }
		
		let distance = (focalLength * 6.2) / (eyeDistancePx / 2)
		DispatchQueue.main.async {
			self.distanceLabel.text = String(format: "%.2f", arguments: [distance])
			
		}
		
		print(distance)
	}
	
	func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage? {
		
		// Получаем изображение из CMSampleBuffer
		
		if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
			
			// Получаем размер изображения
			
			let ciImage: CIImage = CIImage(cvPixelBuffer: pixelBuffer)
			let context: CIContext = CIContext(options: nil)
			let imageRect: CGRect = CGRect(x: 0,
								   y: 0,
								   width: CVPixelBufferGetWidth(pixelBuffer),
								   height: CVPixelBufferGetHeight(pixelBuffer))
			
			// Создаем CGImage из CIImage
			
			if let cgImage = context.createCGImage(ciImage, from: imageRect) {
				
				return UIImage(cgImage: cgImage)
			}
		}
		
		return nil
	}
	
	func getFocalLength(sampleBuffer: CMSampleBuffer) -> Double {
			
		//Retrieving EXIF data of camara frame buffer
		
		let rawMetadata = CMCopyDictionaryOfAttachments(allocator: nil,
														target: sampleBuffer,
														attachmentMode: CMAttachmentMode(kCMAttachmentMode_ShouldPropagate))
		let metadata = CFDictionaryCreateMutableCopy(nil,
													 0,
													 rawMetadata) as NSMutableDictionary
		let exifData = metadata.value(forKey: "{Exif}") as? NSMutableDictionary
		
		let focalLength: Double = exifData?["FocalLength"] as! Double
		let focal_length_35mm = exifData?["FocalLenIn35mmFilm"] as! Double
		let pixelXDimension = exifData?["PixelXDimension"] as! Double
		let pixelYDimension = exifData?["PixelYDimension"] as! Double
//		let FNumber: Double = exifData?["FNumber"] as! Double
//		let ExposureTime: Double = exifData?["ExposureTime"] as! Double
//		let ISOSpeedRatingsArray = exifData!["ISOSpeedRatings"] as? NSArray
//		let ISOSpeedRatings: Double = ISOSpeedRatingsArray![0] as! Double
//		let CalibrationConstant: Double = 50
		
		//Calculating the luminosity
		
		let cropFactor = focal_length_35mm / focalLength
		
		let diagonal_matrix_mm = DIAGONAL_35MM_FILM / cropFactor
		
		let diagonal = hypot(pixelXDimension, pixelYDimension)
		
		let pixelSizeMM = diagonal_matrix_mm / diagonal
		
		var square = Double()
		
		if max4032x3024.contains(UIDevice.modelName) {
			
			square = 4032 * 3024
		} else if max3088x2320.contains(UIDevice.modelName) {
			
			square = 3088 * 2320
		} else if max2560x1920.contains(UIDevice.modelName) {
			
			square = 2560 * 1920
		} else if max1280x960.contains(UIDevice.modelName) {
			
			square = 1280 * 960
		}
		
		let sensorSquare = square * pow(pixelSizeMM, 2)
		
		let cropFactorReal = sqrt(864 / sensorSquare)
		
		let focalLength35MmReal = focalLength * cropFactorReal
		
		let film35Ratio = focal_length_35mm / focalLength35MmReal
		
		var focalLengthPx = focalLength / pixelSizeMM
		
		focalLengthPx = focalLengthPx / film35Ratio
		
		return focalLengthPx
//		let luminosity: Double = (CalibrationConstant * FNumber * FNumber ) / ( ExposureTime * ISOSpeedRatings )
//
//		return luminosity
		
	}
	
	func visionFaceCrop(image: UIImage?) -> Double? {
		
		var width = Double()
		
		guard let cgImage = image?.cgImage else { return width }
		
		cgImage.faceCrop { [weak self] result in
			
			switch result {
				
				case .success(let cgImage):
					let uiImage = UIImage(cgImage: cgImage)
					// print(cgImage.width)
					width = uiImage.size.width
					
				case .notFound, .failure( _):
					print("error")
				
			}
		}
		
		return width
	}
	
}


