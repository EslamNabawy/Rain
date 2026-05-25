# Rain Widget Map

Status: reference map

Last analyzed: 2026-05-25

This document lists the current UI widget surfaces in `apps/rain/lib`. It is a
navigation map for future UI, branding, call, and test work.

## Entry Widgets

| File | Widget or class | Role |
| --- | --- | --- |
| `apps/rain/lib/main.dart` | `RainStartupApp` | Top-level startup widget that runs bootstrap before the app shell |
| `apps/rain/lib/main.dart` | `_RainStartupAppState` | Owns startup async state and renders splash/failure/app |
| `apps/rain/lib/main.dart` | `BootstrapFailureApp` | Minimal failure app when bootstrap fails before normal app shell exists |
| `apps/rain/lib/presentation/screens/rain_app.dart` | `RainApp` | Material app, router, theme, and root Riverpod app surface |

## Routing And Shell

| File | Widget or class | Role |
| --- | --- | --- |
| `presentation/navigation/app_routes.dart` | `AppRoutes` | GoRouter configuration and route factory |
| `presentation/navigation/app_routes.dart` | `AppShellReadiness` | Route guard/readiness data |
| `presentation/navigation/app_routes.dart` | `_RouterRefreshNotifier` | Listenable adapter for route refresh |
| `presentation/navigation/rain_navigation_shell.dart` | `RainNavigationShell` | Main responsive shell around tab content |
| `presentation/navigation/rain_navigation_shell.dart` | `_NetworkStatusStrip` | Network connectivity strip |
| `presentation/navigation/rain_navigation_shell.dart` | `_BottomNavigation` | Mobile bottom navigation |
| `presentation/navigation/rain_navigation_shell.dart` | `_RailLayout` | Wide/desktop navigation rail layout |
| `presentation/navigation/rain_navigation_shell.dart` | `_RainNavigationHaloIcon` | Branded active navigation icon/halo |

## Root And Startup Screens

| File | Widget or class | Role |
| --- | --- | --- |
| `presentation/screens/root_screen.dart` | `RootScreen` | Watches app state and routes between loading, auth, force update, and shell |
| `presentation/screens/root_screen.dart` | `_SessionExpiredResetView` | Clears session-expired state and resets auth flow |
| `presentation/screens/root_screen.dart` | `_ForceUpdateGate` | Blocks app usage when force update policy requires it |
| `presentation/screens/root_screen.dart` | `_LoadingView` | Root loading fallback |
| `presentation/screens/root_screen.dart` | `_ErrorView` | Root error fallback |
| `presentation/screens/splash_screen.dart` | `RainSplashScreen` | Branded startup splash |
| `presentation/screens/splash_screen.dart` | `RainStartupFailureScreen` | Branded startup failure screen |
| `presentation/screens/splash_screen.dart` | `_SplashScaffold` | Common splash screen frame |
| `presentation/screens/splash_screen.dart` | `_SplashBody` | Logo/title/status area |

## Auth Screens

| File | Widget or class | Role |
| --- | --- | --- |
| `presentation/screens/onboarding_screen.dart` | `OnboardingScreen` | Login and account creation screen |
| `presentation/screens/onboarding_screen.dart` | `_CredentialFocusReveal` | Keeps focused credential fields visible around keyboard/insets |
| `presentation/screens/onboarding_screen.dart` | `_AuthMode` | Internal login/register mode enum |

## Home And Chat Screens

