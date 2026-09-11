// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Runmote';

  @override
  String get navAgents => 'Agents';

  @override
  String get navSessions => 'Sessions';

  @override
  String get navSettings => 'Settings';

  @override
  String get pairTitle => 'Runmote';

  @override
  String get pairSubtitle => 'Remote Access Redefined';

  @override
  String get pairConnecting => 'Connecting...';

  @override
  String get pairInvalidCode =>
      'Please enter a 6-digit or 8-character pairing code';

  @override
  String get pairConnectionFailed => 'Connection failed';

  @override
  String get pairDaemonDisconnected =>
      'Daemon disconnected. Run \'runmote\' on your device to reconnect.';

  @override
  String get pairScanQrTitle => 'Scan QR Code';

  @override
  String get pairScanQrSubtitle =>
      'Use your camera to quickly link your device';

  @override
  String get pairManualCodeTitle => 'Enter Manual Code';

  @override
  String get pairManualCodeSubtitle =>
      'Type the 8-character code from your terminal';

  @override
  String get pairGuestModeTitle => 'Continue without pairing';

  @override
  String get pairGuestModeSubtitle =>
      'Use the verification path to preview the app';

  @override
  String get pairNeedHelp => 'Need help finding your code?';

  @override
  String pairInvalidCodeScanned(Object code) {
    return 'Invalid code scanned: $code';
  }

  @override
  String get pairCameraPermissionDenied =>
      'Camera permission permanently denied. Open app settings to enable.';

  @override
  String get pairCameraPermissionRequired =>
      'Camera permission is required to scan QR codes.';

  @override
  String pairCameraError(Object error) {
    return 'Camera error: $error';
  }

  @override
  String get pairCameraStarting => 'Starting camera...';

  @override
  String get pairCodeEntryHeader => 'Enter Code';

  @override
  String get pairCodeHint => 'XXXX-XXXX';

  @override
  String get pairConnect => 'Connect';

  @override
  String get pairConnectionLostTitle => 'Connection Lost';

  @override
  String get pairConnectionLostBody =>
      'The remote device disconnected.\nMake sure the daemon is running on your PC.\n\nRun this command in your terminal:\nrunmote';

  @override
  String get pairBackToOptions => 'Back to Pairing Options';

  @override
  String get pairHelpDialogTitle => 'Get Your Code';

  @override
  String get pairHelpStep1 =>
      '1. Make sure the Runmote daemon is running on your PC';

  @override
  String get pairHelpStep2 =>
      '2. Look for the QR code in the terminal where the daemon is running';

  @override
  String get pairHelpStep3 =>
      '3. Use the QR scanner to scan it, or type the 8-character code shown below it';

  @override
  String get pairHelpGotIt => 'Got it';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsConnection => 'Connection';

  @override
  String get settingsMcpServers => 'MCP Servers';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsData => 'Data';

  @override
  String get settingsUsage => 'Usage';

  @override
  String get settingsUsageThreshold => 'Warn when context passes';

  @override
  String get settingsUsageThresholdOff => 'Off';

  @override
  String get settingsUsageEmpty =>
      'No usage reported yet — figures appear here as your agents work.';

  @override
  String get settingsUsageTokens => 'tokens';

  @override
  String get settingsUsageNotReported => 'not reported';

  @override
  String settingsUsageOver(Object pct) {
    return 'Over $pct% of context';
  }

  @override
  String settingsUsageContext(Object used, Object size) {
    return '$used / $size context';
  }

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsSupport => 'Support';

  @override
  String get settingsConnectionStatus => 'Connection Status';

  @override
  String get settingsConnectedToRelay => 'Connected to Relay';

  @override
  String get settingsConnectingToRelay => 'Connecting to Relay...';

  @override
  String get settingsRelayDetails => 'Relay Details';

  @override
  String get settingsClose => 'Close';

  @override
  String get settingsPairingCode => 'Pairing Code';

  @override
  String get settingsNotPaired => 'Not paired';

  @override
  String get settingsUnpairDevice => 'Unpair Device';

  @override
  String get settingsUnpairSubtitle => 'Disconnect and return to pair screen';

  @override
  String get settingsColorScheme => 'Color Scheme';

  @override
  String get settingsThemeMode => 'Theme Mode';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsClearLocalData => 'Clear Local Data';

  @override
  String get settingsClearLocalDataSubtitle =>
      'Remove all cached messages and sessions';

  @override
  String get settingsReportIssue => 'Report an Issue';

  @override
  String get settingsAppInfo => 'App info';

  @override
  String get settingsAppInfoSubtitle => 'Device and connection details';

  @override
  String get settingsCopyDiagnostics => 'Copy details';

  @override
  String get settingsDiagnosticsCopied => 'Details copied';

  @override
  String settingsVersion(Object version) {
    return 'Runmote v$version';
  }

  @override
  String get settingsFooter => 'Crafted with ❤️ for Developers';

  @override
  String get settingsMcpEmpty => 'No MCP servers configured';

  @override
  String get settingsAddMcp => 'Add MCP server';

  @override
  String get settingsEditMcp => 'Edit MCP server';

  @override
  String get settingsMcpName => 'Name';

  @override
  String get settingsMcpNameHint => 'filesystem';

  @override
  String get settingsStdio => 'STDIO';

  @override
  String get settingsHttp => 'HTTP';

  @override
  String get settingsUrl => 'URL';

  @override
  String get settingsUrlHint => 'https://api.example.com/mcp';

  @override
  String get settingsCommand => 'Command';

  @override
  String get settingsCommandHint => '/path/to/mcp-server';

  @override
  String get settingsArguments => 'Arguments';

  @override
  String get settingsArgumentsHint => '--stdio --debug';

  @override
  String get settingsSave => 'Save';

  @override
  String get settingsCancel => 'Cancel';

  @override
  String get settingsRemoveMcpTitle => 'Remove MCP server?';

  @override
  String settingsRemoveMcpConfirm(Object name) {
    return 'Remove \"$name\"?';
  }

  @override
  String get settingsRemove => 'Remove';

  @override
  String get settingsClearDataTitle => 'Clear local data?';

  @override
  String get settingsClearDataBody =>
      'This will remove all cached messages and sessions. Your pairing will be preserved.';

  @override
  String get settingsClear => 'Clear';

  @override
  String get settingsDataCleared => 'Local data cleared';

  @override
  String get settingsUnpairTitle => 'Unpair device?';

  @override
  String get settingsUnpairBody =>
      'You will need to enter the pairing code again to reconnect.';

  @override
  String get settingsUnpairConfirm => 'Unpair';

  @override
  String get settingsSchemeShadcn => 'Shadcn';

  @override
  String get settingsSchemeMaterial3 => 'Material 3';

  @override
  String get settingsSchemeClassic => 'Classic';

  @override
  String get chatTitle => 'Chat';

  @override
  String get chatCloseSession => 'Close session';

  @override
  String get chatWelcomeTitle => 'Ready to help';

  @override
  String get chatWelcomeSubtitle =>
      'Type a message below to start your conversation with the agent.';

  @override
  String get chatLoadError => 'Could not load chat';

  @override
  String get chatRetry => 'Retry';

  @override
  String get chatAttachImage => 'Attach image';

  @override
  String get chatDaemonOffline => 'Daemon not connected';

  @override
  String get chatMessageHint => 'Message...';

  @override
  String get chatPermissionTitle => 'Permission Requested';

  @override
  String get chatPermissionQuestion =>
      'Allow the agent to perform this action?';

  @override
  String get chatPermissionCancel => 'Cancel';

  @override
  String get thinkingProcess => 'Thinking Process';

  @override
  String get toolExecuting => 'Executing Tools';

  @override
  String get toolRunning => 'Running';

  @override
  String get toolCompleted => 'Completed';

  @override
  String get agentsTitle => 'Agents';

  @override
  String get agentsReconnecting => 'Reconnecting...';

  @override
  String get agentsConnectionLost => 'Connection lost. Tap to reconnect.';

  @override
  String get agentsConnecting => 'Establishing Connection...';

  @override
  String get agentsNoAgents => 'No agents detected';

  @override
  String get agentsNoAgentsSubtitle =>
      'Make sure a Runmote agent is running on your remote machine to get started.';

  @override
  String get agentsRefresh => 'Refresh';

  @override
  String get agentsAgentId => 'Agent ID';

  @override
  String get agentsVersion => 'Version';

  @override
  String get agentsInterrupted => 'Connection Interrupted';

  @override
  String get agentsInterruptedDesc =>
      'The Runmote daemon on your remote machine appears to be offline or unreachable.';

  @override
  String get agentsReactivate => 'Re-activate Daemon';

  @override
  String get agentsReactivateInstruction =>
      'Ensure the daemon is running by executing this command in your terminal:';

  @override
  String get agentsTerminalCommand => 'runmote';

  @override
  String get agentsAutoReconnect =>
      'The app will automatically reconnect once the daemon is back online.';

  @override
  String get agentsCheckConnection => 'Check Connection Status';

  @override
  String get sessionsTitle => 'Sessions';

  @override
  String get sessionsSearchHint => 'Search sessions...';

  @override
  String get sessionsDeleteTitle => 'Delete session?';

  @override
  String get sessionsDeleteConfirm => 'Delete';

  @override
  String get sessionsUntitled => 'Untitled';

  @override
  String get sessionsNoDaemon =>
      'Cannot create session — daemon is not running';

  @override
  String get sessionsCreateFailed =>
      'Failed to create session — daemon may be disconnected';

  @override
  String get sessionsEmptyTitle => 'No sessions found';

  @override
  String get sessionsEmptySubtitle =>
      'Start your first workspace session to begin interacting with the agent.';

  @override
  String get sessionsNewSession => 'New Session';

  @override
  String sessionsNoMatch(Object query) {
    return 'No sessions match \"$query\"';
  }

  @override
  String get sessionsLocalOnly =>
      'Agent doesn\'t support remote listing — showing local sessions';

  @override
  String get sessionsJustNow => 'just now';

  @override
  String get sessionsMinuteAgo => 'm ago';

  @override
  String get sessionsHourAgo => 'h ago';

  @override
  String get sessionsDayAgo => 'd ago';

  @override
  String get sessionsWeekAgo => 'w ago';

  @override
  String get sessionsOffline => 'OFFLINE';

  @override
  String get sessionsActive => 'Active session';

  @override
  String get sessionsDeleteTooltip => 'Delete session';

  @override
  String get dirPickerTitle => 'Choose directory';

  @override
  String get dirPickerShowHidden => 'Show hidden files';

  @override
  String get dirPickerHideHidden => 'Hide hidden files';

  @override
  String get dirPickerDrives => 'Drives';

  @override
  String get dirPickerUp => 'Up';

  @override
  String dirPickerDirCount(Object count) {
    return '$count dirs';
  }

  @override
  String dirPickerFileCount(Object count) {
    return '$count files';
  }

  @override
  String get dirPickerListError => 'Failed to list directory';

  @override
  String get dirPickerDriveError => 'Failed to list drives';

  @override
  String get dirPickerRetry => 'Retry';

  @override
  String get dirPickerEmpty => 'Empty directory';

  @override
  String get dirPickerSelectDrive => 'Select a directory from the list';

  @override
  String dirPickerOpenSession(Object path) {
    return 'Open session in $path';
  }

  @override
  String get daemonOfflineTitle => 'Remote Connection Offline';

  @override
  String get daemonOfflineSubtitle =>
      'Run \"runmote\" on your device to reconnect.';

  @override
  String get statusConnected => 'Connected';

  @override
  String get statusOffline => 'Offline';

  @override
  String get statusConnecting => 'Connecting...';

  @override
  String get statusDaemonOffline => 'Daemon Offline';

  @override
  String ongoingSessionResponding(Object agentName) {
    return '$agentName is responding...';
  }

  @override
  String ongoingSessionsActive(Object count) {
    return '$count sessions active';
  }

  @override
  String terminalHeader(Object id) {
    return 'Terminal $id';
  }

  @override
  String get diffNoChanges => '(no changes)';

  @override
  String get discoveryNoRelay => 'No relay found on network';

  @override
  String discoveryFailed(Object error) {
    return 'Discovery failed: $error';
  }
}
