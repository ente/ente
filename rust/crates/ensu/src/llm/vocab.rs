use llama_cpp_2::model::LlamaModel;
use llama_cpp_2::token::LlamaToken;

pub(super) fn single_token(model: &LlamaModel, text: &str) -> Option<LlamaToken> {
    let vocab = model.vocab();
    match vocab.tokenize(text.as_bytes(), false, true).as_slice() {
        [token] if vocab.token_to_piece(*token, true, None) == text.as_bytes() => Some(*token),
        _ => None,
    }
}
