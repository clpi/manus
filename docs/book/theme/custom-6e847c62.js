document.addEventListener('DOMContentLoaded', function() {
    if (typeof window.hljs !== 'undefined') {
        // Define a dedicated Duo language for highlight.js.
        // It is a superset of Lua with typed-function, match, async, enum,
        // attribute, and type-annotation syntax.
        window.hljs.registerLanguage('duo', function(hljs) {
            const LITERALS = ['true', 'false', 'nil'];

            // Lua core keywords + Duo additions.
            const KEYWORDS = {
                keyword:
                    'and break do else elseif end false for function fun global goto ' +
                    'if in local nil not or repeat return then true until while ' +
                    'const enum match try catch defer async await concept alias private extends',
                type:
                    'i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool void str int float string Table table List list any'
            };

            // Long bracket strings: [[ ... ]], [==[ ... ]==], etc.
            const LONG_STRING = {
                className: 'string',
                begin: /\[(=*)\[/,
                end: /\]\1\]/,
                contains: [hljs.BACKSLASH_ESCAPE]
            };

            return {
                name: 'Duo',
                aliases: ['duo'],
                case_insensitive: false,
                keywords: KEYWORDS,
                literals: LITERALS,
                illegal: /\/\*/,
                contains: [
                    // Block comments: --[[ ... ]], --[==[ ... ]==]
                    {
                        className: 'comment',
                        begin: /--\[(=*)\[/,
                        end: /\]\1\]/,
                        contains: [hljs.PHRASAL_WORDS_MODE]
                    },
                    // Line comments: -- ...
                    hljs.COMMENT('--', '$'),
                    LONG_STRING,
                    // Double- and single-quoted strings.
                    hljs.QUOTE_STRING_MODE,
                    hljs.APOS_STRING_MODE,
                    // Integer and float literals, including hex, binary, and type suffixes.
                    {
                        className: 'number',
                        variants: [
                            { begin: /\b0[xX][0-9a-fA-F]+\b/ },
                            { begin: /\b0[bB][01]+\b/ },
                            { begin: /\b\d+(?:\.\d*)?(?:[eE][+-]?\d+)?[fFdD]?\d*\b/ },
                            { begin: /\b\.\d+(?:[eE][+-]?\d+)?\b/ },
                            { begin: /\b\d+[iu]\d+\b/ }
                        ],
                        relevance: 0
                    },
                    // Attributes: @export, @inline("msg"), etc.
                    {
                        className: 'meta',
                        begin: /@[A-Za-z_]\w*/,
                        contains: [
                            {
                                begin: /\(/,
                                end: /\)/,
                                contains: [
                                    hljs.QUOTE_STRING_MODE,
                                    hljs.APOS_STRING_MODE,
                                    LONG_STRING
                                ]
                            }
                        ]
                    },
                    // Labels and goto targets: ::label::
                    {
                        className: 'symbol',
                        begin: /::[A-Za-z_]\w*::/
                    },
                    // Operators (listed to reduce accidental breakage of single-char matches).
                    {
                        className: 'operator',
                        begin: /\.{2,3}|->|=>|::|==|~=|<=|>=|<<|>>|\/\/|[+\-*\/%^#&|~<>!=]/
                    }
                ]
            };
        });

        // Highlight every code block the browser marked as Duo.
        if (document.querySelectorAll) {
            document.querySelectorAll('pre code.language-duo').forEach(function(block) {
                window.hljs.highlightElement(block);
            });
        }
    }
});
