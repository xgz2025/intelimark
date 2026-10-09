import Foundation
import Model

/// Maps schema.org JSON-LD to a `StructuredData` (Docs/architecture.md §6.2:
/// "facts from structure first"). Picks the most specific entity on the page:
/// product > recipe > event > place > video > article.
public enum SchemaOrg {
    public static func structuredData(fromJSONLD blocks: [String]) -> StructuredData? {
        let nodes = blocks.flatMap { block -> [[String: Any]] in
            guard let data = block.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            else { return [] }
            return collectNodes(json)
        }
        let ranked = nodes.compactMap { node -> (rank: Int, kind: SemanticKind, node: [String: Any])? in
            guard let match = classify(types(of: node)) else { return nil }
            return (match.0, match.1, node)
        }
        guard let best = ranked.min(by: { $0.rank < $1.rank }) else { return nil }
        return StructuredData(kind: best.kind, fields: fields(for: best.kind, from: best.node))
    }

    // MARK: Node discovery

    static func collectNodes(_ json: Any, depth: Int = 0) -> [[String: Any]] {
        guard depth < 4 else { return [] }
        if let array = json as? [Any] {
            return array.flatMap { collectNodes($0, depth: depth + 1) }
        }
        guard let object = json as? [String: Any] else { return [] }
        var nodes: [[String: Any]] = []
        if object["@type"] != nil { nodes.append(object) }
        if let graph = object["@graph"] { nodes += collectNodes(graph, depth: depth + 1) }
        if let main = object["mainEntity"] { nodes += collectNodes(main, depth: depth + 1) }
        return nodes
    }

    static func types(of node: [String: Any]) -> [String] {
        let raw: [String]
        if let single = node["@type"] as? String {
            raw = [single]
        } else {
            raw = node["@type"] as? [String] ?? []
        }
        return raw.map { $0.components(separatedBy: "/").last ?? $0 }
    }

    static let placeTypes: Set<String> = [
        "Place", "LocalBusiness", "Restaurant", "Hotel", "LodgingBusiness", "FoodEstablishment",
        "TouristAttraction", "Store", "CafeOrCoffeeShop", "BarOrPub", "Bakery", "Museum", "Park",
        "Landmark", "Resort", "BedAndBreakfast", "Hostel", "Motel",
    ]
    static let articleTypes: Set<String> = [
        "Article", "NewsArticle", "BlogPosting", "TechArticle", "ScholarlyArticle", "Report", "AnalysisNewsArticle",
    ]

    static func classify(_ types: [String]) -> (Int, SemanticKind)? {
        var best: (Int, SemanticKind)?
        func consider(_ rank: Int, _ kind: SemanticKind) {
            if best == nil || rank < best!.0 { best = (rank, kind) }
        }
        for type in types {
            switch type {
            case "Product", "ProductGroup", "IndividualProduct", "ProductModel": consider(0, .product)
            case "Recipe": consider(1, .recipe)
            case _ where type.hasSuffix("Event"): consider(2, .event)
            case _ where placeTypes.contains(type) || type.hasSuffix("Business"): consider(3, .place)
            case "VideoObject": consider(4, .video)
            case _ where articleTypes.contains(type): consider(5, .article)
            default: break
            }
        }
        return best
    }

    // MARK: Fields

    static func fields(for kind: SemanticKind, from node: [String: Any]) -> TypedFields {
        switch kind {
        case .product: TypedFields(product: product(node))
        case .recipe: TypedFields(recipe: recipe(node))
        case .event: TypedFields(event: event(node))
        case .place: TypedFields(place: place(node))
        case .article: TypedFields(article: article(node))
        default: TypedFields()
        }
    }

    static func product(_ node: [String: Any]) -> ProductFields {
        let offer = first(node["offers"]).flatMap { offers -> [String: Any]? in
            // AggregateOffer nests the real offers one level down.
            if let nested = first(offers["offers"]) { return nested }
            return offers
        }
        let price = number(offer?["price"]) ?? number(offer?["lowPrice"])
        return ProductFields(
            name: string(node["name"]),
            brand: name(of: node["brand"]),
            price: price,
            currency: string(offer?["priceCurrency"]),
            availability: string(offer?["availability"]).map { $0.components(separatedBy: "/").last ?? $0 }
        )
    }

