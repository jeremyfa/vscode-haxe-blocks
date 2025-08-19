package;

using StringTools;

typedef BlockInfo = {

    var name:String;

    var start:Int;

    var end:Int;

    var kind:BlockKind;

    var endsWithComment:Bool;

}

enum abstract BlockKind(String) {

    var FUNCTION;

    var CLASS;

    var INTERFACE;

    var ABSTRACT;

    var ENUM;

    var TYPEDEF;

}

class ParseHaxe {

    var haxe(default,null):String;

    var cleanedHaxe(default,null):String;

    public function new(haxe:String) {

        this.haxe = haxe;

    }

/// Parse

    public var blocks:Array<BlockInfo> = null;

    var i:Int = 0;

    var len:Int = 0;

    var c:Int = 0;

    var cc:String = '';

    var after:String = '';

    var originalAfter:String = '';

    var word:String = '';

    var openBraces:Int = 0;

    var openParens:Int = 0;

    var pendingBlocks:Map<Int,BlockInfo> = null;

    public function parse():Void {

        // Generate cleaned haxe code
        cleanedHaxe = cleanCode(haxe);

        cleanedHaxe = cleanedHaxe.replace("\n", ' ').replace("\r", ' ');

        blocks = [];
        pendingBlocks = new Map();

        i = 0;
        len = haxe.length;
        c = 0;
        cc = '';
        after = '';
        word = '';

        openBraces = 0;
        openParens = 0;

        // Iterate over each character and generate tokens
        //
        while (i < len) {
            updateC();

            if (c == '{'.code) {
                openBraces++;
                i++;
            }
            else if (c == '}'.code) {
                openBraces--;
                i++;

                if (pendingBlocks.exists(blockKey())) {
                    var block = pendingBlocks.get(blockKey());
                    block.end = i;
                    updateOriginalAfter();
                    var ltrimmed = originalAfter.split('\n')[0];
                    if (ltrimmed != null) {
                        ltrimmed = ltrimmed.ltrim();
                        if (ltrimmed.startsWith('//') || ltrimmed.startsWith('/*')) {
                            block.endsWithComment = true;
                        }
                    }
                    blocks.push(block);
                    pendingBlocks.remove(blockKey());
                }
            }
            else if (c == '('.code) {
                openParens++;
                i++;
            }
            else if (c == ')'.code) {
                openParens--;
                i++;
            }
            else {
                updateCC();
                if (BLOCK_KEYWORDS_CC.exists(cc)) {
                    updateAfter(10);
                    updateWord();

                    if (BLOCK_KEYWORDS.exists(word) && (word != 'abstract' || openBraces == 0)) {
                        consumeBlockName(word);
                    }
                    else {
                        i++;
                    }
                }
                else {
                    i++;
                }
            }

        }

    }

    inline function blockKey():Int {

        return openBraces * 1000000 + openParens * 1000;

    }

    function consumeBlockName(blockWord:String) {

        var kind:BlockKind = switch blockWord {
            case 'function': FUNCTION;
            case 'class': CLASS;
            case 'interface': INTERFACE;
            case 'abstract': ABSTRACT;
            case 'enum': ENUM;
            case 'typedef': TYPEDEF;
            default: null;
        }

        var index = i;

        i += word.length;

        var isFunction = (kind == FUNCTION);
        if (isFunction) {
            updateAfter();
            if (!RE_WORD.match(after.ltrim().charAt(0))) {
                // This is an anonymous function block
                return;
            }
        }

        var iStart = i;
        while (i < len) {
            if (i > iStart || !isFunction)
                updateAfter();
            updateWord();

            if (word.length > 0) {
                i += word.length;
                if (isFunction || !BLOCK_KEYWORDS.exists(word)) {
                    var key = blockKey();

                    pendingBlocks.set(key, {
                        name: word,
                        start: index,
                        end: -1,
                        kind: kind,
                        endsWithComment: false
                    });

                    // Skip any generic type parameter
                    updateAfter();
                    if (after.ltrim().charAt(0) == '<') {
                        updateC();
                        var len = haxe.length;
                        while (c != '>'.code && i < len) {
                            i++;
                            updateC();
                        }
                        i++;
                    }

                    // Skip arguments
                    updateAfter();
                    if (after.ltrim().charAt(0) == '(') {
                        var parens = 0;
                        updateC();
                        var len = haxe.length;
                        while (i < len) {
                            i++;
                            if (c == '('.code) {
                                parens++;
                            }
                            else if (c == ')'.code) {
                                parens--;
                                if (parens == 0) {
                                    updateC();
                                    break;
                                }
                            }
                            updateC();
                        }
                    }

                    // Skip return type
                    updateAfter();
                    if (after.ltrim().charAt(0) == ':') {
                        i++;
                        updateAfter();
                        var braces = 0;
                        var lts = 0;
                        updateC();
                        var len = haxe.length;
                        var prevC = ' '.code;
                        var startsWithBrace = false;
                        if (after.ltrim().charAt(0) == '{') {
                            startsWithBrace = true;
                        }
                        while (i < len) {
                            i++;
                            if (c == '{'.code) {
                                if (lts == 0) {
                                    if (startsWithBrace) {
                                        startsWithBrace = false;
                                    }
                                    else {
                                        i--;
                                        updateC();
                                        break;
                                    }
                                }
                                braces++;
                            }
                            else if (c == '}'.code) {
                                braces--;
                                if (braces == 0 && lts == 0) {
                                    updateC();
                                    break;
                                }
                            }
                            else if (c == '<'.code) {
                                lts++;
                            }
                            else if (c == '>'.code && prevC != '-'.code) {
                                lts--;
                                if (braces == 0 && lts == 0) {
                                    updateC();
                                    break;
                                }
                            }
                            else if (c == ';'.code && braces == 0) {
                                // Function finish without being inside braces, nothing to do here
                                pendingBlocks.remove(key);
                                break;
                            }
                            prevC = c;
                            updateC();
                        }
                    }
                    else if (isFunction && after.ltrim().charAt(0) != '{') {
                        // Function with no body or no braces, nothing to do here after all
                        pendingBlocks.remove(key);
                    }

                    break;
                }
            }
            else {
                i++;
            }
        }

    }

/// Conversion helpers

