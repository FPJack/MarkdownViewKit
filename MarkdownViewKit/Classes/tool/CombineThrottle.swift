import Combine
import Foundation

final class CombineThrottle<Value> {

    private let subject = PassthroughSubject<Value, Never>()
    private var cancellable: AnyCancellable?

    init(
        interval: RunLoop.SchedulerTimeType.Stride,
        latest: Bool = true,
        scheduler: RunLoop = .main,
        handler: @escaping (Value) -> Void
    ) {
        cancellable = subject
            .throttle(
                for: interval,
                scheduler: scheduler,
                latest: latest
            )
            .sink { value in
                handler(value)
            }
    }

    func send(_ value: Value) {
        subject.send(value)
    }

    func cancel() {
        cancellable?.cancel()
        cancellable = nil
    }

    deinit {
        cancellable?.cancel()
    }
}
