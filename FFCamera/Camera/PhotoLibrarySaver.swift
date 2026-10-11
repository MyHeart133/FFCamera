import Photos
import UIKit

/// 保存照片到系统相册(仅需 addOnly 权限)。
enum PhotoLibrarySaver {

    enum SaveError: LocalizedError {
        case denied
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .denied:
                return "相册权限被拒绝"
            case .underlying(let error):
                return error.localizedDescription
            }
        }
    }

    static func save(_ image: UIImage, completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                completion(.failure(SaveError.denied))
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            }, completionHandler: { success, error in
                if success {
                    completion(.success(()))
                } else {
                    let err = error ?? NSError(domain: "FFCamera", code: -1)
                    completion(.failure(SaveError.underlying(err)))
                }
            })
        }
    }
}
