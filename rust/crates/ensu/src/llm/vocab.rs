use llama_cpp_2::model::LlamaModel;
use llama_cpp_2::token::LlamaToken;

pub(super) fn single_token(model: &LlamaModel, text: &str) -> Option<LlamaToken> {
    let vocab = model.vocab();
    match vocab.tokenize(text.as_bytes(), false, true).as_slice() {
        [token] if vocab.token_to_piece(*token, true, None) == text.as_bytes() => Some(*token),
        _ => None,
    }
}

pub(super) fn specials(model: &LlamaModel) -> super::tools::Specials {
    let vocab = model.vocab();
    let tokens = (0..vocab.n_tokens())
        .map(LlamaToken)
        .filter(|&token| vocab.is_control(token) || vocab.is_eog(token))
        .chain([vocab.bos(), vocab.eos()])
        .filter(|token| token.0 >= 0)
        .filter_map(|token| String::from_utf8(vocab.token_to_piece(token, true, None)).ok());
    super::tools::Specials::new(tokens)
}
