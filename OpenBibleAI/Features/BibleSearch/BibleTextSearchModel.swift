import BibleDomain
import Observation

@MainActor
@Observable
final class BibleTextSearchModel {
    enum State: Equatable {
        case idle
        case tooShort
        case loading(query: String)
        case loaded(query: String, result: BibleTextSearchResult)
        case failed(query: String, message: String)
    }

    static let defaultResultLimit = 100

    private(set) var state: State = .idle

    @ObservationIgnored private let repository: any BibleTextSearchRepository
    @ObservationIgnored private let resultLimit: Int
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        repository: any BibleTextSearchRepository,
        resultLimit: Int = BibleTextSearchModel.defaultResultLimit
    ) {
        self.repository = repository
        self.resultLimit = resultLimit
    }

    /// Starts a search, cancelling the one this model started before it.
    @discardableResult
    func submit(_ rawQuery: String) -> Task<Void, Never> {
        task?.cancel()
        let newTask = Task { await search(rawQuery) }
        task = newTask
        return newTask
    }

    /// Cancels the task started by `submit` and clears published state.
    func cancel() {
        task?.cancel()
        task = nil
        reset()
    }

    /// Publishes search state only; it never changes reader selection or
    /// the saved reading position. Direct callers own their task.
    func search(_ rawQuery: String) async {
        guard !Task.isCancelled else { return }
        generation += 1
        let requestGeneration = generation

        let query: BibleTextQuery
        do {
            query = try BibleTextQuery(rawQuery)
        } catch {
            state = .tooShort
            return
        }

        state = .loading(query: rawQuery)

        do {
            let result = try await repository.search(query, limit: resultLimit)
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }
            state = .loaded(query: rawQuery, result: result)
        } catch {
            guard requestGeneration == generation else { return }
            if Task.isCancelled || error is CancellationError {
                state = .idle
            } else {
                state = .failed(
                    query: rawQuery,
                    message: "Could not search the Bible. Please try again. \(error)"
                )
            }
        }
    }

    /// Invalidates pending results immediately. The caller should also cancel
    /// its task when leaving search; invalidation cannot stop repository work.
    func reset() {
        generation += 1
        state = .idle
    }
}
