// TemplateMarketplaceService.swift
// BeastMode
// Service for browsing and downloading plan templates from the marketplace

import Foundation
import SwiftData

/// Service for interacting with the plan template marketplace
actor TemplateMarketplaceService {
    private let modelContext: ModelContext

    /// Base URL for the marketplace API
    private let baseURL: URL

    /// URLSession for network requests
    private let session: URLSession

    /// Cache for loaded templates
    private var templateCache: [UUID: PlanTemplate] = [:]

    /// Cache for featured templates
    private var featuredCache: [PlanTemplate]?
    private var featuredCacheDate: Date?

    /// Cache duration in seconds
    private let cacheDuration: TimeInterval = 300  // 5 minutes

    init(modelContext: ModelContext, baseURL: URL? = nil) {
        self.modelContext = modelContext
        self.baseURL = baseURL ?? URL(string: "https://api.beastmode.app/marketplace")!

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Featured Templates

    /// Fetch featured templates for the marketplace homepage
    func fetchFeaturedTemplates() async throws -> [PlanTemplate] {
        // Check cache first
        if let cached = featuredCache,
           let cacheDate = featuredCacheDate,
           Date().timeIntervalSince(cacheDate) < cacheDuration {
            return cached
        }

        // For now, return mock data since we don't have a real backend
        // In production, this would make an API call
        let featured = createMockFeaturedTemplates()

        // Update cache
        featuredCache = featured
        featuredCacheDate = Date()

        return featured
    }

    /// Fetch templates by category
    func fetchTemplates(
        category: PlanTemplateCategory?,
        filter: TemplateFilter = TemplateFilter(),
        sort: TemplateSortOption = .popular,
        page: Int = 1,
        pageSize: Int = 20
    ) async throws -> TemplateSearchResult {
        // In production, this would make an API call with query parameters
        var templates = createMockTemplates()

        // Apply category filter
        if let category {
            templates = templates.filter { $0.category == category }
        }

        // Apply additional filters
        if !filter.categories.isEmpty {
            templates = templates.filter { filter.categories.contains($0.category) }
        }

        if !filter.difficulties.isEmpty {
            templates = templates.filter { filter.difficulties.contains($0.difficulty) }
        }

        if !filter.goals.isEmpty {
            templates = templates.filter { filter.goals.contains($0.goal) }
        }

        if let minRating = filter.minRating {
            templates = templates.filter { $0.rating >= minRating }
        }

        if let maxDuration = filter.maxDurationWeeks {
            templates = templates.filter { $0.durationWeeks <= maxDuration }
        }

        if let minDays = filter.minDaysPerWeek {
            templates = templates.filter { $0.daysPerWeek >= minDays }
        }

        if let maxDays = filter.maxDaysPerWeek {
            templates = templates.filter { $0.daysPerWeek <= maxDays }
        }

        if filter.verifiedOnly {
            templates = templates.filter { $0.isVerified }
        }

        // Apply sorting
        templates = sortTemplates(templates, by: sort)

        // Paginate
        let totalCount = templates.count
        let startIndex = (page - 1) * pageSize
        let endIndex = min(startIndex + pageSize, templates.count)

        guard startIndex < templates.count else {
            return TemplateSearchResult(
                templates: [],
                totalCount: totalCount,
                page: page,
                pageSize: pageSize,
                hasMore: false
            )
        }

        let pageTemplates = Array(templates[startIndex..<endIndex])

        return TemplateSearchResult(
            templates: pageTemplates,
            totalCount: totalCount,
            page: page,
            pageSize: pageSize,
            hasMore: endIndex < totalCount
        )
    }

    /// Search templates by query string
    func searchTemplates(
        query: String,
        filter: TemplateFilter = TemplateFilter(),
        sort: TemplateSortOption = .popular,
        page: Int = 1,
        pageSize: Int = 20
    ) async throws -> TemplateSearchResult {
        guard !query.isEmpty else {
            return try await fetchTemplates(category: nil, filter: filter, sort: sort, page: page, pageSize: pageSize)
        }

        var templates = createMockTemplates()

        // Search in name, description, author, and tags
        let lowercaseQuery = query.lowercased()
        templates = templates.filter { template in
            template.name.lowercased().contains(lowercaseQuery) ||
            template.description.lowercased().contains(lowercaseQuery) ||
            template.author.lowercased().contains(lowercaseQuery) ||
            template.tags.contains { $0.lowercased().contains(lowercaseQuery) }
        }

        // Apply additional filters
        if !filter.isEmpty {
            templates = applyFilters(to: templates, filter: filter)
        }

        // Sort
        templates = sortTemplates(templates, by: sort)

        // Paginate
        let totalCount = templates.count
        let startIndex = (page - 1) * pageSize
        let endIndex = min(startIndex + pageSize, templates.count)

        guard startIndex < templates.count else {
            return TemplateSearchResult(
                templates: [],
                totalCount: totalCount,
                page: page,
                pageSize: pageSize,
                hasMore: false
            )
        }

        let pageTemplates = Array(templates[startIndex..<endIndex])

        return TemplateSearchResult(
            templates: pageTemplates,
            totalCount: totalCount,
            page: page,
            pageSize: pageSize,
            hasMore: endIndex < totalCount
        )
    }

    /// Get a single template by ID
    func getTemplate(id: UUID) async throws -> PlanTemplate {
        // Check cache
        if let cached = templateCache[id] {
            return cached
        }

        // In production, fetch from API
        let templates = createMockTemplates()
        guard let template = templates.first(where: { $0.id == id }) else {
            throw MarketplaceError.templateNotFound
        }

        // Cache it
        templateCache[id] = template

        return template
    }

    // MARK: - Download Template

    /// Download a template and create a WorkoutPlan from it
    func downloadTemplate(_ template: PlanTemplate, userId: UUID) async throws -> WorkoutPlan {
        // Convert the ShareablePlan to a WorkoutPlan
        let plan = template.planData.toPlan(userId: userId)

        // Set additional metadata
        plan.authorName = template.author

        // Insert into context
        modelContext.insert(plan)

        // In production, this would also increment the download count on the server
        // await incrementDownloadCount(templateId: template.id)

        return plan
    }

    /// Download a template by ID
    func downloadTemplate(id: UUID, userId: UUID) async throws -> WorkoutPlan {
        let template = try await getTemplate(id: id)
        return try await downloadTemplate(template, userId: userId)
    }

    // MARK: - Ratings & Reviews

    /// Submit a rating for a template
    func submitRating(
        templateId: UUID,
        userId: UUID,
        userName: String,
        rating: Int,
        title: String? = nil,
        content: String? = nil
    ) async throws -> TemplateReview {
        // Validate rating
        guard (1...5).contains(rating) else {
            throw MarketplaceError.invalidRating
        }

        // In production, this would POST to the API
        let review = TemplateReview(
            templateId: templateId,
            userId: userId,
            userName: userName,
            rating: rating,
            title: title,
            content: content
        )

        return review
    }

    /// Fetch reviews for a template
    func fetchReviews(
        templateId: UUID,
        page: Int = 1,
        pageSize: Int = 10
    ) async throws -> [TemplateReview] {
        // In production, this would fetch from API
        // For now, return mock reviews
        return createMockReviews(for: templateId)
    }

    // MARK: - Categories

    /// Get all available categories with template counts
    func fetchCategories() async throws -> [(category: PlanTemplateCategory, count: Int)] {
        // In production, this would come from the API
        let templates = createMockTemplates()
        var categoryCounts: [PlanTemplateCategory: Int] = [:]

        for template in templates {
            categoryCounts[template.category, default: 0] += 1
        }

        return PlanTemplateCategory.allCases.map { category in
            (category: category, count: categoryCounts[category] ?? 0)
        }.sorted { $0.count > $1.count }
    }

    /// Get popular tags
    func fetchPopularTags(limit: Int = 20) async throws -> [String] {
        // In production, this would come from the API
        return [
            "PPL", "Upper/Lower", "Full Body", "5x5", "PHAT",
            "PHUL", "nSuns", "Starting Strength", "531",
            "Stronglifts", "ICF", "GZCLP", "Reddit PPL",
            "Jeff Nippard", "Renaissance Periodization", "Garage Gym",
            "Minimal Equipment", "Dumbbell Only", "Home Workout", "High Volume"
        ]
    }

    // MARK: - Helpers

    private func sortTemplates(_ templates: [PlanTemplate], by option: TemplateSortOption) -> [PlanTemplate] {
        switch option {
        case .popular:
            return templates.sorted { ($0.downloadCount + $0.reviewCount * 10) > ($1.downloadCount + $1.reviewCount * 10) }
        case .topRated:
            return templates.sorted { $0.rating > $1.rating }
        case .newest:
            return templates.sorted { $0.createdAt > $1.createdAt }
        case .mostDownloads:
            return templates.sorted { $0.downloadCount > $1.downloadCount }
        }
    }

    private func applyFilters(to templates: [PlanTemplate], filter: TemplateFilter) -> [PlanTemplate] {
        var result = templates

        if !filter.categories.isEmpty {
            result = result.filter { filter.categories.contains($0.category) }
        }

        if !filter.difficulties.isEmpty {
            result = result.filter { filter.difficulties.contains($0.difficulty) }
        }

        if !filter.goals.isEmpty {
            result = result.filter { filter.goals.contains($0.goal) }
        }

        if let minRating = filter.minRating {
            result = result.filter { $0.rating >= minRating }
        }

        if let maxDuration = filter.maxDurationWeeks {
            result = result.filter { $0.durationWeeks <= maxDuration }
        }

        if let minDays = filter.minDaysPerWeek {
            result = result.filter { $0.daysPerWeek >= minDays }
        }

        if let maxDays = filter.maxDaysPerWeek {
            result = result.filter { $0.daysPerWeek <= maxDays }
        }

        if filter.verifiedOnly {
            result = result.filter { $0.isVerified }
        }

        return result
    }

    // MARK: - Mock Data

    private func createMockFeaturedTemplates() -> [PlanTemplate] {
        [
            createMockTemplate(
                name: "PPL Hypertrophy Pro",
                description: "A proven push/pull/legs split designed for maximum muscle growth. Features progressive overload tracking and periodized volume.",
                author: "Beast Mode Team",
                category: .hypertrophy,
                difficulty: .intermediate,
                goal: .hypertrophy,
                daysPerWeek: 6,
                durationWeeks: 12,
                downloadCount: 15420,
                rating: 4.8,
                reviewCount: 892,
                isFeatured: true,
                isVerified: true
            ),
            createMockTemplate(
                name: "Starting Strength",
                description: "The classic novice program. Build foundational strength with compound lifts. Perfect for beginners.",
                author: "Beast Mode Team",
                category: .beginner,
                difficulty: .beginner,
                goal: .strength,
                daysPerWeek: 3,
                durationWeeks: 8,
                downloadCount: 28340,
                rating: 4.9,
                reviewCount: 2103,
                isFeatured: true,
                isVerified: true
            ),
            createMockTemplate(
                name: "Powerlifting Peak",
                description: "Competition prep program focusing on squat, bench, and deadlift. Includes peaking protocol.",
                author: "Strong Lifts Co",
                category: .powerlifting,
                difficulty: .advanced,
                goal: .powerlifting,
                daysPerWeek: 4,
                durationWeeks: 16,
                downloadCount: 8750,
                rating: 4.7,
                reviewCount: 456,
                isFeatured: true,
                isVerified: true
            )
        ]
    }

    private func createMockTemplates() -> [PlanTemplate] {
        var templates = createMockFeaturedTemplates()

        templates.append(contentsOf: [
            createMockTemplate(
                name: "Upper/Lower Split",
                description: "Classic 4-day split alternating upper and lower body. Great for intermediates.",
                author: "FitPro",
                category: .hypertrophy,
                difficulty: .intermediate,
                goal: .hypertrophy,
                daysPerWeek: 4,
                durationWeeks: 10,
                downloadCount: 12300,
                rating: 4.6,
                reviewCount: 678
            ),
            createMockTemplate(
                name: "5/3/1 BBB",
                description: "Jim Wendler's 5/3/1 with Boring But Big accessory work. Builds strength and size.",
                author: "Iron Warriors",
                category: .strength,
                difficulty: .intermediate,
                goal: .strength,
                daysPerWeek: 4,
                durationWeeks: 12,
                downloadCount: 9870,
                rating: 4.8,
                reviewCount: 534,
                isVerified: true
            ),
            createMockTemplate(
                name: "Full Body 3x",
                description: "Efficient full body workouts 3 times per week. Perfect for busy schedules.",
                author: "MinMax Fitness",
                category: .beginner,
                difficulty: .beginner,
                goal: .general,
                daysPerWeek: 3,
                durationWeeks: 8,
                downloadCount: 18500,
                rating: 4.5,
                reviewCount: 1245
            ),
            createMockTemplate(
                name: "Athletic Performance",
                description: "Build explosive power and conditioning for sports. Includes plyometrics and agility work.",
                author: "Sport Science Lab",
                category: .athletic,
                difficulty: .intermediate,
                goal: .strength,
                daysPerWeek: 5,
                durationWeeks: 8,
                downloadCount: 5430,
                rating: 4.4,
                reviewCount: 234
            ),
            createMockTemplate(
                name: "Shred 45",
                description: "45-day fat loss program with high-intensity circuits and strategic cardio.",
                author: "Lean Machine",
                category: .weightLoss,
                difficulty: .intermediate,
                goal: .endurance,
                daysPerWeek: 5,
                durationWeeks: 6,
                downloadCount: 21000,
                rating: 4.3,
                reviewCount: 987
            ),
            createMockTemplate(
                name: "Classic Bodybuilding",
                description: "Golden era inspired bodybuilding split. High volume, sculpted physique.",
                author: "Golden Physique",
                category: .bodybuilding,
                difficulty: .advanced,
                goal: .hypertrophy,
                daysPerWeek: 5,
                durationWeeks: 12,
                downloadCount: 7650,
                rating: 4.6,
                reviewCount: 412
            ),
            createMockTemplate(
                name: "Functional Fitness",
                description: "Real-world strength and mobility. Combines lifting, carries, and movement work.",
                author: "Movement Mastery",
                category: .functional,
                difficulty: .intermediate,
                goal: .general,
                daysPerWeek: 4,
                durationWeeks: 8,
                downloadCount: 6200,
                rating: 4.5,
                reviewCount: 298
            ),
            createMockTemplate(
                name: "Dumbbell Only",
                description: "Complete hypertrophy program using only dumbbells. Perfect for home gyms.",
                author: "Home Gym Heroes",
                category: .hypertrophy,
                difficulty: .beginner,
                goal: .hypertrophy,
                daysPerWeek: 4,
                durationWeeks: 10,
                downloadCount: 25600,
                rating: 4.7,
                reviewCount: 1567
            )
        ])

        return templates
    }

    private func createMockTemplate(
        name: String,
        description: String,
        author: String,
        category: PlanTemplateCategory,
        difficulty: PlanDifficulty,
        goal: PlanGoal,
        daysPerWeek: Int,
        durationWeeks: Int,
        downloadCount: Int,
        rating: Double,
        reviewCount: Int,
        isFeatured: Bool = false,
        isVerified: Bool = false
    ) -> PlanTemplate {
        // Create a basic shareable plan
        let planData = ShareablePlan(
            version: 1,
            name: name,
            description: description,
            authorName: author,
            difficulty: difficulty.rawValue,
            goal: goal.rawValue,
            daysPerWeek: daysPerWeek,
            estimatedDuration: durationWeeks,
            days: createMockDays(daysPerWeek: daysPerWeek),
            createdAt: Date()
        )

        return PlanTemplate(
            name: name,
            description: description,
            author: author,
            category: category,
            tags: [category.rawValue, difficulty.rawValue, goal.rawValue],
            difficulty: difficulty,
            goal: goal,
            durationWeeks: durationWeeks,
            daysPerWeek: daysPerWeek,
            downloadCount: downloadCount,
            rating: rating,
            reviewCount: reviewCount,
            previewImages: [],
            planData: planData,
            equipmentRequired: ["Barbell", "Dumbbells", "Bench"],
            targetMuscleGroups: ["Chest", "Back", "Shoulders", "Legs", "Arms"],
            isFeatured: isFeatured,
            isVerified: isVerified
        )
    }

    private func createMockDays(daysPerWeek: Int) -> [ShareablePlanDay] {
        let dayTemplates: [(name: String, exercises: [String])] = [
            ("Push", ["Bench Press", "Overhead Press", "Incline Dumbbell Press", "Lateral Raises", "Tricep Pushdowns"]),
            ("Pull", ["Deadlift", "Barbell Rows", "Pull-ups", "Face Pulls", "Bicep Curls"]),
            ("Legs", ["Squats", "Romanian Deadlift", "Leg Press", "Leg Curls", "Calf Raises"]),
            ("Upper", ["Bench Press", "Barbell Rows", "Overhead Press", "Pull-ups", "Bicep Curls"]),
            ("Lower", ["Squats", "Romanian Deadlift", "Leg Press", "Leg Curls", "Calf Raises"]),
            ("Full Body", ["Squats", "Bench Press", "Barbell Rows", "Overhead Press", "Deadlift"])
        ]

        var days: [ShareablePlanDay] = []
        var usedTemplates = 0

        for weekday in 1...7 {
            if usedTemplates < daysPerWeek && weekday != 1 {  // Skip Sunday as rest
                let template = dayTemplates[usedTemplates % dayTemplates.count]
                let exercises = template.exercises.enumerated().map { index, name in
                    ShareablePlanExercise(
                        name: name,
                        sets: 3,
                        repsMin: 8,
                        repsMax: 12,
                        rpe: nil,
                        restSeconds: 90,
                        notes: nil,
                        superset: false
                    )
                }

                days.append(ShareablePlanDay(
                    weekday: weekday,
                    name: template.name,
                    isRestDay: false,
                    notes: nil,
                    exercises: exercises
                ))
                usedTemplates += 1
            } else {
                days.append(ShareablePlanDay(
                    weekday: weekday,
                    name: "Rest",
                    isRestDay: true,
                    notes: nil,
                    exercises: []
                ))
            }
        }

        return days
    }

    private func createMockReviews(for templateId: UUID) -> [TemplateReview] {
        [
            TemplateReview(
                templateId: templateId,
                userId: UUID(),
                userName: "FitnessFan123",
                rating: 5,
                title: "Great program!",
                content: "Gained significant strength in 8 weeks. Highly recommend for intermediates.",
                helpfulCount: 24
            ),
            TemplateReview(
                templateId: templateId,
                userId: UUID(),
                userName: "GymRat",
                rating: 4,
                title: "Solid routine",
                content: "Good exercise selection. Would prefer more volume on back days.",
                helpfulCount: 12
            ),
            TemplateReview(
                templateId: templateId,
                userId: UUID(),
                userName: "StrengthSeeker",
                rating: 5,
                title: "Perfect for my goals",
                content: "Exactly what I was looking for. Clear progression scheme.",
                helpfulCount: 18
            )
        ]
    }

    // MARK: - Cache Management

    /// Clear all caches
    func clearCache() {
        templateCache.removeAll()
        featuredCache = nil
        featuredCacheDate = nil
    }
}

// MARK: - Errors

enum MarketplaceError: LocalizedError {
    case templateNotFound
    case networkError(Error)
    case invalidRating
    case downloadFailed
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .templateNotFound:
            return "Template not found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidRating:
            return "Rating must be between 1 and 5"
        case .downloadFailed:
            return "Failed to download template"
        case .unauthorized:
            return "Please sign in to perform this action"
        }
    }
}

