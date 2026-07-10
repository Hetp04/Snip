import Foundation
import Supabase
final class SupabaseManager {
    static let shared = SupabaseManager()
    let client: SupabaseClient
    private init() {
        let options = SupabaseClientOptions(
            auth: .init(
                emitLocalSessionAsInitialSession: true
            )
        )
        client = SupabaseClient(
            supabaseURL: AppConstants.supabaseURL,
            supabaseKey: AppConstants.supabaseAnonKey,
            options: options
        )
    }
}