package com.appfactory.vehicle_log

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.*
import org.junit.Test

class DocumentScanLifecycleTest {
    @Test fun recreatedProcessIgnoresOrphanAndDuplicateResults() {
        val oldProcess = DocumentScanLifecycle()
        oldProcess.onMethodCall(MethodCall("begin", null), Result())
        val recreated = DocumentScanLifecycle()
        assertFalse(recreated.consumeResult())
        recreated.onMethodCall(MethodCall("begin", null), Result())
        assertTrue(recreated.consumeResult())
        assertFalse(recreated.consumeResult())
    }

    @Test fun failedLaunchReleasesGuardAndAllowsRetry() {
        val lifecycle = DocumentScanLifecycle()
        lifecycle.onMethodCall(MethodCall("begin", null), Result())
        lifecycle.onMethodCall(MethodCall("finish", null), Result())
        assertFalse(lifecycle.consumeResult())
        val retry = Result()
        lifecycle.onMethodCall(MethodCall("begin", null), retry)
        assertTrue(retry.succeeded)
        assertTrue(lifecycle.consumeResult())
    }

    @Test fun concurrentScanCannotReplaceThePendingCaller() {
        val lifecycle = DocumentScanLifecycle()
        lifecycle.onMethodCall(MethodCall("begin", null), Result())
        val duplicate = Result()
        lifecycle.onMethodCall(MethodCall("begin", null), duplicate)
        assertEquals("scanner_busy", duplicate.errorCode)
        assertTrue(lifecycle.consumeResult())
    }

    private class Result : MethodChannel.Result {
        var succeeded = false
        var errorCode: String? = null
        override fun success(result: Any?) { succeeded = true }
        override fun error(code: String, message: String?, details: Any?) { errorCode = code }
        override fun notImplemented() { fail("Unexpected lifecycle call") }
    }
}
