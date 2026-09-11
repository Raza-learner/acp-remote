import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Runmote'**
  String get appTitle;

  /// No description provided for @navAgents.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get navAgents;

  /// No description provided for @navSessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get navSessions;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @pairTitle.
  ///
  /// In en, this message translates to:
  /// **'Runmote'**
  String get pairTitle;

  /// No description provided for @pairSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Remote Access Redefined'**
  String get pairSubtitle;

  /// No description provided for @pairConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get pairConnecting;

  /// No description provided for @pairInvalidCode.
  ///
  /// In en, this message translates to:
  /// **'Please enter a 6-digit or 8-character pairing code'**
  String get pairInvalidCode;

  /// No description provided for @pairConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get pairConnectionFailed;

  /// No description provided for @pairDaemonDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Daemon disconnected. Run \'runmote\' on your device to reconnect.'**
  String get pairDaemonDisconnected;

  /// No description provided for @pairScanQrTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get pairScanQrTitle;

  /// No description provided for @pairScanQrSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use your camera to quickly link your device'**
  String get pairScanQrSubtitle;

  /// No description provided for @pairManualCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter Manual Code'**
  String get pairManualCodeTitle;

  /// No description provided for @pairManualCodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Type the 8-character code from your terminal'**
  String get pairManualCodeSubtitle;

  /// No description provided for @pairGuestModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Continue without pairing'**
  String get pairGuestModeTitle;

  /// No description provided for @pairGuestModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use the verification path to preview the app'**
  String get pairGuestModeSubtitle;

  /// No description provided for @pairNeedHelp.
  ///
  /// In en, this message translates to:
  /// **'Need help finding your code?'**
  String get pairNeedHelp;

  /// No description provided for @pairInvalidCodeScanned.
  ///
  /// In en, this message translates to:
  /// **'Invalid code scanned: {code}'**
  String pairInvalidCodeScanned(Object code);

  /// No description provided for @pairCameraPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera permission permanently denied. Open app settings to enable.'**
  String get pairCameraPermissionDenied;

  /// No description provided for @pairCameraPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Camera permission is required to scan QR codes.'**
  String get pairCameraPermissionRequired;

  /// No description provided for @pairCameraError.
  ///
  /// In en, this message translates to:
  /// **'Camera error: {error}'**
  String pairCameraError(Object error);

  /// No description provided for @pairCameraStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting camera...'**
  String get pairCameraStarting;

  /// No description provided for @pairCodeEntryHeader.
  ///
  /// In en, this message translates to:
  /// **'Enter Code'**
  String get pairCodeEntryHeader;

  /// No description provided for @pairCodeHint.
  ///
  /// In en, this message translates to:
  /// **'XXXX-XXXX'**
  String get pairCodeHint;

  /// No description provided for @pairConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get pairConnect;

  /// No description provided for @pairConnectionLostTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection Lost'**
  String get pairConnectionLostTitle;

  /// No description provided for @pairConnectionLostBody.
  ///
  /// In en, this message translates to:
  /// **'The remote device disconnected.\nMake sure the daemon is running on your PC.\n\nRun this command in your terminal:\nrunmote'**
  String get pairConnectionLostBody;

  /// No description provided for @pairBackToOptions.
  ///
  /// In en, this message translates to:
  /// **'Back to Pairing Options'**
  String get pairBackToOptions;

  /// No description provided for @pairHelpDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Get Your Code'**
  String get pairHelpDialogTitle;

  /// No description provided for @pairHelpStep1.
  ///
  /// In en, this message translates to:
  /// **'1. Make sure the Runmote daemon is running on your PC'**
  String get pairHelpStep1;

  /// No description provided for @pairHelpStep2.
  ///
  /// In en, this message translates to:
  /// **'2. Look for the QR code in the terminal where the daemon is running'**
  String get pairHelpStep2;

  /// No description provided for @pairHelpStep3.
  ///
  /// In en, this message translates to:
  /// **'3. Use the QR scanner to scan it, or type the 8-character code shown below it'**
  String get pairHelpStep3;

  /// No description provided for @pairHelpGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get pairHelpGotIt;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsConnection;

  /// No description provided for @settingsMcpServers.
  ///
  /// In en, this message translates to:
  /// **'MCP Servers'**
  String get settingsMcpServers;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsData;

  /// No description provided for @settingsUsage.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get settingsUsage;

  /// No description provided for @settingsUsageThreshold.
  ///
  /// In en, this message translates to:
  /// **'Warn when context passes'**
  String get settingsUsageThreshold;

  /// No description provided for @settingsUsageThresholdOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get settingsUsageThresholdOff;

  /// No description provided for @settingsUsageEmpty.
  ///
  /// In en, this message translates to:
  /// **'No usage reported yet — figures appear here as your agents work.'**
  String get settingsUsageEmpty;

  /// No description provided for @settingsUsageTokens.
  ///
  /// In en, this message translates to:
  /// **'tokens'**
  String get settingsUsageTokens;

  /// No description provided for @settingsUsageNotReported.
  ///
  /// In en, this message translates to:
  /// **'not reported'**
  String get settingsUsageNotReported;

  /// No description provided for @settingsUsageOver.
  ///
  /// In en, this message translates to:
  /// **'Over {pct}% of context'**
  String settingsUsageOver(Object pct);

  /// No description provided for @settingsUsageContext.
  ///
  /// In en, this message translates to:
  /// **'{used} / {size} context'**
  String settingsUsageContext(Object used, Object size);

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get settingsSupport;

  /// No description provided for @settingsConnectionStatus.
  ///
  /// In en, this message translates to:
  /// **'Connection Status'**
  String get settingsConnectionStatus;

  /// No description provided for @settingsConnectedToRelay.
  ///
  /// In en, this message translates to:
  /// **'Connected to Relay'**
  String get settingsConnectedToRelay;

  /// No description provided for @settingsConnectingToRelay.
  ///
  /// In en, this message translates to:
  /// **'Connecting to Relay...'**
  String get settingsConnectingToRelay;

  /// No description provided for @settingsRelayDetails.
  ///
  /// In en, this message translates to:
  /// **'Relay Details'**
  String get settingsRelayDetails;

  /// No description provided for @settingsClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get settingsClose;

  /// No description provided for @settingsPairingCode.
  ///
  /// In en, this message translates to:
  /// **'Pairing Code'**
  String get settingsPairingCode;

  /// No description provided for @settingsNotPaired.
  ///
  /// In en, this message translates to:
  /// **'Not paired'**
  String get settingsNotPaired;

  /// No description provided for @settingsUnpairDevice.
  ///
  /// In en, this message translates to:
  /// **'Unpair Device'**
  String get settingsUnpairDevice;

  /// No description provided for @settingsUnpairSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Disconnect and return to pair screen'**
  String get settingsUnpairSubtitle;

  /// No description provided for @settingsColorScheme.
  ///
  /// In en, this message translates to:
  /// **'Color Scheme'**
  String get settingsColorScheme;

  /// No description provided for @settingsThemeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get settingsThemeMode;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsClearLocalData.
  ///
  /// In en, this message translates to:
  /// **'Clear Local Data'**
  String get settingsClearLocalData;

  /// No description provided for @settingsClearLocalDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Remove all cached messages and sessions'**
  String get settingsClearLocalDataSubtitle;

  /// No description provided for @settingsReportIssue.
  ///
  /// In en, this message translates to:
  /// **'Report an Issue'**
  String get settingsReportIssue;

  /// No description provided for @settingsAppInfo.
  ///
  /// In en, this message translates to:
  /// **'App info'**
  String get settingsAppInfo;

  /// No description provided for @settingsAppInfoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Device and connection details'**
  String get settingsAppInfoSubtitle;

  /// No description provided for @settingsCopyDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Copy details'**
  String get settingsCopyDiagnostics;

  /// No description provided for @settingsDiagnosticsCopied.
  ///
  /// In en, this message translates to:
  /// **'Details copied'**
  String get settingsDiagnosticsCopied;

  /// No description provided for @settingsVersion.
  ///
  /// In en, this message translates to:
  /// **'Runmote v{version}'**
  String settingsVersion(Object version);

  /// No description provided for @settingsFooter.
  ///
  /// In en, this message translates to:
  /// **'Crafted with ❤️ for Developers'**
  String get settingsFooter;

  /// No description provided for @settingsMcpEmpty.
  ///
  /// In en, this message translates to:
  /// **'No MCP servers configured'**
  String get settingsMcpEmpty;

  /// No description provided for @settingsAddMcp.
  ///
  /// In en, this message translates to:
  /// **'Add MCP server'**
  String get settingsAddMcp;

  /// No description provided for @settingsEditMcp.
  ///
  /// In en, this message translates to:
  /// **'Edit MCP server'**
  String get settingsEditMcp;

  /// No description provided for @settingsMcpName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get settingsMcpName;

  /// No description provided for @settingsMcpNameHint.
  ///
  /// In en, this message translates to:
  /// **'filesystem'**
  String get settingsMcpNameHint;

  /// No description provided for @settingsStdio.
  ///
  /// In en, this message translates to:
  /// **'STDIO'**
  String get settingsStdio;

  /// No description provided for @settingsHttp.
  ///
  /// In en, this message translates to:
  /// **'HTTP'**
  String get settingsHttp;

  /// No description provided for @settingsUrl.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get settingsUrl;

  /// No description provided for @settingsUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://api.example.com/mcp'**
  String get settingsUrlHint;

  /// No description provided for @settingsCommand.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get settingsCommand;

  /// No description provided for @settingsCommandHint.
  ///
  /// In en, this message translates to:
  /// **'/path/to/mcp-server'**
  String get settingsCommandHint;

  /// No description provided for @settingsArguments.
  ///
  /// In en, this message translates to:
  /// **'Arguments'**
  String get settingsArguments;

  /// No description provided for @settingsArgumentsHint.
  ///
  /// In en, this message translates to:
  /// **'--stdio --debug'**
  String get settingsArgumentsHint;

  /// No description provided for @settingsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsSave;

  /// No description provided for @settingsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settingsCancel;

  /// No description provided for @settingsRemoveMcpTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove MCP server?'**
  String get settingsRemoveMcpTitle;

  /// No description provided for @settingsRemoveMcpConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\"?'**
  String settingsRemoveMcpConfirm(Object name);

  /// No description provided for @settingsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get settingsRemove;

  /// No description provided for @settingsClearDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear local data?'**
  String get settingsClearDataTitle;

  /// No description provided for @settingsClearDataBody.
  ///
  /// In en, this message translates to:
  /// **'This will remove all cached messages and sessions. Your pairing will be preserved.'**
  String get settingsClearDataBody;

  /// No description provided for @settingsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get settingsClear;

  /// No description provided for @settingsDataCleared.
  ///
  /// In en, this message translates to:
  /// **'Local data cleared'**
  String get settingsDataCleared;

  /// No description provided for @settingsUnpairTitle.
  ///
  /// In en, this message translates to:
  /// **'Unpair device?'**
  String get settingsUnpairTitle;

  /// No description provided for @settingsUnpairBody.
  ///
  /// In en, this message translates to:
  /// **'You will need to enter the pairing code again to reconnect.'**
  String get settingsUnpairBody;

  /// No description provided for @settingsUnpairConfirm.
  ///
  /// In en, this message translates to:
  /// **'Unpair'**
  String get settingsUnpairConfirm;

  /// No description provided for @settingsSchemeShadcn.
  ///
  /// In en, this message translates to:
  /// **'Shadcn'**
  String get settingsSchemeShadcn;

  /// No description provided for @settingsSchemeMaterial3.
  ///
  /// In en, this message translates to:
  /// **'Material 3'**
  String get settingsSchemeMaterial3;

  /// No description provided for @settingsSchemeClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get settingsSchemeClassic;

  /// No description provided for @chatTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatTitle;

  /// No description provided for @chatCloseSession.
  ///
  /// In en, this message translates to:
  /// **'Close session'**
  String get chatCloseSession;

  /// No description provided for @chatWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready to help'**
  String get chatWelcomeTitle;

  /// No description provided for @chatWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Type a message below to start your conversation with the agent.'**
  String get chatWelcomeSubtitle;

  /// No description provided for @chatLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load chat'**
  String get chatLoadError;

  /// No description provided for @chatRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get chatRetry;

  /// No description provided for @chatAttachImage.
  ///
  /// In en, this message translates to:
  /// **'Attach image'**
  String get chatAttachImage;

  /// No description provided for @chatDaemonOffline.
  ///
  /// In en, this message translates to:
  /// **'Daemon not connected'**
  String get chatDaemonOffline;

  /// No description provided for @chatMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Message...'**
  String get chatMessageHint;

  /// No description provided for @chatPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Permission Requested'**
  String get chatPermissionTitle;

  /// No description provided for @chatPermissionQuestion.
  ///
  /// In en, this message translates to:
  /// **'Allow the agent to perform this action?'**
  String get chatPermissionQuestion;

  /// No description provided for @chatPermissionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get chatPermissionCancel;

  /// No description provided for @thinkingProcess.
  ///
  /// In en, this message translates to:
  /// **'Thinking Process'**
  String get thinkingProcess;

  /// No description provided for @toolExecuting.
  ///
  /// In en, this message translates to:
  /// **'Executing Tools'**
  String get toolExecuting;

  /// No description provided for @toolRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get toolRunning;

  /// No description provided for @toolCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get toolCompleted;

  /// No description provided for @agentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get agentsTitle;

  /// No description provided for @agentsReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting...'**
  String get agentsReconnecting;

  /// No description provided for @agentsConnectionLost.
  ///
  /// In en, this message translates to:
  /// **'Connection lost. Tap to reconnect.'**
  String get agentsConnectionLost;

  /// No description provided for @agentsConnecting.
  ///
  /// In en, this message translates to:
  /// **'Establishing Connection...'**
  String get agentsConnecting;

  /// No description provided for @agentsNoAgents.
  ///
  /// In en, this message translates to:
  /// **'No agents detected'**
  String get agentsNoAgents;

  /// No description provided for @agentsNoAgentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Make sure a Runmote agent is running on your remote machine to get started.'**
  String get agentsNoAgentsSubtitle;

  /// No description provided for @agentsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get agentsRefresh;

  /// No description provided for @agentsAgentId.
  ///
  /// In en, this message translates to:
  /// **'Agent ID'**
  String get agentsAgentId;

  /// No description provided for @agentsVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get agentsVersion;

  /// No description provided for @agentsInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Connection Interrupted'**
  String get agentsInterrupted;

  /// No description provided for @agentsInterruptedDesc.
  ///
  /// In en, this message translates to:
  /// **'The Runmote daemon on your remote machine appears to be offline or unreachable.'**
  String get agentsInterruptedDesc;

  /// No description provided for @agentsReactivate.
  ///
  /// In en, this message translates to:
  /// **'Re-activate Daemon'**
  String get agentsReactivate;

  /// No description provided for @agentsReactivateInstruction.
  ///
  /// In en, this message translates to:
  /// **'Ensure the daemon is running by executing this command in your terminal:'**
  String get agentsReactivateInstruction;

  /// No description provided for @agentsTerminalCommand.
  ///
  /// In en, this message translates to:
  /// **'runmote'**
  String get agentsTerminalCommand;

  /// No description provided for @agentsAutoReconnect.
  ///
  /// In en, this message translates to:
  /// **'The app will automatically reconnect once the daemon is back online.'**
  String get agentsAutoReconnect;

  /// No description provided for @agentsCheckConnection.
  ///
  /// In en, this message translates to:
  /// **'Check Connection Status'**
  String get agentsCheckConnection;

  /// No description provided for @sessionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get sessionsTitle;

  /// No description provided for @sessionsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search sessions...'**
  String get sessionsSearchHint;

  /// No description provided for @sessionsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete session?'**
  String get sessionsDeleteTitle;

  /// No description provided for @sessionsDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get sessionsDeleteConfirm;

  /// No description provided for @sessionsUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get sessionsUntitled;

  /// No description provided for @sessionsNoDaemon.
  ///
  /// In en, this message translates to:
  /// **'Cannot create session — daemon is not running'**
  String get sessionsNoDaemon;

  /// No description provided for @sessionsCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create session — daemon may be disconnected'**
  String get sessionsCreateFailed;

  /// No description provided for @sessionsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No sessions found'**
  String get sessionsEmptyTitle;

  /// No description provided for @sessionsEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start your first workspace session to begin interacting with the agent.'**
  String get sessionsEmptySubtitle;

  /// No description provided for @sessionsNewSession.
  ///
  /// In en, this message translates to:
  /// **'New Session'**
  String get sessionsNewSession;

  /// No description provided for @sessionsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No sessions match \"{query}\"'**
  String sessionsNoMatch(Object query);

  /// No description provided for @sessionsLocalOnly.
  ///
  /// In en, this message translates to:
  /// **'Agent doesn\'t support remote listing — showing local sessions'**
  String get sessionsLocalOnly;

  /// No description provided for @sessionsJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get sessionsJustNow;

  /// No description provided for @sessionsMinuteAgo.
  ///
  /// In en, this message translates to:
  /// **'m ago'**
  String get sessionsMinuteAgo;

  /// No description provided for @sessionsHourAgo.
  ///
  /// In en, this message translates to:
  /// **'h ago'**
  String get sessionsHourAgo;

  /// No description provided for @sessionsDayAgo.
  ///
  /// In en, this message translates to:
  /// **'d ago'**
  String get sessionsDayAgo;

  /// No description provided for @sessionsWeekAgo.
  ///
  /// In en, this message translates to:
  /// **'w ago'**
  String get sessionsWeekAgo;

  /// No description provided for @sessionsOffline.
  ///
  /// In en, this message translates to:
  /// **'OFFLINE'**
  String get sessionsOffline;

  /// No description provided for @sessionsActive.
  ///
  /// In en, this message translates to:
  /// **'Active session'**
  String get sessionsActive;

  /// No description provided for @sessionsDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete session'**
  String get sessionsDeleteTooltip;

  /// No description provided for @dirPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose directory'**
  String get dirPickerTitle;

  /// No description provided for @dirPickerShowHidden.
  ///
  /// In en, this message translates to:
  /// **'Show hidden files'**
  String get dirPickerShowHidden;

  /// No description provided for @dirPickerHideHidden.
  ///
  /// In en, this message translates to:
  /// **'Hide hidden files'**
  String get dirPickerHideHidden;

  /// No description provided for @dirPickerDrives.
  ///
  /// In en, this message translates to:
  /// **'Drives'**
  String get dirPickerDrives;

  /// No description provided for @dirPickerUp.
  ///
  /// In en, this message translates to:
  /// **'Up'**
  String get dirPickerUp;

  /// No description provided for @dirPickerDirCount.
  ///
  /// In en, this message translates to:
  /// **'{count} dirs'**
  String dirPickerDirCount(Object count);

  /// No description provided for @dirPickerFileCount.
  ///
  /// In en, this message translates to:
  /// **'{count} files'**
  String dirPickerFileCount(Object count);

  /// No description provided for @dirPickerListError.
  ///
  /// In en, this message translates to:
  /// **'Failed to list directory'**
  String get dirPickerListError;

  /// No description provided for @dirPickerDriveError.
  ///
  /// In en, this message translates to:
  /// **'Failed to list drives'**
  String get dirPickerDriveError;

  /// No description provided for @dirPickerRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get dirPickerRetry;

  /// No description provided for @dirPickerEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty directory'**
  String get dirPickerEmpty;

  /// No description provided for @dirPickerSelectDrive.
  ///
  /// In en, this message translates to:
  /// **'Select a directory from the list'**
  String get dirPickerSelectDrive;

  /// No description provided for @dirPickerOpenSession.
  ///
  /// In en, this message translates to:
  /// **'Open session in {path}'**
  String dirPickerOpenSession(Object path);

  /// No description provided for @daemonOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote Connection Offline'**
  String get daemonOfflineTitle;

  /// No description provided for @daemonOfflineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Run \"runmote\" on your device to reconnect.'**
  String get daemonOfflineSubtitle;

  /// No description provided for @statusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get statusConnected;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get statusOffline;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get statusConnecting;

  /// No description provided for @statusDaemonOffline.
  ///
  /// In en, this message translates to:
  /// **'Daemon Offline'**
  String get statusDaemonOffline;

  /// No description provided for @ongoingSessionResponding.
  ///
  /// In en, this message translates to:
  /// **'{agentName} is responding...'**
  String ongoingSessionResponding(Object agentName);

  /// No description provided for @ongoingSessionsActive.
  ///
  /// In en, this message translates to:
  /// **'{count} sessions active'**
  String ongoingSessionsActive(Object count);

  /// No description provided for @terminalHeader.
  ///
  /// In en, this message translates to:
  /// **'Terminal {id}'**
  String terminalHeader(Object id);

  /// No description provided for @diffNoChanges.
  ///
  /// In en, this message translates to:
  /// **'(no changes)'**
  String get diffNoChanges;

  /// No description provided for @discoveryNoRelay.
  ///
  /// In en, this message translates to:
  /// **'No relay found on network'**
  String get discoveryNoRelay;

  /// No description provided for @discoveryFailed.
  ///
  /// In en, this message translates to:
  /// **'Discovery failed: {error}'**
  String discoveryFailed(Object error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