    inline function updateC() {

        c = cleanedHaxe.charCodeAt(i);

    }

    inline function updateCC() {

        cc = cleanedHaxe.substr(i, 2);

    }

    inline function updateAfter(?limit:Int) {

        if (limit != null)
            after = cleanedHaxe.substr(i, limit);
        else
            after = cleanedHaxe.substring(i);

    }

    inline function updateOriginalAfter(?limit:Int) {

        if (limit != null)
            originalAfter = haxe.substr(i, limit);
        else
            originalAfter = haxe.substring(i);

    }

    inline function updateWord() {

        var result:String = '';

        if (i > 0 && RE_SEP_WORD.match(cleanedHaxe.charAt(i-1) + after)) {
            result = RE_SEP_WORD.matched(1);
        }
        else if (i == 0 && RE_WORD.match(after)) {
            result = RE_WORD.matched(0);
        }

        word = result;

    }

/// Helpers

    static function fail(error:Dynamic, pos:Int, code:String) {

        // TODO proper error formatting

        trace(error + ' (' + code.substr(pos, 100) + ')');

        throw '' + error;

    }

    static function cleanCode(code:String) {

        var i = 0;
        var c = '';
        var cc = '';
        var len = code.length;
        var inSingleLineComment = false;
        var inMultiLineComment = false;
        var inRegex = false;
        var inRegexEscapeChar = false;
        var result = new StringBuf();

        while (i < len) {

            c = code.charAt(i);
            cc = i + 1 < len ? (c + code.charAt(i + 1)) : c;

            if (inSingleLineComment) {
                if (c == "\n") {
                    inSingleLineComment = false;
                    result.add(c);
                }
                else {
                    result.add(' ');
                }
                i++;
            }
            else if (inMultiLineComment) {
                if (cc == '*/') {
                    inMultiLineComment = false;
                    result.add('*/');
                    i += 2;
                } else {
                    result.add(' ');
                    i++;
                }
            }
            else if (inRegex) {
                if (inRegexEscapeChar) {
                    inRegexEscapeChar = false;
                    result.add(c);
                    i++;
                }
                else if (c == '\\') {
                    inRegexEscapeChar = true;
                    result.add(c);
                    i++;
                }
                else if (c == '/') {
                    inRegex = false;
                    result.add('/');
                    i++;
                }
                else {
                    result.add(c);
                    i++;
                }
            }
            else if (cc == '//') {
                inSingleLineComment = true;
                result.add('//');
                i += 2;
            }
            else if (cc == '/*') {
                inMultiLineComment = true;
                result.add('/*');
                i += 2;
            }
            else if (cc == '~/') {
                inRegex = true;
                result.add('~/');
                i += 2;
            }
            else if (c == '"') {
                i = cleanDoubleQuotedString(i, code, result);
            }
            else if (c == '\'') {
                i = cleanSingleQuotedString(i, code, result);
            }
            else {
                result.add(c);
                i++;
            }
        }

        return result.toString();

    }

