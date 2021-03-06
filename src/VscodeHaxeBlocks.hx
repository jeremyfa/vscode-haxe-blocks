package;

import vscode.ExtensionContext;
import vscode.DecorationRangeBehavior;
import vscode.DecorationOptions;
import vscode.TextEditorDecorationType;

using StringTools;

class VscodeHaxeBlocks {

/// Exposed

    static var instance:VscodeHaxeBlocks = null;

    @:expose("activate")
    static function activate(context:ExtensionContext) {
        instance = new VscodeHaxeBlocks(context);
    }

/// Properties

    var context:ExtensionContext;

    var decorationType:TextEditorDecorationType;

/// Lifecycle

    function new(context:ExtensionContext) {

        this.context = context;
        
        decorationType = Vscode.window.createTextEditorDecorationType({
            rangeBehavior: DecorationRangeBehavior.ClosedClosed
        });

        context.subscriptions.push(Vscode.commands.registerCommand("haxe-blocks.activate", function() {
            // Nothing to do, extension just needs to be activated
        }));

        bindEditors();
    }

    function bindEditors() {

        // When activating extension, decorate existing editors
        for (editor in Vscode.window.visibleTextEditors)
            if (isEditingHaxeCode(editor))
                decorate(editor);

        // When changing editor focus, update decorations
        Vscode.window.onDidChangeActiveTextEditor(editor -> {
            if (isEditingHaxeCode(editor))
                decorate(editor);
        });

        // When an editor content changes, update decorations
        Vscode.workspace.onDidChangeTextDocument(event -> {
            final openEditors = Vscode.window.visibleTextEditors.filter(editor -> {
                editor.document.uri == event.document.uri;
            });
            for (editor in openEditors)
                if (isEditingHaxeCode(editor))
                    decorate(editor);
        });

    }

    function isEditingHaxeCode(editor:vscode.TextEditor):Bool {

        // Skip anything that is not a haxe file
        if (editor == null
            || editor.document == null
            || editor.document.uri == null
            || editor.document.uri.path == null
            || !editor.document.uri.path.endsWith('.hx'))
            return false;

        return true;

    }

    function decorate(editor:vscode.TextEditor):Void {

        var code = editor.document.getText();
        var decorations:Array<DecorationOptions> = [];

        var parseHaxe = new ParseHaxe(code);
        parseHaxe.parse();

        for (block in parseHaxe.blocks) {

            // Skip block if its end line finishes with comment
            if (block.endsWithComment)
                continue;

            // Compute start line
            var startLine = 0;
            for (i in 0...block.start) {
                var c = code.charCodeAt(i);
                if (c == "\n".code) {
                    startLine++;
                }
            }

            // Compute end line and index in that line
            var line = 0;
            var char = 0;
            for (i in 0...block.end) {
                var c = code.charCodeAt(i);
                if (c == "\n".code) {
                    line++;
                    char = 0;
                }
                else {
                    char++;
                }
            }

            if (line > startLine) {
                var range = new vscode.Range(line, char-1, line, char);
                decorations.push({
                    range: range,
                    hoverMessage: (''+block.kind).toLowerCase() + ' ' + block.name,
                    renderOptions: {
                        after: {
                            contentText: ' ' + block.name,
                            fontStyle: 'italic',
                            color: new vscode.ThemeColor('haxeBlocks.endOfBlockForeground')
                        }
                    }
                });
            }
        }

        editor.setDecorations(decorationType, decorations);

    }

}
