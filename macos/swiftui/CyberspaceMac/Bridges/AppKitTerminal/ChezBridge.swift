/*
 * ChezBridge.swift - Chez Scheme backend for CyberspaceMac
 * Library of Cyberspace
 *
 * Implements SchemeBridge using the Chez Scheme C API. Called directly
 * from Swift via the ChezShim SPM target (no ObjC bridging header needed).
 *
 * Boot file resolution order:
 *   1. RESOURCEPATH env var (set when running from a .app bundle)
 *   2. Homebrew Cellar path fallback (development / REPL panel)
 *
 * Cyberspace modules (vault, security, etc.) are imported only when
 * RESOURCEPATH is set and the lib/ directory exists. The REPL works
 * for base Chez evaluation without them.
 *
 * Copyright (c) 2026 Yoyodyne. See LICENSE.
 */

import Foundation
import ChezShim
import CyberspaceREPLUI

class ChezBridge: SchemeBridge {
    static let shared: ChezBridge = {
        let bridge = ChezBridge()
        _ = bridge.initialize()
        return bridge
    }()

    let name = "Chez"
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    let bundleIdentifier = "com.yoyodyne.cyberspace.chez"

    private var compiledEvalProc: ChezPtr = 0
    private var safeEvalProc: ChezPtr = 0
    private var isInitialized = false

    func initialize() -> Bool {
        if isInitialized { return true }
        Sscheme_init(nil)

        // Resolve boot file directory.
        // Priority: RESOURCEPATH env var → bundle with boot files present →
        //           CHEZ_LIB env var → Homebrew Cellar fallback.
        //
        // Bundle.main.resourcePath is non-nil for SPM executables (points to
        // the generated resources bundle) but doesn't contain boot files.
        // We must verify petite.boot exists before using any candidate path.
        let fm = FileManager.default
        let chezLib = ProcessInfo.processInfo.environment["CHEZ_LIB"]
            ?? "/opt/homebrew/Cellar/chezscheme/10.3.0/lib/csv10.3.0/tarm64osx"

        let bootDir: String
        if let rp = ProcessInfo.processInfo.environment["RESOURCEPATH"],
           fm.fileExists(atPath: "\(rp)/boot/petite.boot") {
            bootDir = rp
            setenv("RESOURCEPATH", rp, 1)
        } else if let rp = Bundle.main.resourcePath,
                  fm.fileExists(atPath: "\(rp)/boot/petite.boot") {
            bootDir = rp
            setenv("RESOURCEPATH", rp, 1)
        } else {
            bootDir = chezLib
        }

        Sregister_boot_file("\(bootDir)/petite.boot")
        Sregister_boot_file("\(bootDir)/scheme.boot")

        Sbuild_heap(nil, nil)

        // Load helper definitions into interaction environment
        guard evalRaw(initForms) else { return false }

        // Set version from bundle (replaces placeholder in initForms)
        evalRaw("(set! *cyberspace-version* \"\(version)\")")

        // Compile the eval-with-capture wrapper once and pin it.
        let wrapper = """
            (lambda (expr-str)
              (guard (outer-exn
                      [else (call-with-string-output-port
                              (lambda (p) (display "Error: " p)
                                (if (message-condition? outer-exn)
                                    (display (condition-message outer-exn) p)
                                    (display "evaluation failed" p))))])
                (let ([output-port (open-output-string)])
                  (let ([result (parameterize ([current-output-port output-port])
                                  (guard (exn
                                          [(and (who-condition? exn) (irritants-condition? exn))
                                           (call-with-string-output-port
                                             (lambda (p)
                                               (display "Error: " p)
                                               (when (who-condition? exn)
                                                 (display (condition-who exn) p)
                                                 (display ": " p))
                                               (let ([irr (condition-irritants exn)])
                                                 (display (if (pair? irr) (car irr) irr) p))))]
                                          [(message-condition? exn)
                                           (call-with-string-output-port
                                             (lambda (p)
                                               (display "Error: " p)
                                               (display (condition-message exn) p)))]
                                          [else
                                           (call-with-string-output-port
                                             (lambda (p) (display "Error: evaluation failed" p)))])
                                    (eval (read (open-string-input-port expr-str))
                                          (interaction-environment))))])
                    (let ([output (get-output-string output-port)])
                      (if (string=? output "")
                          (if (eq? result (void))
                              ""
                              (call-with-string-output-port
                                (lambda (p) (write result p))))
                          output))))))
            """

        let compileProc = lookup("compile")
        let readProc = lookup("read")
        let openStringInput = lookup("open-string-input-port")

        let wrapperStr = Sstring(wrapper)
        let wrapperPort = Scall1(openStringInput, wrapperStr)
        let wrapperSexp = Scall1(readProc, wrapperPort)
        compiledEvalProc = Scall1(compileProc, wrapperSexp)
        Slock_object(compiledEvalProc)  // Pin so GC cannot collect/relocate

        // Safe-eval: wraps eval in guard so module imports don't crash.
        let safeWrapper = """
            (lambda (expr-str)
              (guard (exn
                      [(message-condition? exn)
                       (call-with-string-output-port
                         (lambda (p) (display "Error: " p)
                           (display (condition-message exn) p)))]
                      [else "Error: unknown"])
                (let ([port (open-string-input-port expr-str)])
                  (let loop ([form (read port)])
                    (unless (eof-object? form)
                      (eval form (interaction-environment))
                      (loop (read port)))))
                #t))
            """
        let safeStr = Sstring(safeWrapper)
        let safePort = Scall1(openStringInput, safeStr)
        let safeSexp = Scall1(readProc, safePort)
        safeEvalProc = Scall1(compileProc, safeSexp)
        Slock_object(safeEvalProc)

        // Set up library paths and import Cyberspace modules only when
        // boot files came from the bundle (not from the Homebrew fallback).
        let hasBundle = bootDir != chezLib
        if hasBundle {
            _ = Scall1(safeEvalProc,
                        Sstring("(library-directories '((\"\(bootDir)/lib\" . \"\(bootDir)/lib\")))"))

            let modules = [
                "(import (cyberspace vault))",
                "(import (cyberspace security))",
                "(import (cyberspace server))",
                "(import (cyberspace auto-enroll))",
            ]
            for mod in modules {
                let result = Scall1(safeEvalProc, Sstring(mod))
                if chez_is_string(result) != 0 {
                    break
                }
            }
        }

        isInitialized = true
        return true
    }

