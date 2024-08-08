% Visual Studio Code - Settings
% August 8, 2024

Visual Studio Code (or as most of us call it, VS Code) has become the go-to code editor for developers worldwide. If you’re looking to enhance your development experience, here are some settings that I believe everyone should consider.

# Settings

I recently reset my VS Code settings and decided to start fresh. My goal was to keep things minimal—only adding settings that I really need. Another benefit of this was being able to document each setting I add, along with the reasons behind them.

```json
"files.autoSave": "onFocusChange",
"files.insertFinalNewline": true,
"files.trimFinalNewlines": true,
"files.trimTrailingWhitespace": true,
"window.dialogStyle": "custom",
```

Most of these settings are self-explanatory, but here’s a quick rundown:

- `files.autoSave`: This automatically saves files when focus changes. Personally, I can’t stand pressing `Cmd + S` every time I switch tabs. This setting is a game-changer—if you’re not using it, you’re seriously missing out.

- `files.insertFinalNewline`: Always insert a newline at the end of the file. It’s a small detail, but it’s a good practice that helps avoid merge conflicts.

- `files.trimFinalNewlines`:
- `files.trimTrailingWhitespace`:
These settings remove any extra newlines at the end of the file and any trailing whitespace. Following this practice keeps your code clean and tidy.

- `window.dialogStyle`: I had to dig a bit to find this one as the first link in Google led to an outdate [issue](https://github.com/microsoft/vscode/issues/104365). Most of my development work involves remote servers and SSH. If my system goes to sleep or the connection drops, VS Code shows a dialog box prompting you to “retry connection” or “cancel.” Until you dismiss this box, the Dock icon keeps bouncing in macOS—super annoying. Setting this to `custom` makes the dialog box use VS Code’s built-in dialog instead of the system dialog. No more bouncing Dock icon—this one’s a lifesaver.

# Extensions

_Coming Soon_
