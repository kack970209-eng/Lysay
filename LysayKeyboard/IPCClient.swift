import Foundation
import Network

/// 键盘端：连接主 App 的本机服务。所有回调都在主线程。
final class IPCClient {
    var onEvent: ((IPCEvent) -> Void)?
    var onDisconnect: (() -> Void)?

    private var connection: NWConnection?
    private var buffer = Data()
    private(set) var isConnected = false

    func connect(timeout: TimeInterval = 0.8, completion: @escaping (Bool) -> Void) {
        if isConnected, connection != nil {
            completion(true)
            return
        }
        connection?.cancel()
        buffer = Data()

        let conn = NWConnection(host: NWEndpoint.Host(LysayIPC.host),
                                port: NWEndpoint.Port(rawValue: LysayIPC.port)!,
                                using: .tcp)
        var finished = false
        let finish: (Bool) -> Void = { ok in
            guard !finished else { return }
            finished = true
            completion(ok)
        }

        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn, conn === self.connection else { return }
            switch state {
            case .ready:
                self.isConnected = true
                self.receive(on: conn)
                finish(true)
            case .waiting, .failed:
                // 连接被拒绝 = 主 App 没在运行
                let wasConnected = self.isConnected
                self.isConnected = false
                conn.cancel()
                finish(false)
                if wasConnected { self.onDisconnect?() }
            case .cancelled:
                let wasConnected = self.isConnected
                self.isConnected = false
                finish(false)
                if wasConnected { self.onDisconnect?() }
            default:
                break
            }
        }
        connection = conn
        conn.start(queue: .main)

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak conn] in
            guard !finished else { return }
            conn?.cancel()
            finish(false)
        }
    }

    func send(_ cmd: IPCCommand) {
        guard let conn = connection, isConnected, let data = LineCodec.encode(cmd) else { return }
        conn.send(content: data, completion: .contentProcessed { _ in })
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    private func receive(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, conn === self.connection else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                for line in LineCodec.drainLines(&self.buffer) {
                    if let event = try? JSONDecoder().decode(IPCEvent.self, from: line) {
                        self.onEvent?(event)
                    }
                }
            }
            if isComplete || error != nil {
                conn.cancel()
                return
            }
            self.receive(on: conn)
        }
    }
}
