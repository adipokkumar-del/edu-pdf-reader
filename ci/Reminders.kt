package com.edu.edu_pdf_reader

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

data class Reminder(
    val id: Int,
    val at: Long,
    val title: String,
    val text: String,
    val alarm: Boolean,
    val repeat: Boolean
)

object Reminders {
    private const val CHANNEL_REMINDER = "reminders"
    private const val CHANNEL_ALARM = "alarms"
    private const val PREFS = "edu_reminders"
    private const val KEY = "list"
    private const val DAY = 24L * 60L * 60L * 1000L

    fun canExact(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        return alarmManager(ctx).canScheduleExactAlarms()
    }

    /** Replaces every scheduled reminder with the list sent from Dart. */
    fun sync(ctx: Context, json: String) {
        for (old in load(ctx)) cancel(ctx, old.id)
        val fresh = parse(json)
        save(ctx, fresh)
        for (r in fresh) schedule(ctx, r)
    }

    /** The system forgets alarms after a reboot or an update; schedule them again. */
    fun restore(ctx: Context) {
        for (r in load(ctx)) schedule(ctx, r)
    }

    fun fire(ctx: Context, id: Int) {
        val all = load(ctx)
        val r = all.find { it.id == id } ?: return
        show(ctx, r)
        if (r.repeat) {
            val updated = r.copy(at = nextTime(r.at))
            save(ctx, all.map { if (it.id == id) updated else it })
            schedule(ctx, updated)
        }
    }

    // ---- Scheduling ---------------------------------------------------------

    private fun alarmManager(ctx: Context): AlarmManager =
        ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun pending(ctx: Context, id: Int): PendingIntent {
        val intent = Intent(ctx, ReminderReceiver::class.java).putExtra("id", id)
        return PendingIntent.getBroadcast(
            ctx, id, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun cancel(ctx: Context, id: Int) {
        alarmManager(ctx).cancel(pending(ctx, id))
    }

    private fun nextTime(at: Long): Long {
        val now = System.currentTimeMillis()
        if (at > now) return at
        val missedDays = (now - at) / DAY + 1
        return at + missedDays * DAY
    }

    private fun schedule(ctx: Context, r: Reminder) {
        val at = if (r.repeat) nextTime(r.at) else r.at
        if (at <= System.currentTimeMillis()) return

        val manager = alarmManager(ctx)
        val pi = pending(ctx, r.id)
        try {
            if (canExact(ctx)) {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            } else {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
            }
        } catch (e: SecurityException) {
            manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        }
    }

    // ---- Storage ------------------------------------------------------------

    private fun parse(json: String): List<Reminder> {
        val out = ArrayList<Reminder>()
        try {
            val array = JSONArray(json)
            for (i in 0 until array.length()) {
                val o = array.getJSONObject(i)
                out.add(
                    Reminder(
                        o.getInt("id"),
                        o.getLong("at"),
                        o.optString("title", "Reminder"),
                        o.optString("text", ""),
                        o.optBoolean("alarm", false),
                        o.optBoolean("repeat", false)
                    )
                )
            }
        } catch (e: Exception) {
            // Ignore malformed data.
        }
        return out
    }

    private fun load(ctx: Context): List<Reminder> {
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return parse(prefs.getString(KEY, "[]") ?: "[]")
    }

    private fun save(ctx: Context, list: List<Reminder>) {
        val array = JSONArray()
        for (r in list) {
            array.put(
                JSONObject()
                    .put("id", r.id)
                    .put("at", r.at)
                    .put("title", r.title)
                    .put("text", r.text)
                    .put("alarm", r.alarm)
                    .put("repeat", r.repeat)
            )
        }
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY, array.toString()).apply()
    }

    // ---- Notification -------------------------------------------------------

    private fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val reminders = NotificationChannel(
            CHANNEL_REMINDER, "Reminders", NotificationManager.IMPORTANCE_HIGH
        )
        reminders.description = "Reminders for your notes and checklists"
        manager.createNotificationChannel(reminders)

        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val alarms = NotificationChannel(
            CHANNEL_ALARM, "Alarms", NotificationManager.IMPORTANCE_HIGH
        )
        alarms.description = "Loud alarms for important tasks"
        alarms.setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM), attributes)
        alarms.enableVibration(true)
        alarms.vibrationPattern = longArrayOf(0, 600, 300, 600, 300, 600)
        manager.createNotificationChannel(alarms)
    }

    @Suppress("DEPRECATION")
    private fun show(ctx: Context, r: Reminder) {
        ensureChannels(ctx)
        val manager = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(ctx, if (r.alarm) CHANNEL_ALARM else CHANNEL_REMINDER)
        } else {
            Notification.Builder(ctx)
                .setDefaults(Notification.DEFAULT_ALL)
                .setPriority(Notification.PRIORITY_HIGH)
        }

        builder
            .setSmallIcon(ctx.applicationInfo.icon)
            .setContentTitle(r.title)
            .setContentText(r.text)
            .setStyle(Notification.BigTextStyle().bigText(r.text))
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setCategory(if (r.alarm) Notification.CATEGORY_ALARM else Notification.CATEGORY_REMINDER)

        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        if (launch != null) {
            builder.setContentIntent(
                PendingIntent.getActivity(
                    ctx, r.id, launch,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
            )
        }

        val notification = builder.build()
        if (r.alarm) {
            // Keep ringing until the notification is dismissed.
            notification.flags = notification.flags or Notification.FLAG_INSISTENT
        }
        manager.notify(r.id, notification)
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", -1)
        if (id >= 0) Reminders.fire(context, id)
    }
}

/** Lets other apps read the small sample PDF used to pick the default PDF app. */
class EduFileProvider : androidx.core.content.FileProvider()

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Reminders.restore(context)
    }
}
