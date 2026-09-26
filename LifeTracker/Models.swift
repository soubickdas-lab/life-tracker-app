import Foundation

/// Everything the sheet hands back in one call.
struct TrackerState: Codable, Sendable {
    var today: String = ""
    var days: [DayBlock] = []
    var habits: [Habit] = []
    var weight: String = ""
    var journeys: [Journey] = []
    var notes: [Note] = []

    var todayBlock: DayBlock? { days.first { $0.label == "Today" } }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        today = (try? c.decode(String.self, forKey: .today)) ?? ""
        days = (try? c.decode([DayBlock].self, forKey: .days)) ?? []
        habits = (try? c.decode([Habit].self, forKey: .habits)) ?? []
        weight = (try? c.decode(String.self, forKey: .weight)) ?? ""
        journeys = (try? c.decode([Journey].self, forKey: .journeys)) ?? []
        notes = (try? c.decode([Note].self, forKey: .notes)) ?? []
    }
}

struct DayBlock: Codable, Identifiable, Sendable {
    var date: String
    var label: String
    var pretty: String
    var tasks: [TaskItem]

    var id: String { date }
    var doneCount: Int { tasks.filter(\.done).count }
    var openCount: Int { tasks.count - doneCount }
    var progress: Double { tasks.isEmpty ? 0 : Double(doneCount) / Double(tasks.count) }
}

struct TaskItem: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var task: String
    var start: String
    var end: String
    var slot: String
    var done: Bool
    var repeats: Bool
    var carried: Bool
    var pending: Bool = false      /* typed here, not written to the sheet yet */

    /// "All day" reads better than an empty gap.
    var when: String { slot.isEmpty ? "All day" : slot }

    enum CodingKeys: String, CodingKey {
        case id, task, start, end, slot, done, carried
        case repeats = "repeat"
    }

    init(id: String, task: String, start: String = "", end: String = "", slot: String = "",
         done: Bool = false, repeats: Bool = false, carried: Bool = false, pending: Bool = false) {
        self.id = id; self.task = task; self.start = start; self.end = end
        self.slot = slot; self.done = done; self.repeats = repeats
        self.carried = carried; self.pending = pending
    }
}

struct Habit: Codable, Identifiable, Sendable, Equatable {
    var name: String
    var target: String
    var done: Bool
    var streak: Int
    var every: Int = 1                 /* every day, every 2nd day, … */

    var id: String { name }
    var rhythm: String { every <= 1 ? "" : "every \(every) days" }
}

/// Something you are working towards by a date, and the habits that get you there.
struct Journey: Codable, Identifiable, Sendable, Equatable {
    var id: Int
    var name: String
    var kind: String
    var starts: String
    var ends: String
    var unit: String
    var from: String
    var to: String
    var now: String
    var dayNumber: Int
    var daysTotal: Int
    var daysLeft: Int
    var timePct: Int
    var habits: [JourneyHabit]
    var doneToday: Int
    var dueToday: Int
    var keptPct: Int
    var perfectDays: Int
    var perfectRun: Int
    var movedPct: Int?
    var photos: Int = 0
    var weights: [WeighIn] = []