    func evaluate(_ expr: String) -> String? {
        guard compiledEvalProc != 0 else { return nil }

        let exprStr = Sstring(expr)
        let resultStr = Scall1(compiledEvalProc, exprStr)

        guard chez_is_string(resultStr) != 0 else {
            return "Error: evaluation returned non-string result"
        }

        let len = Int(chez_string_length(resultStr))
        guard len > 0 else { return "" }

        var scalars = [Unicode.Scalar]()
        scalars.reserveCapacity(len)
        for i in 0..<len {
            let cp = UInt32(chez_string_ref(resultStr, ChezIptr(i)))
            if let s = Unicode.Scalar(cp) {
                scalars.append(s)
            }
        }
        return String(String.UnicodeScalarView(scalars))
    }

    @discardableResult
    func evaluateRaw(_ expr: String) -> Bool {
        return evalRaw(expr)
    }

    func cleanup() {
        guard isInitialized else { return }
        if compiledEvalProc != 0 {
            Sunlock_object(compiledEvalProc)
            compiledEvalProc = 0
        }
        if safeEvalProc != 0 {
            Sunlock_object(safeEvalProc)
            safeEvalProc = 0
        }
        Sscheme_deinit()
        isInitialized = false
    }

    // MARK: - Private

    private func lookup(_ name: String) -> ChezPtr {
        return Stop_level_value(Sstring_to_symbol(name))
    }

