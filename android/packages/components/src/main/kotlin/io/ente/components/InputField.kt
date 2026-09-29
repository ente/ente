package io.ente.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp

@Composable
public fun InputField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null,
    required: Boolean = false,
    placeholder: String? = null,
    message: String? = null,
    state: InputState = InputState.Normal,
    enabled: Boolean = true,
    readOnly: Boolean = false,
    singleLine: Boolean = true,
    minLines: Int = 1,
    maxLines: Int = Int.MAX_VALUE,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    visualTransformation: VisualTransformation = VisualTransformation.None,
    interactionSource: MutableInteractionSource = remember { MutableInteractionSource() },
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    val palette = LocalEntePalette.current
    val focused by interactionSource.collectIsFocusedAsState()
    val statusColor =
        when (state) {
            InputState.Normal -> palette.mutedText
            InputState.Error -> palette.danger
            InputState.Success -> palette.primary
        }
    val border =
        when {
            state != InputState.Normal -> statusColor
            focused -> palette.hintText
            else -> palette.faintBorder
        }
    val textColor = if (enabled) palette.text else palette.disabledText
    val hintColor = if (enabled) palette.hintText else palette.disabledText
    val shape = RoundedCornerShape(EnteRadius.large)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(EnteSpacing.sm)) {
        if (label != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(label, style = EnteTypography.body, color = textColor)
                if (required) {
                    Text("*", style = EnteTypography.bodyBold, color = palette.danger)
                }
            }
        }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            modifier =
                Modifier.fillMaxWidth().semantics(mergeDescendants = true) {
                    (label ?: placeholder)?.let { contentDescription = it }
                    if (state == InputState.Error && message != null) error(message)
                },
            enabled = enabled,
            readOnly = readOnly,
            singleLine = singleLine,
            minLines = minLines,
            maxLines = maxLines,
            keyboardOptions = keyboardOptions,
            keyboardActions = keyboardActions,
            visualTransformation = visualTransformation,
            textStyle = EnteTypography.body.copy(color = textColor),
            cursorBrush = SolidColor(palette.primary),
            interactionSource = interactionSource,
            decorationBox = { innerTextField ->
                CompositionLocalProvider(LocalContentColor provides hintColor) {
                    Row(
                        modifier =
                            Modifier.fillMaxWidth()
                                .heightIn(min = 52.dp)
                                .clip(shape)
                                .background(if (enabled) palette.surface else palette.fill)
                                .border(1.dp, border, shape)
                                .padding(
                                    horizontal = EnteSpacing.lg,
                                    vertical = if (singleLine) 0.dp else EnteSpacing.lg,
                                ),
                        verticalAlignment =
                            if (singleLine) Alignment.CenterVertically else Alignment.Top,
                    ) {
                        leading?.let {
                            it()
                            Spacer(Modifier.width(EnteSpacing.sm))
                        }
                        Box(
                            Modifier.weight(1f)
                                .padding(vertical = if (singleLine) EnteSpacing.lg else 0.dp)
                        ) {
                            if (value.isEmpty() && placeholder != null) {
                                Text(placeholder, style = EnteTypography.body, color = hintColor)
                            }
                            innerTextField()
                        }
                        trailing?.let {
                            Spacer(Modifier.width(EnteSpacing.sm))
                            it()
                        }
                    }
                }
            },
        )
        if (message != null) {
            Text(message, style = EnteTypography.mini, color = statusColor)
        }
    }
}
