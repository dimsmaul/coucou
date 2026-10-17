import Foundation

// MARK: - MCPClient Tests

func runMCPClientTests() {
    print("Testing MCPClient & Tool Schemas...")

    // 1. Tool schema conversion to Anthropic format
    let schema: [String: AnyCodable] = [
        "type": AnyCodable("object"),
        "properties": AnyCodable([
            "url": ["type": "string", "description": "The URL to navigate to"]
        ]),
        "required": AnyCodable(["url"])
    ]
    let tool = MCPTool(
        name: "playwright_navigate",
        description: "Navigates the browser to a specific URL",
        inputSchema: schema
    )

    let anthropicTool = tool.toAnthropicTool()
    assert(anthropicTool["name"] as? String == "playwright_navigate", "Anthropic tool name mismatch")
    assert(anthropicTool["description"] as? String == "Navigates the browser to a specific URL", "Anthropic tool description mismatch")
    assert(anthropicTool["input_schema"] != nil, "Anthropic tool input_schema missing")
    print("  ✓ toAnthropicTool() produces valid schema")

    // 2. Tool schema conversion to OpenAI / Gemini format
    let openAIFunc = tool.toOpenAIFunction()
    assert(openAIFunc["type"] as? String == "function", "OpenAI type must be 'function'")
    guard let fn = openAIFunc["function"] as? [String: Any] else {
        fatalError("OpenAI function block missing")
    }
    assert(fn["name"] as? String == "playwright_navigate", "Function name mismatch")
    assert(fn["parameters"] != nil, "Function parameters missing")
    print("  ✓ toOpenAIFunction() produces valid schema")

    // 3. AnyCodable roundtrip
    let originalDict: [String: Any] = [
        "name": "Playwright",
        "retries": 3,
        "headless": true,
        "viewport": ["width": 1280, "height": 720]
    ]
    let anyCodableDict = originalDict.mapValues { AnyCodable($0) }
    do {
        let data = try JSONEncoder().encode(anyCodableDict)
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)
        assert(decoded["name"]?.value as? String == "Playwright", "Decoded string mismatch")
        assert(decoded["retries"]?.value as? Int == 3, "Decoded int mismatch")
        assert(decoded["headless"]?.value as? Bool == true, "Decoded bool mismatch")
        print("  ✓ AnyCodable encodes and decodes arbitrary JSON values losslessly")
    } catch {
        fatalError("AnyCodable roundtrip failed: \(error)")
    }

    // 4. MCPServerConfig test
    let config = MCPServerConfig(
        id: "test_mcp",
        name: "Test Server",
        command: "npx",
        args: ["-y", "@modelcontextprotocol/server-playwright"],
        env: ["DEBUG": "pw:api"],
        isEnabled: true
    )
    assert(config.command == "npx", "Command mismatch")
    assert(config.args.count == 2, "Args count mismatch")
    assert(config.env["DEBUG"] == "pw:api", "Env mismatch")
    print("  ✓ MCPServerConfig stores parameters correctly")

    print("\nAll MCPClient tests passed successfully! 🚀")
}

@main
struct MCPTestMain {
    static func main() {
        runMCPClientTests()
    }
}
