"use strict";

const admin = require("firebase-admin");
const { onCall } = require("firebase-functions/v2/https");

const guardrails = require("./connectionRequestGuardrails");

const callableOptions = {
  region: "us-central1",
};

const actionTypes = Object.freeze({
  createConnectionRequest: "createConnectionRequest",
  cancelConnectionRequest: "cancelConnectionRequest",
  acceptConnectionRequest: "acceptConnectionRequest",
  rejectConnectionRequest: "rejectConnectionRequest",
  markConnectionRequestSeen: "markConnectionRequestSeen",
  muteConnectionRequestsFromPeer: "muteConnectionRequestsFromPeer",
  unmuteConnectionRequestsFromPeer: "unmuteConnectionRequestsFromPeer",
  getConnectionRequestQuotaSummary: "getConnectionRequestQuotaSummary",
});

function rootFromDeps(deps) {
  if (deps && deps.root) {
    return deps.root;
  }
  return admin.database().ref();
}

function nowFromDeps(deps) {
  return guardrails.serverNow(deps && deps.clock);
}

async function preparePeerOperation(data, request, deps, action) {
  const now = nowFromDeps(deps);
  let peer;
  try {
    peer = guardrails.peerFromData(data);
  } catch (error) {
    return {
      ok: false,
      response: guardrails.denied(error.reasonCode || "malformedRequest", {
        diagnostics: {
          action,
          serverNow: now,
        },
      }),
    };
  }

  const auth = await guardrails.resolveAuthUsername(rootFromDeps(deps), request);
  if (!auth.ok) {
    return {
      ok: false,
      response: attachDiagnostics(auth.response, {
        action,
        serverNow: now,
      }),
    };
  }

  if (auth.username === peer) {
    return {
      ok: false,
      response: guardrails.denied("selfRequest", {
        peerLabel: peer,
        diagnostics: {
          action,
          serverNow: now,
          sender: auth.username,
          peer,
        },
      }),
    };
  }

  return {
    ok: true,
    action,
    now,
    sender: auth.username,
    peer,
    pairKey: guardrails.connectionRequestPairKey(auth.username, peer),
  };
}

async function prepareRequestOperation(data, request, deps, action) {
  const now = nowFromDeps(deps);
  let requestId;
  try {
    requestId = guardrails.requestIdFromData(data);
  } catch (error) {
    return {
      ok: false,
      response: guardrails.denied(error.reasonCode || "malformedRequest", {
        diagnostics: {
          action,
          serverNow: now,
        },
      }),
    };
  }

  const auth = await guardrails.resolveAuthUsername(rootFromDeps(deps), request);
  if (!auth.ok) {
    return {
      ok: false,
      response: attachDiagnostics(auth.response, {
        action,
        serverNow: now,
        requestId,
      }),
    };
  }

  return {
    ok: true,
    action,
    now,
    requestId,
    sender: auth.username,
  };
}

async function prepareAccountOperation(request, deps, action) {
  const now = nowFromDeps(deps);
  const auth = await guardrails.resolveAuthUsername(rootFromDeps(deps), request);
  if (!auth.ok) {
    return {
      ok: false,
      response: attachDiagnostics(auth.response, {
        action,
        serverNow: now,
      }),
    };
  }

  return {
    ok: true,
    action,
    now,
    sender: auth.username,
  };
}

async function createConnectionRequestCore(data, request, deps = {}) {
  const prepared = await preparePeerOperation(
    data,
    request,
    deps,
    actionTypes.createConnectionRequest,
  );
  if (!prepared.ok) {
    return prepared.response;
  }
  return foundationNotReady(prepared);
}

async function cancelConnectionRequestCore(data, request, deps = {}) {
  return requestShell(data, request, deps, actionTypes.cancelConnectionRequest);
}

async function acceptConnectionRequestCore(data, request, deps = {}) {
  return requestShell(data, request, deps, actionTypes.acceptConnectionRequest);
}

async function rejectConnectionRequestCore(data, request, deps = {}) {
  return requestShell(data, request, deps, actionTypes.rejectConnectionRequest);
}

async function markConnectionRequestSeenCore(data, request, deps = {}) {
  return requestShell(
    data,
    request,
    deps,
    actionTypes.markConnectionRequestSeen,
  );
}

async function muteConnectionRequestsFromPeerCore(data, request, deps = {}) {
  const prepared = await preparePeerOperation(
    data,
    request,
    deps,
    actionTypes.muteConnectionRequestsFromPeer,
  );
  if (!prepared.ok) {
    return prepared.response;
  }
  return foundationNotReady(prepared);
}

async function unmuteConnectionRequestsFromPeerCore(data, request, deps = {}) {
  const prepared = await preparePeerOperation(
    data,
    request,
    deps,
    actionTypes.unmuteConnectionRequestsFromPeer,
  );
  if (!prepared.ok) {
    return prepared.response;
  }
  return foundationNotReady(prepared);
}

async function getConnectionRequestQuotaSummaryCore(_data, request, deps = {}) {
  const prepared = await prepareAccountOperation(
    request,
    deps,
    actionTypes.getConnectionRequestQuotaSummary,
  );
  if (!prepared.ok) {
    return prepared.response;
  }
  return foundationNotReady(prepared);
}

async function requestShell(data, request, deps, action) {
  const prepared = await prepareRequestOperation(data, request, deps, action);
  if (!prepared.ok) {
    return prepared.response;
  }
  return foundationNotReady(prepared);
}

function foundationNotReady(prepared) {
  return guardrails.denied("backendUnavailable", {
    requestId: prepared.requestId,
    peerLabel: prepared.peer,
    diagnostics: {
      action: prepared.action,
      foundationReady: true,
      serverNow: prepared.now,
      sender: prepared.sender,
      peer: prepared.peer,
      pairKey: prepared.pairKey,
      requestId: prepared.requestId,
    },
  });
}

function attachDiagnostics(response, diagnostics) {
  return {
    ...response,
    diagnostics: {
      ...(response.diagnostics || {}),
      ...diagnostics,
    },
  };
}

function callable(coreHandler) {
  return onCall(callableOptions, async (request) => {
    return coreHandler(request.data, request);
  });
}

module.exports = {
  createConnectionRequest: callable(createConnectionRequestCore),
  cancelConnectionRequest: callable(cancelConnectionRequestCore),
  acceptConnectionRequest: callable(acceptConnectionRequestCore),
  rejectConnectionRequest: callable(rejectConnectionRequestCore),
  markConnectionRequestSeen: callable(markConnectionRequestSeenCore),
  muteConnectionRequestsFromPeer: callable(muteConnectionRequestsFromPeerCore),
  unmuteConnectionRequestsFromPeer: callable(
    unmuteConnectionRequestsFromPeerCore,
  ),
  getConnectionRequestQuotaSummary: callable(
    getConnectionRequestQuotaSummaryCore,
  ),
  __test: {
    actionTypes,
    acceptConnectionRequestCore,
    cancelConnectionRequestCore,
    createConnectionRequestCore,
    getConnectionRequestQuotaSummaryCore,
    markConnectionRequestSeenCore,
    muteConnectionRequestsFromPeerCore,
    rejectConnectionRequestCore,
    unmuteConnectionRequestsFromPeerCore,
  },
};
