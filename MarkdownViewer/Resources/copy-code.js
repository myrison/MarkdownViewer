(function() {
    var SVG_COPY = '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 0 1 0 1.5h-1.5a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-1.5a.75.75 0 0 1 1.5 0v1.5A1.75 1.75 0 0 1 9.25 16h-7.5A1.75 1.75 0 0 1 0 14.25Z"></path><path d="M5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0 1 14.25 11h-7.5A1.75 1.75 0 0 1 5 9.25Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25Z"></path></svg>';
    var SVG_CHECK = '<svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><path d="M13.78 4.22a.75.75 0 0 1 0 1.06l-7.25 7.25a.75.75 0 0 1-1.06 0L2.22 9.28a.751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018L6 10.94l6.72-6.72a.75.75 0 0 1 1.06 0Z"></path></svg>';

    function copyText(text) {
        var textarea = document.createElement("textarea");
        textarea.value = text;
        textarea.style.position = "fixed";
        textarea.style.opacity = "0";
        document.body.appendChild(textarea);
        textarea.select();
        document.execCommand("copy");
        document.body.removeChild(textarea);
    }

    function addCopyButtons() {
        var pres = document.querySelectorAll("pre");
        for (var i = 0; i < pres.length; i++) {
            var pre = pres[i];
            var code = pre.querySelector("code");
            if (!code) continue;
            if (pre.querySelector(".copy-code-btn")) continue;

            pre.style.position = "relative";

            var btn = document.createElement("button");
            btn.className = "copy-code-btn";
            btn.innerHTML = SVG_COPY;
            btn.title = "Copy";
            btn.setAttribute("aria-label", "Copy code to clipboard");

            (function(button, codeEl) {
                button.addEventListener("click", function(e) {
                    e.preventDefault();
                    e.stopPropagation();
                    copyText(codeEl.textContent);
                    button.innerHTML = SVG_CHECK;
                    button.classList.add("copied");
                    setTimeout(function() {
                        button.innerHTML = SVG_COPY;
                        button.classList.remove("copied");
                    }, 2000);
                });
            })(btn, code);

            pre.appendChild(btn);
        }
    }

    addCopyButtons();

    // Re-run after Mermaid/highlight.js may have modified the DOM
    if (typeof MutationObserver !== "undefined") {
        var observer = new MutationObserver(function() {
            addCopyButtons();
        });
        observer.observe(document.body, { childList: true, subtree: true });
    }
})();
