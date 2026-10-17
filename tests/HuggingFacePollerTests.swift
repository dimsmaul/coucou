import Foundation

@main
enum HuggingFacePollerTests {
    static var failures = 0

    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func main() {
        print("--- Testing HuggingFace Token Resolution ---")
        let token = HuggingFacePoller.readLocalToken()
        check("readLocalToken resolves token if ~/.cache/huggingface/token exists",
              FileManager.default.fileExists(atPath: NSString(string: "~/.cache/huggingface/token").expandingTildeInPath) ? token != nil : true)

        KeychainStore.shared.set("huggingface-api-key", value: "hf_custom_key_123")
        check("Keychain token takes precedence over local token",
              HuggingFacePoller.shared.token == "hf_custom_key_123")
        check("isUsingLocalToken is false when Keychain key is set",
              !HuggingFacePoller.isUsingLocalToken)

        KeychainStore.shared.remove("huggingface-api-key")
        check("isUsingLocalToken is true when Keychain key is removed and local token exists",
              HuggingFacePoller.readLocalToken() != nil ? HuggingFacePoller.isUsingLocalToken : true)

        print("\n--- Testing HuggingFace Data Models ---")
        let user = HuggingFaceUser(id: "123", name: "dimsmauls", fullname: "Dimas Maulana Ahmad", isPro: true, avatarUrl: "https://example.com/avatar.png")
        check("HuggingFaceUser name and isPro", user.name == "dimsmauls" && user.isPro)

        let model = HuggingFaceModel(id: "dimsmauls/qwen2.5-coder", likes: 12, downloads: 450, isPrivate: false, pipelineTag: "text-generation", createdAt: nil)
        check("HuggingFaceModel repoName parsing", model.repoName == "qwen2.5-coder")
        check("HuggingFaceModel url generation", model.url == "https://huggingface.co/dimsmauls/qwen2.5-coder")

        let dataset = HuggingFaceDataset(id: "dimsmauls/code4ml", likes: 5, downloads: 120, isPrivate: true, createdAt: nil)
        check("HuggingFaceDataset repoName parsing", dataset.repoName == "code4ml")
        check("HuggingFaceDataset url generation", dataset.url == "https://huggingface.co/datasets/dimsmauls/code4ml")

        let space = HuggingFaceSpace(id: "dimsmauls/demo-app", likes: 3, isPrivate: false, stage: "RUNNING")
        check("HuggingFaceSpace repoName parsing", space.repoName == "demo-app")
        check("HuggingFaceSpace url generation", space.url == "https://huggingface.co/spaces/dimsmauls/demo-app")
        check("HuggingFaceSpace stage", space.stage == "RUNNING")

        print("\n--- Testing PillCatalog Hugging Face Entry ---")
        let hfPill = PillFixture.available.first { $0.id == "integration_huggingface" }
        check("Pill exists in catalog fixture", hfPill != nil)
        check("Pill category is service", hfPill?.category == .service)
        check("Pill color is HuggingFace yellow (#FFD21E)", hfPill?.defaultColor == "#FFD21E")

        if failures > 0 {
            print("\n❌ \(failures) test(s) failed.")
            exit(1)
        } else {
            print("\nAll HuggingFace tests passed successfully!")
        }
    }
}
