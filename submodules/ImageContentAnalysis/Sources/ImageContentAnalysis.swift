import Foundation
import UIKit
import Vision
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramUIPreferences

private final class CachedImageRecognizedContent: Codable {
    public let results: [RecognizedContent]
    
    public init(results: [RecognizedContent]) {
        self.results = results
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.results = try container.decode([RecognizedContent].self, forKey: "results")
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(self.results, forKey: "results")
    }
}

private func cachedImageRecognizedContent(postbox: Postbox, messageId: MessageId) -> Signal<CachedImageRecognizedContent?, NoError> {
    return postbox.transaction { transaction -> CachedImageRecognizedContent? in
        let key = ValueBoxKey(length: 8)
        key.setInt32(0, value: messageId.namespace)
        key.setInt32(4, value: messageId.id)
        if let entry = transaction.retrieveItemCacheEntry(id: ItemCacheEntryId(collectionId: ApplicationSpecificItemCacheCollectionId.cachedImageRecognizedContent, key: key))?.get(CachedImageRecognizedContent.self) {
            return entry
        } else {
            return nil
        }
    }
}

private let collectionSpec = ItemCacheCollectionSpec(lowWaterItemCount: 50, highWaterItemCount: 100)

private func updateCachedImageRecognizedContent(postbox: Postbox, messageId: MessageId, content: CachedImageRecognizedContent?) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        let key = ValueBoxKey(length: 8)
        key.setInt32(0, value: messageId.namespace)
        key.setInt32(4, value: messageId.id)
        let id = ItemCacheEntryId(collectionId: ApplicationSpecificItemCacheCollectionId.cachedImageRecognizedContent, key: key)
        if let content = content, let entry = CodableEntry(content) {
            transaction.putItemCacheEntry(id: id, entry: entry, collectionSpec: collectionSpec)
        } else {
            transaction.removeItemCacheEntry(id: id)
        }
    }
}

extension CGPoint {
    func distanceTo(_ a: CGPoint) -> CGFloat {
        let xDist = a.x - x
        let yDist = a.y - y
        return CGFloat(sqrt((xDist * xDist) + (yDist * yDist)))
    }
    
    func midPoint(_ other: CGPoint) -> CGPoint {
        return CGPoint(x: (self.x + other.x) / 2.0, y: (self.y + other.y) / 2.0)
    }
}

public struct RecognizedContent: Codable {
    public enum Content {
        case text(text: String, words: [(Range<String.Index>, Rect)])
        case qrCode(payload: String)
    }
    
    public struct Rect: Codable {
        struct Point: Codable {
            let x: Double
            let y: Double
            
            init(cgPoint: CGPoint) {
                self.x = cgPoint.x
                self.y = cgPoint.y
            }
            
            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: StringCodingKey.self)
             