    var countdown: String {
        "Day \(dayNumber) of \(daysTotal) · \(daysLeft) \(daysLeft == 1 ? "day" : "days") to go"
    }
    var hasTarget: Bool { !from.isEmpty && !to.isEmpty }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? "Journey"
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "general"
        starts = (try? c.decode(String.self, forKey: .starts)) ?? ""
        ends = (try? c.decode(String.self, forKey: .ends)) ?? ""
        unit = (try? c.decode(String.self, forKey: .unit)) ?? ""
        from = (try? c.decode(String.self, forKey: .from)) ?? ""
        to = (try? c.decode(String.self, forKey: .to)) ?? ""
        now = (try? c.decode(String.self, forKey: .now)) ?? ""
        dayNumber = (try? c.decode(Int.self, forKey: .dayNumber)) ?? 1
        daysTotal = (try? c.decode(Int.self, forKey: .daysTotal)) ?? 1
        daysLeft = (try? c.decode(Int.self, forKey: .daysLeft)) ?? 0
        timePct = (try? c.decode(Int.self, forKey: .timePct)) ?? 0
        habits = (try? c.decode([JourneyHabit].self, forKey: .habits)) ?? []
        doneToday = (try? c.decode(Int.self, forKey: .doneToday)) ?? 0
        dueToday = (try? c.decode(Int.self, forKey: .dueToday)) ?? 0
        keptPct = (try? c.decode(Int.self, forKey: .keptPct)) ?? 0
        perfectDays = (try? c.decode(Int.self, forKey: .perfectDays)) ?? 0
        perfectRun = (try? c.decode(Int.self, forKey: .perfectRun)) ?? 0
        movedPct = try? c.decode(Int.self, forKey: .movedPct)
        photos = (try? c.decode(Int.self, forKey: .photos)) ?? 0
        weights = (try? c.decode([WeighIn].self, forKey: .weights)) ?? []
    }
}

/// One reading on the way, for the line on the journey screen.
struct WeighIn: Codable, Identifiable, Sendable, Equatable {
    var day: String
    var kg: String

    var id: String { day }
    var value: Double? { Double(kg) }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = (try? c.decode(String.self, forKey: .day)) ?? ""
        kg = (try? c.decode(String.self, forKey: .kg)) ?? ""
    }
}

struct JourneyHabit: Codable, Identifiable, Sendable, Equatable {
    var name: String
    var due: Bool
    var done: Bool
    var every: Int
    var needsPhoto: Bool = false
    var hasPhoto: Bool = false
    var days: [String] = []

    var id: String { name }

    /// A photo habit is ticked by the photo, not by the circle.
    var ticked: Bool { needsPhoto ? hasPhoto : done }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        due = (try? c.decode(Bool.self, forKey: .due)) ?? true
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
        every = (try? c.decode(Int.self, forKey: .every)) ?? 1
        needsPhoto = (try? c.decode(Bool.self, forKey: .needsPhoto)) ?? false
        hasPhoto = (try? c.decode(Bool.self, forKey: .hasPhoto)) ?? false
        days = (try? c.decode([String].self, forKey: .days)) ?? []
    }
}

struct Note: Codable, Identifiable, Sendable {
    var when: String
    var text: String

    var id: String { when + text }
}

struct APIReply: Codable, Sendable {
    var ok: Bool
    var pending: Bool?
    var said: String?
    var error: String?
    var state: TrackerState?
    var extra: SheetExtra?
}

// MARK: - The rest of the sheet

struct SheetExtra: Codable, Sendable {
    var setup: [SetupItem] = []
    var categories: [String] = []
    var habitCfg: [HabitConfig] = []
    var scheduled: [ScheduledItem] = []
    var goals: [Goal] = []
    var body: [BodyRow] = []
    var log: [LogRow] = []
    var history: [HistoryDay] = []
    var habitGrid: HabitGridData = HabitGridData()
    var dash: DashData = DashData()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        setup = (try? c.decode([SetupItem].self, forKey: .setup)) ?? []
        categories = (try? c.decode([String].self, forKey: .categories)) ?? []
        habitCfg = (try? c.decode([HabitConfig].self, forKey: .habitCfg)) ?? []
        scheduled = (try? c.decode([ScheduledItem].self, forKey: .scheduled)) ?? []
        goals = (try? c.decode([Goal].self, forKey: .goals)) ?? []
        body = (try? c.decode([BodyRow].self, forKey: .body)) ?? []
        log = (try? c.decode([LogRow].self, forKey: .log)) ?? []
        history = (try? c.decode([HistoryDay].self, forKey: .history)) ?? []
        habitGrid = (try? c.decode(HabitGridData.self, forKey: .habitGrid)) ?? HabitGridData()
        dash = (try? c.decode(DashData.self, forKey: .dash)) ?? DashData()
    }
}