| File | Widget or class | Role |
| --- | --- | --- |
| `presentation/screens/home_screen.dart` | `HomeScreen` | Main chat screen and selected conversation coordinator |
| `presentation/screens/home_screen.dart` | `_HomeScreenState` | Watches runtime, selected peer, messages, transfers, calls, and UI actions |
| `presentation/screens/home_screen.dart` | `_ConnectionStatus` | Internal connection status projection for chat header/status UI |
| `presentation/widgets/home/shell_header.dart` | `_ShellHeader` | Home shell/header content |
| `presentation/widgets/home/shell_header.dart` | `_RainHeaderIcon` | Branded header icon |
| `presentation/widgets/home/friends_list.dart` | `_FriendsListView` | Friend/conversation list |
| `presentation/widgets/home/friends_list.dart` | `_FriendTile` | One friend row with status and selection behavior |
| `presentation/widgets/home/chat_panel.dart` | `_ChatPanel` | Conversation panel, message list, composer, call/file surfaces |
| `presentation/widgets/home/file_transfer_bubble.dart` | `_FileTransferBubble` | File transfer bubble in chat timeline |
| `presentation/widgets/home/file_transfer_bubble.dart` | `_FileTransferHeader` | Transfer title/header row |
| `presentation/widgets/home/file_transfer_bubble.dart` | `_FileTransferMetaRow` | File size/progress/status row |
| `presentation/widgets/home/file_transfer_bubble.dart` | `_FileTransferActions` | Accept/reject/cancel/export actions |
| `presentation/widgets/home/link_status.dart` | `_MobileLinkStatusBar` | Compact mobile link health/status area |
| `presentation/widgets/home/link_status.dart` | `_MobileLinkGlyph` | Visual route glyph |
| `presentation/widgets/home/link_status.dart` | `_MobileLinkMeter` | Signal/strength meter |
| `presentation/widgets/home/link_status.dart` | `_LinkStat` | Internal stat value model |
| `presentation/widgets/home/link_status.dart` | `_LinkStatGrid` | Desktop/wide connection stats grid |
| `presentation/widgets/home/link_status.dart` | `_LinkStatCard` | One connection stat card |

## Search And Friend Profile

| File | Widget or class | Role |
| --- | --- | --- |
| `presentation/screens/search_screen.dart` | `SearchScreen` | Find users and send friend requests |
| `presentation/screens/search_screen.dart` | `_SearchHint` | Empty search hint |
| `presentation/screens/search_screen.dart` | `_SearchLoading` | Search loading state |
| `presentation/screens/search_screen.dart` | `_SearchError` | Search error state |
| `presentation/screens/search_screen.dart` | `_SearchResults` | Search result list |
| `presentation/screens/friend_profile_screen.dart` | `FriendProfileScreen` | Friend identity, relationship, and actions |
| `presentation/screens/friend_profile_screen.dart` | `_InfoSection` | Profile info section |
| `presentation/screens/friend_profile_screen.dart` | `_InfoTile` | One profile field/action row |

## Settings

| File | Widget or class | Role |
| --- | --- | --- |
| `presentation/screens/settings_screen.dart` | `SettingsScreen` | Settings, profile, audio, diagnostics, blocking, logout |
| `presentation/screens/settings_screen.dart` | `_SettingsScreenState` | Coordinates settings actions and provider writes |
| `presentation/screens/settings_screen.dart` | `_ProfileAction` | Internal profile action menu enum |
| `presentation/screens/settings_screen.dart` | `_MicrophoneTestTile` | Mic test entry |
| `presentation/screens/settings_screen.dart` | `_VoiceAudioSettingsControls` | Voice input/output preference controls |
| `presentation/screens/settings_screen.dart` | `_OutputPreferenceMenuRow` | Output route option row |
| `presentation/screens/settings_screen.dart` | `_LastCrashTile` | Last crash diagnostic card |
| `presentation/screens/settings_screen.dart` | `_SoundDiagnosticsTile` | Sound system diagnostic card |
| `presentation/screens/settings_screen.dart` | `_BlockedUsersList` | Blocked users section |
| `presentation/screens/settings_screen.dart` | `_BlockedUserTile` | One blocked user row |

## Shared App Components

