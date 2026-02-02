// TemplateMarketplaceView.swift
// BeastMode
// Main marketplace view for browsing and downloading plan templates

import SwiftUI
import SwiftData

/// Main marketplace view for discovering plan templates
struct TemplateMarketplaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var featuredTemplates: [PlanTemplate] = []
    @State private var searchText = ""
    @State private var selectedCategory: PlanTemplateCategory?
    @State private var selectedTemplate: PlanTemplate?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var showFilters = false
    @State private var filter = TemplateFilter()
    @State private var sortOption: TemplateSortOption = .popular

    private var userId: UUID? {
        profiles.first?.id
    }

    private var service: TemplateMarketplaceService {
        TemplateMarketplaceService(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if isLoading {
                        loadingView
                    } else if let error {
                        errorView(error)
                    } else {
                        // Search bar
                        searchBarSection

                        // Featured section
                        if searchText.isEmpty && selectedCategory == nil {
                            featuredSection
                        }

                        // Categories
                        if searchText.isEmpty && selectedCategory == nil {
                            categoriesSection
                        }

                        // Selected category or search results
                        if selectedCategory != nil || !searchText.isEmpty {
                            searchResultsSection
                        }

                        // Popular templates (when on home)
                        if searchText.isEmpty && selectedCategory == nil {
                            popularTemplatesSection
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(L10n.Marketplace.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: filter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .sheet(item: $selectedTemplate) { template in
                TemplateDetailSheet(template: template, userId: userId)
            }
            .sheet(isPresented: $showFilters) {
                FilterSheet(filter: $filter, sortOption: $sortOption)
            }
            .task {
                await loadFeaturedTemplates()
            }
        }
    }

    // MARK: - Loading & Error Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(L10n.Marketplace.loading)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label(L10n.Marketplace.errorLoading, systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button(L10n.Common.tryAgain) {
                Task {
                    await loadFeaturedTemplates()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Search Bar

    private var searchBarSection: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField(L10n.Marketplace.searchPlaceholder, text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )

            if selectedCategory != nil {
                Button {
                    selectedCategory = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Featured Section

    private var featuredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.Marketplace.featured)
                    .font(.title2.weight(.bold))

                Spacer()

                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(featuredTemplates) { template in
                        FeaturedTemplateCard(template: template) {
                            selectedTemplate = template
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Categories Section

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Marketplace.categories)
                .font(.title2.weight(.bold))
                .padding(.horizontal)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(PlanTemplateCategory.allCases) { category in
                    CategoryCard(category: category) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Search Results Section

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let category = selectedCategory {
                    HStack(spacing: 8) {
                        Image(systemName: category.icon)
                            .foregroundStyle(Color(hex: category.colorHex))
                        Text(category.rawValue)
                            .font(.title2.weight(.bold))
                    }
                } else {
                    Text(L10n.Marketplace.searchResults)
                        .font(.title2.weight(.bold))
                }

                Spacer()

                Menu {
                    ForEach(TemplateSortOption.allCases) { option in
                        Button {
                            sortOption = option
                        } label: {
                            Label(option.rawValue, systemImage: option.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(sortOption.rawValue)
                            .font(.caption)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            TemplateSearchResultsView(
                category: selectedCategory,
                searchQuery: searchText,
                filter: filter,
                sortOption: sortOption,
                onSelect: { template in
                    selectedTemplate = template
                }
            )
        }
    }

    // MARK: - Popular Templates Section

    private var popularTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.Marketplace.popular)
                    .font(.title2.weight(.bold))

                Spacer()

                Button {
                    // Show all
                } label: {
                    Text(L10n.Marketplace.seeAll)
                        .font(.subheadline)
                }
            }
            .padding(.horizontal)

            LazyVStack(spacing: 12) {
                ForEach(featuredTemplates.prefix(5)) { template in
                    TemplateRowView(template: template) {
                        selectedTemplate = template
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Data Loading

    private func loadFeaturedTemplates() async {
        isLoading = true
        error = nil

        do {
            featuredTemplates = try await service.fetchFeaturedTemplates()
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }
}

// MARK: - Featured Template Card

struct FeaturedTemplateCard: View {
    let template: PlanTemplate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with category badge
                HStack {
                    CategoryBadge(category: template.category)

                    Spacer()

                    if template.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                    }
                }

                // Title and author
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                        .lineLimit(2)

                    Text("by \(template.author)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Stats
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text(template.ratingText)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.green)
                        Text(template.downloadCountText)
                    }
                }
                .font(.caption)

                // Quick info
                Text(template.summaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(width: 260)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: template.category.colorHex).opacity(0.15),
                                Color(hex: template.category.colorHex).opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(hex: template.category.colorHex).opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Card

struct CategoryCard: View {
    let category: PlanTemplateCategory
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: category.colorHex).opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: category.icon)
                        .font(.title3)
                        .foregroundStyle(Color(hex: category.colorHex))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.rawValue)
                        .font(.subheadline.weight(.semibold))

                    Text(category.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Category Badge

struct CategoryBadge: View {
    let category: PlanTemplateCategory

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
            Text(category.rawValue)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(Color(hex: category.colorHex))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(hex: category.colorHex).opacity(0.15))
        )
    }
}

// MARK: - Template Row View

struct TemplateRowView: View {
    let template: PlanTemplate
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: template.category.colorHex).opacity(0.2))
                        .frame(width: 56, height: 56)

                    Image(systemName: template.goal.icon)
                        .font(.title2)
                        .foregroundStyle(Color(hex: template.category.colorHex))
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(template.name)
                            .font(.headline)

                        if template.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }

                    Text("by \(template.author)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text(template.ratingText)
                        }

                        Text("\(template.daysPerWeek) days/wk")

                        Text(template.difficulty.rawValue)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(template.downloadCountText)
                        .font(.subheadline.weight(.semibold))
                    Text("downloads")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Template Search Results View

struct TemplateSearchResultsView: View {
    let category: PlanTemplateCategory?
    let searchQuery: String
    let filter: TemplateFilter
    let sortOption: TemplateSortOption
    let onSelect: (PlanTemplate) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var templates: [PlanTemplate] = []
    @State private var isLoading = true
    @State private var currentPage = 1
    @State private var hasMore = true

    private var service: TemplateMarketplaceService {
        TemplateMarketplaceService(modelContext: modelContext)
    }

    var body: some View {
        Group {
            if isLoading && templates.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if templates.isEmpty {
                ContentUnavailableView {
                    Label(L10n.Marketplace.noResults, systemImage: "magnifyingglass")
                } description: {
                    Text(L10n.Marketplace.tryDifferentSearch)
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(templates) { template in
                        TemplateRowView(template: template) {
                            onSelect(template)
                        }
                        .onAppear {
                            if template == templates.last && hasMore {
                                loadMore()
                            }
                        }
                    }

                    if isLoading {
                        ProgressView()
                            .padding()
                    }
                }
                .padding(.horizontal)
            }
        }
        .task(id: "\(category?.rawValue ?? "")-\(searchQuery)-\(sortOption.rawValue)") {
            await loadTemplates()
        }
    }

    private func loadTemplates() async {
        isLoading = true
        currentPage = 1

        do {
            let result: TemplateSearchResult
            if searchQuery.isEmpty {
                result = try await service.fetchTemplates(
                    category: category,
                    filter: filter,
                    sort: sortOption,
                    page: 1
                )
            } else {
                result = try await service.searchTemplates(
                    query: searchQuery,
                    filter: filter,
                    sort: sortOption,
                    page: 1
                )
            }

            templates = result.templates
            hasMore = result.hasMore
        } catch {
            templates = []
        }

        isLoading = false
    }

    private func loadMore() {
        guard !isLoading && hasMore else { return }

        isLoading = true
        currentPage += 1

        Task {
            do {
                let result: TemplateSearchResult
                if searchQuery.isEmpty {
                    result = try await service.fetchTemplates(
                        category: category,
                        filter: filter,
                        sort: sortOption,
                        page: currentPage
                    )
                } else {
                    result = try await service.searchTemplates(
                        query: searchQuery,
                        filter: filter,
                        sort: sortOption,
                        page: currentPage
                    )
                }

                templates.append(contentsOf: result.templates)
                hasMore = result.hasMore
            } catch {
                // Handle error
            }

            isLoading = false
        }
    }
}

// MARK: - Template Detail Sheet

struct TemplateDetailSheet: View {
    let template: PlanTemplate
    let userId: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var isDownloading = false
    @State private var downloadedPlan: WorkoutPlan?
    @State private var showReviews = false
    @State private var error: Error?

    private var service: TemplateMarketplaceService {
        TemplateMarketplaceService(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Stats
                    statsSection

                    // Description
                    descriptionSection

                    // Schedule preview
                    schedulePreviewSection

                    // Equipment
                    if !template.equipmentRequired.isEmpty {
                        equipmentSection
                    }

                    // Tags
                    if !template.tags.isEmpty {
                        tagsSection
                    }

                    // Reviews preview
                    reviewsPreviewSection

                    Spacer(minLength: 100)
                }
                .padding()
            }
            .overlay(alignment: .bottom) {
                downloadButtonOverlay
            }
            .navigationTitle(L10n.Marketplace.templateDetails)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: template.name) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .alert(L10n.Marketplace.downloadSuccess, isPresented: .init(
                get: { downloadedPlan != nil },
                set: { if !$0 { downloadedPlan = nil } }
            )) {
                Button(L10n.Common.done) {
                    dismiss()
                }
            } message: {
                Text(L10n.Marketplace.planAddedToLibrary)
            }
            .alert(L10n.Marketplace.downloadError, isPresented: .init(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button(L10n.Common.tryAgain) {
                    downloadTemplate()
                }
                Button(L10n.Common.cancel, role: .cancel) {}
            } message: {
                if let error {
                    Text(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CategoryBadge(category: template.category)

                Spacer()

                if template.isVerified {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.blue)
                        Text(L10n.Marketplace.verified)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.blue)
                    }
                }
            }

            Text(template.name)
                .font(.title.weight(.bold))

            HStack(spacing: 4) {
                Text("by")
                    .foregroundStyle(.secondary)
                Text(template.author)
                    .fontWeight(.medium)
            }
            .font(.subheadline)

            // Rating
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= Int(template.rating.rounded()) ? "star.fill" : "star")
                            .foregroundStyle(star <= Int(template.rating.rounded()) ? .yellow : .gray)
                    }
                }

                Text(template.ratingText)
                    .fontWeight(.semibold)

                Text("(\(template.reviewCount) reviews)")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statsSection: some View {
        HStack(spacing: 0) {
            StatBox(value: "\(template.daysPerWeek)", label: "Days/Week", icon: "calendar")
            Divider().frame(height: 40)
            StatBox(value: "\(template.durationWeeks)", label: "Weeks", icon: "clock")
            Divider().frame(height: 40)
            StatBox(value: "\(template.totalExercises)", label: "Exercises", icon: "figure.strengthtraining.traditional")
            Divider().frame(height: 40)
            StatBox(value: template.downloadCountText, label: "Downloads", icon: "arrow.down.circle")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Marketplace.about)
                .font(.headline)

            Text(template.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: template.difficulty.icon)
                    Text(template.difficulty.rawValue)
                }

                HStack(spacing: 4) {
                    Image(systemName: template.goal.icon)
                    Text(template.goal.rawValue)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var schedulePreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Marketplace.weeklySchedule)
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(template.planData.days.sorted(by: { $0.weekday < $1.weekday }), id: \.weekday) { day in
                    HStack {
                        Text(weekdayName(for: day.weekday))
                            .font(.subheadline)
                            .frame(width: 80, alignment: .leading)

                        Text(day.name)
                            .font(.subheadline)
                            .foregroundStyle(day.isRestDay ? .secondary : .primary)

                        Spacer()

                        if !day.isRestDay {
                            Text("\(day.exercises.count) exercises")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(day.isRestDay ? Color.blue.opacity(0.1) : .ultraThinMaterial)
                    )
                }
            }
        }
    }

    private var equipmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Marketplace.equipmentNeeded)
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(template.equipmentRequired, id: \.self) { equipment in
                    Text(equipment)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Marketplace.tags)
                .font(.headline)

            FlowLayout(spacing: 8) {
                ForEach(template.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "FF6B35"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(hex: "FF6B35").opacity(0.15))
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reviewsPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.Marketplace.reviews)
                    .font(.headline)

                Spacer()

                Button {
                    showReviews = true
                } label: {
                    Text(L10n.Marketplace.seeAll)
                        .font(.subheadline)
                }
            }

            // Show first few reviews
            Text(L10n.Marketplace.reviewsAvailable(template.reviewCount))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var downloadButtonOverlay: some View {
        VStack(spacing: 0) {
            Divider()

            Button {
                downloadTemplate()
            } label: {
                HStack {
                    if isDownloading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    Text(L10n.Marketplace.downloadTemplate)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(hex: "FF6B35"))
                )
                .foregroundStyle(.white)
            }
            .disabled(isDownloading || userId == nil)
            .padding()
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Actions

    private func downloadTemplate() {
        guard let userId else { return }

        isDownloading = true
        error = nil

        Task {
            do {
                let plan = try await service.downloadTemplate(template, userId: userId)
                await MainActor.run {
                    downloadedPlan = plan
                    isDownloading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    isDownloading = false
                }
            }
        }
    }

    private func weekdayName(for weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(weekday: weekday)) ?? .now
        return formatter.string(from: date)
    }
}

