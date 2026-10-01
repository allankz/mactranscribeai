import Foundation

/// Uma única passada de tradução via chat completions. Sem reescrita, sem resumo,
/// sem comentário: só o mesmo texto em inglês.
enum Translator {

    private static let system = """
    You are a translation engine. Translate the user's message into English.

    Output ONLY the translation. No quotes, no preamble, no notes, no explanations.
    Preserve the original line breaks, punctuation, capitalization style, proper nouns,
    numbers, code, and technical terms. Do not summarize, expand, correct, or reword —
    translate faithfully, including informal or incomplete phrasing.

    If the text is already in English, output it unchanged.
    """

    @discardableResult
    static func translateToEnglish(_ text: String,
                                   completion: @escaping (Result<String, Error>) -> Void) -> URLSessionDataTask? {
        guard let apiKey = Keychain.apiKey else {
            completion(.failure(TranscribeError.noAPIKey))
            return nil
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": Config.translationModel,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": text],
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
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
                let body = String(data: data, encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    completion(.failure(TranscribeError.http(http.statusCode, String(body.prefix(400)))))
                }
                return
            }
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let message = choices.first?["message"] as? [String: Any],
                let content = message["content"] as? String
            else {
                DispatchQueue.main.async { completion(.failure(TranscribeError.badResponse)) }
                return
            }

            let translated = content.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                translated.isEmpty
                    ? completion(.failure(TranscribeError.badResponse))
                    : completion(.success(translated))
            }
        }
        task.resume()
        return task
    }
}
