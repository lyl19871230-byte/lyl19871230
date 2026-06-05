import Foundation
import UIKit

struct GLMClient {
    private let apiKey: String
    private let baseURL = URL(string: "https://open.bigmodel.cn/api/paas/v4")!

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func transcribeAudio(fileURL: URL) async throws -> String {
        let url = baseURL.appendingPathComponent("audio").appendingPathComponent("transcriptions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        var body = Data()
        body.appendMultipartField(name: "model", value: "glm-asr-2512", boundary: boundary)
        body.appendMultipartField(name: "response_format", value: "json", boundary: boundary)
        body.appendMultipartFile(
            name: "file",
            filename: fileURL.lastPathComponent,
            mimeType: "audio/mp4",
            data: audioData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(GLMTranscriptionResponse.self, from: data)
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func summarizeTask(text: String, imageURLs: [URL]) async throws -> String {
        let url = baseURL.appendingPathComponent("chat").appendingPathComponent("completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var content: [GLMContentPart] = [
            .text("""
            你是一个个人任务整理助手。请把用户输入的文字、语音转写内容和图片内容，整理成一条清楚、简短、可执行的中文任务。
            只输出任务本身，不要输出解释、编号、标题或多余寒暄。

            用户输入：
            \(text)
            """)
        ]

        for imageURL in imageURLs {
            let data = try Data(contentsOf: imageURL)
            let image = UIImage(data: data)
            let compressed = image?.jpegData(compressionQuality: 0.75) ?? data
            let base64 = compressed.base64EncodedString()
            content.append(.imageURL("data:image/jpeg;base64,\(base64)"))
        }

        let payload = GLMChatRequest(
            model: "glm-5v-turbo",
            messages: [
                GLMMessage(role: "user", content: content)
            ],
            temperature: 0.2
        )

        request.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(GLMChatResponse.self, from: data)
        guard let result = decoded.choices.first?.message.content else {
            throw GLMError.emptyResponse
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GLMError.httpStatus(http.statusCode, body)
        }
    }
}

private struct GLMTranscriptionResponse: Decodable {
    let text: String
}

private struct GLMChatRequest: Encodable {
    let model: String
    let messages: [GLMMessage]
    let temperature: Double
}

private struct GLMMessage: Encodable {
    let role: String
    let content: [GLMContentPart]
}

private enum GLMContentPart: Encodable {
    case text(String)
    case imageURL(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            try container.encode(["url": url], forKey: .imageURL)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

private struct GLMChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

enum GLMError: LocalizedError {
    case missingAPIKey
    case emptyResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先在设置中填写 GLM API Key。"
        case .emptyResponse:
            return "GLM 没有返回任务内容。"
        case .httpStatus(let status, let body):
            return "GLM 请求失败：\(status) \(body)"
        }
    }
}

private extension Data {
    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipartFile(name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