| File | Widget or class | Role |
| --- | --- | --- |
| `presentation/widgets/app_components.dart` | `AppSectionCard` | Shared framed content card |
| `presentation/widgets/app_components.dart` | `AppSectionTitle` | Shared section heading |
| `presentation/widgets/app_components.dart` | `AppPageFrame` | Shared page layout with responsive constraints |
| `presentation/widgets/app_components.dart` | `AppStateMessage` | Shared empty/error/loading message surface |
| `presentation/widgets/app_components.dart` | `AppLowerCaseTextFormatter` | Lowercase text input formatter |
| `presentation/widgets/app_components.dart` | `AppTextInputField` | Shared branded input field |
| `presentation/widgets/app_components.dart` | `_AppTextInputFieldState` | Input field focus/password state |
| `presentation/widgets/app_dialogs.dart` | `_AppTextInputDialog` | Shared text input dialog |
| `presentation/widgets/app_dialogs.dart` | `_AppTextInputDialogState` | Dialog input lifecycle |
| `presentation/widgets/backend_banner.dart` | `BackendBanner` | Displays backend/environment banner |
| `presentation/widgets/chat_composer.dart` | `ChatComposer` | Message composer with attachment/send actions |
| `presentation/widgets/chat_composer.dart` | `_ChatComposerState` | Composer text/focus/send state |

## Chat-Specific Shared Widgets

| File | Widget or class | Role |
| --- | --- | --- |
| `presentation/widgets/rain_chat_widgets.dart` | `RainAvatar` | Avatar/identity mark for user/friend |
| `presentation/widgets/rain_chat_widgets.dart` | `RainMiniStatusChip` | Small status chip |
| `presentation/widgets/rain_chat_widgets.dart` | `RainLiveLinkBar` | Direct/relay/connection health bar |
| `presentation/widgets/rain_chat_widgets.dart` | `RainMessageDayDivider` | Day separator in message list |
| `presentation/widgets/rain_chat_widgets.dart` | `RainMessageBubble` | Text/system/file message bubble |
| `presentation/widgets/rain_chat_widgets.dart` | `RainComposerCommandStrip` | Composer command row |
| `presentation/widgets/rain_chat_widgets.dart` | `RainVoiceCallButton` | Header voice call action |
| `presentation/widgets/rain_chat_widgets.dart` | `RainVideoCallButton` | Header video call action |
| `presentation/widgets/rain_chat_widgets.dart` | `RainMicrophoneSelector` | Microphone selection menu |
| `presentation/widgets/rain_chat_widgets.dart` | `RainCameraSelector` | Camera selection menu |
| `presentation/widgets/rain_chat_widgets.dart` | `_RainDeviceMenuRow` | One media device row |

## Video Stage Widgets

| File | Widget or class | Role |
| --- | --- | --- |
| `presentation/widgets/rain_chat_widgets.dart` | `RainVideoCallStage` | Embedded video stage for call surfaces |
| `presentation/widgets/rain_chat_widgets.dart` | `RainVideoCallStageLayout` | Stage layout mode enum |
| `presentation/widgets/rain_chat_widgets.dart` | `_RainRemoteVideoSurface` | Remote video as main surface |
| `presentation/widgets/rain_chat_widgets.dart` | `_RainLocalVideoPreview` | Local preview overlay |
| `presentation/widgets/rain_chat_widgets.dart` | `_RainRemoteVideoPreview` | Remote preview when swapped |
| `presentation/widgets/rain_chat_widgets.dart` | `_RainLocalVideoSurface` | Local video as main surface when swapped |
| `presentation/widgets/rain_chat_widgets.dart` | `_RainVideoPreviewFrame` | Shared preview frame |
| `presentation/widgets/rain_chat_widgets.dart` | `_RainVideoPlaceholder` | Empty/disabled video placeholder |

## Call Panel And Controls