// MARK: - ShareablePlan Extension for Direct Init

extension ShareablePlan {
    /// Direct initialization for creating mock data
    init(
        version: Int,
        name: String,
        description: String?,
        authorName: String?,
        difficulty: String,
        goal: String,
        daysPerWeek: Int,
        estimatedDuration: Int,
        days: [ShareablePlanDay],
        createdAt: Date
    ) {
        self.version = version
        self.name = name
        self.description = description
        self.authorName = authorName
        self.difficulty = difficulty
        self.goal = goal
        self.daysPerWeek = daysPerWeek
        self.estimatedDuration = estimatedDuration
        self.days = days
        self.createdAt = createdAt
    }
}

extension ShareablePlanDay {
    /// Direct initialization for creating mock data
    init(
        weekday: Int,
        name: String,
        isRestDay: Bool,
        notes: String?,
        exercises: [ShareablePlanExercise]
    ) {
        self.weekday = weekday
        self.name = name
        self.isRestDay = isRestDay
        self.notes = notes
        self.exercises = exercises
    }
}

extension ShareablePlanExercise {
    /// Direct initialization for creating mock data
    init(
        name: String,
        sets: Int,
        repsMin: Int,
        repsMax: Int,
        rpe: Double?,
        restSeconds: Int,
        notes: String?,
        superset: Bool
    ) {
        self.name = name
        self.sets = sets
        self.repsMin = repsMin
        self.repsMax = repsMax
        self.rpe = rpe
        self.restSeconds = restSeconds
        self.notes = notes
        self.superset = superset
    }
}
