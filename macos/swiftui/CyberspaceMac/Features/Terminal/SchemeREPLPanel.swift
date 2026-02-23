/*
 * SchemeREPLPanel.swift - Cyberspace Chez Scheme REPL panel
 *
 * Platforms-side seam: instantiates ChezBridge (the Chez Scheme C backend)
 * and hands it to CyberspaceREPLView from the CyberspaceREPLUI package.
 *
 * REPL UI implementation lives in cyber-nas-overlay (CyberspaceREPLUI).
 * Only bridge creation lives here.
 */

import SwiftUI
import CyberspaceREPLUI

struct SchemeREPLPanel: View {
    // Keep a process-wide bridge so tab switches do not reinitialize Chez.
    private let bridge = ChezBridge.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tip: if lambda mode is triggered, type `(novice)` to return to novice mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
            CyberspaceREPLView(bridge: bridge)
        }
    }
}