                self.x = try container.decode(Double.self, forKey: "x")
                self.y = try container.decode(Double.self, forKey: "y")
            }
            
            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: StringCodingKey.self)
                
                try container.encode(self.x, forKey: "x")
                try container.encode(self.y, forKey: "y")
            }
            
            var cgPoint: CGPoint {
                return CGPoint(x: self.x, y: self.y)
            }
        }
        
        public let topLeft: CGPoint
        public let topRight: CGPoint
        public let bottomLeft: CGPoint
        public let bottomRight: CGPoint
        
        public var boundingFrame: CGRect {
            let top: CGFloat = min(topLeft.y, topRight.y)
            let left: CGFloat = min(topLeft.x, bottomLeft.x)
            let right: CGFloat = max(topRight.x, bottomRight.x)
            let bottom: CGFloat = max(bottomLeft.y, bottomRight.y)
            return CGRect(x: left, y: top, width: abs(right - left), height: abs(bottom - top))
        }
                
        public var leftMidPoint: CGPoint {
            return self.topLeft.midPoint(self.bottomLeft)
        }
        
        public var leftHeight: CGFloat {
            return self.topLeft.distanceTo(self.bottomLeft)
        }
        
        public var rightMidPoint: CGPoint {
            return self.topRight.midPoint(self.bottomRight)
        }
        
        public var rightHeight: CGFloat {
            return self.topRight.distanceTo(self.bottomRight)
        }
                
        public func convertTo(size: CGSize, insets: UIEdgeInsets = UIEdgeInsets()) -> Rect {
            return Rect(
                topLeft: CGPoint(x: self.topLeft.x * size.width + insets.left, y: size.height - self.topLeft.y * size.height + insets.top),
                topRight: CGPoint(x: self.topRight.x * size.width - insets.right, y: size.height - self.topRight.y * size.height + insets.top),
                bottomLeft: CGPoint(x: self.bottomLeft.x * size.width + insets.left, y: size.height - self.bottomLeft.y * size.height - insets.bottom),
                bottomRight: CGPoint(x: self.bottomRight.x * size.width - insets.right, y: size.height - self.bottomRight.y * size.height - insets.bottom)
            )
        }
        
        public init() {
            self.topLeft = CGPoint()
            self.topRight = CGPoint()
            self.bottomLeft = CGPoint()
            self.bottomRight = CGPoint()
        }
        
        public init(topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) {
            self.topLeft = topLeft
            self.topRight = topRight
            self.bottomLeft = bottomLeft
            self.bottomRight = bottomRight
        }
                
        @available(iOS 11.0, *)
        public init(observation: VNRectangleObservation) {
            self.topLeft = observation.topLeft
            self.topRight = observation.topRight
            self.bottomLeft = observation.bottomLeft
            self.bottomRight = observation.bottomRight
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: StringCodingKey.self)
            
            self.topLeft = try container.decode(Point.self, forKey: "topLeft").cgPoint
            self.topRight = try container.decode(Point.self, forKey: "topRight").cgPoint
            self.bottomLeft = try container.decode(Point.self, forKey: "bottomLeft").cgPoint
            self.bottomRight = try container.decode(Point.self, forKey: "bottomRight").cgPoint
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: StringCodingKey.self)
            
            try container.encode(Point(cgPoint: self.topLeft), forKey: "topLeft")
            try container.encode(Point(cgPoint: self.topRight), forKey: "topRight")
            try container.encode(Point(cgPoint: self.bottomLeft), forKey: "bottomLeft")
            try container.encode(Point(cgPoint: self.bottomRight), forKey: "bottomRight")
        }
    }
    
    public let rect: Rect
    public let content: Content
    
    @available(iOS 11.0, *)
    init?(observation: VNObservation) {
        if let barcode = observation as? VNBarcodeObservation, case .qr = barcode.symbology, let payload = barcode.payloadStringValue {
            self.content = .qrCode(payload: payload)
            self.rect = Rect(observation: barcode)
        } else if #available(iOS 13.0, *), let text = observation as? VNRecognizedTextObservation, let candidate = text.topCandidates(1).first, candidate.confidence >= 0.5 {
            let string = candidate.string
            var words: [(Range<String.Index>, Rect)] = []
            string.enumerateSubstrings(in: string.startIndex ..< string.endIndex, options: .byWords) { _, substringRange, _, _ in
                if let rectangle = try? candidate.boundingBox(for: substringRange) {
                    words.append((substringRange, Rect(observation: rectangle)))
                }
            }
            self.content = .text(text: string, words: words)
            self.rect = Rect(observation: text)
        } else {
            return nil
        }
    }
    
    struct WordRangeAndRect: Codable {
        let start: Int32
        let end: Int32
        let rect: Rect
        
        init(text: String, range: Range<String.Index>, rect: Rect) {
            self.start = Int32(text.distance(from: text.startIndex, to: range.lowerBound))
            self.end = Int32(text.distance(from: text.startIndex, to: range.upperBound))
            self.rect = rect
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: StringCodingKey.self)
            
            self.start = try container.decode(Int32.self, forKey: "start")
            self.end = try container.decode(Int32.self, forKey: "end")
            self.rect = try container.decode(Rect.self, forKey: "rect")
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: StringCodingKey.self)
            
            try container.encode(self.start, forKey: "start")
            try container.encode(self.end, forKey: "end")
            try container.encode(self.rect, forKey: "rect")
        }
        
        func toRangeWithRect(text: String) -> (Range<String.Index>, Rect) {
            return (text.index(text.startIndex, offsetBy: Int(self.start)) ..< text.index(text.startIndex, offsetBy: Int(self.end)), self.rect)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        let type = try container.decode(Int32.self, forKey: "t")
        if type == 0 {
            let text = try container.decode(String.self, forKey: "text")
            let rangesWithRects = try container.decode([WordRangeAndRect].self, forKey: "words")
            let words = rangesWithRects.map { $0.toRangeWithRect(text: text) }
            self.content = .text(text: text, words: words)
            self.rect = try container.decode(Rect.self, forKey: "rect")
        } else if type == 1 {
            let payload = try container.decode(String.self, forKey: "payload")
            self.content = .qrCode(payload: payload)
            self.rect = try container.decode(Rect.self, forKey: "rect")
        } else {
            assertionFailure()
            self.content = .text(text: "", words: [])
            self.rect = Rect()
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        switch self.content {
            case let .text(text, words):
                try container.encode(Int32(0), forKey: "t")
                try container.encode(text, forKey: "text")
                 
                let rangesWithRects: [WordRangeAndRect] = words.map { WordRangeAndRect(text: text, range: $0.0, rect: $0.1) }
                try container.encode(rangesWithRects, forKey: "words")
                try container.encode(rect, forKey: "rect")
            case let .qrCode(payload):
                try container.encode(Int32(1), forKey: "t")
                try container.encode(payload, forKey: "payload")
                try container.encode(rect, forKey: "rect")
        }
    }
}

