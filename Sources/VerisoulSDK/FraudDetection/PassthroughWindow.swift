import SwiftUI
import UIKit

class PassthroughWindow: UIView {
    
    weak var capturer: FraudDetection?
    var isFirst = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear // Semi-transparent
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        
        if !isFirst {
            capturer?.handleTouchEnded(touch: point,downTime: Date())
            isFirst = true
        } else {
            isFirst = false
        }
        
        return nil
    }
}
