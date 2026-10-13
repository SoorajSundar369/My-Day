package com.sujay.taskme.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import com.sujay.taskme.MainActivity
import com.sujay.taskme.R
import java.util.Calendar

/** Builds the "open the add form" tap action used by every widget button and shortcut. */
object QuickLaunch {
    const val ACTION = "com.sujay.taskme.QUICK"

    /** button id -> (what to add, optional preset) */
    private val buttons: List<Triple<Int, String, String?>> = listOf(
        Triple(R.id.btn_expense, "expense", null),
        Triple(R.id.btn_income, "income", null),
        Triple(R.id.btn_journal, "journal", null),
        Triple(R.id.btn_voice, "journal_voice", null),
        Triple(R.id.btn_task, "task", null),
        Triple(R.id.btn_reminder, "reminder", null),
        Triple(R.id.btn_habit, "habit", null),
        Triple(R.id.chip_hour, "reminder", "hour"),
        Triple(R.id.chip_tonight, "reminder", "tonight"),
        Triple(R.id.chip_tomorrow, "reminder", "tomorrow"),
    )

    private fun flags() = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE

    private fun pending(ctx: Context, kind: String, preset: String?, code: Int): PendingIntent {
        val intent = Intent(ctx, MainActivity::class.java).apply {
            action = ACTION
            // a distinct data URI keeps every button's PendingIntent separate
            data = Uri.parse("myday://quick/$kind" + (preset?.let { "?when=$it" } ?: ""))
            putExtra("quick", kind)
            preset?.let { putExtra("when", it) }
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        return PendingIntent.getActivity(ctx, code, intent, flags())
    }

    /** Wires every known button that exists in [views]. Missing ids are simply ignored. */
    fun bind(ctx: Context, views: RemoteViews) {
        buttons.forEachIndexed { i, (id, kind, preset) ->
            views.setOnClickPendingIntent(id, pending(ctx, kind, preset, 100 + i))
        }
        // "Open app" just opens MyDay normally (the PIN screen will ask for the PIN)
        val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        if (open != null) {
            views.setOnClickPendingIntent(R.id.btn_open, PendingIntent.getActivity(ctx, 99, open, flags()))
        }
    }
}

/** Common behaviour: pick a layout for the widget's current size and wire the buttons. */
abstract class BaseWidget : AppWidgetProvider() {
    /** Layout for a widget of [w] x [h] dp. */
    abstract fun layoutFor(w: Int, h: Int): Int

    open fun fill(ctx: Context, views: RemoteViews) {}

    override fun onUpdate(context: Context, mgr: AppWidgetManager, ids: IntArray) {
        ids.forEach { render(context, mgr, it) }
    }

    override fun onAppWidgetOptionsChanged(context: Context, mgr: AppWidgetManager, id: Int, newOptions: android.os.Bundle) {
        render(context, mgr, id)
    }

    private fun render(ctx: Context, mgr: AppWidgetManager, id: Int) {
        val o = mgr.getAppWidgetOptions(id)
        val w = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 250)
        val h = o.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 110)
        val views = RemoteViews(ctx.packageName, layoutFor(w, h))
        QuickLaunch.bind(ctx, views)
        fill(ctx, views)
        mgr.updateAppWidget(id, views)
    }
}

/** Income and Expense side by side. */
class MoneyWidget : BaseWidget() {
    override fun layoutFor(w: Int, h: Int) = if (w >= 170) R.layout.widget_money else R.layout.widget_money_compact
}

/** A writing idea of the day plus Write / Voice. Never shows any entry. */
class JournalWidget : BaseWidget() {
    override fun layoutFor(w: Int, h: Int) =
        if (w >= 170 && h >= 120) R.layout.widget_journal else R.layout.widget_journal_compact

    override fun fill(ctx: Context, views: RemoteViews) {
        val day = Calendar.getInstance().get(Calendar.DAY_OF_YEAR)
        views.setTextViewText(R.id.prompt, PROMPTS[day % PROMPTS.size])
    }

    companion object {
        val PROMPTS = listOf(
            "What made you smile today?",
            "What are you grateful for right now?",
            "Describe the best part of your day.",
            "What is something you learned recently?",
            "Who made a difference to you this week, and how?",
            "What is on your mind that you have not said out loud?",
            "What would make tomorrow a good day?",
            "Describe a small moment you want to remember.",
            "What are you proud of lately?",
            "What is something you are looking forward to?",
            "What is a worry you could let go of today?",
            "Write about a place that makes you feel calm.",
            "What did you do today that was just for you?",
            "What is one thing you would tell your younger self?",
            "How are you really feeling, and why?",
            "What was the hardest part of today, and how did you handle it?",
            "What is a habit you want to start or stop?",
            "Describe someone you love in three words, then say why.",
            "What would you do if you knew you could not fail?",
            "What is something small that went right today?",
        )
    }
}

/** Add a task or a reminder, with quick time choices. */
class TaskWidget : BaseWidget() {
    override fun layoutFor(w: Int, h: Int) =
        if (w >= 170 && h >= 110) R.layout.widget_task else R.layout.widget_task_compact
}

/** Start a new habit, or open the app. */
class HabitWidget : BaseWidget() {
    override fun layoutFor(w: Int, h: Int) = if (w >= 170) R.layout.widget_habit else R.layout.widget_habit_compact
}

/** All six quick actions with labels (falls back to the icon bar when small). */
class QuickMediumWidget : BaseWidget() {
    override fun layoutFor(w: Int, h: Int) = when {
        w >= 170 && h >= 110 -> R.layout.widget_quick_medium
        w >= 230 -> R.layout.widget_quickbar
        else -> R.layout.widget_quickbar_small
    }
}

/** The slim icon bar. */
class QuickBarWidget : BaseWidget() {
    override fun layoutFor(w: Int, h: Int) = if (w >= 230) R.layout.widget_quickbar else R.layout.widget_quickbar_small
}
