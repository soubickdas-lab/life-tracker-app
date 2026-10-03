import Foundation

/// The few numbers that come with every reply — enough for a line on Today.
struct MoneySummary: Codable, Sendable, Equatable {
    var month: String = ""
    var opening: Double = 0
    var openingTyped: Bool = false
    var came: Double = 0
    var went: Double = 0
    var balance: Double = 0
    var todayIn: Double = 0
    var todayOut: Double = 0
    var entries: Int = 0

    enum CodingKeys: String, CodingKey {
        case month, opening, openingTyped, balance, todayIn, todayOut, entries
        case came = "in"
        case went = "out"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = (try? c.decode(String.self, forKey: .month)) ?? ""
        opening = (try? c.decode(Double.self, forKey: .opening)) ?? 0
        openingTyped = (try? c.decode(Bool.self, forKey: .openingTyped)) ?? false
        came = (try? c.decode(Double.self, forKey: .came)) ?? 0
        went = (try? c.decode(Double.self, forKey: .went)) ?? 0
        balance = (try? c.decode(Double.self, forKey: .balance)) ?? 0
        todayIn = (try? c.decode(Double.self, forKey: .todayIn)) ?? 0
        todayOut = (try? c.decode(Double.self, forKey: .todayOut)) ?? 0
        entries = (try? c.decode(Int.self, forKey: .entries)) ?? 0
    }

    /// Nothing typed yet, nothing spent — the strip on Today stays out of the way.
    var isEmpty: Bool { entries == 0 && !openingTyped && balance == 0 }
}

/// One line of money, in or out.
struct MoneyEntry: Codable, Identifiable, Sendable, Equatable {
    var id: Int = 0
    var day: String = ""
    var amount: Double = 0
    var kind: String = "out"
    var category: String = ""
    var note: String = ""

    var isIn: Bool { kind == "in" }

    init(id: Int, day: String, amount: Double, kind: String, category: String, note: String) {
        self.id = id; self.day = day; self.amount = amount
        self.kind = kind; self.category = category; self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        day = (try? c.decode(String.self, forKey: .day)) ?? ""
        amount = (try? c.decode(Double.self, forKey: .amount)) ?? 0
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "out"
        category = (try? c.decode(String.self, forKey: .category)) ?? ""
        note = (try? c.decode(String.self, forKey: .note)) ?? ""
    }
}

struct MoneySlice: Codable, Identifiable, Sendable, Equatable {
    var name: String = ""
    var total: Double = 0
    var id: String { name }
}

struct MoneyDay: Codable, Identifiable, Sendable, Equatable {
    var day: String = ""
    var out: Double = 0
    var id: String { day }
}

struct MoneyCategories: Codable, Sendable, Equatable {
    var out: [String] = ["Food", "Travel", "Bills", "Shopping", "Health", "Fun", "Other"]
    var `in`: [String] = ["Salary", "YouTube", "Freelance", "Refund", "Other"]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        out = (try? c.decode([String].self, forKey: .out)) ?? out
        `in` = (try? c.decode([String].self, forKey: .in)) ?? `in`
    }
}

/// A whole month, for the money screen.
struct MoneyMonth: Codable, Sendable, Equatable {
    var month: String = ""
    var opening: Double = 0
    var openingTyped: Bool = false
    var came: Double = 0
    var went: Double = 0
    var balance: Double = 0
    var entries: [MoneyEntry] = []
    var byCategory: [MoneySlice] = []
    var days: [MoneyDay] = []
    var categories = MoneyCategories()

    enum CodingKeys: String, CodingKey {
        case month, opening, openingTyped, balance, entries, byCategory, days, categories
        case came = "in"
        case went = "out"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = (try? c.decode(String.self, forKey: .month)) ?? ""
        opening = (try? c.decode(Double.self, forKey: .opening)) ?? 0
        openingTyped = (try? c.decode(Bool.self, forKey: .openingTyped)) ?? false
        came = (try? c.decode(Double.self, forKey: .came)) ?? 0
        went = (try? c.decode(Double.self, forKey: .went)) ?? 0
        balance = (try? c.decode(Double.self, forKey: .balance)) ?? 0
        entries = (try? c.decode([MoneyEntry].self, forKey: .entries)) ?? []
        byCategory = (try? c.decode([MoneySlice].self, forKey: .byCategory)) ?? []
        days = (try? c.decode([MoneyDay].self, forKey: .days)) ?? []
        categories = (try? c.decode(MoneyCategories.self, forKey: .categories)) ?? MoneyCategories()
    }
}

/// Rupees the way they are written here: ₹1,23,456 — and no paise unless there are some.
enum Rupees {
    static func text(_ value: Double, sign: Bool = false) -> String {
        let format = NumberFormatter()
        format.numberStyle = .decimal
        format.locale = Locale(identifier: "en_IN")
        format.maximumFractionDigits = value == value.rounded() ? 0 : 2
        let body = format.string(from: NSNumber(value: abs(value))) ?? String(abs(value))
        let lead = value < 0 ? "−" : (sign ? "+" : "")
        return lead + "₹" + body
    }
}