    static function cleanAsIsUntil(i:Int, input:String, output:StringBuf, until:Int, allowInterpolation:Bool = false) {

        var openBraces:Int = 0;
        var openParens:Int = 0;
        var openBrackets:Int = 0;

        while (i < input.length) {

            var c = input.charCodeAt(i);

            if (openBraces <= 0 && openParens <= 0 && openBrackets <= 0) {
                if (c == until) {
                    i++;
                    break;
                }
            }

            if (c == '{'.code) {
                output.addChar(c);
                openBraces++;
                i++;
            }
            else if (c == '}'.code) {
                output.addChar(c);
                openBraces--;
                i++;
            }
            else if (c == '('.code) {
                output.addChar(c);
                openParens++;
                i++;
            }
            else if (c == ')'.code) {
                output.addChar(c);
                openParens--;
                i++;
            }
            else if (c == '['.code) {
                output.addChar(c);
                openBrackets++;
                i++;
            }
            else if (c == ']'.code) {
                output.addChar(c);
                openBrackets--;
                i++;
            }
            else if (c == '"'.code) {
                i = cleanDoubleQuotedString(i, input, output, allowInterpolation);
            }
            else if (c == '\''.code) {
                i = cleanSingleQuotedString(i, input, output);
            }
            else if (c == '\n'.code || c == '\r'.code) {
                output.addChar(c);
                i++;
            }
            else {
                output.addChar(' '.code);
                i++;
            }
        }

        return i;

    }

    static function cleanDoubleQuotedString(i:Int, input:String, output:StringBuf, allowInterpolation:Bool = false) {

        output.addChar(allowInterpolation ? ' '.code : '"'.code);
        i++; // Skip opening quote

        while (i < input.length) {

            var c = input.charCodeAt(i);

            if (c == '\\'.code) {
                // Handle escape sequences
                output.addChar(' '.code);
                i++;
                if (i < input.length) {
                    output.addChar(' '.code);
                    i++;
                }
            }
            else if (allowInterpolation && c == '$'.code && i + 1 < input.length && input.charCodeAt(i + 1) == '{'.code) {
                // Handle string interpolation
                output.addChar(' '.code);
                output.addChar(' '.code);
                i += 2;
                i = cleanAsIsUntil(i, input, output, '}'.code) - 1;
            }
            else if (c == '"'.code) {
                // End of string
                output.addChar(allowInterpolation ? ' '.code : c);
                i++;
                break;
            }
            else if (c == '\n'.code || c == '\r'.code) {
                output.addChar(c);
                i++;
            }
            else {
                output.addChar(' '.code);
                i++;
            }
        }

        return i;

    }

    static function cleanSingleQuotedString(i:Int, input:String, output:StringBuf) {

        output.addChar('\''.code);
        i++; // Skip opening quote

        while (i < input.length) {
            var c = input.charCodeAt(i);

            if (c == '\\'.code) {
                // Handle escape sequences
                output.addChar(' '.code);
                i++;
                if (i < input.length) {
                    output.addChar(' '.code);
                    i++;
                }
            }
            else if (c == '$'.code && i + 1 < input.length && input.charCodeAt(i + 1) == '{'.code) {
                // Handle string interpolation
                output.addChar(' '.code);
                output.addChar(' '.code);
                i += 2;
                i = cleanAsIsUntil(i, input, output, '}'.code, true) - 1;
            }
            else if (c == '\''.code) {
                // End of string (only if we're not inside interpolation)
                output.addChar(c);
                i++;
                break;
            }
            else if (c == '\n'.code || c == '\r'.code) {
                output.addChar(c);
                i++;
            }
            else {
                output.addChar(' '.code);
                i++;
            }
        }

        return i;

    }

/// Maps

    static var BLOCK_KEYWORDS = [
        'function' => true,
        'class' => true,
        'interface' => true,
        'abstract' => true,
        'enum' => true,
        'typedef' => true
    ];

    static var BLOCK_KEYWORDS_CC = [
        'fu' => true,
        'cl' => true,
        'in' => true,
        'ab' => true,
        'en' => true,
        'ty' => true
    ];

/// Regular expressions

    static var RE_WORD = ~/^[a-zA-Z0-9_]+/;

    static var RE_SEP_WORD = ~/^[^a-zA-Z0-9_]([a-zA-Z0-9_]+)/;

    static var RE_STRING = ~/^(?:"(?:[^"\\]*(?:\\.[^"\\]*)*)"|'(?:[^'\\]*(?:\\.[^'\\]*)*)')/;

}
