// Writes a Terminal.app profile (.terminal) for recording the demo: a readable font,
// a dark theme, a fixed window size, and the command to run.
// Usage: osascript -l JavaScript terminal-profile.js <out.terminal> <command>
ObjC.import('AppKit')

function archive(object) {
  return $.NSKeyedArchiver.archivedDataWithRootObjectRequiringSecureCodingError(object, false, null)
}

function color(hex) {
  const n = parseInt(hex.slice(1), 16)
  return archive($.NSColor.colorWithSRGBRedGreenBlueAlpha(((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255, 1))
}

function run(argv) {
  const [out, command] = argv
  const settings = {
    name: "Where's My PRD demo",
    type: 'Window Settings',
    ProfileCurrentVersion: $.NSNumber.numberWithDouble(2.07),
    Font: archive($.NSFont.fontWithNameSize('Menlo-Regular', 15)),
    FontAntialias: $.NSNumber.numberWithBool(true),
    columnCount: $.NSNumber.numberWithInt(100),
    rowCount: $.NSNumber.numberWithInt(46),
    BackgroundColor: color('#101216'),
    TextColor: color('#E6E8EB'),
    TextBoldColor: color('#FFFFFF'),
    CursorColor: color('#E6E8EB'),
    SelectionColor: color('#2A3140'),
    CommandString: command,
    RunCommandAsShell: $.NSNumber.numberWithBool(true),
    shellExitAction: $.NSNumber.numberWithInt(1),
    WindowTitle: 'claude',
    ShowActiveProcessInTitle: $.NSNumber.numberWithBool(false),
    ShowActiveProcessArgumentsInTitle: $.NSNumber.numberWithBool(false),
    ShowShellCommandInTitle: $.NSNumber.numberWithBool(false),
    ShowWindowSettingsNameInTitle: $.NSNumber.numberWithBool(false),
    ShowDimensionsInTitle: $.NSNumber.numberWithBool(false),
    ShowRepresentedURLInTitle: $.NSNumber.numberWithBool(false),
    ShowRepresentedURLPathInTitle: $.NSNumber.numberWithBool(false),
    ShowTTYNameInTitle: $.NSNumber.numberWithBool(false),
    ShowCommandKeyInTitle: $.NSNumber.numberWithBool(false),
    ShowActivityIndicatorInTab: $.NSNumber.numberWithBool(false),
    ShouldLimitScrollback: $.NSNumber.numberWithBool(false),
    ShowRepresentedURLInTabTitle: $.NSNumber.numberWithBool(false),
  }
  const dict = $.NSMutableDictionary.alloc.init
  for (const key of Object.keys(settings)) dict.setObjectForKey(settings[key], key)
  if (!dict.writeToFileAtomically(out, true)) throw new Error('could not write ' + out)
  return out
}
