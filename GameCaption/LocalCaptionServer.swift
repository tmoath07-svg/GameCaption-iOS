import Foundation
import Network
import Darwin

/// Serves only the current translated caption to browsers on the same Wi-Fi.
/// No external services, credentials, or reference-app resources are used.
final class LocalCaptionServer: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var urlString = ""
    var subtitle = ""
    private var listener: NWListener?
    private var active: [NWConnection] = []
    private var accessKey = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private let port: UInt16 = 8877

    func start() {
        guard listener == nil else { return }
        errorMessage = nil
        subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        accessKey = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            errorMessage = "رقم منفذ غير صالح."
            return
        }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: nwPort)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.running = true
                    let address = Self.wifiAddress() ?? "IPHONE_WIFI_IP"
                    self.urlString = "http://\(address):\(self.port)/?key=\(self.accessKey)"
                    if address == "IPHONE_WIFI_IP" {
                        self.errorMessage = "ما حصلنا IP الواي فاي. شبّك الآيفون على Wi-Fi وابدأ المشاركة من جديد."
                    }
                case .failed(let error):
                    self.errorMessage = "فشل تشغيل مشاركة الشاشة: \(error.localizedDescription)"
                    self.stop()
                case .cancelled: self.running = false
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.start(queue: .main)
        } catch {
            errorMessage = "ما قدرنا نفتح المنفذ المحلي: \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for connection in active { connection.cancel() }
        active.removeAll()
        running = false
        urlString = ""
    }

    private func accept(_ connection: NWConnection) {
        active.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .cancelled = state, let connection {
                self?.active.removeAll { $0 === connection }
            }
        }
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self, weak connection] data, _, _, error in
            guard let self, let connection else { return }
            guard error == nil, let data,
                  let request = String(data: data, encoding: .utf8),
                  let requestLine = request.components(separatedBy: "\r\n").first else {
                self.respond(connection, code: "400 Bad Request", type: "text/plain", body: Data("Bad Request".utf8))
                return
            }
            let fields = requestLine.split(separator: " ")
            guard fields.count >= 2, fields[0] == "GET" else {
                self.respond(connection, code: "405 Method Not Allowed", type: "text/plain", body: Data("Method Not Allowed".utf8))
                return
            }
            let path = String(fields[1])
            guard let components = URLComponents(string: "http://localhost" + path),
                  components.queryItems?.first(where: { $0.name == "key" })?.value == self.accessKey else {
                self.respond(connection, code: "403 Forbidden", type: "text/plain", body: Data("Forbidden".utf8))
                return
            }
            if components.path == "/caption" {
                let data = (try? JSONSerialization.data(withJSONObject: ["subtitle": self.subtitle], options: [])) ?? Data("{}".utf8)
                self.respond(connection, code: "200 OK", type: "application/json; charset=utf-8", body: data)
            } else if components.path == "/" {
                self.respond(connection, code: "200 OK", type: "text/html; charset=utf-8", body: Data(Self.captionHTML.utf8))
            } else {
                self.respond(connection, code: "404 Not Found", type: "text/plain", body: Data("Not Found".utf8))
            }
        }
    }

    private func respond(_ connection: NWConnection, code: String, type: String, body: Data) {
        let header = "HTTP/1.1 \(code)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
        var packet = Data(header.utf8)
        packet.append(body)
        connection.send(content: packet, completion: .contentProcessed { [weak connection] _ in connection?.cancel() })
    }

    private static func wifiAddress() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let start = addresses else { return nil }
        defer { freeifaddrs(start) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = start
        while let current = pointer {
            let interface = current.pointee
            if String(cString: interface.ifa_name) == "en0",
               let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &hostname,
                               socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: hostname)
                }
            }
            pointer = interface.ifa_next
        }
        return nil
    }

    private static let captionHTML = """
    <!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>GameCaption TV</title><style>
    html,body{height:100%;margin:0;background:#071020;color:white;font-family:system-ui,-apple-system,sans-serif}
    main{height:100%;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;box-sizing:border-box;padding:6vw}
    #caption{max-width:94%;font-size:clamp(26px,5vw,68px);line-height:1.35;text-align:center;font-weight:800;
    text-shadow:0 3px 9px #000;background:#000a;border-radius:18px;padding:14px 26px;white-space:pre-wrap;overflow-wrap:anywhere}
    #hint{position:fixed;top:16px;left:18px;opacity:.5;font-size:12px}
    </style></head><body><div id="hint">GAMECAPTION • LAN</div>
    <main><div id="caption" role="status" aria-live="polite">بانتظار الترجمة...</div></main>
    <script>
    const key = new URL(location.href).searchParams.get('key') || '';
    async function update(){try{const res=await fetch('/caption?key='+encodeURIComponent(key),{cache:'no-store'});
    if(res.ok){const obj=await res.json();document.getElementById('caption').textContent=obj.subtitle||'بانتظار الترجمة...';}}
    catch(e){document.getElementById('caption').textContent='تأكد أن التطبيق مفتوح والآيفون متصل بنفس الشبكة';}}
    setInterval(update,1100); update();
    </script></body></html>
    """
}
