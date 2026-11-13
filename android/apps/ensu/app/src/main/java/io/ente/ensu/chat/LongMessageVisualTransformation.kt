package io.ente.ensu.chat

import android.icu.lang.UCharacter
import android.icu.lang.UCharacterDirection
import android.icu.text.BreakIterator
import android.text.TextDirectionHeuristics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import java.util.Locale

internal object LongMessageVisualTransformation : VisualTransformation {
    private const val LongRunLength = 8192
    private const val LayoutSectionLength = 2048

    override fun filter(text: AnnotatedString): TransformedText {
        if (!text.hasEqualAnnotations(AnnotatedString(""))) {
            return TransformedText(text, OffsetMapping.Identity)
        }
        val breaks = mutableListOf<Int>()
        var characters: BreakIterator? = null
        var words: BreakIterator? = null
        var start = 0
        while (start < text.length) {
            val end = text.text.indexOf('\n', start).let { if (it < 0) text.length else it }
            if (
                end - start > LongRunLength &&
                    !hasDirectionSensitiveText(text.text, start, end) &&
                    isLeftToRight(text.text, start, end)
            ) {
                var runStart = start
                while (runStart < end) {
                    if (text.text[runStart].isWhitespace()) {
                        runStart++
                        continue
                    }
                    var runEnd = runStart + 1
                    while (runEnd < end && !text.text[runEnd].isWhitespace()) runEnd++
                    if (runEnd - runStart > LongRunLength) {
                        val iterator =
                            characters
                                ?: BreakIterator.getCharacterInstance(Locale.ROOT).also {
                                    it.setText(text.text)
                                    characters = it
                                }
                        val wordIterator =
                            words
                                ?: BreakIterator.getWordInstance(Locale.getDefault()).also {
                                    it.setText(text.text)
                                    words = it
                                }
                        var boundary = iterator.following(runStart + LayoutSectionLength - 1)
                        while (boundary != BreakIterator.DONE && boundary < runEnd) {
                            if (
                                text.text[boundary - 1].isAsciiLetterOrDigit() &&
                                    text.text[boundary].isAsciiLetterOrDigit() &&
                                    !wordIterator.isBoundary(boundary)
                            ) {
                                breaks.add(boundary)
                                if (runEnd - boundary <= LayoutSectionLength) break
                                boundary = iterator.following(boundary + LayoutSectionLength - 1)
                            } else {
                                boundary = iterator.next()
                            }
                        }
                    }
                    runStart = runEnd
                }
            }
            start = end + 1
        }
        if (breaks.isEmpty()) return TransformedText(text, OffsetMapping.Identity)

        val rendered = StringBuilder(text.length + breaks.size)
        var previous = 0
        breaks.forEach { end ->
            rendered.append(text.text, previous, end)
            rendered.append('\u200E')
            previous = end
        }
        rendered.append(text.text, previous, text.length)
        return TransformedText(
            AnnotatedString(rendered.toString()),
            LayoutOffsetMapping(breaks.toIntArray()),
        )
    }

    private fun Char.isAsciiLetterOrDigit(): Boolean =
        this in 'a'..'z' || this in 'A'..'Z' || this in '0'..'9'

    private fun hasDirectionSensitiveText(text: String, start: Int, end: Int): Boolean {
        var index = start
        while (index < end) {
            val codePoint = Character.codePointAt(text, index)
            when (UCharacter.getDirection(codePoint)) {
                UCharacterDirection.RIGHT_TO_LEFT,
                UCharacterDirection.RIGHT_TO_LEFT_ARABIC,
                UCharacterDirection.ARABIC_NUMBER,
                UCharacterDirection.LEFT_TO_RIGHT_EMBEDDING,
                UCharacterDirection.LEFT_TO_RIGHT_OVERRIDE,
                UCharacterDirection.RIGHT_TO_LEFT_EMBEDDING,
                UCharacterDirection.RIGHT_TO_LEFT_OVERRIDE,
                UCharacterDirection.POP_DIRECTIONAL_FORMAT,
                UCharacterDirection.LEFT_TO_RIGHT_ISOLATE.toInt(),
                UCharacterDirection.RIGHT_TO_LEFT_ISOLATE.toInt(),
                UCharacterDirection.FIRST_STRONG_ISOLATE.toInt(),
                UCharacterDirection.POP_DIRECTIONAL_ISOLATE.toInt() -> return true
            }
            index += Character.charCount(codePoint)
        }
        return false
    }

    private fun isLeftToRight(text: String, start: Int, end: Int): Boolean =
        !TextDirectionHeuristics.FIRSTSTRONG_RTL.isRtl(text, start, end - start)

    private class LayoutOffsetMapping(private val breaks: IntArray) : OffsetMapping {
        private val renderedBreaks = IntArray(breaks.size) { breaks[it] + it }

        override fun originalToTransformed(offset: Int): Int {
            val index = breaks.binarySearch(offset)
            val count = if (index < 0) -index - 1 else index + 1
            return offset + count
        }

        override fun transformedToOriginal(offset: Int): Int {
            val index = renderedBreaks.binarySearch(offset)
            val count = if (index < 0) -index - 1 else index
            return offset - count
        }
    }
}
