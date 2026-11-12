import Foundation
import PortalKit

/// DemoBrowser opens the built-in browser on an invented page, for screenshots.
@MainActor
enum DemoBrowser {
    static func show(in model: AppModel, account: Account) {
        let session = model.webSession(for: account)
        session.loadHTML(
            """
            <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
            <title>controller1</title>
            <style>
            body { font-family: -apple-system, sans-serif; margin: 0; background: #f2f2f7; color: #1c1c1e; }
            header { background: #1d3c8a; color: white; padding: 18px 20px; font-size: 20px; font-weight: 600; }
            main { padding: 16px 20px; }
            .card { background: white; border-radius: 14px; padding: 14px 16px; margin-bottom: 12px; }
            .ok { color: #1a7f37; font-weight: 600; }
            @media (prefers-color-scheme: dark) { body { background: #000; color: #f2f2f7; } .card { background: #1c1c1e; } .ok { color: #3fb950; } }
            </style></head><body>
            <header>controller1</header>
            <main>
            <div class="card"><div>Planner</div><div class="ok">Running</div></div>
            <div class="card"><div>Robot bridge</div><div class="ok">Connected</div></div>
            <div class="card"><div>Last pick</div><div>2 minutes ago</div></div>
            </main></body></html>
            """)
        model.presentedWeb = session
    }

    /// The page a demo web app opens on, after the browser has been presented on its address.
    static func showApp(named name: String, in model: AppModel, account: Account) {
        model.webSession(for: account).loadHTML(
            """
            <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(name)</title>
            <style>
            body { font-family: -apple-system, sans-serif; margin: 0; background: #f2f2f7; color: #1c1c1e; }
            header { background: #1d3c8a; color: white; padding: 18px 20px; font-size: 20px; font-weight: 600; }
            main { padding: 16px 20px; }
            .card { background: white; border-radius: 14px; padding: 14px 16px; margin-bottom: 12px; }
            @media (prefers-color-scheme: dark) { body { background: #000; color: #f2f2f7; } .card { background: #1c1c1e; } }
            </style></head><body>
            <header>\(name)</header>
            <main><div class="card">This stands in for the app, opened on its own page.</div></main>
            </body></html>
            """)
    }
}