struct SetupItem: Codable, Identifiable, Sendable, Equatable {
    var name: String
    var value: String
    var isBool: Bool

    var id: String { name }
    var boolValue: Bool { value.lowercased() == "true" }
    var isSecret: Bool { name.localizedCaseInsensitiveContains("key") || name.localizedCaseInsensitiveContains("token") }
}

struct HabitConfig: Codable, Identifiable, Sendable, Equatable {
    var slot: Int
    var name: String
    var target: String
    var active: Bool
    var every: Int = 1

    var id: Int { slot }
}

struct ScheduledItem: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var task: String
    var date: String
    var pretty: String
    var slot: String
    var done: Bool
}

struct Goal: Codable, Identifiable, Sendable, Equatable {
    var row: Int
    var goal: String
    var why: String
    var target: String
    var status: String
    var pct: Int
    var notes: String

    var id: Int { row }
}

struct BodyRow: Codable, Identifiable, Sendable, Equatable {
    var date: String
    var pretty: String
    var wt: String
    var waist: String
    var chest: String
    var arm: String
    var fat: String
    var notes: String

    var id: String { date }
}

struct LogRow: Codable, Identifiable, Sendable {
    var when: String
    var tab: String
    var what: String
    var detail: String

    var id: String { when + what + detail }
}

struct HistoryDay: Codable, Identifiable, Sendable, Equatable {
    var date: String
    var done: Int
    var total: Int

    var id: String { date }
    var share: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

struct HabitGridData: Codable, Sendable {
    var year: Int = 0
    var month: Int = 0
    var days: Int = 0
    var label: String = ""
    var today: Int = 0
    var rows: [HabitGridRow] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        year = (try? c.decode(Int.self, forKey: .year)) ?? 0
        month = (try? c.decode(Int.self, forKey: .month)) ?? 0
        days = (try? c.decode(Int.self, forKey: .days)) ?? 0
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        today = (try? c.decode(Int.self, forKey: .today)) ?? 0
        rows = (try? c.decode([HabitGridRow].self, forKey: .rows)) ?? []
    }
}

struct HabitGridRow: Codable, Identifiable, Sendable, Equatable {
    var name: String
    var target: String
    var marks: [Bool]
    var due: [Bool] = []               /* the days this one is actually meant to happen */
    var every: Int = 1
    var owed: Int = 0
    var done: Int
    var streak: Int
    var pct: Int

    var id: String { name }
    var rhythm: String { every <= 1 ? "" : "every \(every) days" }
    func isDue(_ index: Int) -> Bool { index < due.count ? due[index] : true }
}

struct DashData: Codable, Sendable {
    var monthLabel: String = ""
    var tasksDone: Int = 0
    var tasksTotal: Int = 0
    var tasksPct: Int = 0
    var habitDone: Int = 0
    var habitCells: Int = 0
    var habitPct: Int = 0
    var bestStreak: Int = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monthLabel = (try? c.decode(String.self, forKey: .monthLabel)) ?? ""
        tasksDone = (try? c.decode(Int.self, forKey: .tasksDone)) ?? 0
        tasksTotal = (try? c.decode(Int.self, forKey: .tasksTotal)) ?? 0
        tasksPct = (try? c.decode(Int.self, forKey: .tasksPct)) ?? 0
        habitDone = (try? c.decode(Int.self, forKey: .habitDone)) ?? 0
        habitCells = (try? c.decode(Int.self, forKey: .habitCells)) ?? 0
        habitPct = (try? c.decode(Int.self, forKey: .habitPct)) ?? 0
        bestStreak = (try? c.decode(Int.self, forKey: .bestStreak)) ?? 0
    }
}

/// What /api/login and /api/signup answer with.
struct DoorReply: Codable, Sendable {
    var ok: Bool
    var token: String?
    var email: String?
    var status: String?
    var error: String?
}

/// What /api/me answers with.
struct MeReply: Codable, Sendable {
    var ok: Bool
    var email: String?
    var status: String?
    var admin: Bool?
    var calendar: String?
    var error: String?
}
