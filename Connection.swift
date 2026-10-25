import SwiftUI
import Security

struct Credentials: Codable { let url: String; let token: String }
enum KeyStore {
    static let service = "nl.wiegerz.machine.remote.localv3"
    static func load() -> Credentials? {
        let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service,
                               kSecAttrAccount as String:"controller", kSecReturnData as String:true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from:data)
    }
    static func save(_ value: Credentials) throws {
        let data = try JSONEncoder().encode(value)
        let q: [String: Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"controller"]
        SecItemDelete(q as CFDictionary)
        var add=q; add[kSecValueData as String]=data
        add[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(add as CFDictionary,nil)==errSecSuccess else { throw RemoteError.message("Opslaan in Keychain mislukt") }
    }
    static func clear() {
        SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"controller"] as CFDictionary)
    }
}
enum RemoteError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s)=self { return s }; return nil }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor final class Connection: ObservableObject {
    @Published var credentials = KeyStore.load()
    @Published var data: [String: Any] = [:]
    @Published var online=false
    @Published var message="Verbind met je machine"
    @Published var receipt=""
    @Published var sending=false
    @Published var active=false
    @Published var lastUpdate: Date?
    private var receiptID: Int?
    private var latestCommandSequence: Int64 = 0
    private var generation=0
    private var task: Task<Void,Never>?
    private let delegate=NoRedirect()
    private lazy var session: URLSession = {
        let c=URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest=5; c.timeoutIntervalForResource=7
        c.urlCache=nil; c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration:c,delegate:delegate,delegateQueue:nil)
    }()
    var connected: Bool { credentials != nil }
    func number(_ key:String) -> Int { (data[key] as? NSNumber)?.intValue ?? 0 }
    func flag(_ key:String) -> Bool { number(key) != 0 }
    func text(_ key:String) -> String { data[key] as? String ?? "—" }
    private func request(_ body:[String:Any], credentials override:Credentials?=nil) async throws -> [String:Any] {
        guard let c=override ?? credentials, let url=URL(string:c.url), url.scheme=="http", url.host=="192.168.4.1",
              url.user==nil, url.password==nil, url.query==nil, url.fragment==nil, url.path=="/api" else {
            throw RemoteError.message("Verbind met MachineRemote-ESP8266 en gebruik http://192.168.4.1/api")
        }
        var req=URLRequest(url:url); req.httpMethod="POST"
        req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        req.httpBody=try JSONSerialization.data(withJSONObject:body)
        let (bytes,response)=try await session.data(for:req)
        guard bytes.count<32768, let http=response as? HTTPURLResponse else { throw RemoteError.message("Ongeldig serverantwoord") }
        let json=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any] ?? [:]
        guard http.statusCode==200 else { throw RemoteError.message(json["error"] as? String ?? "Serverfout \(http.statusCode)") }
        return json
    }
    func connect(url:String) async {
        do {
            let clean=url.trimmingCharacters(in:.whitespacesAndNewlines)
            let c=Credentials(url:clean,token:"")
            try KeyStore.save(c)
            credentials=c
            message="Adres opgeslagen. Verbind met machine-wifi."
            resume()
            await refresh()
        } catch { message=error.localizedDescription }
    }
    func resume() {
        guard connected else { return }; active=true
        guard task==nil else { return }
        task=Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                do { try await Task.sleep(nanoseconds:1_000_000_000) } catch { break }
            }
        }
    }
    func refresh() async {
        guard active,connected else { return }
        let gen=generation
        do {
            var body:[String:Any]=["op":"status","active":true]
            if let receiptID { body["receipt"]=receiptID }
            let r=try await request(body)
            guard active,gen==generation,!Task.isCancelled else { return }
            online=r["online"] as? Bool ?? false
            data=r["status"] as? [String:Any] ?? [:]; lastUpdate=Date()
            message=online ? "Rechtstreeks via machine-wifi" : "Machine offline — bediening geblokkeerd"
            if let rec=r["receipt"] as? [String:Any], let state=rec["state"] as? String {
                switch state {
                case "acknowledged": receipt="Bevestigd: \(rec["result"] as? String ?? "ontvangen")"
                case "delivered": receipt="Afgeleverd — wacht op bevestiging van de machine"
                case "expired": receipt="Opdracht verlopen; niet opnieuw verstuurd"
                case "cancelled": receipt="Opdracht geannuleerd"
                default: receipt="Opdracht onderweg"
                }
            }
        } catch {
            guard active,gen==generation else { return }
            online=false; message="Verbinding verbroken: \(error.localizedDescription)"
        }
    }
    func send(_ value:String) async {
        guard active,connected,(online || value=="stop"),(!sending || value=="stop") else { return }
        let seq=max(Int64(Date().timeIntervalSince1970 * 1000),Int64(UserDefaults.standard.double(forKey:"commandSequence"))+1)
        UserDefaults.standard.set(Double(seq),forKey:"commandSequence")
        latestCommandSequence=seq
        sending=true; defer { if latestCommandSequence==seq { sending=false } }
        do {
            let r=try await request(["op":"command","value":value,"sequence":seq])
            guard latestCommandSequence==seq else { return }
            receiptID=r["id"] as? Int
            receipt="Opdracht onderweg — nog niet bevestigd"
        } catch { guard latestCommandSequence==seq else { return }; receipt="Niet bevestigd: \(error.localizedDescription). Geen automatische herhaling." }
    }
    func suspend() {
        guard active else { return }
        active=false; online=false; generation+=1
        task?.cancel(); task=nil
        // Best effort only. Device-side lease handles app suspension/termination.
        let saved=credentials
        Task { _ = try? await request(["op":"status","active":false],credentials:saved) }
    }
    func disconnect() async {
        suspend()
        KeyStore.clear(); credentials=nil; data=[:]; receipt=""; receiptID=nil
        message="Verbinding verwijderd. Vul opnieuw alleen het API-adres in."
    }
}
