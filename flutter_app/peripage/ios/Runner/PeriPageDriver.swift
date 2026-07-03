import Foundation

// MARK: - Protocol Constants (Porting from protocol.py)
struct PeriPageProtocol {
    // Printer Initialization
    static let INIT: [UInt8] = [0x1B, 0x40]
    
    // Feed lines
    static func FEED_LINES(_ count: Int) -> [UInt8] {
        return [0x1B, 0x64, UInt8(count)]
    }
    
    // Cut paper
    static let CUT_PAPER: [UInt8] = [0x1D, 0x56, 0x42, 0x00]
    
    // Text formatting
    static let TEXT_ALIGN_LEFT: [UInt8] = [0x1B, 0x61, 0x00]
    static let TEXT_ALIGN_CENTER: [UInt8] = [0x1B, 0x61, 0x01]
    static let TEXT_ALIGN_RIGHT: [UInt8] = [0x1B, 0x61, 0x02]
    
    static let TEXT_SIZE_NORMAL: [UInt8] = [0x1D, 0x21, 0x00]
    static let TEXT_SIZE_DOUBLE: [UInt8] = [0x1D, 0x21, 0x11]
    
    static let TEXT_BOLD_OFF: [UInt8] = [0x1B, 0x45, 0x00]
    static let TEXT_BOLD_ON: [UInt8] = [0x1B, 0x45, 0x01]
    
    // Image constants
    static let IMG_RASTER_FORMAT: [UInt8] = [0x1D, 0x76, 0x30, 0x00]
}

// MARK: - Driver Logic (Porting from driver.py)
class PeriPageDriver {
    
    private var commandBuffer: [UInt8] = []
    
    // Reset buffer
    func reset() {
        commandBuffer.removeAll()
        commandBuffer.append(contentsOf: PeriPageProtocol.INIT)
    }
    
    // Add text to buffer
    func addText(_ text: String, align: String = "left", bold: Bool = false, doubleSize: Bool = false) {
        // Alignment
        switch align {
        case "center":
            commandBuffer.append(contentsOf: PeriPageProtocol.TEXT_ALIGN_CENTER)
        case "right":
            commandBuffer.append(contentsOf: PeriPageProtocol.TEXT_ALIGN_RIGHT)
        default:
            commandBuffer.append(contentsOf: PeriPageProtocol.TEXT_ALIGN_LEFT)
        }
        
        // Style
        if bold {
            commandBuffer.append(contentsOf: PeriPageProtocol.TEXT_BOLD_ON)
        } else {
            commandBuffer.append(contentsOf: PeriPageProtocol.TEXT_BOLD_OFF)
        }
        
        if doubleSize {
            commandBuffer.append(contentsOf: PeriPageProtocol.TEXT_SIZE_DOUBLE)
        } else {
            commandBuffer.append(contentsOf: PeriPageProtocol.TEXT_SIZE_NORMAL)
        }
        
        // Content
        commandBuffer.append(contentsOf: Data(text.utf8))
        commandBuffer.append(0x0A) // New line
    }
    
    // Add image data (expects pre-processed bitmap data from Flutter or Swift ImageProcessor)
    func addImage(_ imageData: Data) {
        // In a real scenario, we need to convert UIImage to 1-bit bitmap here
        // For now, we assume imageData is already formatted as 1-bit raster data
        // This matches the logic where Python would use Pillow to preprocess
        
        commandBuffer.append(contentsOf: PeriPageProtocol.IMG_RASTER_FORMAT)
        
        // Calculate dimensions (assuming simple structure for now, needs refinement based on actual bitmap header)
        // This is a placeholder; actual implementation needs width/height from bitmap
        let height = imageData.count / 32 // Example calculation
        let widthBytes = 32
        
        // Append dimension bytes (little endian)
        commandBuffer.append(UInt8(widthBytes & 0xFF))
        commandBuffer.append(UInt8((widthBytes >> 8) & 0xFF))
        commandBuffer.append(UInt8(height & 0xFF))
        commandBuffer.append(UInt8((height >> 8) & 0xFF))
        
        commandBuffer.append(contentsOf: imageData)
    }
    
    // Feed and Cut
    func finish() {
        commandBuffer.append(contentsOf: PeriPageProtocol.FEED_LINES(4))
        commandBuffer.append(contentsOf: PeriPageProtocol.CUT_PAPER)
    }
    
    // Get final command buffer
    func getCommands() -> Data {
        return Data(commandBuffer)
    }
}
