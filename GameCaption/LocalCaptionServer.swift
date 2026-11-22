import Foundation
import Combine
import Network
import Darwin

/// Shares the current caption with local browsers while GameCaption is in the foreground.
final class LocalCaptionServer: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var urlString = ""
    var subtitle = ""
    var overlayURLString: String { urlString.isEmpty ? "" : urlString + "&view=overlay" }

    private var listener: NWListener?
    private var active: [NWConnection] = []
    private var accessKey = ""
    private let port: NWEndpoint.Port
    private let interfaceAddress: () -> String?

    init(port: NWEndpoint.Port = 8877, interfaceAddress: (() -> String?)? = nil) {
        self.port = port
        self.interfaceAddress = interfaceAddress ?? Self.wifiAddress
    }

    func start() {
        guard listener == nil else { return }
        errorMessage = nil
        guard let address = interfaceAddress() else {
            errorMessage = "شبّك الآيفون على Wi-Fi ثم ابدأ المشاركة مجددًا."
            return
        }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: port)
            self.listener = listener
            accessKey = UUID().uuidString
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener, self.listener === listener else { return }
                switch state {
                case .ready:
                    guard let boundPort = listener.port else { return }
                    self.urlString = "http://\(address):\(boundPort.rawValue)/?key=\(self.accessKey)"
                    self.errorMessage = nil
                    self.running = true
                case .waiting(let error):
                    self.errorMessage = "تحقق من إذن الشبكة المحلية في الإعدادات. \(error.localizedDescription)"
                case .failed(let error):
                    self.errorMessage = "تعذر بدء المشاركة: \(error.localizedDescription)"
                    self.stop()
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self, weak listener] connection in
                guard let self, let listener, self.listener === listener else {
                    connection.cancel()
                    return
                }
                self.accept(connection)
            }
            listener.start(queue: .main)
        } catch {
            errorMessage = "تعذر فتح المنفذ المحلي: \(error.localizedDescription)"
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
        guard active.count < 12 else { connection.cancel(); return }
        active.append(connection)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            switch state {
            case .failed, .cancelled:
                connection.cancel()
                self?.active.removeAll { $0 === connection }
            default: break
            }
        }
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak connection] in
            connection?.cancel()
        }
        receive(connection, buffered: Data())
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - buffered.count) {
            [weak self, weak connection] data, _, finished, error in
            guard let self, let connection else { return }
            guard error == nil else { connection.cancel(); return }
            var request = buffered
            if let data { request.append(data) }
            if let line = request.range(of: Data("\r\n".utf8)) {
                self.route(connection, line: String(decoding: request[..<line.lowerBound], as: UTF8.self))
            } else if request.count >= 8192 || finished {
                self.respond(connection, "400 Bad Request")
            } else {
                self.receive(connection, buffered: request)
            }
        }
    }

    private func route(_ connection: NWConnection, line: String) {
        let fields = line.split(separator: " ")
        guard fields.count == 3, fields[1].hasPrefix("/") else {
            respond(connection, "400 Bad Request")
            return
        }
        guard fields[0] == "GET" else { respond(connection, "405 Method Not Allowed"); return }
        guard let parts = URLComponents(string: "http://localhost" + fields[1]),
              parts.queryItems?.first(where: { $0.name == "key" })?.value == accessKey else {
            respond(connection, "403 Forbidden")
            return
        }
        switch parts.path {
        case "/caption":
            let data = (try? JSONSerialization.data(withJSONObject: ["subtitle": subtitle])) ?? Data("{}".utf8)
            respond(connection, "200 OK", type: "application/json; charset=utf-8", body: data)
        case "/":
            respond(connection, "200 OK", type: "text/html; charset=utf-8", body: Data(Self.captionHTML.utf8))
        default:
            respond(connection, "404 Not Found")
        }
    }

    private func respond(_ connection: NWConnection, _ status: String,
                         type: String = "text/plain; charset=utf-8", body: Data = Data()) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
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
    <title>GameCaption</title><style>
    html,body{height:100%;margin:0;color:white;font-family:system-ui,sans-serif}
    body{background:#071020} body.overlay{background:transparent}
    main{height:100%;display:flex;align-items:flex-end;justify-content:center;box-sizing:border-box;padding:3vh 4vw}
    #caption{max-width:94%;font-size:5vw;font-size:clamp(24px,4vw,64px);line-height:1.35;text-align:center;
    font-weight:750;text-shadow:0 2px 6px #000;background:rgba(0,0,0,.75);border-radius:12px;padding:10px 24px;
    white-space:pre-wrap;overflow-wrap:break-word}
    #caption:empty{display:none}
    </style></head><body>
    <main><div id="caption" dir="auto" role="status" aria-live="polite"></div></main>
    <script>
    (function () {
      var key = /(?:[?&])key=([A-Za-z0-9-]+)/.exec(location.search);
      var overlay = /(?:[?&])view=overlay(?:&|$)/.test(location.search);
      var caption = document.getElementById('caption');
      if (overlay) document.body.className = 'overlay';
      function display(text) {
        if (caption.textContent !== text) caption.textContent = text;
      }
      function disconnected() {
        display(overlay ? '' : 'أبقِ GameCaption مفتوحًا وتحقق من اتصال الشبكة.');
      }
      function update() {
        var request = new XMLHttpRequest();
        request.open('GET', '/caption?key=' + (key ? key[1] : ''), true);
        request.timeout = 2500;
        request.onload = function () {
          try {
            if (request.status !== 200) { disconnected(); return; }
            var text = JSON.parse(request.responseText).subtitle;
            display(text || (overlay ? '' : 'بانتظار الترجمة...'));
          } catch (error) { disconnected(); }
        };
        request.onerror = disconnected;
        request.ontimeout = disconnected;
        request.onloadend = function () { setTimeout(update, 400); };
        request.send();
      }
      display(overlay ? '' : 'بانتظار الترجمة...');
      update();
    }());
    </script></body></html>
    """
}
