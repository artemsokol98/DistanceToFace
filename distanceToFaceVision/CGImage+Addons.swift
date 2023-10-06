//
//  CGImage+Addons.swift
//  distanceToFaceVision
//
//  Created by Артем Соколовский on 06.10.2023.
//

import Foundation
import Vision
import AVFoundation

public enum FaceCropResult {
	
	case success(CGImage)
	case notFound
	case failure(Error)
}

public extension CGImage {
	
	@available(iOS 11.0, *)
	func faceCrop(margin: CGFloat = 0, completion: @escaping (FaceCropResult) -> Void) {
		
		let req = VNDetectFaceRectanglesRequest { request, error in
			
			if let error = error {
				
				completion(.failure(error))
				
				return
			}
			
			guard let results = request.results, !results.isEmpty else {
				
				completion(.notFound)
				
				return
			}
			
			var faces: [VNFaceObservation] = []
			
			for result in results {
				
				guard let face = result as? VNFaceObservation else { continue }
				faces.append(face)
			}
			
			let croppingRect = self.getCroppingRect(for: faces, margin: margin)
			let faceImage = self.cropping(to: croppingRect)
			
			guard let result = faceImage else {
				
				completion(.notFound)
				
				return
			}
			
			completion(.success(result))
		}
		
		do {
			
			try VNImageRequestHandler(cgImage: self, options: [:]).perform([req])
			
		} catch let error {
			
			completion(.failure(error))
		}
	}
	
	@available(iOS 11.0, *)
	private func getCroppingRect(for faces: [VNFaceObservation], margin: CGFloat) -> CGRect {
		
		var totalX: CGFloat = CGFloat(0)
		var totalY: CGFloat = CGFloat(0)
		var totalW: CGFloat = CGFloat(0)
		var totalH: CGFloat = CGFloat(0)
		var minX: CGFloat = CGFloat.greatestFiniteMagnitude
		var minY: CGFloat = CGFloat.greatestFiniteMagnitude
		let numFaces: CGFloat = CGFloat(faces.count)
		
		for face in faces {
			
			let w: CGFloat = face.boundingBox.width * CGFloat(width)
			let h: CGFloat = face.boundingBox.height * CGFloat(height)
			let x: CGFloat = face.boundingBox.origin.x * CGFloat(width)
			let y: CGFloat = (1 - face.boundingBox.origin.y) * CGFloat(height) - h
			totalX += x
			totalY += y
			totalW += w
			totalH += h
			minX = .minimum(minX, x)
			minY = .minimum(minY, y)
		}
		
		let avgX: CGFloat = totalX / numFaces
		let avgY: CGFloat = totalY / numFaces
		let avgW: CGFloat = totalW / numFaces
		let avgH: CGFloat = totalH / numFaces
		
		let offset: CGFloat = margin + avgX - minX
		
		return CGRect(x: avgX - offset,
					  y: avgY - offset,
					  width: avgW + (offset * 2),
					  height: avgH + (offset * 2))
	}
}
