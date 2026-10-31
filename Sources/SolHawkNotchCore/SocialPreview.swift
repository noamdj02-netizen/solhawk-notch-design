import Foundation

/// Aperçu d'un lien social (texte public de la page). Donnée du créateur ou de la page : non vérifiée, affichée telle quelle (nettoyée).
public struct SocialPreview: Sendable, Equatable {
    public var title: String?
    public var text: String?
    public var members: String?     // « 12 345 members » pour Telegram, si la page l'affiche
    public init(title: String? = nil, text: String? = nil, members: String? = nil) { self.title = title; self.text = text; self.members = members }
}

/// Extrait les balises og:title / og:description et le compteur Telegram d'une page HTML (pas de JavaScript, rien d'exécuté).
public func parsePreview(html: String) -> SocialPreview {
    func meta(_ prop: String) -> String? {
        let pattern = "<meta[^>]+property=\"\(prop)\"[^>]+content=\"([^\"]{0,600})\""
        guard let r = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let g = Range(m.range(at: 1), in: html) else { return nil }
        return clean(String(html[g]))
    }
    var members: String?
    if let r = try? NSRegularExpression(pattern: "class=\"tgme_page_extra\">([^<]{1,80})<"),
       let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let g = Range(m.range(at: 1), in: html) {
        members = clean(String(html[g]))
    }
    return SocialPreview(title: meta("og:title"), text: meta("og:description"), members: members)
}

/// Texte d'un tweet depuis la réponse oEmbed de X (champ html : on retire les balises, on garde le texte).
public func parseTweetOEmbed(json: Data) -> SocialPreview? {
    guard let o = try? JSONSerialization.jsonObject(with: json) as? [String: Any], let html = o["html"] as? String else { return nil }
    let noTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    return SocialPreview(title: (o["author_name"] as? String).map(clean), text: clean(noTags), members: nil)
}

func clean(_ s: String) -> String {
    let decoded = s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&nbsp;", with: " ")
    let t = String(decoded.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint && ($0.value >= 32 || $0 == "\n") }.map(Character.init))
    return String(t.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(400))
}

/// Adresse à lire pour l'aperçu : page publique t.me, ou oEmbed officiel de X pour un tweet. nil = pas d'aperçu possible.
public func previewURL(for s: Social) -> URL? {
    guard let u = safeSocialURL(s) else { return nil }
    switch s.kind {
    case "telegram": return u
    case "twitter":
        guard u.path.contains("/status/") else { return nil }   // un profil X ne donne pas d'aperçu sans compte
        var c = URLComponents(string: "https://publish.twitter.com/oembed")
        c?.queryItems = [URLQueryItem(name: "url", value: u.absoluteString), URLQueryItem(name: "omit_script", value: "1"), URLQueryItem(name: "dnt", value: "true")]
        return c?.url
    default: return nil
    }
}