private func recognizeContent(in image: UIImage) -> Signal<[RecognizedContent], NoError> {
    if #available(iOS 11.0, *) {
        guard let cgImage = image.cgImage else {
            return .complete()
        }
        return Signal { subscriber in
            var requests: [VNRequest] = []
        
            let barcodeResult = Atomic<[RecognizedContent]?>(value: nil)
            let textResult = Atomic<[RecognizedContent]?>(value: nil)
            
            let completion = {
                let barcode = barcodeResult.with { $0 }
                let text = textResult.with { $0 }
                
                if let barcode = barcode, let text = text {
                    subscriber.putNext(barcode + text)
                    subscriber.putCompletion()
                }
            }
            
            let barcodeRequest = VNDetectBarcodesRequest { request, error in
                let mappedResults = request.results?.compactMap { RecognizedContent(observation: $0) } ?? []
                let _ = barcodeResult.swap(mappedResults)
                completion()
            }
            requests.append(barcodeRequest)
            
            if #available(iOS 13.0, *) {
                let textRequest = VNRecognizeTextRequest { request, error in
                    let mappedResults = request.results?.compactMap { RecognizedContent(observation: $0) } ?? []
                    let _ = textResult.swap(mappedResults)
                    completion()
                }
                textRequest.usesLanguageCorrection = true
                requests.append(textRequest)
            } else {
                let _ = textResult.swap([])
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform(requests)
            
            return ActionDisposable {
                
            }
        }
    } else {
        return .single([])
    }
}

public func recognizedContent(postbox: Postbox, image: @escaping () -> UIImage?, messageId: MessageId) -> Signal<[RecognizedContent], NoError> {
    return cachedImageRecognizedContent(postbox: postbox, messageId: messageId)
    |> mapToSignal { cachedContent -> Signal<[RecognizedContent], NoError> in
        if let cachedContent = cachedContent {
            return .single(cachedContent.results)
        } else if let image = image() {
            return recognizeContent(in: image)
            |> beforeNext { results in
                let _ = updateCachedImageRecognizedContent(postbox: postbox, messageId: messageId, content: CachedImageRecognizedContent(results: results)).start()
            }
        } else {
            return .single([])
        }
    }
}