    static func place(_ node: [String: Any]) -> PlaceFields {
        let geo = first(node["geo"])
        return PlaceFields(
            name: string(node["name"]),
            address: address(node["address"]),
            latitude: number(geo?["latitude"]),
            longitude: number(geo?["longitude"]),
            telephone: string(node["telephone"])
        )
    }

    static func event(_ node: [String: Any]) -> EventFields {
        let location = first(node["location"])
        return EventFields(
            name: string(node["name"]),
            startDate: SchemaDate.parse(string(node["startDate"])),
            endDate: SchemaDate.parse(string(node["endDate"])),
            venue: location.flatMap { string($0["name"]) } ?? string(node["location"]),
            address: location.flatMap { address($0["address"]) }
        )
    }

    static func recipe(_ node: [String: Any]) -> RecipeFields {
        let ingredients = (node["recipeIngredient"] ?? node["ingredients"]) as? [Any] ?? []
        let total = SchemaDuration.minutes(string(node["totalTime"]))
            ?? zip2(SchemaDuration.minutes(string(node["prepTime"])), SchemaDuration.minutes(string(node["cookTime"])))
        let servings: String? = {
            if let array = node["recipeYield"] as? [Any] { return array.first.flatMap { scalarString($0) } }
            return scalarString(node["recipeYield"])
        }()
        return RecipeFields(
            name: string(node["name"]),
            ingredients: ingredients.compactMap { scalarString($0) }.map(HTMLText.collapseWhitespace).filter { !$0.isEmpty },
            totalMinutes: total,
            servings: servings
        )
    }

    static func article(_ node: [String: Any]) -> ArticleFields {
        ArticleFields(
            headline: string(node["headline"]) ?? string(node["name"]),
            author: name(of: node["author"]),
            publisher: name(of: node["publisher"]),
            publishedAt: SchemaDate.parse(string(node["datePublished"]))
        )
    }

    // MARK: Value helpers

    /// The first object of a value that may be an object or an array of objects.
    static func first(_ value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] { return object }
        return (value as? [Any])?.lazy.compactMap { $0 as? [String: Any] }.first
    }

    static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let cleaned = HTMLText.collapseWhitespace(HTMLText.decodeEntities(text))
        return cleaned.isEmpty ? nil : cleaned
    }

    static func scalarString(_ value: Any?) -> String? {
        if let text = string(value) { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func number(_ value: Any?) -> Double? {
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ""))
        }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    /// `"Ann"`, `{"name": "Ann"}` or `[{"name": "Ann"}, …]` → `"Ann"`.
    static func name(of value: Any?) -> String? {
        if let text = string(value) { return text }
        if let object = first(value) { return string(object["name"]) }
        return nil
    }

    static func address(_ value: Any?) -> String? {
        if let text = string(value) { return text }
        guard let object = first(value) else { return nil }
        let country = string(object["addressCountry"]) ?? name(of: object["addressCountry"])
        let parts = [
            string(object["streetAddress"]), string(object["addressLocality"]),
            string(object["addressRegion"]), string(object["postalCode"]), country,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func zip2(_ a: Int?, _ b: Int?) -> Int? {
        switch (a, b) {
        case let (a?, b?): a + b
        case let (a?, nil): a
        case let (nil, b?): b
        default: nil
        }
    }
}

enum SchemaDate {
    static func parse(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime], [.withFullDate],
        ] {
            iso.formatOptions = options
            if let date = iso.date(from: text) { return date }
        }
        // Local date-times without an offset are common for events.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: text) { return date }
        }
        return nil
    }
}

enum SchemaDuration {
    static let pattern = HTMLText.regex(#"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?$"#)

    /// ISO 8601 durations such as `PT1H15M` → minutes.
    static func minutes(_ text: String?) -> Int? {
        guard let text = text?.trimmingCharacters(in: .whitespaces).uppercased(), text.hasPrefix("P"),
              let groups = HTMLText.matches(pattern, in: text).first
        else { return nil }
        let days = groups[1].flatMap { Int($0) } ?? 0
        let hours = groups[2].flatMap { Int($0) } ?? 0
        let minutes = groups[3].flatMap { Int($0) } ?? 0
        let total = days * 24 * 60 + hours * 60 + minutes
        return total > 0 ? total : nil
    }
}
