# VERUS LUXE source

`index.html` is the deployed file; the LUXE layer is inlined at the end of it.
These files are the editable source of that layer.

Regenerate index.html from the untouched backup after editing luxe.css / luxe.js:

    python3 tools/luxe/apply_luxe.py backup/index-truoc-nang-cap-luxe.html index.html
    npm test
