package io.ente.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.AutofillNode
import androidx.compose.ui.autofill.AutofillType
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalAutofill
import androidx.compose.ui.platform.LocalAutofillTree
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalComposeUiApi::class)
@Composable
public fun VerificationCodeField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    error: String? = null,
    enabled: Boolean = true,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
) {
    val palette = LocalEntePalette.current
    val interactionSource = remember { MutableInteractionSource() }
    val focused by interactionSource.collectIsFocusedAsState()
    val canAutofill by rememberUpdatedState(enabled)
    val update by
        rememberUpdatedState<(String) -> Unit>({ input ->
            onValueChange(input.filter { it in '0'..'9' }.take(6))
        })
    val autofill = LocalAutofill.current
    val autofillTree = LocalAutofillTree.current
    val autofillNode = remember {
        AutofillNode(
            autofillTypes = listOf(AutofillType.SmsOtpCode),
            onFill = { if (canAutofill) update(it) },
        )
    }
    DisposableEffect(autofillTree, autofillNode) {
        autofillTree += autofillNode
        onDispose {
            autofill?.cancelAutofillForNode(autofillNode)
            autofillTree.children.remove(autofillNode.id)
        }
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(EnteSpacing.sm)) {
        BasicTextField(
            value = value,
            onValueChange = update,
            enabled = enabled,
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            keyboardActions = keyboardActions,
            interactionSource = interactionSource,
            cursorBrush = SolidColor(Color.Transparent),
            modifier =
                Modifier.widthIn(max = 324.dp)
                    .fillMaxWidth()
                    .onGloballyPositioned { autofillNode.boundingBox = it.boundsInWindow() }
                    .onFocusChanged {
                        if (it.isFocused) autofill?.requestAutofillForNode(autofillNode)
                        else autofill?.cancelAutofillForNode(autofillNode)
                    }
                    .semantics {
                        contentDescription = label
                        if (error != null) error(error)
                    },
            decorationBox = { input ->
                Box {
                    Row(
                        Modifier.fillMaxWidth().clearAndSetSemantics {},
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        repeat(6) { index ->
                            val filled = index < value.length
                            val active = focused && index == value.length.coerceAtMost(5)
                            val shape = RoundedCornerShape(EnteRadius.large)
                            val border =
                                when {
                                    !enabled -> palette.faintBorder
                                    error != null -> palette.danger
                                    filled || active -> palette.primary
                                    else -> palette.border
                                }
                            Box(
                                Modifier.weight(1f)
                                    .heightIn(min = 52.dp)
                                    .background(
                                        when {
                                            !enabled -> palette.fill
                                            filled && error == null -> palette.primarySurface
                                            else -> palette.surface
                                        },
                                        shape,
                                    )
                                    .border(
                                        if (error != null || filled || active) 2.dp else 1.dp,
                                        border,
                                        shape,
                                    ),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    value.getOrNull(index)?.toString() ?: " ",
                                    style =
                                        EnteTypography.body.copy(
                                            fontSize = 20.sp,
                                            lineHeight = 26.sp,
                                            fontWeight = FontWeight.Bold,
                                        ),
                                    color =
                                        when {
                                            !enabled -> palette.mutedText
                                            error != null -> palette.danger
                                            else -> palette.primary
                                        },
                                )
                            }
                        }
                    }
                    Box(Modifier.size(1.dp).alpha(0f)) { input() }
                }
            },
        )
        if (error != null) Text(error, style = EnteTypography.mini, color = palette.danger)
    }
}
