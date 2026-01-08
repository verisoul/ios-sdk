//
//  VerisoulSDK
//
//  Created by ahmed alaa on 26/05/2025.
//

import Foundation

public enum SDKType: String {
    case native = "native"
    case flutter = "flutter"
    case reactNative = "react-native"
}
public class InternalVerisoulCore {
   public static let shared = InternalVerisoulCore()
  public  var sdkType: SDKType = .native
    private init() {}
}


struct SDKInfo: Codable {
    let sdkVersion: String
    let sdkName: String
    let sdkType: String

    enum CodingKeys: String, CodingKey {
        case sdkVersion = "sdk_version"
        case sdkName = "sdk_name"
        case sdkType = "sdk_type"
    }

    init(sdkVersion: String = "1.0.0", sdkName: String = "ios", sdkType: String = "native") {
        self.sdkVersion = sdkVersion
        self.sdkName = sdkName
        self.sdkType = sdkType
    }
    func toDictionary() -> [String: Any]? {
            do {
                let data = try JSONEncoder().encode(self)
                let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
                return jsonObject as? [String: Any]
            } catch {
                print("Error converting SDKInfo to dictionary:", error)
                return nil
            }
        }
}
