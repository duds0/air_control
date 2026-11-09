package br.com.hrzon.air_control

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Draws the home-screen widget from the values the Dart side stores
 * (see lib/widget/ac_widget_service.dart). Every button fires a background
 * callback in Dart, so the app never has to open.
 *
 * Anti-blink rule: an update re-applies every action below to the live views.
 * Only cheap, idempotent properties are set here (text, text color, background
 * resource, visibility, alpha). Icons are static in the layout: setting an
 * icon's color filter/drawable on each update makes the launcher reload it,
 * which is what used to flash.
 */
class AcWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, build(context, widgetData))
        }
    }

    private fun tap(context: Context, path: String) =
        HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("airwidget://$path"))

    private fun build(context: Context, d: SharedPreferences): RemoteViews {
        val v = RemoteViews(context.packageName, R.layout.ac_widget)

        val has = d.getBoolean("w_has", false)
        val power = has && d.getBoolean("w_power", false)
        val tempOk = power && d.getBoolean("w_tempOk", false)
        val swingOn = d.getBoolean("w_swing", false)
        val displayOn = d.getBoolean("w_display", false)
        val windSel = d.getString("w_wind", "") ?: ""

        val dim = context.getColor(R.color.widget_dim)
        val accent = context.getColor(R.color.widget_accent)

        // Header: name, status line (mode and room temperature), target temp
        v.setTextViewText(R.id.title, d.getString("w_title", null) ?: "Ar-condicionado")
        v.setTextViewText(
            R.id.status,
            d.getString("w_status", null) ?: "Abra o app para conectar",
        )
        v.setTextViewText(R.id.temp, if (has) (d.getString("w_big", null) ?: "--") else "--")

        // Power: accent circle + light icon when on, grey circle + dark icon off.
        // Two static icons; only their visibility changes.
        v.setInt(R.id.power, "setBackgroundResource",
            if (power) R.drawable.widget_round_on else R.drawable.widget_round_off)
        v.setViewVisibility(R.id.power_icon_on, if (power) View.VISIBLE else View.GONE)
        v.setViewVisibility(R.id.power_icon_off, if (power) View.GONE else View.VISIBLE)

        // Temperature is adjustable only while on and cooling (same rule as the app)
        v.setFloat(R.id.row_temp, "setAlpha", if (tempOk) 1f else 0.35f)

        // Fan: ONE chip with a - / + stepper over Auto, 1..5 (Auto is the first
        // value). windSel is "0" (Auto), "1".."5", or "" (unknown, shown as Auto).
        // Shows the number when a numbered speed is set (kept while the unit is
        // off; the whole row is dimmed then), otherwise a small "Auto".
        val hasSpeed = windSel.isNotEmpty() && windSel != "0"
        v.setTextViewText(R.id.wind_value, windSel)
        v.setViewVisibility(R.id.wind_value, if (hasSpeed) View.VISIBLE else View.GONE)
        v.setViewVisibility(R.id.wind_value_auto, if (hasSpeed) View.GONE else View.VISIBLE)

        // Swing / display toggles: state is the background ring + label color
        val swingActive = power && swingOn
        val displayActive = power && displayOn
        v.setInt(R.id.swing, "setBackgroundResource",
            if (swingActive) R.drawable.widget_chip_on else R.drawable.widget_chip_off)
        v.setTextColor(R.id.swing_label, if (swingActive) accent else dim)
        v.setInt(R.id.display, "setBackgroundResource",
            if (displayActive) R.drawable.widget_chip_on else R.drawable.widget_chip_off)
        v.setTextColor(R.id.display_label, if (displayActive) accent else dim)

        v.setFloat(R.id.row_bottom, "setAlpha", if (power) 1f else 0.35f)

        // Taps
        v.setOnClickPendingIntent(R.id.power, tap(context, "power"))
        v.setOnClickPendingIntent(R.id.temp_minus, tap(context, "temp?d=-1"))
        v.setOnClickPendingIntent(R.id.temp_plus, tap(context, "temp?d=1"))
        v.setOnClickPendingIntent(R.id.wind_minus, tap(context, "wind?d=-1"))
        v.setOnClickPendingIntent(R.id.wind_plus, tap(context, "wind?d=1"))
        v.setOnClickPendingIntent(R.id.swing, tap(context, "swing"))
        v.setOnClickPendingIntent(R.id.display, tap(context, "display"))
        v.setOnClickPendingIntent(R.id.status, tap(context, "refresh")) // tap the status to refresh
        v.setOnClickPendingIntent(
            R.id.title,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )
        return v
    }
}
