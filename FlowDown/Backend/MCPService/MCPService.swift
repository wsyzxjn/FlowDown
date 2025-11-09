//
//  MCPService.swift
//  FlowDown
//
//  Created by LiBr on 6/29/25.
//

import Combine
import Foundation
import MCP
import Storage

class MCPService: NSObject {
    static let shared = MCPService()
    static let executor = MCPServiceActor.shared

    // MARK: - Properties

    let servers: CurrentValueSubject<[ModelContextServer], Never> = .init([])
    private(set) var connections: [ModelContextServer.ID: MCPConnection] = [:]
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    override private init() {
        super.init()
        for server in sdb.modelContextServerList() {
            updateServerStatus(server.id, status: .disconnected)
        }
        updateFromDatabase()
        setupServerSync()

        NotificationCenter.default.publisher(for: SyncEngine.ModelContextServerChanged)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                logger.infoFile("Recived SyncEngine.ModelContextServerChanged")
                self?.updateFromDatabase()
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func setupServerSync() {
        servers
            .map { $0.filter(\.isEnabled) }
            .removeDuplicates()
            .ensureMainThread()
            .sink { [weak self] enabledServers in
                guard let self else { return }
                Task {
                    await MCPService.executor.run {
                        await self.syncServerConnections(enabledServers)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    @discardableResult
    func prepareForConversation() async -> [Swift.Error] {
        var errors: [Swift.Error] = []
        let snapshot = connections // for thread safety
        for (serverID, connection) in snapshot {
            guard let server = server(with: serverID), server.isEnabled else { continue }
            if connection.isConnected { continue }
            do {
                try await MCPService.executor.run {
                    try await connection.connect()
                }
            } catch {
                Logger.network.errorFile("failed to connect to server \(serverID): \(error.localizedDescription)")
                errors.append(error)
            }
        }
        return errors
    }

    func insert(_ server: ModelContextServer) {
        sdb.modelContextServerPut(object: server)
        updateFromDatabase()
    }

    func ensureOrReconnect(_ serverID: ModelContextServer.ID) {
        if let connection = connections[serverID], connection.client != nil { return }
        guard let server = sdb.modelContextServerWith(serverID) else { return }
        updateServerStatus(serverID, status: .disconnected)
        Task {
            await MCPService.executor.run {
                await self.connectToServer(server)
            }
        }
    }

    func testConnection(
        serverID: ModelContextServer.ID,
        completion: @escaping (Result<String, Swift.Error>) -> Void
    ) {
        Task {
            await MCPService.executor.run {
                do {
                    guard let server = self.server(with: serverID) else {
                        throw MCPError.invalidConfiguration
                    }
                    self.connections[serverID]?.disconnect()
                    self.connections.removeValue(forKey: serverID)
                    self.updateServerStatus(serverID, status: .disconnected)
                    let connection: MCPConnection = try await self.connectOnce(server)
                    if server.isEnabled { self.connections[serverID] = connection }
                    guard let client = connection.client else {
                        assertionFailure()
                        throw MCPError.connectionFailed
                    }
                    await self.negotiateCapabilities(client: client, config: server)
                    let tools = try await client.listTools().tools
                    let toolSummary = tools.map { tool in
                        if let toolServer = self.server(with: serverID) {
                            return "\(toolServer.displayName): \(tool.name)"
                        }
                        return tool.name
                    }.joined(separator: ", ")
                    completion(.success(toolSummary))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Private Connection Management

    private func syncServerConnections(_ eligibleServers: [ModelContextServer]) async {
        for server in eligibleServers {
            ensureOrReconnect(server.id)
        }

        let eligibleServerIds = Set(eligibleServers.map(\.id))
        for (serverId, connection) in connections {
            if !eligibleServerIds.contains(serverId) {
                connection.disconnect()
                connections.removeValue(forKey: serverId)
                updateServerStatus(serverId, status: .disconnected)
            }
        }
    }

    private func connectToServer(_ config: ModelContextServer) async {
        updateServerStatus(config.id, status: .connecting)

        do {
            let connection = try await MCPService.executor.run {
                try await self.connectOnce(config)
            }
            connections[config.id] = connection
        } catch {
            Logger.network.errorFile("failed to connect to server \(config.id): \(error.localizedDescription)")
            updateServerStatus(config.id, status: .disconnected)
        }
    }

    private func connectOnce(_ config: ModelContextServer) async throws -> MCPConnection {
        let connection = MCPConnection(config: config)
        try await connection.connect()
        if let client = connection.client {
            await negotiateCapabilities(client: client, config: config)
        } else {
            assertionFailure("failed to establish client connection")
        }
        updateServerStatus(config.id, status: .connected)
        return connection
    }

    private func updateServerStatus(_ serverId: ModelContextServer.ID, status: ModelContextServer.ConnectionStatus) {
        // 连接状态不进行同步
        edit(identifier: serverId, skipSync: true) {
            $0.update(\.connectionStatus, to: status)
            if status == .connected {
                $0.update(\.lastConnected, to: .now)
            }
        }
    }

    private func negotiateCapabilities(client: MCP.Client, config: ModelContextServer) async {
        var discoveredCapabilities: [String] = []

        do {
            let (tools, _) = try await client.listTools()
            if !tools.isEmpty {
                discoveredCapabilities.append("tools")
            }
        } catch {
            Logger.network.errorFile("failed to list tools: \(error.localizedDescription)")
        }

        // capabilities不进行同步
        edit(identifier: config.id, skipSync: true) {
            $0.assign(\.capabilities, to: StringArrayCodable(discoveredCapabilities))
        }
    }

    func listServerTools() async -> [MCPTool] {
        let toolInfos = await getAllTools()
        return toolInfos.map { MCPTool(toolInfo: $0, mcpService: self) }
    }

    // MARK: - Database Methods

    func updateFromDatabase() {
        servers.send(sdb.modelContextServerList())
    }

    func create(block: Storage.ModelContextServerMakeInitDataBlock? = nil) -> ModelContextServer {
        defer { updateFromDatabase() }
        return sdb.modelContextServerMake(block)
    }

    func server(with identifier: ModelContextServer.ID?) -> ModelContextServer? {
        guard let identifier else { return nil }
        return sdb.modelContextServerWith(identifier)
    }

    func remove(_ identifier: ModelContextServer.ID) {
        defer { updateFromDatabase() }
        sdb.modelContextServerRemove(identifier: identifier)
    }

    func edit(identifier: ModelContextServer.ID, skipSync: Bool = false, block: @escaping (inout ModelContextServer) -> Void) {
        defer { updateFromDatabase() }
        sdb.modelContextServerEdit(identifier: identifier, skipSync: skipSync, block)
    }
}
