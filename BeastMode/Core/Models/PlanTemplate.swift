// PlanTemplate.swift
// BeastMode
// Model for marketplace plan templates

import Foundation

// MARK: - Plan Template Category

/// Categories for organizing plan templates in the marketplace
enum PlanTemplateCategory: String, Codable, CaseIterable, Identifiable {
    case strength = "Strength"
    case hypertrophy = "Hypertrophy"
    case powerlifting = "Powerlifting"
    case athletic = "Athletic"
    case beginner = "Beginner"
    case weightLoss = "Weight Loss"
    case bodybuilding = "Bodybuilding"
    case functional = "Functional"
    case sport = "Sport Specific"
    case rehabilitation = "Rehabilitation"

    var id: String { rawValue }

    /// SF Symbol icon for the category
    var icon: String {
        switch self {
        case .strength: return "bolt.fill"
        case .hypertrophy: return "figure.strengthtraining.traditional"
        case .powerlifting: return "scalemass.fill"
        case .athletic: return "figure.run"
        case .beginner: return "star.fill"
        case .weightLoss: return "flame.fill"
        case .bodybuilding: return "figure.arms.open"
        case .functional: return "figure.mixed.cardio"
        case .sport: return "sportscourt.fill"
        case .rehabilitation: return "heart.circle.fill"
        }
    }

    /// Color hex for the category
    var colorHex: String {
        switch self {
        case .strength: return "EF4444"      // Red
        case .hypertrophy: return "F59E0B"   // Amber
        case .powerlifting: return "8B5CF6"  // Purple
        case .athletic: return "10B981"      // Emerald
        case .beginner: return "22C55E"      // Green
        case .weightLoss: return "F97316"    // Orange
        case .bodybuilding: return "3B82F6"  // Blue
        case .functional: return "06B6D4"    // Cyan
        case .sport: return "EC4899"         // Pink
        case .rehabilitation: return "14B8A6" // Teal
        }
    }

    /// Description for the category
    var description: String {
        switch self {
        case .strength:
            return "Build raw strength with heavy compound lifts"
        case .hypertrophy:
            return "Maximize muscle growth and size"
        case .powerlifting:
            return "Squat, bench, and deadlift focused programs"
        case .athletic:
            return "Improve speed, power, and athleticism"
        case .beginner:
            return "Perfect for those new to weight training"
        case .weightLoss:
            return "High-intensity programs for fat loss"
        case .bodybuilding:
            return "Sculpt and define your physique"
        case .functional:
            return "Real-world strength and mobility"
        case .sport:
            return "Tailored for specific sports performance"
        case .rehabilitation:
            return "Recovery and injury prevention focused"
        }
    }
}

// MARK: - Plan Template Model

/// A workout plan template available in the marketplace
struct PlanTemplate: Codable, Identifiable, Hashable {
    /// Unique identifier for the template
    let id: UUID

    /// Template name
    let name: String

    /// Detailed description of the template
    let description: String

    /// Author/creator name
    let author: String

    /// Author's unique identifier (if registered user)
    let authorId: UUID?

    /// Primary category
    let category: PlanTemplateCategory

    /// Secondary categories/tags
    let tags: [String]

    /// Difficulty level
    let difficulty: PlanDifficulty

    /// Primary training goal
    let goal: PlanGoal

    /// Duration of the program in weeks
    let durationWeeks: Int

    /// Days per week the program requires
    let daysPerWeek: Int

    /// Number of times this template has been downloaded
    var downloadCount: Int

    /// Average user rating (1-5)
    var rating: Double

    /// Number of reviews
    var reviewCount: Int

    /// URLs to preview images
    let previewImages: [String]

    /// The actual workout plan data
    let planData: ShareablePlan

    /// Equipment required for this program
    let equipmentRequired: [String]

    /// Target muscle groups
    let targetMuscleGroups: [String]

    /// Whether this template is featured
    var isFeatured: Bool

    /// Whether this template is verified/official
    var isVerified: Bool

    /// Date the template was created
    let createdAt: Date

    /// Date the template was last updated
    var updatedAt: Date

