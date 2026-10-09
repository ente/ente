use llama_cpp_2::model::LlamaModel;

use super::{ChatMessage, Error, chat_template_bridge, format_error};

pub(super) fn build_chat_prompt(
    model: &LlamaModel,
    messages: Vec<ChatMessage>,
    template_override: Option<String>,
    add_assistant: bool,
) -> Result<String, Error> {
    let source = match template_override {
        Some(template) => template,
        None => model
            .chat_template(None)
            .ok()
            .and_then(|template| template.to_string().ok())
            .unwrap_or_else(|| "chatml".to_owned()),
    };
    let vocab = model.vocab();
    let special_token = |token: llama_cpp_2::token::LlamaToken| {
        if token.0 < 0 {
            return Ok(String::new());
        }
        String::from_utf8(vocab.token_to_piece(token, true, None))
            .map_err(|err| Error::InvalidInput(format_error("Invalid special token", err)))
    };
    render(
        &source,
        &special_token(vocab.bos())?,
        &special_token(vocab.eos())?,
        &messages,
        add_assistant,
    )
}

fn render(
    source: &str,
    bos: &str,
    eos: &str,
    messages: &[ChatMessage],
    add_assistant: bool,
) -> Result<String, Error> {
    let messages = serde_json::to_string(messages)
        .map_err(|err| Error::InvalidInput(format_error("Invalid chat messages", err)))?;
    chat_template_bridge::render(source, bos, eos, &messages, add_assistant)
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fixture {
        model_id: &'static str,
        template: &'static str,
        bos: &'static str,
        eos: &'static str,
    }

    fn message(role: &str, content: &str) -> ChatMessage {
        ChatMessage {
            role: role.to_owned(),
            content: content.to_owned(),
        }
    }

    #[test]
    fn default_templates_preserve_turns_unicode_images_and_assistant_prefixes() {
        for fixture in DEFAULT_TEMPLATES {
            let messages = [
                message("system", "Be concise."),
                message("user", "नमस्ते 🐈\n<__media__>"),
                message("assistant", "A cat."),
                message("user", "What colour?"),
            ];
            let gemma = fixture.model_id.starts_with("gemma");
            let (start, end, assistant) = if gemma {
                ("<|turn>", "<turn|>", "model")
            } else {
                ("<|im_start|>", "<|im_end|>", "assistant")
            };
            let mut expected = fixture.bos.to_owned();
            for msg in &messages {
                let role = if msg.role == "assistant" {
                    assistant
                } else {
                    &msg.role
                };
                expected.push_str(&format!("{start}{role}\n{}{end}\n", msg.content));
            }
            for add_assistant in [false, true] {
                let prompt = render(
                    fixture.template,
                    fixture.bos,
                    fixture.eos,
                    &messages,
                    add_assistant,
                )
                .unwrap();
                let expected = if add_assistant {
                    format!("{expected}{start}{assistant}\n")
                } else {
                    expected.clone()
                };
                assert_eq!(
                    prompt, expected,
                    "{}: add_assistant={add_assistant}",
                    fixture.model_id
                );
            }
        }
    }

    #[test]
    fn overrides_receive_a_boolean_false_and_special_tokens() {
        assert_eq!(
            render("llama2", "", "", &[message("user", "Hi")], true).unwrap(),
            "[INST] Hi [/INST]"
        );
        let template = "{{ bos_token }}{% if enable_thinking is not defined or enable_thinking %}THINKING{% else %}DIRECT{% endif %}:{{ messages[0].content }}{{ eos_token }}{% if add_generation_prompt %}ASSISTANT{% endif %}";
        let prompt = render(
            template,
            "<bos>",
            "<eos>",
            &[message("user", "你好\n<__media__>")],
            true,
        )
        .unwrap();
        assert_eq!(prompt, "<bos>DIRECT:你好\n<__media__><eos>ASSISTANT");
    }

    #[test]
    fn template_errors_are_returned_and_subsequent_renders_recover() {
        assert!(render("{% if %}", "", "", &[message("user", "Hi")], true).is_err());
        assert!(render("bad\0template", "", "", &[], true).is_err());
        assert!(render("llama2", "", "", &[message("user", "Hi\0there")], true).is_err());
        let messages = [message("user", "Hello")];
        for template in ["", "chatml"] {
            assert_eq!(
                render(template, "", "", &messages, true).unwrap(),
                "<|im_start|>user\nHello<|im_end|>\n<|im_start|>assistant\n"
            );
        }
    }

    const DEFAULT_TEMPLATES: &[Fixture] = &[
        Fixture {
            model_id: "lfm-vl-1.6b",
            template: concat!(
                "{{- bos_token -}}\n{%- set keep_past_thinking = keep_past_thinking | default(false) -%}\n{%- set ns = namespace(system_prompt=\"\") -%}\n{%- if messages[0][\"role\"] == \"system\" -%}\n    {%- set sys_content = ",
                "messages[0][\"content\"] -%}\n    {%- if sys_content is not string -%}\n        {%- for item in sys_content -%}\n            {%- if item[\"type\"] == \"text\" -%}\n                {%- set ns.system_prompt = ns.system_prompt + ",
                "item[\"text\"] -%}\n            {%- endif -%}\n        {%- endfor -%}\n    {%- else -%}\n        {%- set ns.system_prompt = sys_content -%}\n    {%- endif -%}\n    {%- set messages = messages[1:] -%}\n{%- endif -%}\n{%- if tools ",
                "-%}\n    {%- set ns.system_prompt = ns.system_prompt + (\"\\n\" if ns.system_prompt else \"\") + \"List of tools: [\" -%}\n    {%- for tool in tools -%}\n        {%- if tool is not string -%}\n            {%- set tool = tool | ",
                "tojson -%}\n        {%- endif -%}\n        {%- set ns.system_prompt = ns.system_prompt + tool -%}\n        {%- if not loop.last -%}\n            {%- set ns.system_prompt = ns.system_prompt + \", \" -%}\n        {%- endif -%}\n  ",
                "  {%- endfor -%}\n    {%- set ns.system_prompt = ns.system_prompt + \"]\" -%}\n{%- endif -%}\n{%- if ns.system_prompt -%}\n    {{- \"<|im_start|>system\\n\" + ns.system_prompt + \"<|im_end|>\\n\" -}}\n{%- endif -%}\n{%- set ",
                "ns.last_assistant_index = -1 -%}\n{%- for message in messages -%}\n    {%- if message[\"role\"] == \"assistant\" -%}\n        {%- set ns.last_assistant_index = loop.index0 -%}\n    {%- endif -%}\n{%- endfor -%}\n{%- for message ",
                "in messages -%}\n    {{- \"<|im_start|>\" + message[\"role\"] + \"\\n\" -}}\n    {%- set content = message[\"content\"] -%}\n    {%- if content is not string -%}\n        {%- set ns.content = \"\" -%}\n        {%- for item in content ",
                "-%}\n            {%- if item[\"type\"] == \"image\" -%}\n                {%- set ns.content = ns.content + \"<image>\" -%}\n            {%- elif item[\"type\"] == \"text\" -%}\n                {%- set ns.content = ns.content + ",
                "item[\"text\"] -%}\n            {%- else -%}\n                {%- set ns.content = ns.content + item | tojson -%}\n            {%- endif -%}\n        {%- endfor -%}\n        {%- set content = ns.content -%}\n    {%- endif -%}\n  ",
                "  {%- if message[\"role\"] == \"assistant\" and not keep_past_thinking and loop.index0 != ns.last_assistant_index -%}\n        {%- if \"</think>\" in content -%}\n            {%- set content = content.split(\"</think>\")[-1] | ",
                "trim -%}\n        {%- endif -%}\n    {%- endif -%}\n    {{- content + \"<|im_end|>\\n\" -}}\n{%- endfor -%}\n{%- if add_generation_prompt -%}\n    {{- \"<|im_start|>assistant\\n\" -}}\n{%- endif -%}",
            ),
            bos: "<|startoftext|>",
            eos: "<|im_end|>",
        },
        Fixture {
            model_id: "gemma-4-e2b-q4km",
            template: concat!(
                "{%- macro format_parameters(properties, required, filter_keys=false) -%}\n    {%- set standard_keys = ['description', 'type', 'properties', 'required', 'nullable'] -%}\n    {%- set ns = namespace(found_first=false) -%}\n   ",
                " {%- for key, value in properties | dictsort -%}\n        {%- set add_comma = false -%}\n        {%- if not filter_keys or key not in standard_keys -%}\n            {%- if ns.found_first %},{% endif -%}\n            {%- set ",
                "ns.found_first = true -%}\n            {{ key }}:{\n            {%- if value['description'] -%}\n                description:<|\"|>{{ value['description'] }}<|\"|>\n                {%- set add_comma = true -%}\n            {%- ",
                "endif -%}\n            {%- if value['type'] | upper == 'STRING' -%}\n                {%- if value['enum'] -%}\n                    {%- if add_comma %},{%- else -%} {%- set add_comma = true -%} {% endif -%}\n                 ",
                "   enum:{{ format_argument(value['enum']) }}\n                {%- endif -%}\n            {%- elif value['type'] | upper == 'ARRAY' -%}\n                {%- if value['items'] is mapping and value['items'] -%}\n               ",
                "     {%- if add_comma %},{%- else -%} {%- set add_comma = true -%} {% endif -%}\n                    items:{\n                    {%- set ns_items = namespace(found_first=false) -%}\n                    {%- for item_key, ",
                "item_value in value['items'] | dictsort -%}\n                        {%- if item_value is not none -%}\n                            {%- if ns_items.found_first %},{% endif -%}\n                            {%- set ",
                "ns_items.found_first = true -%}\n                            {%- if item_key == 'properties' -%}\n                                properties:{\n                                {%- if item_value is mapping -%}\n              ",
                "                      {{- format_parameters(item_value, value['items']['required'] | default([])) -}}\n                                {%- endif -%}\n                                }\n                            {%- elif ",
                "item_key == 'required' -%}\n                                required:[\n                                {%- for req_item in item_value -%}\n                                    <|\"|>{{- req_item -}}<|\"|>\n                    ",
                "                {%- if not loop.last %},{% endif -%}\n                                {%- endfor -%}\n                                ]\n                            {%- elif item_key == 'type' -%}\n                          ",
                "      {%- if item_value is string -%}\n                                    type:{{ format_argument(item_value | upper) }}\n                                {%- else -%}\n                                    type:{{ ",
                "format_argument(item_value | map('upper') | list) }}\n                                {%- endif -%}\n                            {%- else -%}\n                                {{ item_key }}:{{ format_argument(item_value) ",
                "}}\n                            {%- endif -%}\n                        {%- endif -%}\n                    {%- endfor -%}\n                    }\n                {%- endif -%}\n            {%- endif -%}\n            {%- if ",
                "value['nullable'] %}\n                {%- if add_comma %},{%- else -%} {%- set add_comma = true -%} {% endif -%}\n                nullable:true\n            {%- endif -%}\n            {%- if value['type'] | upper == ",
                "'OBJECT' -%}\n                {%- if value['properties'] is defined and value['properties'] is mapping -%}\n                    {%- if add_comma %},{%- else -%} {%- set add_comma = true -%} {% endif -%}\n                   ",
                " properties:{\n                    {{- format_parameters(value['properties'], value['required'] | default([])) -}}\n                    }\n                {%- elif value is mapping -%}\n                    {%- if add_comma ",
                "%},{%- else -%} {%- set add_comma = true -%} {% endif -%}\n                    properties:{\n                    {{- format_parameters(value, value['required'] | default([]), filter_keys=true) -}}\n                    }\n   ",
                "             {%- endif -%}\n                {%- if value['required'] -%}\n                    {%- if add_comma %},{%- else -%} {%- set add_comma = true -%} {% endif -%}\n                    required:[\n                    ",
                "{%- for item in value['required'] | default([]) -%}\n                        <|\"|>{{- item -}}<|\"|>\n                        {%- if not loop.last %},{% endif -%}\n                    {%- endfor -%}\n                    ]\n   ",
                "             {%- endif -%}\n            {%- endif -%}\n            {%- if add_comma %},{%- else -%} {%- set add_comma = true -%} {% endif -%}\n            type:<|\"|>{{ value['type'] | upper }}<|\"|>}\n        {%- endif -%}\n  ",
                "  {%- endfor -%}\n{%- endmacro -%}\n{%- macro format_function_declaration(tool_data) -%}\n    declaration:{{- tool_data['function']['name'] -}}{description:<|\"|>{{- tool_data['function']['description'] -}}<|\"|>\n    {%- set ",
                "params = tool_data['function']['parameters'] -%}\n    {%- if params -%}\n        ,parameters:{\n        {%- if params['properties'] -%}\n            properties:{ {{- format_parameters(params['properties'], ",
                "params['required']) -}} },\n        {%- endif -%}\n        {%- if params['required'] -%}\n            required:[\n            {%- for item in params['required'] -%}\n                <|\"|>{{- item -}}<|\"|>\n                {{- ",
                "',' if not loop.last -}}\n            {%- endfor -%}\n            ],\n        {%- endif -%}\n        {%- if params['type'] -%}\n            type:<|\"|>{{- params['type'] | upper -}}<|\"|>}\n        {%- endif -%}\n    {%- endif ",
                "-%}\n    {%- if 'response' in tool_data['function'] -%}\n        {%- set response_declaration = tool_data['function']['response'] -%}\n        ,response:{\n        {%- if response_declaration['description'] -%}\n            ",
                "description:<|\"|>{{- response_declaration['description'] -}}<|\"|>,\n        {%- endif -%}\n        {%- if response_declaration['type'] | upper == 'OBJECT' -%}\n            type:<|\"|>{{- response_declaration['type'] | upper ",
                "-}}<|\"|>}\n        {%- endif -%}\n    {%- endif -%}\n    }\n{%- endmacro -%}\n{%- macro format_argument(argument, escape_keys=True) -%}\n    {%- if argument is none -%}\n        {{- 'null' -}}\n    {%- elif argument is string ",
                "-%}\n        {{- '<|\"|>' + argument + '<|\"|>' -}}\n    {%- elif argument is boolean -%}\n        {{- 'true' if argument else 'false' -}}\n    {%- elif argument is mapping -%}\n        {{- '{' -}}\n        {%- set ns = ",
                "namespace(found_first=false) -%}\n        {%- for key, value in argument | dictsort -%}\n            {%- if ns.found_first %},{% endif -%}\n            {%- set ns.found_first = true -%}\n            {%- if escape_keys -%}\n  ",
                "              {{- '<|\"|>' + key + '<|\"|>' -}}\n            {%- else -%}\n                {{- key -}}\n            {%- endif -%}\n            :{{- format_argument(value, escape_keys=escape_keys) -}}\n        {%- endfor -%}\n   ",
                "     {{- '}' -}}\n    {%- elif argument is sequence -%}\n        {{- '[' -}}\n        {%- for item in argument -%}\n            {{- format_argument(item, escape_keys=escape_keys) -}}\n            {%- if not loop.last %},{% ",
                "endif -%}\n        {%- endfor -%}\n        {{- ']' -}}\n    {%- else -%}\n        {{- argument -}}\n    {%- endif -%}\n{%- endmacro -%}\n{%- macro strip_thinking(text) -%}\n    {%- set ns = namespace(result='') -%}\n    {%- for ",
                "part in text.split('<channel|>') -%}\n        {%- if '<|channel>' in part -%}\n            {%- set ns.result = ns.result + part.split('<|channel>')[0] -%}\n        {%- else -%}\n            {%- set ns.result = ns.result + ",
                "part -%}\n        {%- endif -%}\n    {%- endfor -%}\n    {{- ns.result | trim -}}\n{%- endmacro -%}\n\n{%- macro format_tool_response_block(tool_name, response) -%}\n    {{- '<|tool_response>' -}}\n    {%- if response is ",
                "mapping -%}\n        {{- 'response:' + tool_name + '{' -}}\n        {%- for key, value in response | dictsort -%}\n            {{- key -}}:{{- format_argument(value, escape_keys=False) -}}\n            {%- if not loop.last ",
                "%},{% endif -%}\n        {%- endfor -%}\n        {{- '}' -}}\n    {%- else -%}\n        {{- 'response:' + tool_name + '{value:' + format_argument(response, escape_keys=False) + '}' -}}\n    {%- endif -%}\n    {{- ",
                "'<tool_response|>' -}}\n{%- endmacro -%}\n\n{#- ===== SETUP ===== -#}\n{%- set ns = namespace(prev_message_type=None, prev_non_tool_role=None) -%}\n{%- set loop_messages = messages -%}\n{%- set enable_thinking = ",
                "enable_thinking | default(false) -%}\n{%- set preserve_thinking = preserve_thinking | default(false) -%}\n{{- bos_token -}}\n{#- Handle System/Tool Definitions Block -#}\n{%- if enable_thinking or tools or (messages and ",
                "messages[0]['role'] in ['system', 'developer']) -%}\n    {{- '<|turn>system\\n' -}}\n    {#- Inject Thinking token at the very top of the FIRST system turn -#}\n    {%- if enable_thinking -%}\n        {{- '<|think|>\\n' -}}\n  ",
                "      {%- set ns.prev_message_type = 'think' -%}\n    {%- endif -%}\n    {%- if messages and messages[0]['role'] in ['system', 'developer'] -%}\n        {%- if messages[0]['content'] is string -%}\n            {{- ",
                "messages[0]['content'] | trim -}}\n        {%- elif messages[0]['content'] is sequence -%}\n            {%- for item in messages[0]['content'] -%}\n                {{- item['text'] | trim + ' '-}}\n            {%- endfor ",
                "-%}\n        {%- endif -%}\n        {%- set loop_messages = messages[1:] -%}\n    {%- endif -%}\n    {%- if tools -%}\n        {%- for tool in tools %}\n            {{- '<|tool>' -}}\n            {{- ",
                "format_function_declaration(tool) | trim -}}\n            {{- '<tool|>' -}}\n        {%- endfor %}\n        {%- set ns.prev_message_type = 'tool' -%}\n    {%- endif -%}\n    {{- '<turn|>\\n' -}}\n{%- endif %}\n\n{#- Pre-scan: ",
                "find last user message index for reasoning guard -#}\n{%- set ns_turn = namespace(last_user_idx=-1) -%}\n{%- for i in range(loop_messages | length) -%}\n    {%- if loop_messages[i]['role'] == 'user' -%}\n        {%- set ",
                "ns_turn.last_user_idx = i -%}\n    {%- endif -%}\n{%- endfor -%}\n\n{#- Loop through messages -#}\n{%- for message in loop_messages -%}\n    {%- if message['role'] != 'tool' -%}\n    {%- set ns.prev_message_type = None -%}\n    ",
                "{%- set role = 'model' if message['role'] == 'assistant' else message['role'] -%}\n    {#- Detect continuation using tracked state — O(1) instead of O(n) backward scan -#}\n    {%- set continue_same_model_turn = (role == ",
                "'model' and ns.prev_non_tool_role == 'assistant') -%}\n    {%- if not continue_same_model_turn -%}\n        {{- '<|turn>' + role + '\\n' }}\n    {%- endif -%}\n\n    {#- Render reasoning/reasoning_content as thinking channel ",
                "-#}\n    {%- set thinking_text = message.get('reasoning') or message.get('reasoning_content') -%}\n    {%- set thinking_gate = (loop.index0 > ns_turn.last_user_idx) or (preserve_thinking and message.get('tool_calls')) -%}\n",
                "    {%- if thinking_text and thinking_gate -%}\n        {{- '<|channel>thought\\n' + thinking_text + '\\n<channel|>' -}}\n    {%- endif -%}\n\n            {%- if message.get('tool_calls') -%}\n                {%- for tool_call ",
                "in message.get('tool_calls') -%}\n                    {%- set function = tool_call['function'] -%}\n                    {{- '<|tool_call>call:' + function['name'] + '{' -}}\n                    {%- if function['arguments'] ",
                "is mapping -%}\n                        {%- set ns_args = namespace(found_first=false) -%}\n                        {%- for key, value in function['arguments'] | dictsort -%}\n                            {%- if ",
                "ns_args.found_first %},{% endif -%}\n                            {%- set ns_args.found_first = true -%}\n                            {{- key -}}:{{- format_argument(value, escape_keys=False) -}}\n                        ",
                "{%- endfor -%}\n                    {%- elif function['arguments'] is none -%}\n                    {%- elif function['arguments'] is string -%}\n                        {#- Pre-serialized args (e.g. an OpenAI JSON ",
                "string). We cannot JSON-parse\n                            portably in-template, so render non-fatally instead of erroring. Strip an\n                            outer {...} so it composes with the DSL braces rather than ",
                "double-wrapping.\n                            Prefer passing arguments as a mapping for exact Gemma DSL. -#}\n                        {%- set argstr = function['arguments'] | trim -%}\n                        {%- if ",
                "argstr[:1] == '{' and argstr[-1:] == '}' -%}\n                            {{- argstr[1:-1] -}}\n                        {%- else -%}\n                            {{- function['arguments'] -}}\n                        {%- ",
                "endif -%}\n                    {%- endif -%}\n                    {{- '}<tool_call|>' -}}\n                {%- endfor -%}\n                {%- set ns.prev_message_type = 'tool_call' -%}\n            {%- endif -%}\n\n           ",
                " {%- set ns_tr_out = namespace(flag=false) -%}\n            {%- if message.get('tool_responses') -%}\n                {#- Legacy: tool_responses embedded on the assistant message (Google/Gemma native) -#}\n                ",
                "{%- for tool_response in message.get('tool_responses') -%}\n                    {{- format_tool_response_block(tool_response['name'] | default('unknown', true), tool_response['response']) -}}\n                    {%- set ",
                "ns_tr_out.flag = true -%}\n                    {%- set ns.prev_message_type = 'tool_response' -%}\n                {%- endfor -%}\n            {%- elif message.get('tool_calls') -%}\n                {#- OpenAI Chat ",
                "Completions: forward-scan consecutive role:tool messages -#}\n                {%- set ns_tool_scan = namespace(stopped=false) -%}\n                {%- for k in range(loop.index0 + 1, loop_messages | length) -%}\n           ",
                "         {%- if ns_tool_scan.stopped -%}\n                    {%- elif loop_messages[k]['role'] != 'tool' -%}\n                        {%- set ns_tool_scan.stopped = true -%}\n                    {%- else -%}\n              ",
                "          {%- set follow = loop_messages[k] -%}\n                        {#- Resolve tool_call_id to function name -#}\n                        {%- set ns_tname = namespace(name=follow.get('name') or 'unknown') -%}\n       ",
                "                 {%- for tc in message.get('tool_calls') -%}\n                            {%- if tc.get('id') == follow.get('tool_call_id') -%}\n                                {%- set ns_tname.name = ",
                "tc['function']['name'] -%}\n                            {%- endif -%}\n                        {%- endfor -%}\n                        {#- Handle content as string or content-parts array -#}\n                        {%- set ",
                "tool_body = follow.get('content') -%}\n                        {%- if tool_body is string -%}\n                            {{- format_tool_response_block(ns_tname.name, tool_body) -}}\n                        {%- elif ",
                "tool_body is sequence and tool_body is not string -%}\n                            {%- set ns_txt = namespace(s='') -%}\n                            {%- for part in tool_body -%}\n                                {%- if ",
                "part.get('type') == 'text' -%}\n                                    {%- set ns_txt.s = ns_txt.s + (part.get('text') | default('')) -%}\n                                {%- endif -%}\n                            {%- endfor ",
                "-%}\n                            {{- format_tool_response_block(ns_tname.name, ns_txt.s) -}}\n                            {%- for part in tool_body -%}\n                                {%- if part.get('type') in ['image', ",
                "'image_url'] -%}\n                                    {{- '<|image|>' -}}\n                                {%- elif part.get('type') in ['audio', 'input_audio'] -%}\n                                    {{- '<|audio|>' -}}\n ",
                "                               {%- elif part.get('type') == 'video' -%}\n                                    {{- '<|video|>' -}}\n                                {%- endif -%}\n                            {%- endfor -%}\n   ",
                "                     {%- else -%}\n                            {{- format_tool_response_block(ns_tname.name, tool_body) -}}\n                        {%- endif -%}\n                        {%- set ns_tr_out.flag = true -%}\n ",
                "                       {%- set ns.prev_message_type = 'tool_response' -%}\n                    {%- endif -%}\n                {%- endfor -%}\n            {%- endif -%}\n\n            {%- set captured_content -%}\n            ",
                "{%- if message.get('content') is string -%}\n                {%- if role == 'model' -%}\n                    {{- strip_thinking(message['content']) -}}\n                {%- else -%}\n                    {{- ",
                "message['content'] | trim -}}\n                {%- endif -%}\n            {%- elif message.get('content') is sequence -%}\n                {%- for item in message['content'] -%}\n                    {%- if item.get('type') ",
                "== 'text' -%}\n                        {%- if role == 'model' -%}\n                            {{- strip_thinking(item['text']) -}}\n                        {%- else -%}\n                            {{- item['text'] | trim ",
                "-}}\n                        {%- endif -%}\n                    {%- elif item.get('type') in ['image', 'image_url'] -%}\n                        {{- '<|image|>' -}}\n                    {%- elif item.get('type') in ",
                "['audio', 'input_audio'] -%}\n                        {{- '<|audio|>' -}}\n                    {%- elif item.get('type') == 'video' -%}\n                        {{- '<|video|>' -}}\n                    {%- endif -%}\n        ",
                "        {%- endfor -%}\n            {%- endif -%}\n            {%- endset -%}\n\n            {{- captured_content -}}\n            {%- set has_content = captured_content | trim | length > 0 -%}\n\n        {#- Forward-scan: ",
                "find next non-tool message role for continuation detection -#}\n        {%- set next_nt = namespace(role=None, found=false) -%}\n        {%- for j in range(loop.index0 + 1, loop_messages | length) -%}\n            {%- if ",
                "not next_nt.found -%}\n                {%- if loop_messages[j]['role'] != 'tool' -%}\n                    {%- set next_nt.role = loop_messages[j]['role'] -%}\n                    {%- set next_nt.found = true -%}\n           ",
                "     {%- endif -%}\n            {%- endif -%}\n        {%- endfor -%}\n\n        {%- set continues_into_next = (\n            role == 'model'\n            and next_nt.role == 'assistant'\n            and (not ",
                "message.get('tool_calls') or ns_tr_out.flag)\n        ) -%}\n\n        {%- if ns.prev_message_type == 'tool_call' and not ns_tr_out.flag -%}\n            {{- '<|tool_response>' -}}\n        {%- elif continues_into_next -%}\n  ",
                "      {%- elif not (ns_tr_out.flag and not has_content and not next_nt.found) -%}\n            {{- '<turn|>\\n' -}}\n        {%- endif -%}\n\n    {#- Track previous non-tool role for next iteration (avoids O(n) backward ",
                "scan) -#}\n    {%- set ns.prev_non_tool_role = message['role'] -%}\n    {%- endif -%}\n{%- endfor -%}\n\n{%- if add_generation_prompt -%}\n    {%- if ns.prev_message_type != 'tool_response' and ns.prev_message_type != ",
                "'tool_call' -%}\n        {{- '<|turn>model\\n' -}}\n    {%- elif ns.prev_message_type == 'tool_response' and enable_thinking -%}\n        {{- '<|channel>thought\\n' -}}\n    {%- endif -%}\n{%- endif -%}\n",
            ),
            bos: "<bos>",
            eos: "<turn|>",
        },
    ];
}
