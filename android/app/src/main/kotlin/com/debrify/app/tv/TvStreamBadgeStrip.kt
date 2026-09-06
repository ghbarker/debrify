package com.debrify.app.tv

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import com.bumptech.glide.Glide

/** Non-focusable bounded wrapping chips. Matching is performed by Flutter's
 * cancellable worker; the native UI receives only finished display records. */
class TvStreamBadgeStrip(context: Context) : ViewGroup(context) {
    private var shown: List<Map<*, *>>? = null
    private val positions = mutableListOf<Pair<Int, Int>>()
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    fun show(badges: List<Map<*, *>>) {
        if (shown === badges) return
        shown = badges
        clearImages()
        removeAllViews()
        for (badge in badges) {
            val label = badge["label"] as? String ?: continue
            val image = badge["imageUrl"] as? String
            val fill = (badge["fillColor"] as? Number)?.toInt() ?: 0xFF2A2A2A.toInt()
            val foreground = (badge["textColor"] as? Number)?.toInt() ?: -1
            val border = (badge["borderColor"] as? Number)?.toInt()
            val chip: View = if (image.isNullOrBlank()) {
                TextView(context).apply {
                    text = label.uppercase()
                    textSize = 11f
                    setTextColor(foreground)
                    setSingleLine(true)
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    maxWidth = dp(180)
                    gravity = android.view.Gravity.CENTER
                    setPadding(dp(7), 0, dp(7), 0)
                    layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, dp(22))
                }
            } else {
                ImageView(context).apply {
                    contentDescription = label
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    setPadding(dp(3), dp(2), dp(3), dp(2))
                    layoutParams = LayoutParams(dp(110), dp(22))
                    Glide.with(this).load(image).fitCenter().override(dp(110), dp(22))
                        .placeholder(BadgeLabelDrawable(label, resources.displayMetrics.density))
                        .error(BadgeLabelDrawable(label, resources.displayMetrics.density)).into(this)
                }
            }
            chip.isFocusable = false
            chip.isClickable = false
            chip.background = GradientDrawable().apply {
                setColor(if (image.isNullOrBlank()) fill else 0xFF2A2A2A.toInt())
                cornerRadius = dp(4).toFloat()
                if (border != null) setStroke(dp(1), border)
            }
            addView(chip)
        }
        requestLayout()
    }

    private fun clearImages() {
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child is ImageView) Glide.with(context.applicationContext).clear(child)
        }
    }

    override fun onDetachedFromWindow() {
        clearImages()
        super.onDetachedFromWindow()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val gap = dp(4)
        var x = 0
        var y = if (childCount > 0) dp(8) else 0
        var rowHeight = 0
        positions.clear()
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            val available = if (child.layoutParams.width > 0) minOf(width, child.layoutParams.width) else width
            child.measure(MeasureSpec.makeMeasureSpec(available,
                if (child.layoutParams.width > 0) MeasureSpec.EXACTLY else MeasureSpec.AT_MOST),
                MeasureSpec.makeMeasureSpec(dp(22), MeasureSpec.EXACTLY))
            if (x > 0 && x + child.measuredWidth > width) {
                x = 0; y += rowHeight + gap; rowHeight = 0
            }
            positions.add(x to y)
            x += child.measuredWidth + gap
            rowHeight = maxOf(rowHeight, child.measuredHeight)
        }
        setMeasuredDimension(width, resolveSize(y + rowHeight, heightMeasureSpec))
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            val (x, y) = positions.getOrElse(i) { 0 to 0 }
            child.layout(x, y, x + child.measuredWidth, y + child.measuredHeight)
        }
    }
}

private class BadgeLabelDrawable(private val label: String, density: Float) : android.graphics.drawable.Drawable() {
    private val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
        color = android.graphics.Color.WHITE
        textSize = 11 * density
        textAlign = android.graphics.Paint.Align.CENTER
    }
    override fun draw(canvas: android.graphics.Canvas) {
        val text = android.text.TextUtils.ellipsize(label, android.text.TextPaint(paint), bounds.width().toFloat(), android.text.TextUtils.TruncateAt.END).toString()
        canvas.drawText(text, bounds.exactCenterX(), bounds.exactCenterY() - (paint.ascent() + paint.descent()) / 2, paint)
    }
    override fun setAlpha(alpha: Int) { paint.alpha = alpha }
    override fun setColorFilter(filter: android.graphics.ColorFilter?) { paint.colorFilter = filter }
    @Deprecated("Deprecated in Java")
    override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
}
