package com.appfactory.vehicle_log

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class MeterReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ReminderNotifier.expireTestAction) {
            ReminderNotifier.expireTest(context, intent)
            return
        }
        val meterId = intent.getStringExtra("meter_id") ?: return
        if (ReminderStore.planningState(context, meterId) == "failed") return
        val reminder = ReminderStore.find(context, meterId) ?: return
        val nextTrigger = ReminderStore.nextTrigger(context, meterId)
        // A previously queued broadcast may arrive after an edit or delivery.
        if (nextTrigger != null && nextTrigger > System.currentTimeMillis()) return
        try {
            val postedAt = ReminderNotifier.showMeter(context, reminder)
            if (postedAt != null) {
                ReminderStore.setLastTriggered(context, meterId, postedAt)
                ReminderStore.setDeliveryFailed(context, meterId, false)
            } else if (ReminderNotifier.availability(context, reminder.isPunctual) == ReminderAvailability.UNKNOWN) {
                ReminderStore.setDeliveryFailed(context, meterId, true)
            }
        } catch (_: Exception) {
            ReminderStore.setDeliveryFailed(context, meterId, true)
        } finally {
            ReminderScheduler.scheduleNext(context, reminder)
            context.sendBroadcast(Intent(REMINDER_STATUS_CHANGED).setPackage(context.packageName))
        }
    }
}

class ReminderRescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ReminderScheduler.rescheduleAll(
            context,
            clockChanged = intent.action == Intent.ACTION_TIME_CHANGED ||
                intent.action == Intent.ACTION_TIMEZONE_CHANGED,
        )
        context.sendBroadcast(Intent(REMINDER_STATUS_CHANGED).setPackage(context.packageName))
    }
}
