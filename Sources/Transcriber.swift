import Foundation

enum TranscribeError: LocalizedError {
    case noAPIKey
    case http(Int, String)
    case badResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Nenhuma chave da API configurada.\nUse o menu da barra → “Definir chave da API…”."
        case .http(let code, let body):
            if code == 401 { return "Chave da API rejeitada (401). Verifique a chave no menu da barra." }
            if code == 429 { return "Limite de uso atingido (429). Cheque créditos na sua conta OpenAI." }
            return "Erro HTTP \(code):\n\(body)"
        case .badResponse:
            return "Resposta inesperada da API."
        case .network(let m):
            return "Falha de rede: \(m)"
        }
    }
}

enum Transcriber {

    /// Devolve a task para que Esc possa abortar o upload em andamento.
    @discardableResult
    static func transcribe(fileURL: URL,
                           completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        guard let apiKey = Keychain.apiKey else {
            completion(.failure(TranscribeError.noAPIKey))
            return nil
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = "----MacTranscribe\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            guard !value.isEmpty else { return }
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        field("model", Config.model)
        field("language", Config.language)
        field("prompt", Config.vocabularyPrompt)
        field("response_format", "json")

        guard let audio = try? Data(contentsOf: fileURL) else {
            completion(.failure(TranscribeError.badResponse))
            return nil
        }
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
        body.append("Content-Type: audio/m4a\r\n\r\n")
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            try? FileManager.default.removeItem(at: fileURL)

            // Cancelado com Esc: quem cancelou já cuidou do estado da UI.
            if let error = error as? URLError, error.code == .cancelled { return }

            if let error {
                DispatchQueue.main.async { completion(.failure(TranscribeError.network(error.localizedDescription))) }
                return
            }
            guard let http = response as? HTTPURLResponse, let data else {
                DispatchQueue.main.async { completion(.failure(TranscribeError.badResponse)) }
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let text = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    completion(.failure(TranscribeError.http(http.statusCode, String(text.prefix(400)))))
                }
                return
            }
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let text = json["text"] as? String
            else {
                DispatchQueue.main.async { completion(.failure(TranscribeError.badResponse)) }
                return
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { completion(.success(trimmed)) }
        }
        task.resume()
        return task
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
