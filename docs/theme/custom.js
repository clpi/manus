document.addEventListener('DOMContentLoaded', function() {
    if (typeof window.hljs !== 'undefined') {
        window.hljs.registerAliases('duo', { languageName: 'lua' });
        document.querySelectorAll('pre code.language-duo').forEach(function(block) {
            window.hljs.highlightElement(block);
        });
    }
});
