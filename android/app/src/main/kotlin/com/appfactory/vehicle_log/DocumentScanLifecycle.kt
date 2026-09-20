package com.appfactory.vehicle_log

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Guards the pinned scanner plugin, which dereferences a lost pending result
 * when Android returns from a scan after recreating the app process. */
internal class DocumentScanLifecycle : MethodChannel.MethodCallHandler {
    private var pending = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "begin" -> {
                if (pending) {
                    result.error("scanner_busy", "Ein Scan läuft bereits.", null)
                } else {
                    pending = true
                    result.success(null)
                }
            }
            "finish" -> {
                pending = false
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun consumeResult(): Boolean {
        val deliver = pending
        pending = false
        return deliver
    }

    companion object {
        const val CHANNEL = "com.appfactory.vehicle_log/document_scan_lifecycle"
        // google_mlkit_document_scanner 0.4.1 DocumentScanner.java.
        const val REQUEST_CODE = 0x362738
    }
}