| File | Widget or class | Role |
| --- | --- | --- |
| `presentation/widgets/rain_chat_widgets.dart` | `RainCallPanel` | Chat-level call panel surface |
| `presentation/widgets/rain_chat_widgets.dart` | `RainVoiceCallPanel` | Voice-focused chat-level call panel |
| `presentation/widgets/calls/rain_call_controls.dart` | `RainCallControls` | Shared call control row |
| `presentation/widgets/calls/rain_call_controls.dart` | `RainCallControlVisual` | Visual metadata for a control button |
| `presentation/widgets/calls/rain_call_controls.dart` | `RainCallTicker` | Call duration ticker |
| `presentation/widgets/calls/rain_call_controls.dart` | `_RainCallTickerState` | Ticker timer lifecycle |
| `presentation/widgets/calls/rain_call_manager_bar.dart` | `RainCallManagerBar` | Top manager bar for minimized/active calls |
| `presentation/widgets/calls/rain_call_manager_bar.dart` | `_WideCallManagerContent` | Desktop/wide bar layout |
| `presentation/widgets/calls/rain_call_manager_bar.dart` | `_CompactCallManagerContent` | Mobile compact bar layout |
| `presentation/widgets/calls/rain_call_manager_bar.dart` | `_CallIdentity` | Peer/avatar call identity |
| `presentation/widgets/calls/rain_call_manager_bar.dart` | `_CallStatusText` | Call phase/duration/status text |
| `presentation/widgets/calls/rain_call_manager_bar.dart` | `_CallManagerActions` | Bar action group |
| `presentation/widgets/calls/rain_call_manager_bar.dart` | `_CallPrimaryToggles` | Mute/deafen/video toggles |
| `presentation/widgets/calls/rain_call_manager_bar.dart` | `_CallRestoreButton` | Restore popup/stage |
| `presentation/widgets/calls/rain_call_manager_bar.dart` | `_CallFullscreenButton` | Enter/exit fullscreen video |
| `presentation/widgets/calls/rain_call_manager_bar.dart` | `_HangUpButton` | Hang up action |
| `presentation/widgets/calls/rain_call_manager_bar.dart` | `_CallManagerIconButton` | Shared icon button style |

## Call Overlay

| File | Widget or class | Role |
| --- | --- | --- |
| `presentation/widgets/calls/rain_call_overlay.dart` | `RainCallOverlay` | App-level expanded/minimized/fullscreen call overlay |
| `presentation/widgets/calls/rain_call_overlay.dart` | `_RainFullscreenVideoSurface` | Fullscreen video surface |
| `presentation/widgets/calls/rain_call_overlay.dart` | `_RainExpandedCallPanel` | Expanded popup panel |
| `presentation/widgets/calls/rain_call_overlay.dart` | `_RainPopupHeader` | Popup top identity/status/actions |
| `presentation/widgets/calls/rain_call_overlay.dart` | `_RainCallMediaFrame` | Voice/video media frame |
| `presentation/widgets/calls/rain_call_overlay.dart` | `_RainFailureFocus` | Failed-call focus surface |
| `presentation/widgets/calls/rain_call_overlay.dart` | `_RainPopupStatusText` | Popup status text |
| `presentation/widgets/calls/rain_call_overlay.dart` | `_RainCallControlDock` | Popup control dock |
| `presentation/widgets/calls/rain_call_overlay.dart` | `_RainCallStatusGlyph` | Call status icon/glyph |
| `presentation/widgets/calls/rain_call_overlay.dart` | `_RainCallAudioActivity` | Real audio activity surface |
| `presentation/widgets/calls/rain_call_overlay.dart` | `_RainCallAudioWave` | Audio wave painter/widget |
| `presentation/widgets/calls/rain_call_overlay.dart` | `_RainRouteSummary` | Route summary in call UI |

Call rendering rule:

- When the expanded popup is visible, the top manager bar should not duplicate
  controls.
- When minimized, the top manager bar is the persistent control surface.
- Fullscreen video should prioritize remote video as the main content and local
  video as preview unless the user swaps them.

## Branding, Theme, And Backdrop