    /// Version of the template
    let version: Int

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        author: String,
        authorId: UUID? = nil,
        category: PlanTemplateCategory,
        tags: [String] = [],
        difficulty: PlanDifficulty = .intermediate,
        goal: PlanGoal = .strength,
        durationWeeks: Int = 8,
        daysPerWeek: Int = 4,
        downloadCount: Int = 0,
        rating: Double = 0,
        reviewCount: Int = 0,
        previewImages: [String] = [],
        planData: ShareablePlan,
        equipmentRequired: [String] = [],
        targetMuscleGroups: [String] = [],
        isFeatured: Bool = false,
        isVerified: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        version: Int = 1
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.author = author
        self.authorId = authorId
        self.category = category
        self.tags = tags
        self.difficulty = difficulty
        self.goal = goal
        self.durationWeeks = durationWeeks
        self.daysPerWeek = daysPerWeek
        self.downloadCount = downloadCount
        self.rating = rating
        self.reviewCount = reviewCount
        self.previewImages = previewImages
        self.planData = planData
        self.equipmentRequired = equipmentRequired
        self.targetMuscleGroups = targetMuscleGroups
        self.isFeatured = isFeatured
        self.isVerified = isVerified
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.version = version
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PlanTemplate, rhs: PlanTemplate) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Computed Properties

    /// Formatted rating string
    var ratingText: String {
        if reviewCount == 0 {
            return "No reviews"
        }
        return String(format: "%.1f", rating)
    }

    /// Formatted download count
    var downloadCountText: String {
        if downloadCount >= 1_000_000 {
            return String(format: "%.1fM", Double(downloadCount) / 1_000_000)
        } else if downloadCount >= 1_000 {
            return String(format: "%.1fK", Double(downloadCount) / 1_000)
        }
        return "\(downloadCount)"
    }

    /// Summary text for display
    var summaryText: String {
        "\(daysPerWeek) days/week • \(durationWeeks) weeks • \(difficulty.rawValue)"
    }

    /// Total exercises in the plan
    var totalExercises: Int {
        planData.days.reduce(0) { $0 + $1.exercises.count }
    }

    /// Total sets in the plan
    var totalSets: Int {
        planData.days.reduce(0) { total, day in
            total + day.exercises.reduce(0) { $0 + $1.sets }
        }
    }
}

// MARK: - Template Review

/// A user review for a plan template
struct TemplateReview: Codable, Identifiable {
    let id: UUID
    let templateId: UUID
    let userId: UUID
    let userName: String
    let rating: Int  // 1-5
    let title: String?
    let content: String?
    let createdAt: Date
    var helpfulCount: Int

    init(
        id: UUID = UUID(),
        templateId: UUID,
        userId: UUID,
        userName: String,
        rating: Int,
        title: String? = nil,
        content: String? = nil,
        createdAt: Date = .now,
        helpfulCount: Int = 0
    ) {
        self.id = id
        self.templateId = templateId
        self.userId = userId
        self.userName = userName
        self.rating = min(5, max(1, rating))  // Clamp to 1-5
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.helpfulCount = helpfulCount
    }
}

// MARK: - Template Search Result

/// Result from a template search query
struct TemplateSearchResult: Codable {
    let templates: [PlanTemplate]
    let totalCount: Int
    let page: Int
    let pageSize: Int
    let hasMore: Bool
}

// MARK: - Template Filter

/// Filters for searching templates
struct TemplateFilter {
    var categories: Set<PlanTemplateCategory> = []
    var difficulties: Set<PlanDifficulty> = []
    var goals: Set<PlanGoal> = []
    var minRating: Double?
    var maxDurationWeeks: Int?
    var minDaysPerWeek: Int?
    var maxDaysPerWeek: Int?
    var tags: Set<String> = []
    var verifiedOnly: Bool = false

    var isEmpty: Bool {
        categories.isEmpty &&
        difficulties.isEmpty &&
        goals.isEmpty &&
        minRating == nil &&
        maxDurationWeeks == nil &&
        minDaysPerWeek == nil &&
        maxDaysPerWeek == nil &&
        tags.isEmpty &&
        !verifiedOnly
    }

    mutating func reset() {
        categories.removeAll()
        difficulties.removeAll()
        goals.removeAll()
        minRating = nil
        maxDurationWeeks = nil
        minDaysPerWeek = nil
        maxDaysPerWeek = nil
        tags.removeAll()
        verifiedOnly = false
    }
}

// MARK: - Sort Option

/// Sort options for template listings
enum TemplateSortOption: String, CaseIterable, Identifiable {
    case popular = "Most Popular"
    case topRated = "Top Rated"
    case newest = "Newest"
    case mostDownloads = "Most Downloads"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .popular: return "flame.fill"
        case .topRated: return "star.fill"
        case .newest: return "clock.fill"
        case .mostDownloads: return "arrow.down.circle.fill"
        }
    }
}
