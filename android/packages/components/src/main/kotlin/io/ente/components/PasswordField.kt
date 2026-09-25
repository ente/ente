package io.ente.components

import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.AutofillNode
import androidx.compose.ui.autofill.AutofillType
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalAutofill
import androidx.compose.ui.platform.LocalAutofillTree
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation

@OptIn(ExperimentalComposeUiApi::class)
@Composable
public fun PasswordField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null,
    required: Boolean = false,
    isRevealed: Boolean = false,
    newPassword: Boolean = false,
    placeholder: String? = null,
    message: String? = null,
    state: InputState = InputState.Normal,
    enabled: Boolean = true,
    imeAction: ImeAction = ImeAction.Done,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
    trailing: (@Composable () -> Unit)? = null,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val focused by interactionSource.collectIsFocusedAsState()
    val canAutofill by rememberUpdatedState(enabled)
    val update by rememberUpdatedState(onValueChange)
    val autofill = LocalAutofill.current
    val tree = LocalAutofillTree.current
    val node =
        remember(newPassword) {
            AutofillNode(
                autofillTypes =
                    listOf(if (newPassword) AutofillType.NewPassword else AutofillType.Password),
                onFill = { if (canAutofill) update(it) },
            )
        }
    var bounds by remember { mutableStateOf<Rect?>(null) }
    node.boundingBox = bounds
    DisposableEffect(tree, node) {
        tree += node
        onDispose { tree.children.remove(node.id) }
    }
    DisposableEffect(autofill, node, focused, enabled, bounds) {
        val requested = focused && enabled && bounds != null
        if (requested) autofill?.requestAutofillForNode(node)
        onDispose { if (requested) autofill?.cancelAutofillForNode(node) }
    }
    val mask = remember { PasswordVisualTransformation() }
    InputField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.onGloballyPositioned { bounds = it.boundsInWindow() },
        label = label,
        required = required,
        placeholder = placeholder,
        message = message,
        state = state,
        enabled = enabled,
        keyboardOptions =
            KeyboardOptions(
                autoCorrectEnabled = false,
                keyboardType = KeyboardType.Password,
                imeAction = imeAction,
            ),
        keyboardActions = keyboardActions,
        visualTransformation = if (isRevealed) VisualTransformation.None else mask,
        interactionSource = interactionSource,
        trailing = trailing,
    )
}
