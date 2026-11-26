use crate::llm::{self, ChatRequest, Context, EventSink, Generation, GenerationSummary};

pub trait PassRunner {
    fn context_size(&self) -> usize;
    fn measure(&mut self, request: &ChatRequest) -> Result<usize, llm::Error>;
    fn pass(
        &mut self,
        request: ChatRequest,
        sink: &mut dyn EventSink,
    ) -> Result<GenerationSummary, llm::Error>;
    fn cancelled(&self) -> bool;
}

pub struct ContextRunner<'a> {
    context: &'a Context,
    generation: Generation<'a>,
}

impl<'a> ContextRunner<'a> {
    pub fn begin(context: &'a Context, sink: &mut dyn EventSink) -> Self {
        Self {
            context,
            generation: context.begin(sink),
        }
    }
}

impl PassRunner for ContextRunner<'_> {
    fn context_size(&self) -> usize {
        self.context.context_size() as usize
    }

    fn measure(&mut self, request: &ChatRequest) -> Result<usize, llm::Error> {
        self.context.measure_text_chat_prompt(request)
    }

    fn pass(
        &mut self,
        request: ChatRequest,
        sink: &mut dyn EventSink,
    ) -> Result<GenerationSummary, llm::Error> {
        self.generation.pass(request, sink)
    }

    fn cancelled(&self) -> bool {
        self.generation.cancelled()
    }
}
