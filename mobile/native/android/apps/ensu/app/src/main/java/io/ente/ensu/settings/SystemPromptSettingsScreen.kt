package io.ente.ensu.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.unit.dp
import io.ente.ensu.components.PrimaryButton
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuCornerRadius
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography

@Composable
fun SystemPromptSettingsScreen(
    defaultPromptBody: String,
    datePlaceholder: String,
    systemPrompt: String,
    onSave: (String) -> Unit,
    onReset: () -> Unit
) {
    val resolvedPrompt = systemPrompt.trim().ifEmpty { defaultPromptBody }
    var value by remember(systemPrompt) { mutableStateOf(resolvedPrompt) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(EnsuSpacing.pageHorizontal.dp)
    ) {
        Text(
            text = "This prompt is used as-is. Use $datePlaceholder anywhere to insert the current date.",
            style = EnsuTypography.small,
            color = EnsuColor.textMuted()
        )

        Spacer(modifier = Modifier.height(EnsuSpacing.lg.dp))

        OutlinedTextField(
            value = value,
            onValueChange = { value = it },
            modifier = Modifier
                .fillMaxWidth()
                .height(220.dp),
            placeholder = {
                Text(
                    text = "Example: You are a concise assistant. Current date: $datePlaceholder",
                    style = EnsuTypography.body
                )
            },
            colors = TextFieldDefaults.colors(
                focusedContainerColor = EnsuColor.fillFaint(),
                unfocusedContainerColor = EnsuColor.fillFaint(),
                focusedIndicatorColor = EnsuColor.fillFaint(),
                unfocusedIndicatorColor = EnsuColor.fillFaint()
            ),
            shape = RoundedCornerShape(EnsuCornerRadius.input.dp)
        )

        Spacer(modifier = Modifier.height(EnsuSpacing.sm.dp))
        Text(
            text = "Leave blank to use the default prompt.",
            style = EnsuTypography.small,
            color = EnsuColor.textMuted()
        )

        Spacer(modifier = Modifier.height(EnsuSpacing.xl.dp))

        PrimaryButton(
            text = "Save",
            isLoading = false,
            isEnabled = value.trim() != resolvedPrompt
        ) {
            val normalizedValue = value.trim()
            val valueToSave = if (normalizedValue == defaultPromptBody) "" else normalizedValue
            onSave(valueToSave)
        }

        Spacer(modifier = Modifier.height(EnsuSpacing.md.dp))

        TextButton(onClick = { onReset() }) {
            Text(
                text = "Use Default Prompt",
                style = EnsuTypography.body,
                color = EnsuColor.action()
            )
        }
    }
}
