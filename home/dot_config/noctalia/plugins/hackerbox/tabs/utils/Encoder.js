// Pure JS encoding/decoding functions
. pragma library

function encode(text, algo) {
    switch (algo) {
        case "Base64":
            return Qt.btoa(text);
        case "URL":
            return encodeURIComponent(text);
        case "Hex":
            return Array.from(text).map(c => 
                c.charCodeAt(0).toString(16).padStart(2, '0')
            ).join('');
        default:
            return text;
    }
}

function decode(text, algo) {
    try {
        switch (algo) {
            case "Base64": 
                return Qt. atob(text);
            case "URL":
                return decodeURIComponent(text);
            case "Hex": 
                return text.match(/.{1,2}/g)?.map(b => 
                    String.fromCharCode(parseInt(b, 16))
                ).join('') ??  "";
            default: 
                return text;
        }
    } catch (e) {
        return "Error:  Invalid " + algo;
    }
}