// MARK: - Stat Box

struct StatBox: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Filter Sheet

struct FilterSheet: View {
    @Binding var filter: TemplateFilter
    @Binding var sortOption: TemplateSortOption
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Sort
                Section(L10n.Marketplace.sortBy) {
                    Picker(L10n.Marketplace.sortBy, selection: $sortOption) {
                        ForEach(TemplateSortOption.allCases) { option in
                            Label(option.rawValue, systemImage: option.icon)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                // Difficulty
                Section(L10n.Plan.difficulty) {
                    ForEach(PlanDifficulty.allCases, id: \.self) { difficulty in
                        Toggle(isOn: Binding(
                            get: { filter.difficulties.contains(difficulty) },
                            set: { isOn in
                                if isOn {
                                    filter.difficulties.insert(difficulty)
                                } else {
                                    filter.difficulties.remove(difficulty)
                                }
                            }
                        )) {
                            HStack {
                                Image(systemName: difficulty.icon)
                                    .foregroundStyle(Color(hex: difficulty.color))
                                Text(difficulty.rawValue)
                            }
                        }
                    }
                }

                // Goal
                Section(L10n.Plan.goal) {
                    ForEach(PlanGoal.allCases, id: \.self) { goal in
                        Toggle(isOn: Binding(
                            get: { filter.goals.contains(goal) },
                            set: { isOn in
                                if isOn {
                                    filter.goals.insert(goal)
                                } else {
                                    filter.goals.remove(goal)
                                }
                            }
                        )) {
                            HStack {
                                Image(systemName: goal.icon)
                                Text(goal.rawValue)
                            }
                        }
                    }
                }

                // Days per week
                Section(L10n.Plan.daysPerWeek) {
                    Stepper(
                        "Min: \(filter.minDaysPerWeek ?? 1) days",
                        value: Binding(
                            get: { filter.minDaysPerWeek ?? 1 },
                            set: { filter.minDaysPerWeek = $0 == 1 ? nil : $0 }
                        ),
                        in: 1...7
                    )

                    Stepper(
                        "Max: \(filter.maxDaysPerWeek ?? 7) days",
                        value: Binding(
                            get: { filter.maxDaysPerWeek ?? 7 },
                            set: { filter.maxDaysPerWeek = $0 == 7 ? nil : $0 }
                        ),
                        in: 1...7
                    )
                }

                // Minimum rating
                Section(L10n.Marketplace.minimumRating) {
                    Picker(L10n.Marketplace.minimumRating, selection: Binding(
                        get: { filter.minRating ?? 0 },
                        set: { filter.minRating = $0 == 0 ? nil : $0 }
                    )) {
                        Text("Any").tag(Double(0))
                        ForEach([3.0, 3.5, 4.0, 4.5], id: \.self) { rating in
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                Text("\(rating, specifier: "%.1f")+ stars")
                            }
                            .tag(rating)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                // Verified only
                Section {
                    Toggle(L10n.Marketplace.verifiedOnly, isOn: $filter.verifiedOnly)
                }

                // Reset
                Section {
                    Button(L10n.Marketplace.resetFilters, role: .destructive) {
                        filter.reset()
                    }
                }
            }
            .navigationTitle(L10n.Marketplace.filters)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.done) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )

        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(
                x: bounds.minX + result.positions[index].x,
                y: bounds.minY + result.positions[index].y
            ), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
                self.size.width = max(self.size.width, currentX)
            }

            self.size.height = currentY + lineHeight
        }
    }
}

// MARK: - Preview

#Preview {
    TemplateMarketplaceView()
}
