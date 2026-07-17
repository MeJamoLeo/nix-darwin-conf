// HTML escape utility — prevents XSS from API data in innerHTML
function escHtml(s) {
    if (typeof s !== 'string') return String(s);
    return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
