# Friendship And Blocking

## Purpose

Restrict communication to accepted friends and allow users to block unwanted peers.

## Business Value

Keeps Rain private and trust-scoped.

## User Flow

1. Search for username.
2. Send friend request.
3. Receiver accepts or rejects.
4. Accepted friends can connect, chat, call, and transfer files.

## Technical Flow

- RTDB paths: `friendRequests`, `outgoingFriendRequests`, `friendships`, `blocks`, `blockedBy`, `userSearch`.
- Drift table: `friends`.

## Edge Cases

- User cannot friend themselves.
- Blocked peers cannot create new friend/call/request artifacts.
- Unfriend should remove or disable communication state.

## Testing Requirements

- Request, accept, reject, block, unblock.
- Blocked user cannot call or send connection request.

Related: [[Presence And Direct Connect]], [[Security Review]].
