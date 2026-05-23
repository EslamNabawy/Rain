# Rain App Context

This document describes Rain from the product and user point of view.

## Product Identity

Rain is a private friend-to-friend chat app for Android and Windows. The app is
built around accepted friendships, direct conversations, file sharing, and
one-to-one voice calls.

The product should feel calm, reliable, and personal. Users should understand
who they are talking to, whether the connection is healthy, and what action is
available next without confusing wording.

## Core Promise

Rain should let two accepted friends:

- Sign in or create an account.
- Find each other.
- Send and accept friend requests.
- Chat in real time.
- Share files when no call is active.
- Start an audio-only call when both apps are open and reachable.
- Recover cleanly from failed calls, lost network, or denied microphone access.

## Target Users

Rain is for people who want a simple private chat experience between known
friends, especially across Android and Windows. The user should not need special
knowledge to use the app.

## Supported Product Scope

Rain currently targets:

- Android phones.
- Windows desktop.
- Accepted friend relationships.
- One active voice call at a time.
- Foreground use for voice calls.

Rain does not currently promise:

- Background ringing.
- Group calls.
- Call history.
- Public discovery beyond user search.
- Voice calling when either app is closed.
- Voice calls on unsupported desktop or mobile platforms.

## Main Screens

### Sign In

The sign-in screen introduces Rain, accepts username and password, and provides
access to account creation. Both input fields should look and behave the same.
On Android, the keyboard must never hide the focused field or submit action.

### Create Account

The account creation flow should feel close to sign-in, with matching field
style and spacing. Username rules should be easy to satisfy and errors should
be short.

### Chats

The chats area is the main home. It shows conversations, friend status, current
connection health, and the active chat. Empty states should be quiet and clear,
not decorative or noisy.

### Chat Detail

The chat view shows the selected friend, their identity, connection status,
messages, file actions, and the call button. Chat should remain usable during
an active call.

### Find

Find lets users search for people and send friend requests. Results should be
easy to tap on narrow mobile screens.

### Friend Profile

Friend profile gives access to friend-specific actions such as viewing identity,
opening chat, managing relationship state, or blocking.

### Settings

Settings covers user-facing preferences and account actions such as display
name, theme, blocked users, and logout.

## Friendship Rules

Communication is built around accepted friendships.

- A user can send a friend request.
- The other user can accept or reject it.
- Either user can unfriend.
- Either user can block.
- Blocked users should not be able to start interaction.
- Removed or blocked relationships should not leave stale chat or call state.

## Chat Behavior

Chat should be predictable and resilient.

- Messages should appear in a stable order.
- Offline or interrupted sends should be recoverable.
- Clear failures are better than silent failure.
- The user should know when a conversation has no messages yet.
- Chat should remain available while a voice call is active.

## File Sharing Behavior

File sharing is part of chat, but calls take priority.

- Users can attach and send files in a chat.
- Progress should be visible while transfers are active.
- Completed received files should be exportable.
- New file sends or accepts should be blocked during a voice call.
- The block message should be clear: finish the call first.

## Voice Call Behavior

Voice call is audio-only and one-to-one.

- Calls are only for accepted friends.
- Both apps must be open for this version.
- Only one call can be active globally.
- The caller should not ring the other person until microphone access is ready.
- The callee should not accept until microphone access is ready.
- Incoming calls need clear accept and reject actions.
- Active calls need elapsed time, mute, and hangup controls.
- Hanging up should release the microphone indicator.
- Repeated calls should work without restarting the app.
- Failed calls must not leave a stale busy state.

## Voice Call Failure Messages

User-facing call errors should be short and typed by cause.

Preferred wording:

- "Microphone permission required."
- "Peer is busy."
- "Call media could not connect. Try again."
- "Call ended."
- "Connection lost."

Avoid exposing long failure text directly in normal UI. Extra failure details
can be kept for troubleshooting, but the user should see a calm human-readable
message.

## Connection Feedback

Rain shows users whether the current chat path is healthy. The connection banner
should make the state understandable without confusing detail.

Useful user-facing states:

- Connected.
- Connecting.
- Direct.
- Relay.
- Disconnected.
- Retry available.

When the connection drops, the app should not rapidly flicker between states.
It should either recover quietly or show a clear stable state.

## Error Handling Principles

Errors should:

- Tell the user what happened.
- Say what they can do next when there is a next action.
- Avoid blaming the user.
- Avoid raw internal wording.
- Clear themselves when the underlying problem is gone.
- Never block unrelated actions unless necessary.

Examples:

- A failed call should not break chat.
- A failed file send should not corrupt the conversation.
- A rejected microphone permission should show a retry path.
- A network loss should not leave an impossible busy state.

## Visual Direction

Rain uses a dark, quiet visual style with a teal/cyan brand accent. The UI
should feel focused and practical rather than like a marketing page.

Design expectations:

- Compact layouts.
- Clear hierarchy.
- Consistent input fields.
- Comfortable touch targets on Android.
- No overlapping text.
- No hidden fields behind the keyboard.
- No oversized decorative sections in the app shell.
- Clear icon buttons with understandable meaning.

## Mobile Expectations

Android is a first-class product target.

- Screens must work on small phones.
- Keyboard behavior is critical.
- Tap targets should be reliable.
- Error banners should not cover core actions permanently.
- Battery, network, and permission interruptions should be handled cleanly.

## Windows Expectations

Windows is a first-class product target.

- The app should launch as a portable desktop experience.
- Chat and calls should work across Windows and Android.
- Desktop controls should feel natural with mouse and keyboard.
- The app should not require a restart after normal call failures.

## Release Expectations

A release should not be treated as ready just because automated checks pass.
Voice calls must be manually verified on a real Android phone and a Windows
machine.

Manual release proof should cover:

- Windows calling Android.
- Android calling Windows.
- Direct and relay connection paths.
- Microphone denial.
- Caller hangup.
- Callee hangup.
- Network loss while ringing.
- Network loss during an active call.
- Repeated calls without restarting.
- Chat during a call.
- File sharing blocked during a call.

## Current Release Status

The latest local release check produced Android and Windows demo install files,
but physical-device voice-call verification is still blocked on this machine
because no Android phone is visible to the local environment.

This means the product is not manually proven ready for voice-call release yet.

## Product Risks To Keep Watching

- Voice call connects but audio does not become audible both ways.
- Call failure leaves the peer stuck as busy.
- Microphone permission denial creates a confusing state.
- Android keyboard hides login or account fields.
- Connection status looks connected while messages or calls fail.
- File sharing starts during a call.
- A call failure breaks chat.
- Long error text leaks into user-facing UI.
- Repeated calls require app restart.

## Product Quality Bar

Rain should be judged by what a real user experiences:

- Can they sign in without fighting the keyboard?
- Can they find and add a friend?
- Can they chat reliably?
- Can they call and hear the other person?
- Can they hang up and call again?
- Can they recover from failure without reinstalling or restarting?
- Are errors clear enough to act on?

If any of those fail in normal use, the feature is not finished.
