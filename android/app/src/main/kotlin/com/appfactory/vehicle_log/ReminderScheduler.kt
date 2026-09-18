package com.appfactory.vehicle_log

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.media.AudioManager
import android.os.SystemClock
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat

internal object ReminderScheduler {
    private const val fireAction =
        "com.appfactory.vehicle_log.FIRE_METER_REMINDER"

    fun update(context: Context, reminder: StoredReminder): Boolean {
        val triggerAt = reminder.nextTriggerForUpdate(
            ReminderStore.find(context, reminder.meterId),
            ReminderStore.nextTrigger(context, reminder.meterId),
            System.currentTimeMillis(),
        )
        return scheduleAt(context, reminder, triggerAt)
    }

    fun scheduleNext(context: Context, reminder: StoredReminder): Boolean =
        scheduleAt(context, reminder, reminder.nextTriggerAfter(System.currentTimeMillis()))

    private fun scheduleAt(context: Context, reminder: StoredReminder, triggerAt: Long): Boolean {
        return try {
            val alarmManager = context.getSystemService(AlarmManager::class.java)
            val operation = requireNotNull(firePendingIntent(context, reminder.meterId, false))
            val exact = reminder.isPunctual && canScheduleExact(context)
            if (exact) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerAt,
                        operation,
                    )
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, operation)
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAt,
                    operation,
                )
            } else {
                alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, operation)
            }
            // Persist only after Android accepts the alarm. Reusing the PendingIntent
            // replaces its alarm without losing a due but delayed occurrence.
            ReminderStore.save(context, reminder, triggerAt, exact)
            true
        } catch (_: Exception) {
            // A queued old alarm must not deliver a new, unaccepted schedule.
            ReminderStore.planningFailed(context, reminder, triggerAt)
            false
        }
    }

    fun cancelPending(context: Context, meterId: String) {
        val operation = firePendingIntent(context, meterId, true) ?: return
        context.getSystemService(AlarmManager::class.java).cancel(operation)
        operation.cancel()
    }

    fun cancel(context: Context, meterId: String): Boolean {
        ReminderStore.remove(context, meterId)
        return try {
            cancelPending(context, meterId)
            ReminderNotifier.acknowledge(context, meterId)
            true
        } catch (_: Exception) {
            ReminderStore.cancelFailed(context, meterId)
            false
        }
    }

    fun status(context: Context, meterId: String, activeIds: Set<String> = ReminderNotifier.activeMeterIds(context)): Map<String, Any?> = mapOf(
        "meterId" to meterId,
        "isNotificationActive" to activeIds.contains(meterId),
        "lastTriggeredAtMillis" to ReminderStore.lastTriggered(context, meterId),
        "nextTriggerAtMillis" to ReminderStore.nextTrigger(context, meterId),
        "planningState" to ReminderStore.planningState(context, meterId),
        "isExact" to ReminderStore.isExact(context, meterId),
        "deliveryFailed" to ReminderStore.deliveryFailed(context, meterId),
    )

    fun rescheduleAll(context: Context, clockChanged: Boolean = false) {
        ReminderStore.all(context).forEach { reminder ->
            if (clockChanged) {
                scheduleNext(context, reminder)
            } else {
                update(context, reminder)
            }
        }
    }

    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return context.getSystemService(AlarmManager::class.java)
            .canScheduleExactAlarms()
    }

    private fun firePendingIntent(
        context: Context,
        meterId: String,
        onlyIfExisting: Boolean,
    ): PendingIntent? {
        val intent = Intent(context, MeterReminderReceiver::class.java)
            .setAction(fireAction)
            .setData(
                Uri.Builder()
                    .scheme("reading-progress-log")
                    .authority("reminder")
                    .appendPath(meterId)
                    .build(),
            )
            .putExtra("meter_id", meterId)
        var flags = PendingIntent.FLAG_IMMUTABLE
        flags = flags or if (onlyIfExisting) {
            PendingIntent.FLAG_NO_CREATE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        return PendingIntent.getBroadcast(
            context,
            stableRequestCode(meterId, 0),
            intent,
            flags,
        )
    }
}

internal enum class ReminderAvailability(val wireValue: String) {
    AVAILABLE("available"),
    APP_BLOCKED("appBlocked"),
    CHANNEL_BLOCKED("channelBlocked"),
    UNKNOWN("unknown"),
}

internal object ReminderNotifier {
    private const val normalChannelId = "reading_progress_reminders"
    private const val alarmChannelId = "reading_progress_alarm_reminders_v1"
    private const val meterNotificationId = 1001
    private const val testNotificationId = 2001
    private const val meterTagPrefix = "meter:"
    private const val testTag = "reminder:test"

    fun channelId(punctual: Boolean): String = if (punctual) alarmChannelId else normalChannelId

