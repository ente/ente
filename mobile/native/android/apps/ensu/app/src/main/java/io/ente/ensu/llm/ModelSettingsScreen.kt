package io.ente.ensu.llm

import android.widget.Toast
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.bindings.ConfigDefaults
import io.ente.ensu.llm.ModelSettingsState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelSettingsScreen(
    defaults: ConfigDefaults,
    state: ModelSettingsState,
    onSave: (ModelSettingsState) -> Unit,
    onReset: () -> Unit
) {
    val context = LocalContext.current
    val modelChoices = remember {
        listOf(
            ModelChoice(
                id = DEFAULT_OPTION_ID,
                title = defaults.mobileDefaultModel.title,
                isDefault = true
            )
        ) + defaults.mobileModelPresets.map { preset ->
            ModelChoice(
                id = preset.id,
                title = preset.title
            )
        }
    }

    var selectedModelId by remember(state) {
        mutableStateOf(initialSelectionId(state, modelChoices))
    }
    var contextLength by remember(state) { mutableStateOf(state.contextLength) }
    var maxTokens by remember(state) { mutableStateOf(state.maxTokens) }
    var temperature by remember(state) { mutableStateOf(state.temperature) }
    var showAdvancedLimits by remember(state) {
        mutableStateOf(
            state.contextLength.isNotBlank() ||
                state.maxTokens.isNotBlank() ||
                state.temperature.isNotBlank()
        )
    }
    var isModelMenuExpanded by remember { mutableStateOf(false) }

    val selectedModel = modelChoices.firstOrNull { it.id == selectedModelId } ?: modelChoices.first()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(EnsuSpacing.pageHorizontal.dp)
    ) {
        SectionHeader("Select model")
        Spacer(modifier = Modifier.height(EnsuSpacing.xs.dp))
        Text(
            text = "Choose a built-in model.",
            style = EnsuTypography.small,
            color = EnsuColor.textMuted()
        )
        Spacer(modifier = Modifier.height(EnsuSpacing.sm.dp))
        ExposedDropdownMenuBox(
            expanded = isModelMenuExpanded,
            onExpandedChange = { isModelMenuExpanded = !isModelMenuExpanded }
        ) {
            OutlinedTextField(
                value = selectedModel.title,
                onValueChange = {},
                readOnly = true,
                label = { Text("Model") },
                trailingIcon = {
                    ExposedDropdownMenuDefaults.TrailingIcon(expanded = isModelMenuExpanded)
                },
                modifier = Modifier
                    .menuAnchor()
                    .fillMaxWidth()
            )

            ExposedDropdownMenu(
                expanded = isModelMenuExpanded,
                onDismissRequest = { isModelMenuExpanded = false }
            ) {
                modelChoices.forEach { choice ->
                    DropdownMenuItem(
                        text = { Text(choice.title) },
                        onClick = {
                            selectedModelId = choice.id
                            isModelMenuExpanded = false
                        }
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(EnsuSpacing.lg.dp))
        ExpandButton(
            title = "Advanced limits",
            expanded = showAdvancedLimits,
            collapsedHint = "Context length, output, temperature",
            onToggle = { showAdvancedLimits = !showAdvancedLimits }
        )
        AnimatedVisibility(showAdvancedLimits) {
            Column {
                Spacer(modifier = Modifier.height(EnsuSpacing.sm.dp))
                Row {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(text = "Context length", style = EnsuTypography.small, color = EnsuColor.textMuted())
                        Spacer(modifier = Modifier.height(EnsuSpacing.xs.dp))
                        OutlinedTextField(
                            value = contextLength,
                            onValueChange = { contextLength = it },
                            placeholder = { Text(text = "8192") },
                            modifier = Modifier.fillMaxWidth(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                        )
                    }
                    Spacer(modifier = Modifier.width(EnsuSpacing.md.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(text = "Max output", style = EnsuTypography.small, color = EnsuColor.textMuted())
                        Spacer(modifier = Modifier.height(EnsuSpacing.xs.dp))
                        OutlinedTextField(
                            value = maxTokens,
                            onValueChange = { maxTokens = it },
                            placeholder = { Text(text = "2048") },
                            modifier = Modifier.fillMaxWidth(),
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                        )
                    }
                }

                Spacer(modifier = Modifier.height(EnsuSpacing.md.dp))
                Text(text = "Temperature", style = EnsuTypography.small, color = EnsuColor.textMuted())
                Spacer(modifier = Modifier.height(EnsuSpacing.xs.dp))
                OutlinedTextField(
                    value = temperature,
                    onValueChange = { temperature = it },
                    placeholder = { Text(text = "0.7") },
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
                )

                Spacer(modifier = Modifier.height(EnsuSpacing.sm.dp))
                Text(text = "Leave blank to use model defaults", style = EnsuTypography.small, color = EnsuColor.textMuted())
                Spacer(modifier = Modifier.height(EnsuSpacing.xs.dp))
                Text(
                    text = "Values below 0.35 or above 0.7 are clamped automatically.",
                    style = EnsuTypography.small,
                    color = EnsuColor.textMuted()
                )
            }
        }

        Spacer(modifier = Modifier.height(EnsuSpacing.xl.dp))
        HorizontalDivider()
        Spacer(modifier = Modifier.height(EnsuSpacing.lg.dp))

        Button(
            onClick = {
                val savedState = state.copy(
                    modelId = selectedModel.id.takeUnless { selectedModel.isDefault }.orEmpty(),
                    contextLength = contextLength,
                    maxTokens = maxTokens,
                    temperature = temperature
                )
                onSave(savedState)
                Toast.makeText(context, "Model settings saved", Toast.LENGTH_SHORT).show()
            },
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(containerColor = EnsuColor.accent())
        ) {
            Text(text = "Save Model Settings", style = EnsuTypography.body)
        }

        Spacer(modifier = Modifier.height(EnsuSpacing.md.dp))

        TextButton(onClick = {
            onReset()
            selectedModelId = DEFAULT_OPTION_ID
            contextLength = ""
            maxTokens = ""
            temperature = ""
            Toast.makeText(context, "Model settings reset", Toast.LENGTH_SHORT).show()
        }) {
            Text(text = "Reset to defaults", style = EnsuTypography.body, color = EnsuColor.action())
        }

        Spacer(modifier = Modifier.height(EnsuSpacing.md.dp))
        Text(
            text = "Changes apply the next time the model loads.",
            style = EnsuTypography.small,
            color = EnsuColor.textMuted()
        )
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(text = title, style = EnsuTypography.body)
}

@Composable
private fun ExpandButton(
    title: String,
    expanded: Boolean,
    collapsedHint: String,
    onToggle: () -> Unit
) {
    TextButton(onClick = onToggle, modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.fillMaxWidth()) {
            Text(text = title, style = EnsuTypography.body, color = EnsuColor.action())
            if (!expanded) {
                Spacer(modifier = Modifier.height(EnsuSpacing.xs.dp))
                Text(text = collapsedHint, style = EnsuTypography.small, color = EnsuColor.textMuted())
            }
        }
    }
}

private data class ModelChoice(
    val id: String,
    val title: String,
    val isDefault: Boolean = false
)

private fun initialSelectionId(
    state: ModelSettingsState,
    choices: List<ModelChoice>
): String {
    return choices.firstOrNull { it.id == state.modelId }?.id ?: DEFAULT_OPTION_ID
}

private const val DEFAULT_OPTION_ID = "default"
