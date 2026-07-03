import Foundation
import UIKit
import CoreGraphics

// MARK: - Image Processing (Porting Pillow logic from Python)
class ImageProcessor {
    
    /// Converts UIImage to 1-bit bitmap data suitable for thermal printer
    /// Matches the logic of Python's Pillow conversion used in peripage_logic.py
    static func processImageToBitmap(_ image: UIImage, width: Int = 384) -> Data? {
        // Resize image to printer width (maintain aspect ratio)
        let aspectRatio = image.size.height / image.size.width
        let newHeight = Int(Double(width) * aspectRatio)
        
        guard let resizedImage = resizeImage(image, width: width, height: newHeight) else {
            return nil
        }
        
        // Convert to grayscale and then to 1-bit black/white
        guard let grayImage = convertToGrayscale(resizedImage) else {
            return nil
        }
        
        // Threshold to 1-bit (dithering could be added here for better quality)
        let bitmapData = thresholdTo1Bit(grayImage, width: width, height: newHeight)
        
        return bitmapData
    }
    
    /// Resize image to specific dimensions
    private static func resizeImage(_ image: UIImage, width: Int, height: Int) -> UIImage? {
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: rendererFormat)
        
        let resizedImage = renderer.image { context in
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        
        return resizedImage
    }
    
    /// Convert image to grayscale
    private static func convertToGrayscale(_ image: UIImage) -> CGImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitsPerComponent = 8
        let bytesPerRow = width
        
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: bitsPerComponent,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: 0) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
    
    /// Threshold grayscale image to 1-bit bitmap
    /// Uses simple thresholding (can be improved with Floyd-Steinberg dithering)
    private static func thresholdTo1Bit(_ grayImage: CGImage, width: Int, height: Int) -> Data {
        guard let dataProvider = grayImage.dataProvider,
              let pixelData = dataProvider.data else {
            return Data()
        }
        
        let pixels = CFDataGetBytePtr(pixelData)
        var bitmapData = Data()
        
        // Thermal printers usually expect data in chunks of 8 pixels (1 byte)
        // Each bit represents a pixel (0 = white, 1 = black)
        let threshold: UInt8 = 128
        
        for y in 0..<height {
            var rowBytes: [UInt8] = []
            var currentByte: UInt8 = 0
            var bitPosition = 7 // MSB first
            
            for x in 0..<width {
                let pixelIndex = y * width + x
                let pixelValue = pixels![pixelIndex]
                
                // Threshold: if pixel < 128, it's black (1), else white (0)
                let bit: UInt8 = (pixelValue < threshold) ? 1 : 0
                
                currentByte |= (bit << bitPosition)
                bitPosition -= 1
                
                if bitPosition < 0 {
                    rowBytes.append(currentByte)
                    currentByte = 0
                    bitPosition = 7
                }
            }
            
            // Handle remaining bits in the last byte if width is not multiple of 8
            if bitPosition != 7 {
                rowBytes.append(currentByte)
            }
            
            bitmapData.append(contentsOf: rowBytes)
        }
        
        return bitmapData
    }
}
