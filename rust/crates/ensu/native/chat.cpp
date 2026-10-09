#include "chat.h"

#include <cstdlib>
#include <cstring>
#include <exception>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

extern "C" {
struct ensu_chat_result {
    char * data;
    size_t len;
    int status;
};

static ensu_chat_result copy_result(const char * text, size_t len, int status) noexcept {
    auto * data = static_cast<char *>(std::malloc(len + 1));
    if (!data) {
        return {nullptr, 0, 2};
    }
    std::memcpy(data, text, len);
    data[len] = '\0';
    return {data, len, status};
}

ensu_chat_result ensu_chat_render(const char * source, const char * bos, const char * eos,
                                  const char * messages_json, bool add_assistant) noexcept {
    try {
        auto messages = common_chat_msgs_parse_oaicompat(common_json::parse(messages_json));
        std::vector<const char *> builtins(llama_chat_builtin_templates(nullptr, 0));
        llama_chat_builtin_templates(builtins.data(), builtins.size());
        for (const auto * builtin : builtins) {
            if (std::strcmp(source, builtin) != 0 || std::strcmp(source, "chatml") == 0) {
                continue;
            }
            std::vector<llama_chat_message> chat;
            for (const auto & message : messages) {
                if (message.role.find('\0') != std::string::npos || message.content.find('\0') != std::string::npos) {
                    throw std::runtime_error("Invalid built-in chat message: embedded NUL");
                }
                chat.push_back({message.role.c_str(), message.content.c_str()});
            }
            const auto length = llama_chat_apply_template(source, chat.data(), chat.size(), add_assistant, nullptr, 0);
            if (length < 0) {
                throw std::runtime_error("Failed to apply built-in chat template");
            }
            std::string prompt(length, '\0');
            const auto written = llama_chat_apply_template(source, chat.data(), chat.size(), add_assistant, prompt.data(), length);
            if (written != length) {
                throw std::runtime_error("Invalid built-in chat template output length");
            }
            return copy_result(prompt.data(), prompt.size(), 0);
        }
        auto templates = common_chat_templates_init(nullptr, source[0] ? source : "chatml", bos, eos);
        common_chat_templates_inputs inputs;
        inputs.messages = std::move(messages);
        inputs.add_generation_prompt = add_assistant;
        inputs.use_jinja = true;
        inputs.enable_thinking = false;
        inputs.chat_template_kwargs["enable_thinking"] = "false";
        inputs.add_bos = false;
        inputs.add_eos = false;
        const auto result = common_chat_templates_apply(templates.get(), inputs);
        return copy_result(result.prompt.data(), result.prompt.size(), 0);
    } catch (const std::exception & error) {
        return copy_result(error.what(), std::strlen(error.what()), 1);
    } catch (...) {
        constexpr char error[] = "Unknown chat template error";
        return copy_result(error, sizeof(error) - 1, 1);
    }
}

void ensu_chat_free(char * data) noexcept {
    std::free(data);
}
}
