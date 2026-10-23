import Foundation
import Network

/// 监听 127.0.0.1:47821，供键盘扩展连接。
final class LocalServer {
    final class Client {
        let connection: NWConnection
        fileprivate var buffer = Data()
        init(_ c: NWConnection) { connection = c }

        func send(_ event: IPCEvent) {
            guard let data = LineCodec.encode(event) else { return }
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    /// 收到命令时在主线程回调
    var onCommand: ((IPCCommand, Client) -> Void)?

    private var listener: NWListener?
    private var clients: [ObjectIdentifier: Client] = [:]
    private let queue = DispatchQueue(label: "lysay.server")
    private var restartScheduled = false

    func start() {
        queue.async { self.startOnQueue() }
    }

    private func startOnQueue() {
        if let l = listener {
            switch l.state {
            case .ready, .setup, .waiting: return
            default:
                l.cancel()
                listener = nil
            }
        }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            // 只接受本机回环连接，不对外暴露
            params.requiredInterfaceType = .loopback
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: LysayIPC.port)!)
            l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            l.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed(let err):
                    NSLog("[Lysay] 监听失败: \(err)")
                    self?.scheduleRestart()
                case .cancelled:
                    break
                default:
                    break
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            NSLog("[Lysay] 无法创建监听: \(error)")
            scheduleRestart()
        }
    }

    private func scheduleRestart() {
        guard !restartScheduled else { return }
        restartScheduled = true
        queue.asyncAfter(deadline: .now() + 1) {
            self.restartScheduled = false
            self.listener?.cancel()
            self.listener = nil
            self.startOnQueue()
        }
    }

    func broadcast(_ event: IPCEvent) {
        queue.async {
            for c in self.clients.values { c.send(event) }
        }
    }

    private func accept(_ conn: NWConnection) {
        let client = Client(conn)
        let key = ObjectIdentifier(client)
        clients[key] = client
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.queue.async { self?.clients.removeValue(forKey: key) }
            default:
                break
            }
        }
        conn.start(queue: queue)
        receive(client)
    }

    private func receive(_ client: Client) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                client.buffer.append(data)
                for line in LineCodec.drainLines(&client.buffer) {
                    if let cmd = try? JSONDecoder().decode(IPCCommand.self, from: line) {
                        DispatchQueue.main.async { self.onCommand?(cmd, client) }
                    }
                }
            }
            if isComplete || error != nil {
                client.connection.cancel()
                return
            }
            self.receive(client)
        }
    }
}
