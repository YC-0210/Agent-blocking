# Version the chat selector resource

The user still saw an English selector after the Traditional Chinese build.
Fresh isolated browser checks confirmed that the current artifact rendered Chinese
even with an English browser locale, but every build advertised the same
`ui://docard/focus-timeline.html` address. The chat host could reuse an older UI
resource or retain an already-loaded selector. The earlier claim that a fresh
tool call alone necessarily loaded the new language was incorrect.

The MCP server now captures the built HTML at initialization and uses a content
hash in the resource URI. Both picker tools and their app-only tools share that
version. Resource bytes are pinned to that address for the server's lifetime;
changing the build requires a client reload and creates a new address. The build
script publishes HTML atomically so a newly starting server cannot read a partly
written resource. The isolated host resolves the URI from advertised tool
metadata instead of hardcoding the old address.

Validation: the existing public MCP test failed on the old stable resource URI,
then passed with the versioned address. All 113 Node tests pass. A newly started
isolated host loaded the advertised resource and displayed Chinese session and
maximum controls under an English browser locale. Fresh real stdio initialization
also retained the shared phone and draft-only behavior. No phone build or blocking
command is involved in this fix.

Current recording artifact remains built with `DO_CARD_DEMO_LANGUAGE=zh-Hant`.
The user must restart Codex once to reload the updated tool/resource metadata,
then open a new selector. Previously opened inline widgets keep their old code.
Live chat rendering after that restart still awaits user verification. Inline
widgets were not available to the MCP Apps inspection surface, so isolated UI
proof must not be presented as a screenshot of the user's current chat.

Evidence: `/tmp/docard-picker-cache-{red,node,browser,stdio}.log`.