    fun availability(context: Context, punctual: Boolean): ReminderAvailability = try {
        if (!notificationsEnabled(context)) {
            ReminderAvailability.APP_BLOCKED
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Reusing the same IDs preserves the user's channel preferences.
            ensureChannels(context)
            val manager = context.getSystemService(NotificationManager::class.java)
            val channel = manager.getNotificationChannel(channelId(punctual))
            val groupBlocked = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && channel?.group != null) {
                manager.getNotificationChannelGroup(channel.group)?.isBlocked == true
            } else {
                false
            }
            when {
                channel == null -> ReminderAvailability.UNKNOWN
                channel.importance == NotificationManager.IMPORTANCE_NONE || groupBlocked ->
                    ReminderAvailability.CHANNEL_BLOCKED
                else -> ReminderAvailability.AVAILABLE
            }
        } else {
            ReminderAvailability.AVAILABLE
        }
    } catch (_: Exception) {
        ReminderAvailability.UNKNOWN
    }

    fun doNotDisturbEnabled(context: Context): Boolean? = try {
        // Reading the current filter needs no notification-policy access.
        when (context.getSystemService(NotificationManager::class.java).currentInterruptionFilter) {
            NotificationManager.INTERRUPTION_FILTER_ALL -> false
            NotificationManager.INTERRUPTION_FILTER_PRIORITY,
            NotificationManager.INTERRUPTION_FILTER_ALARMS,
            NotificationManager.INTERRUPTION_FILTER_NONE -> true
            else -> null
        }
    } catch (_: Exception) {
        null
    }

    fun notificationsEnabled(context: Context): Boolean {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.N ||
            manager.areNotificationsEnabled()
    }

    fun showMeter(
        context: Context,
        reminder: StoredReminder,
        postedAt: Long = System.currentTimeMillis(),
    ): Long? {
        if (availability(context, reminder.isPunctual) != ReminderAvailability.AVAILABLE) return null
        val channelId = channelId(reminder.isPunctual)
        val category = if (reminder.isPunctual) {
            NotificationCompat.CATEGORY_ALARM
        } else {
            NotificationCompat.CATEGORY_REMINDER
        }
        val latestReading = if (
            !reminder.latestValue.isNullOrBlank()
        ) {
            "Letzter Eintrag: ${reminder.latestValue} ${reminder.latestUnit.orEmpty()}".trim()
        } else {
            "Noch kein Eintrag"
        }
        val summary = "${reminder.meterTypeLabel} · $latestReading"
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(notificationIcon(reminder.meterType))
            .setColor(notificationColor(reminder.meterType))
            .setContentTitle("${reminder.meterTypeLabel} · ${reminder.label}")
            .setContentText(summary)
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "$latestReading\nJetzt Kilometerstand fotografieren oder eintragen und den Fahrzeugverlauf aktualisieren.",
                ),
            )
            .apply { configureLegacySound(this, reminder.isPunctual) }
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(category)
            .setAutoCancel(true)
            .setWhen(postedAt)
            .setShowWhen(true)
            .setContentIntent(openMeterIntent(context, reminder.meterId))
            .build()
        context.getSystemService(NotificationManager::class.java).notify(
            meterTag(reminder.meterId),
            meterNotificationId,
            notification,
        )
        return postedAt
    }

    private fun notificationIcon(meterType: String): Int = when (meterType) {
        "electricity" -> R.drawable.ic_stat_vehicle
        "electricityFeedIn" -> R.drawable.ic_stat_vehicle
        "gas" -> R.drawable.ic_stat_vehicle
        "water" -> R.drawable.ic_stat_vehicle
        "coldWater" -> R.drawable.ic_stat_vehicle
        "hotWater" -> R.drawable.ic_stat_vehicle
        "heat" -> R.drawable.ic_stat_vehicle
        "heatingCostAllocator" -> R.drawable.ic_stat_vehicle
        "oil" -> R.drawable.ic_stat_vehicle
        else -> R.drawable.ic_stat_vehicle
    }

    private fun notificationColor(meterType: String): Int = when (meterType) {
        "electricity" -> Color.rgb(49, 94, 128)
        "electricityFeedIn" -> Color.rgb(49, 94, 128)
        "gas" -> Color.rgb(49, 94, 128)
        "water" -> Color.rgb(49, 94, 128)
        "coldWater" -> Color.rgb(49, 94, 128)
        "hotWater" -> Color.rgb(49, 94, 128)
        "heat" -> Color.rgb(49, 94, 128)
        "heatingCostAllocator" -> Color.rgb(49, 94, 128)
        "oil" -> Color.rgb(49, 94, 128)
        else -> Color.rgb(49, 94, 128)
    }

    fun migrateLegacyNotification(context: Context, reminder: StoredReminder) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val legacy = manager.activeNotifications.firstOrNull { notification ->
            notification.tag == null &&
                notification.id == stableRequestCode(reminder.meterId, 0)
        } ?: return
        manager.cancel(legacy.id)
        if (showMeter(context, reminder, legacy.postTime) != null) {
            ReminderStore.setLastTriggered(
                context,
                reminder.meterId,
                legacy.postTime,
            )
        }
    }

    fun showTest(
        context: Context,
        meterId: String?,
        label: String,
        meterType: String,
        meterTypeLabel: String,
        latestValue: String?,
        latestUnit: String?,
        punctual: Boolean,
    ): String {
        val availability = availability(context, punctual)
        if (availability != ReminderAvailability.AVAILABLE) return availability.wireValue
        val latestReading = if (!latestValue.isNullOrBlank()) {
            "Letzter Eintrag: $latestValue ${latestUnit.orEmpty()}".trim()
        } else {
            "Noch kein Eintrag"
        }
        val target = if (meterId.isNullOrBlank()) "die App" else "die Fahrzeugkarte"
        val notification = NotificationCompat.Builder(
            context,
            channelId(punctual),
        )
            .setSmallIcon(notificationIcon(meterType))
            .setColor(notificationColor(meterType))
            .setContentTitle("Test: $meterTypeLabel · $label")
            .setContentText(latestReading)
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "$latestReading\nDas ist eine Test-Erinnerung. Tippen öffnet $target.",
                ),
            )
            .apply { configureLegacySound(this, punctual) }
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(
                if (punctual) {
                    NotificationCompat.CATEGORY_ALARM
                } else {
                    NotificationCompat.CATEGORY_REMINDER
                },
            )
            .setAutoCancel(true)
            .setTimeoutAfter(60_000L)
            .setContentIntent(
                if (meterId.isNullOrBlank()) {
                    openAppIntent(context)
                } else {
                    openMeterIntent(context, meterId)
                },
            )
            .build()
        return try {
            scheduleLegacyTestExpiry(context)
            context.getSystemService(NotificationManager::class.java).notify(
                testTag,
                testNotificationId,
                notification,
            )
            "posted"
        } catch (_: Exception) {
            "failed"
        }
    }

    fun acknowledge(context: Context, meterId: String) {
        context.getSystemService(NotificationManager::class.java)
            .cancel(meterTag(meterId), meterNotificationId)
    }

    fun activeMeterIds(context: Context): Set<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptySet()
        return context.getSystemService(NotificationManager::class.java)
            .activeNotifications
            .mapNotNull { notification ->
                notification.tag
                    ?.takeIf { it.startsWith(meterTagPrefix) }
                    ?.removePrefix(meterTagPrefix)
            }
            .toSet()
    }

    private fun configureLegacySound(builder: NotificationCompat.Builder, punctual: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) return
        val sound = RingtoneManager.getDefaultUri(if (punctual) RingtoneManager.TYPE_ALARM else RingtoneManager.TYPE_NOTIFICATION)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        builder.setSound(sound, if (punctual) AudioManager.STREAM_ALARM else AudioManager.STREAM_NOTIFICATION)
            .setVibrate(longArrayOf(0L, 200L, 100L, 200L))
    }

    internal const val expireTestAction = "com.appfactory.vehicle_log.EXPIRE_REMINDER_TEST"

    private fun scheduleLegacyTestExpiry(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) return
        val deadline = SystemClock.elapsedRealtime() + 60_000L
        val operation = PendingIntent.getBroadcast(context, 2002,
            Intent(context, MeterReminderReceiver::class.java).setAction(expireTestAction)
                .putExtra("deadline", deadline),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        context.getSystemService(AlarmManager::class.java).setExactAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP, deadline, operation)
    }

    fun expireTest(context: Context, intent: Intent) {
        // A previously queued expiration must not remove a newer test early.
        if (SystemClock.elapsedRealtime() < intent.getLongExtra("deadline", Long.MAX_VALUE)) return
        context.getSystemService(NotificationManager::class.java).cancel(testTag, testNotificationId)
    }

    private fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val normal = NotificationChannel(
            normalChannelId,
            "Fahrzeugerinnerungen",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Optionale Erinnerungen für regelmäßige Einträge."
            enableVibration(true)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
        val alarmSound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val alarm = NotificationChannel(
            alarmChannelId,
            "Pünktliche Fahrzeugerinnerungen",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Pünktliche Fahrzeugerinnerungen mit Alarmton."
            enableVibration(true)
            setSound(
                alarmSound,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
        manager.createNotificationChannels(listOf(normal, alarm))
    }

    private fun openMeterIntent(context: Context, meterId: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction("com.appfactory.vehicle_log.OPEN_METER")
            .putExtra("meter_id", meterId)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context,
            stableRequestCode(meterId, 1),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun openAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context,
            stableRequestCode(testTag, 1),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun meterTag(meterId: String) = meterTagPrefix + meterId
}

internal fun stableRequestCode(value: String, salt: Int): Int {
    var hash = 0x811c9dc5L
    value.forEach { character ->
        hash = hash xor character.code.toLong()
        hash = (hash * 0x01000193L) and 0x7fffffffL
    }
    return ((hash + salt) and 0x7fffffffL).toInt().coerceAtLeast(1)
}