    @discardableResult
    private func evalRaw(_ code: String) -> Bool {
        let readProc = lookup("read")
        let openStringInput = lookup("open-string-input-port")
        let evalProc = lookup("eval")
        let interactionEnv = lookup("interaction-environment")

        let codeStr = Sstring(code)
        let port = Scall1(openStringInput, codeStr)

        var form = Scall1(readProc, port)
        while form != chez_eof_object() {
            let env = Scall0(interactionEnv)
            Scall2(evalProc, form, env)
            form = Scall1(readProc, port)
        }

        return true
    }

    // Chez-specific init forms: guard (not handle-exceptions), printf (not format),
    // get-line (not read-line), div (not quotient), .sls (not .scm).
    let initForms: String = """
        (begin

        (define (discover-modules lib-path)
          (if (file-directory? lib-path)
              (sort string<?
                (let loop ((files (directory-list lib-path)) (acc '()))
                  (if (null? files) acc
                      (let* ((f (car files))
                             (len (string-length f)))
                        (loop (cdr files)
                              (if (and (> len 4)
                                       (string=? ".sls" (substring f (- len 4) len)))
                                  (cons (substring f 0 (- len 4)) acc)
                                  acc))))))
              '()))

        (define (cs-string-trim-both s)
          (let* ((len (string-length s))
                 (start (let loop ((i 0))
                          (if (or (= i len) (not (char-whitespace? (string-ref s i))))
                              i (loop (+ i 1)))))
                 (end (let loop ((i (- len 1)))
                        (if (or (< i start) (not (char-whitespace? (string-ref s i))))
                            (+ i 1) (loop (- i 1))))))
            (substring s start end)))

        (define (cs-string-contains str substr)
          (let ((slen (string-length str))
                (sslen (string-length substr)))
            (let loop ((i 0))
              (cond ((> (+ i sslen) slen) #f)
                    ((string=? (substring str i (+ i sslen)) substr) i)
                    (else (loop (+ i 1)))))))

        (define (analyze-source src-file)
          (if (not (file-exists? src-file))
              '((loc . 0) (lambdas . 0) (loc/lambda . 0))
              (call-with-input-file src-file
                (lambda (port)
                  (let loop ((loc 0) (lambdas 0))
                    (let ((line (get-line port)))
                      (if (eof-object? line)
                          (let ((ratio (if (> lambdas 0) (div loc lambdas) 0)))
                            `((loc . ,loc) (lambdas . ,lambdas) (loc/lambda . ,ratio)))
                          (let* ((trimmed (cs-string-trim-both line))
                                 (is-blank (string=? trimmed ""))
                                 (is-comment (and (> (string-length trimmed) 0)
                                                  (char=? (string-ref trimmed 0) #\\;)))
                                 (has-define (cs-string-contains line "(define "))
                                 (has-lambda (cs-string-contains line "(lambda ")))
                            (loop (if (or is-blank is-comment) loc (+ loc 1))
                                  (+ lambdas
                                     (if has-define 1 0)
                                     (if has-lambda 1 0)))))))))))

        (define (sicp)
          (guard (exn [else (display "Error in sicp: ")
                            (display exn)
                            (newline)
                            (flush-output-port (current-output-port))])
            (let* ((resources (getenv "RESOURCEPATH"))
                   (lib-path (if resources
                                 (string-append resources "/lib/cyberspace/")
                                 (or (let ((home (getenv "CYBERSPACE_HOME")))
                                       (and home (string-append home "/chez/cyberspace/")))
                                     "/Users/ddp/cyberspace/spki/scheme/chez/cyberspace/")))
                   (modules (discover-modules lib-path)))
            (printf "~%SICP Metrics - Cyberspace Chez (~a modules)~%~%" (length modules))
            (let loop ((modules modules)
                       (total-loc 0)
                       (total-lambdas 0)
                       (count 0))
              (if (null? modules)
                  (begin
                    (printf "~%  \\x03A3; ~a LOC \\x00B7; ~a \\x03BB; \\x00B7; ~a LOC/\\x03BB;~%~%"
                            total-loc total-lambdas
                            (if (> total-lambdas 0) (div total-loc total-lambdas) 0))
                    (flush-output-port (current-output-port)))
                  (let* ((mod (car modules))
                         (src (string-append lib-path mod ".sls"))
                         (metrics (analyze-source src))
                         (loc (cdr (assq 'loc metrics)))
                         (lambdas (cdr (assq 'lambdas metrics)))
                         (ratio (cdr (assq 'loc/lambda metrics))))
                    (when (> loc 0)
                      (let ((padded (string-append mod
                                      (make-string (max 0 (- 15 (string-length mod))) #\\space))))
                        (printf "  ~a: ~a LOC \\x00B7; ~a \\x03BB; \\x00B7; ~a LOC/\\x03BB;~%"
                                padded loc lambdas ratio)))
                    (loop (cdr modules)
                          (+ total-loc loc)
                          (+ total-lambdas lambdas)
                          (if (> loc 0) (+ count 1) count))))))))

        (define (help)
          (guard (exn [else (display "Error in help: ")
                            (display exn)
                            (newline)
                            (flush-output-port (current-output-port))])
            (display "Available commands:\\n\\n")
            (flush-output-port (current-output-port))
            (display "Core:\\n")
            (display "  (sicp)           - Analyze SICP metrics for all modules\\n")
            (display "  (help)           - This message\\n")
            (display "  (version)        - Show version info\\n\\n")
            (flush-output-port (current-output-port))
            (display "Vault:\\n")
            (display "  (vault-status)   - Show vault status\\n")
            (display "  (vault-path)     - Show vault path\\n")
            (display "  (catalog)        - List vault contents\\n\\n")
            (flush-output-port (current-output-port))
            (display "Crypto:\\n")
            (display "  (keygen)         - Generate key pair\\n")
            (display "  (sign data)      - Sign data\\n")
            (display "  (verify sig)     - Verify signature\\n\\n")
            (flush-output-port (current-output-port))
            (display "SPKI:\\n")
            (display "  (make-cert ...)  - Create certificate\\n")
            (display "  (verify-cert c)  - Verify certificate\\n")
            (flush-output-port (current-output-port))
            (void)))

        (define *cyberspace-version* "unknown")

        (define (version)
          (printf "Library of Cyberspace v~a\\n" *cyberspace-version*)
          (display "Chez Scheme REPL\\n"))

        (define (sicp-string)
          (call-with-string-output-port
            (lambda (p) (parameterize ((current-output-port p)) (sicp)))))

        (define (novice) (display "Switched to novice mode\\n"))
        (define (schemer) (display "Switched to schemer mode\\n"))

        (define (module-summary)
          (guard (exn [else (display "Error: ") (display exn) (newline)])
            (let* ((resources (getenv "RESOURCEPATH"))
                   (lib-path (if resources
                                 (string-append resources "/lib/cyberspace/")
                                 (or (let ((home (getenv "CYBERSPACE_HOME")))
                                       (and home (string-append home "/chez/cyberspace/")))
                                     "/Users/ddp/cyberspace/spki/scheme/chez/cyberspace/")))
                   (modules (discover-modules lib-path)))
              (let loop ((mods modules)
                         (total-loc 0)
                         (total-lambdas 0))
                (if (null? mods)
                    (begin
                      (printf "Total: ~a modules, ~a LOC, ~a lambdas, ~a LOC/lambda\\n"
                              (length modules)
                              total-loc total-lambdas
                              (if (> total-lambdas 0) (div total-loc total-lambdas) 0))
                      (void))
                    (let* ((mod (car mods))
                           (src (string-append lib-path mod ".sls"))
                           (metrics (analyze-source src))
                           (loc (cdr (assq 'loc metrics)))
                           (lambdas (cdr (assq 'lambdas metrics))))
                      (loop (cdr mods)
                            (+ total-loc loc)
                            (+ total-lambdas lambdas))))))))

        )
        """
}
