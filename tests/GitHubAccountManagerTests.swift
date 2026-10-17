import Foundation

@main
enum GitHubAccountManagerTests {
    static var failures = 0

    static func check(_ label: String, _ condition: Bool) {
        if condition {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            failures += 1
        }
    }

    static func main() {
        print("--- Testing GitHubAccountManager YAML Parsing ---")
        let sampleYAML = """
        github.com:
            git_protocol: https
            users:
                dimsmaul:
                eularix:
                maulana-cavos:
            user: maulana-cavos
        """

        let (accounts, active) = GitHubAccountManager.parseHostsYAML(sampleYAML)
        check("found 3 accounts", accounts.count == 3)
        check("active user is maulana-cavos", active["github.com"] == "maulana-cavos")
        check("maulana-cavos is marked active", accounts.first(where: { $0.username == "maulana-cavos" })?.isActive == true)
        check("dimsmaul is marked inactive", accounts.first(where: { $0.username == "dimsmaul" })?.isActive == false)
        check("eularix is marked inactive", accounts.first(where: { $0.username == "eularix" })?.isActive == false)

        print("\n--- Testing YAML Active User Switch ---")
        let switchedYAML = sampleYAML.replacingOccurrences(of: "user: maulana-cavos", with: "user: dimsmaul")
        let (switchedAccounts, switchedActive) = GitHubAccountManager.parseHostsYAML(switchedYAML)
        check("switched active user is dimsmaul", switchedActive["github.com"] == "dimsmaul")
        check("dimsmaul is now marked active", switchedAccounts.first(where: { $0.username == "dimsmaul" })?.isActive == true)
        check("maulana-cavos is now marked inactive", switchedAccounts.first(where: { $0.username == "maulana-cavos" })?.isActive == false)

        print("\n--- Testing YAML Parsing with Multiple Hosts & Nested Properties ---")
        let multiHostYAML = """
        github.com:
            git_protocol: https
            users:
                alice:
                    oauth_token: gho_token1
                bob:
                    oauth_token: gho_token2
            user: bob
        github.mycompany.com:
            git_protocol: ssh
            users:
                work-alice:
            user: work-alice
        """

        let (multiAccounts, multiActive) = GitHubAccountManager.parseHostsYAML(multiHostYAML)
        check("found 3 accounts across hosts", multiAccounts.count == 3)
        check("bob is active on github.com", multiActive["github.com"] == "bob")
        check("work-alice is active on github.mycompany.com", multiActive["github.mycompany.com"] == "work-alice")
        check("bob is marked active", multiAccounts.first(where: { $0.username == "bob" })?.isActive == true)
        check("alice is marked inactive", multiAccounts.first(where: { $0.username == "alice" })?.isActive == false)
        check("work-alice is marked active", multiAccounts.first(where: { $0.username == "work-alice" })?.isActive == true)

        print("\n--- Testing gh auth status output parsing ---")
        let sampleAuthStatus = """
        github.com
          ✓ Logged in to github.com account maulana-cavos (keyring)
          - Active account: true
          - Git operations protocol: https
          - Token: gho_************************************
          - Token scopes: 'gist', 'read:org', 'repo', 'workflow'

          ✓ Logged in to github.com account dimsmaul (keyring)
          - Active account: false
          - Git operations protocol: https
          - Token: gho_************************************
          - Token scopes: 'gist', 'repo'

          ✓ Logged in to github.com account eularix (keyring)
          - Active account: false
          - Git operations protocol: https
          - Token: gho_************************************
          - Token scopes: 'admin:org', 'gist', 'repo', 'workflow'
        """

        let statusAccounts = GitHubAccountManager.parseAuthStatusOutput(sampleAuthStatus)
        check("status parsed 3 accounts", statusAccounts.count == 3)
        check("maulana-cavos has 4 scopes", statusAccounts.first(where: { $0.username == "maulana-cavos" })?.scopes.count == 4)
        check("maulana-cavos is active", statusAccounts.first(where: { $0.username == "maulana-cavos" })?.isActive == true)
        check("dimsmaul is inactive", statusAccounts.first(where: { $0.username == "dimsmaul" })?.isActive == false)
        check("eularix has admin:org scope", statusAccounts.first(where: { $0.username == "eularix" })?.scopes.contains("admin:org") == true)

        print("\n--- Testing Binary Resolution ---")
        let ghPath = GitHubAccountManager.resolveGhBinary()
        if let path = ghPath {
            check("resolved gh binary is executable", FileManager.default.isExecutableFile(atPath: path))
            print("  Resolved path: \(path)")
        } else {
            print("  gh not found in standard paths (acceptable in minimal test env)")
        }

        if failures > 0 {
            print("\n\(failures) test(s) failed.")
            exit(1)
        }
        print("\nAll GitHubAccountManager tests passed successfully!")
    }
}
