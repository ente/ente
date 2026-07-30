package io.ente.ensu.chat

import android.content.Context
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.agog.mathdisplay.MTMathView
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuSpacing

@Composable
fun LaTeXView(latex: String, modifier: Modifier = Modifier) {
    val isDark = isSystemInDarkTheme()
    val textColor = if (isDark) EnsuColor.textPrimaryDark else EnsuColor.textPrimaryLight
    val paddingPx = with(LocalDensity.current) { EnsuSpacing.cardPadding.dp.roundToPx() }
    val fontSizePx = 16f * LocalDensity.current.density

    AndroidView(
        factory = { context ->
            LatexContainerView(context).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                )
                update(latex, textColor.toArgb(), fontSizePx, paddingPx)
            }
        },
        update = { view ->
            view.update(latex, textColor.toArgb(), fontSizePx, paddingPx)
        },
        modifier = modifier
    )
}

@Composable
fun InlineLaTeXView(
    latex: String,
    modifier: Modifier = Modifier,
    fontSizeSp: Float = 15f
) {
    val isDark = isSystemInDarkTheme()
    val textColor = if (isDark) EnsuColor.textPrimaryDark else EnsuColor.textPrimaryLight
    val fontSizePx = fontSizeSp * LocalDensity.current.density
    val paddingPx = with(LocalDensity.current) { 2.dp.roundToPx() }

    AndroidView(
        factory = { context ->
            InlineLatexContainerView(context).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                )
                update(latex, textColor.toArgb(), fontSizePx, paddingPx)
            }
        },
        update = { view ->
            view.update(latex, textColor.toArgb(), fontSizePx, paddingPx)
        },
        modifier = modifier
    )
}

private class InlineLatexContainerView(context: Context) : FrameLayout(context) {
    private val mathView = MTMathView(context)
    private val fallbackView = TextView(context)

    init {
        addView(
            mathView,
            LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        addView(
            fallbackView,
            LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        fallbackView.visibility = View.GONE
    }

    fun update(latex: String, textColor: Int, fontSizePx: Float, paddingPx: Int) {
        val sanitizedLatex = latex.replace("\\boxed", "")

        fallbackView.text = latex
        fallbackView.setTextColor(textColor)
        fallbackView.setTextSize(TypedValue.COMPLEX_UNIT_PX, fontSizePx)
        fallbackView.setPadding(paddingPx, paddingPx, paddingPx, paddingPx)

        mathView.textColor = textColor
        mathView.fontSize = fontSizePx
        mathView.setPadding(paddingPx, paddingPx, paddingPx, paddingPx)
        MathViewCompat.setMathTextAlignment(
            mathView,
            MTMathView.MTTextAlignment.KMTTextAlignmentLeft
        )
        MathViewCompat.setDisplayErrorInline(mathView, false)

        val shouldRender = latexLooksRenderable(sanitizedLatex)
        if (shouldRender) {
            mathView.latex = sanitizedLatex
        }

        val error = if (shouldRender) MathViewCompat.getError(mathView) else null
        val useFallback = !shouldRender || !error.isNullOrBlank()
        mathView.visibility = if (useFallback) View.GONE else View.VISIBLE
        fallbackView.visibility = if (useFallback) View.VISIBLE else View.GONE
    }
}

private class LatexContainerView(context: Context) : FrameLayout(context) {
    private val mathView = MTMathView(context)
    private val fallbackView = TextView(context)

    init {
        addView(
            mathView,
            LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        addView(
            fallbackView,
            LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        fallbackView.visibility = View.GONE
    }

    fun update(latex: String, textColor: Int, fontSizePx: Float, paddingPx: Int) {
        val sanitizedLatex = latex.replace("\\boxed", "")

        fallbackView.text = latex
        fallbackView.setTextColor(textColor)
        fallbackView.setTextSize(TypedValue.COMPLEX_UNIT_PX, fontSizePx)
        fallbackView.setPadding(paddingPx, paddingPx, paddingPx, paddingPx)

        mathView.textColor = textColor
        mathView.fontSize = fontSizePx
        mathView.setPadding(paddingPx, paddingPx, paddingPx, paddingPx)
        MathViewCompat.setMathTextAlignment(
            mathView,
            MTMathView.MTTextAlignment.KMTTextAlignmentLeft
        )
        MathViewCompat.setDisplayErrorInline(mathView, false)

        val shouldRender = latexLooksRenderable(sanitizedLatex)
        if (shouldRender) {
            mathView.latex = sanitizedLatex
        }

        val error = if (shouldRender) MathViewCompat.getError(mathView) else null
        val useFallback = !shouldRender || !error.isNullOrBlank()
        mathView.visibility = if (useFallback) View.GONE else View.VISIBLE
        fallbackView.visibility = if (useFallback) View.VISIBLE else View.GONE
    }
}

private object LatexRegex {
    val left = Regex("\\\\left")
    val right = Regex("\\\\right")
    val beginEnvironment = Regex("\\\\begin\\{([^}]+)\\}")
    val endEnvironment = Regex("\\\\end\\{([^}]+)\\}")
}

private fun latexLooksRenderable(latex: String): Boolean {
    val trimmed = latex.trim()
    if (trimmed.isEmpty()) {
        return false
    }

    var braceBalance = 0
    var escaped = false
    for (char in trimmed) {
        if (escaped) {
            escaped = false
            continue
        }
        if (char == '\\') {
            escaped = true
            continue
        }
        if (char == '{') {
            braceBalance += 1
        } else if (char == '}') {
            braceBalance -= 1
            if (braceBalance < 0) {
                return false
            }
        }
    }

    if (escaped || braceBalance != 0) {
        return false
    }

    if (countMatches(trimmed, LatexRegex.left) != countMatches(trimmed, LatexRegex.right)) {
        return false
    }

    return environmentsBalanced(trimmed)
}

private fun countMatches(text: String, regex: Regex): Int {
    return regex.findAll(text).count()
}

private fun environmentsBalanced(text: String): Boolean {
    val beginMatches = runCatching {
        LatexRegex.beginEnvironment
            .findAll(text)
            .map { it.groupValues[1] }
            .toList()
    }.getOrElse { return false }
    val endMatches = runCatching {
        LatexRegex.endEnvironment
            .findAll(text)
            .map { it.groupValues[1] }
            .toList()
    }.getOrElse { return false }
    if (beginMatches.size != endMatches.size) {
        return false
    }
    return beginMatches.sorted() == endMatches.sorted()
}
