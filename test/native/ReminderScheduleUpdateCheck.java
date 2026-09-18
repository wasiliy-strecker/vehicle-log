import com.appfactory.vehicle_log.StoredReminder;
import java.time.Instant;
import java.time.ZoneId;

/** Runs against the actual compiled Kotlin scheduler model, without Android mocks. */
class ReminderScheduleUpdateCheck {
    private static int checks;
    private static final ZoneId BERLIN = ZoneId.of("Europe/Berlin");

    private static StoredReminder reminder(String interval, int day, Integer month,
            int hour, int minute, Long start, String label, String mode) {
        return new StoredReminder("saved", label, "other", "Test",
                "123", "Einheiten", interval, day, month, hour, minute, mode, start);
    }

    private static long instant(String value) {
        return Instant.parse(value).toEpochMilli();
    }

    private static void equal(long actual, long expected) {
        checks++;
        if (actual != expected) {
            throw new AssertionError("Expected " + expected + ", received " + actual);
        }
    }

    public static void main(String[] args) {
        long due = instant("2026-09-16T07:00:00Z");
        long now = due + 5 * 60_000L;
        for (String interval : new String[]{"hourly", "daily", "weekly", "monthly", "yearly"}) {
            int day = interval.equals("weekly") ? 3 : 16;
            StoredReminder original = reminder(interval, day, 9, 9, 0, due, "Old", "normal");
            StoredReminder edited = reminder(interval, day, 9, 9, 0, due, "New", "punctualWithSound");
            // A cold app start, metadata edit or permission/mode change preserves the due occurrence.
            equal(original.nextTriggerForUpdate(original, due, now, BERLIN), due);
            equal(edited.nextTriggerForUpdate(original, due, now, BERLIN), due);
            // The same holds before the alarm becomes due.
            equal(edited.nextTriggerForUpdate(original, due, due - 1, BERLIN), due);
            // New and legacy schedules without persisted occurrence data use the normal calculation.
            equal(original.nextTriggerForUpdate(null, null, now, BERLIN), original.nextTriggerAfter(now, BERLIN));
            equal(original.nextTriggerForUpdate(original, null, now, BERLIN), original.nextTriggerAfter(now, BERLIN));
            // Receiving an occurrence advances it strictly past now. Subsequent app starts retain that new time.
            long next = edited.nextTriggerAfter(now, BERLIN);
            if (next <= now) throw new AssertionError("Delivered occurrence did not advance");
            equal(edited.nextTriggerForUpdate(edited, next, now, BERLIN), next);
        }
        StoredReminder original = reminder("daily", 1, null, 9, 0, null, "Test", "normal");
        for (StoredReminder changed : new StoredReminder[]{
                reminder("daily", 1, null, 10, 0, null, "Test", "normal"),
                reminder("daily", 1, null, 9, 30, null, "Test", "normal"),
                reminder("weekly", 4, null, 9, 0, null, "Test", "normal"),
                reminder("monthly", 17, null, 9, 0, null, "Test", "normal"),
                reminder("yearly", 16, 10, 9, 0, null, "Test", "normal")}) {
            equal(changed.nextTriggerForUpdate(original, due, now, BERLIN), changed.nextTriggerAfter(now, BERLIN));
        }
        for (String interval : new String[]{"weekly", "monthly", "yearly"}) {
            int day = interval.equals("weekly") ? 3 : 16;
            StoredReminder before = reminder(interval, day, 9, 9, 0, null, "Test", "normal");
            StoredReminder after = reminder(interval, day + 1, 9, 9, 0, null, "Test", "normal");
            equal(after.nextTriggerForUpdate(before, due, now, BERLIN), after.nextTriggerAfter(now, BERLIN));
        }
        StoredReminder yearBefore = reminder("yearly", 16, 9, 9, 0, null, "Test", "normal");
        StoredReminder yearAfter = reminder("yearly", 16, 10, 9, 0, null, "Test", "normal");
        equal(yearAfter.nextTriggerForUpdate(yearBefore, due, now, BERLIN), yearAfter.nextTriggerAfter(now, BERLIN));
        StoredReminder hourlyBefore = reminder("hourly", 1, null, 9, 0, due, "Test", "normal");
        StoredReminder hourlyAfter = reminder("hourly", 1, null, 9, 30, due + 30 * 60_000L, "Test", "normal");
        equal(hourlyAfter.nextTriggerForUpdate(hourlyBefore, due, now, BERLIN), due + 30 * 60_000L);
        System.out.println("Android reminder update scheduling: " + checks + " checks passed");
    }
}