| File | Widget or class | Role |
| --- | --- | --- |
| `presentation/branding/rain_brand_assets.dart` | `RainBrandAssets` | Central asset path registry |
| `presentation/branding/rain_peer_core_mark.dart` | `RainPeerCoreMark` | Static peer core logo/mark |
| `presentation/branding/rain_peer_core_mark.dart` | `RainPeerCoreAnimatedMark` | Animated logo mark |
| `presentation/branding/rain_peer_core_mark.dart` | `RainPeerCoreMotion` | Logo motion mode enum |
| `presentation/branding/rain_peer_core_mark.dart` | `_PeerCoreMeshLayer` | Inner peer mesh layer |
| `presentation/branding/rain_peer_core_mark.dart` | `_WaveLayer` | Wave/ripple layer |
| `presentation/branding/rain_ripple_halo_surface.dart` | `RainRippleHaloSurface` | Component-level ripple halo wrapper |
| `presentation/branding/rain_ripple_halo_surface.dart` | `_RainRippleHaloSurfaceState` | One-shot state-change ripple animation |
| `presentation/branding/rain_ripple_halo_surface.dart` | `_RainRippleHaloPainter` | Halo painter |
| `presentation/branding/rain_state_surfaces.dart` | `RainMistStateCard` | Branded neutral/warning/error card |
| `presentation/branding/rain_state_surfaces.dart` | `RainStateSeverity` | Severity enum |
| `presentation/branding/rain_state_surfaces.dart` | `RainStreakSkeleton` | Loading skeleton |
| `presentation/branding/rain_streak_surface.dart` | Legacy/wrapper streak surface | Kept for compatibility while ripple halos replace active treatment |
| `presentation/theme/rain_theme.dart` | `RainColors` | Color tokens |
| `presentation/theme/rain_theme.dart` | `RainTextureTokens` | Texture/backdrop tokens |
| `presentation/theme/rain_theme.dart` | `RainMotion` | Motion duration/curve tokens |
| `presentation/theme/rain_theme.dart` | `RainTheme` | Material theme construction |
| `presentation/theme/rain_theme.dart` | `_RainPageTransitionsBuilder` | Page transition builder |
| `presentation/widgets/rain_backdrop.dart` | `RainBackdrop` | App background/backdrop surface |
| `presentation/widgets/rain_backdrop.dart` | `RainBackdropVariant` | Backdrop variant enum |
| `presentation/widgets/rain_backdrop.dart` | `_RainBackdropStyle` | Variant style data |
| `presentation/widgets/rain_backdrop.dart` | `_RainAtmosphere` | Backdrop atmosphere layer |
| `presentation/widgets/rain_backdrop.dart` | `_RainSignalMistPainter` | Mist/texture painter |

## Runtime State Feeding Widgets

These are not widgets, but they are the main state sources that UI widgets
consume.

| File | Role |
| --- | --- |
| `application/state/app_providers.dart` | App-level provider wiring |
| `application/state/app_state.dart` | App state model |
| `application/state/call_surface_providers.dart` | Call overlay/manager bar presentation state |
| `application/state/connection_diagnostics.dart` | Connection diagnostics projection |
| `application/state/core_providers.dart` | Core singleton providers |
| `application/state/file_transfer_view.dart` | File transfer view models |
| `application/state/identity_providers.dart` | Identity/profile providers |
| `application/state/messaging_providers.dart` | Message list and delivery providers |
| `application/state/runtime_providers.dart` | Runtime controller providers |
| `application/state/search_providers.dart` | User search providers |
| `application/state/settings_providers.dart` | Settings providers |
| `application/state/sound_event_providers.dart` | Sound event providers |

## Widget Test Priority Map

Highest priority surfaces for regression tests:

1. `OnboardingScreen` keyboard visibility and matching input fields.
2. `HomeScreen` selected chat, connection status, and file/call blocking.
3. `RainCallOverlay` expanded, minimized, and fullscreen states.
4. `RainCallManagerBar` visibility contract with overlay.
5. `RainVideoCallStage` remote/local role switching.
6. `SettingsScreen` media device selection and route controls.
7. `RainSplashScreen` startup ownership and reduced-motion behavior.
8. `RainRippleHaloSurface` reduced-motion and one-shot ripple behavior.
